package LANraragi::Plugin::Metadata::YamlInfo;

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use List::Util qw(uniq);
use Mojo::File;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Util qw(html_unescape);
use YAML::XS qw( LoadFile );

use LANraragi::Model::Plugins;
use LANraragi::Utils::Archive qw(is_file_in_archive extract_file_from_archive);
use LANraragi::Utils::Generic qw(remove_spaces);
use LANraragi::Utils::Logging qw(get_plugin_logger);

my $DEFAULT_METAFILE = 'comic-info.yml';

#Meta-information about your plugin.
sub plugin_info {

    return (
        #Standard metadata
        name        => "YamlInfo",
        type        => "metadata",
        namespace   => "yi-plugin",
        author      => "IceBreeze",
        version     => "0.1",
        description => "Loads metadata from YAML files stored in folders or embedded in the archives.",
        parameters => [
            { type => "string", desc => "Custom metadata file name (default: 'comic-info.yml')" },
            { type => "string", desc => "Custom metadata embedded file name (default: 'comic-info.yml')" },
            { type => "bool", desc => "Convert tags to lowercase" },
            { type => "bool", desc => "Replace the title with the one in the metadata files" },
            { type => "bool", desc => "Include embedded metadata" },
            { type => "bool", desc => "Search for metadata in the parent folders" }
        ],
        icon         => "data:image/png;base64,"
                        . "iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAIAAAAC64paAAAAAXNSR0IArs4c6QAA"
                        . "AARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAABZSURBVDhPzY5J"
                        . "CgAhDATzSl+e/2irOUjQSFzQog5hhqIl3uBEHPxIXK7oFXwVE+Hj5IYX4lYVtN6M"
                        . "UW4tGw5jNdjdt5bLkwX1q2rFU0/EIJ9OUEm8xquYOQFEhr9vvu2U8gAAAABJRU5E"
                        . "rkJggg=="
    );

}

sub get_tags {
    my $logger = get_plugin_logger();

    # better handled in the caller
    my %hashdata = eval { internal_get_tags(@_); };
    if ($@) {
        $logger->error($@);
        return ( error => $@ );
    }

    $logger->info("Sending the following tags to LRR: " . $hashdata{tags});
    return %hashdata;
}

sub internal_get_tags {
    my $params = read_and_validate_params(@_);
    my $logger = get_plugin_logger();

    my $archive = $params->{archive};

    $logger->info('Searching tags for "' . $archive->to_string . '"');

    my $data = load_metadata_from_files( $params, $archive );
    $logger->info("Loaded metadatas: " . encode_json($data)) if $data;

    my @tags = get_all_tags( $data, $archive->basename );

    @tags = map { lc } @tags if ($params->{use_lowercase});

    my %hashdata = ( tags => join( ', ', @tags ) );

    if ( $params->{replace_title} ) {
        my $title = get_archive_title($data, $archive->basename);
        $hashdata{title} = $title if ( $title );
    }

    return %hashdata;
}

sub read_and_validate_params {
    my %params;
    my $lrr_info = $_[1];
    $params{archive}       = Mojo::File->new($lrr_info->{file_path});
    $params{meta_name}     = $_[2] || $DEFAULT_METAFILE;
    $params{meta_name_emb} = $_[3] || $DEFAULT_METAFILE;
    $params{use_lowercase} = $_[4];
    $params{replace_title} = $_[5];
    $params{get_embedded}  = $_[6];
    $params{check_parent}  = $_[7];
    return \%params;
}

sub load_metadata_from_files {
    my ( $params, $archive ) = @_;

    my $folder   = $archive->dirname;
    my $sidecar  = $archive->basename($archive->extname) . "yml";
    my $data_dir = $ENV{LRR_DATA_DIRECTORY} || '/';
    my $count = 0;

    my %data;
    $data{sidecar} = load_metadatas_from_yaml_file( $folder, $sidecar );
    $data{file}    = load_metadata_from_archive( "$archive", $params->{meta_name_emb} ) if ($params->{get_embedded});
    do {
        $data{"dir" . $count++} = load_metadatas_from_yaml_file( $folder, $params->{meta_name} );
        $folder = dirname($folder);
    } while ( $params->{check_parent} && $folder ne $data_dir );

    return \%data;
}

sub load_metadatas_from_yaml_file {
    my ( $folder, $ymlfile ) = @_;
    if ( -f "$folder/$ymlfile" ) {
        return LoadFile ("$folder/$ymlfile");
    }
    return {};
}

sub load_metadata_from_archive {
    my ( $archive, $ymlfile ) = @_;
    if ( is_file_in_archive($archive, $ymlfile) ) {
        return LoadFile( extract_file_from_archive($archive, $ymlfile) );
    }
    return {};
}

sub get_all_tags {
    my ( $data, $filename ) = @_;
    my @tags;
    while ( my( $k, $v ) = each %$data ) {
        push( @tags, get_tags_from_metadata( $v, $filename ) ) if ($v);
    }
    return uniq(@tags);
}

sub get_tags_from_metadata {
    my ( $data, $filename ) = @_;
    my @tags;
    #get_plugin_logger()->info(Dumper($data));
    while ( my( $k, $v ) = each %$data ) {
        next if (!$v);
        my $v_type = ref $v;
        # order does matter!
        if ( $k eq 'files' ) { push( @tags, get_metadata_associated_to_file( $filename, $v ) ) if ($filename); }
        elsif ( $v_type eq 'HASH' ) { next; }             # skip any unknown structure
        elsif ( $k eq 'tags' ) { push( @tags, @$v ); }
        elsif ( $v_type eq 'ARRAY' ) { push( @tags, get_array_with_namespace($k, $v) ); }
        elsif ( $k eq 'title' ) { next; }                 # nothing to do with the title here
        else { push( @tags, "$k:$v" ); }
    }
    return @tags;
}

sub get_metadata_associated_to_file {
    my ( $filename, $files_data ) = @_;
    my $metadata = $files_data->{$filename} || $files_data->{ strip_extension($filename) };
    return get_tags_from_metadata( $metadata, undef );
}

sub strip_extension {
    my ( $filename ) = @_;
    (my $filename_no_ext = $filename) =~ s/\.[^.]+$//;
    return $filename_no_ext;
}

sub get_array_with_namespace {
    my ( $namespace, $list ) = @_;
    return map { "$namespace:$_" } @$list;
}

sub get_tags_from_reference {
    my ( $ref_value, $ref_folder ) = @_;

    my $data = load_metadata_from_yaml_file("$ref_folder/$ref_value.yml");
    return get_tags_from_metadata($data);
}

sub get_archive_title {
    my ( $data, $filename ) = @_;
    my $title = $data->{file}{title};
    $title = $data->{sidecar}{title} if (!$title);
    $title = $data->{dir0}{files}{$filename}{title} if (!$title);
    $title = $data->{dir0}{files}{ strip_extension($filename) }{title} if (!$title);
    $title = $data->{dir0}{title} if (!$title);
    return $title;
}

1;
