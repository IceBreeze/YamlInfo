package LANraragi::Plugin::Sideloaded::Metadata::YamlInfo;

use strict;
use warnings;

use Data::Dumper;
use File::Basename;
use List::Util qw(uniq);
use Mojo::File;
use Mojo::JSON qw(encode_json);
use YAML::XS   qw( LoadFile );
use Time::Piece;

use LANraragi::Model::Plugins;
use LANraragi::Utils::Archive qw(is_file_in_archive extract_file_from_archive);
use LANraragi::Utils::Logging qw(get_plugin_logger);
use LANraragi::Utils::String  qw(trim);

my $DEFAULT_METAFILE      = 'comic-info.yaml';
my $DEFAULT_SUMMARY_FIELD = 'description';

#Meta-information about your plugin.
sub plugin_info {

    return (
        #Standard metadata
        name        => "YamlInfo",
        type        => "metadata",
        namespace   => "yi-plugin",
        author      => "IceBreeze",
        version     => "1.0.1",
        description => "Loads metadata from YAML (.yaml) files.<BR>"
          . "YAML files can be:<BR>"
          . "- embedded in the archive<BR>"
          . "- associated with an archive with the same name (excluding the extension)<BR>"
          . "- associated to all files in the folder",

        to_named_params => [ 'meta_filename', 'meta_embedded', 'use_lowercase', 'replace_title', 'get_embedded', 'check_parent' ],
        parameters      => {
            'assume_language'  => { type => "string", desc => "Assume language (empty for none)" },
            'check_parent'     => { type => "bool",   desc => "Search for metadata in the parent folders" },
            'dotnotation_url'  => { type => "bool",   desc => "Use dot notation for the URL field" },
            'get_embedded'     => { type => "bool",   desc => "Include embedded metadata" },
            'get_summary'      => { type => "bool",   desc => "Load the summary" },
            'get_summary_from' => {
                type    => "string",
                default => $DEFAULT_SUMMARY_FIELD,
                desc    => "Summary field name (default: '${DEFAULT_SUMMARY_FIELD}')"
            },
            'meta_embedded' => {
                type    => "string",
                default => $DEFAULT_METAFILE,
                desc    => "Custom metadata embedded file name (default: '${DEFAULT_METAFILE}')"
            },
            'meta_filename' => {
                type    => "string",
                default => $DEFAULT_METAFILE,
                desc    => "Custom metadata file name (default: '${DEFAULT_METAFILE}')"
            },
            'replace_title' => { type => "bool", desc => "Replace the title with the one in the metadata file" },
            'use_lowercase' => { type => "bool", desc => "Convert tags to lowercase" }
        },

        icon => 'data:image/svg+xml;base64,'
          . 'PHN2ZyB3aWR0aD0iNTEyIiBoZWlnaHQ9IjUxMiIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIw'
          . 'MDAvc3ZnIiBmaWxsPSJjdXJyZW50Q29sb3IiPgogPGcgaWQ9IkxheWVyXzEiPgogIDx0aXRsZT5Z'
          . 'PC90aXRsZT4KICA8ZWxsaXBzZSBmaWxsPSIjRTZDMzZBIiBzdHJva2Utd2lkdGg9IjAiIGN4PSIy'
          . 'NTYiIGN5PSIyNTUiIGlkPSJzdmdfMSIgcng9IjI1NSIgcnk9IjI1NSIvPgogIDx0ZXh0IGZpbGw9'
          . 'IiNmZmZmZmYiIHN0cm9rZS13aWR0aD0iMCIgeD0iMTI4LjMxNTA4IiB5PSIzOTAuOTg1ODIiIGlk'
          . 'PSJzdmdfNCIgZm9udC1zaXplPSIyNTAiIGZvbnQtZmFtaWx5PSInTm90byBTYW5zIE1vbm8nIiB0'
          . 'ZXh0LWFuY2hvcj0ic3RhcnQiIHhtbDpzcGFjZT0icHJlc2VydmUiIHRyYW5zZm9ybT0icm90YXRl'
          . 'KDAuMDEzMDA0NSwgMjU2LjE2NCwgMjUwLjk1NCkgbWF0cml4KDEuODI5OTksIDAsIDAsIDEuNjY3'
          . 'NSwgLTEyMC42NDcsIC0yMzkuNDc2KSIgZm9udC1zdHlsZT0ibm9ybWFsIiBmb250LXdlaWdodD0i'
          . 'Ym9sZCI+WTwvdGV4dD4KIDwvZz4KCjwvc3ZnPg=='
    );

}

sub get_tags {
    my ( undef, $lrr_info, $params ) = @_;

    my $logger = get_plugin_logger();

    my $archive = Mojo::File->new( $lrr_info->{file_path} );

    $logger->info("Searching tags for ${archive}");

    my $data = load_metadata( $params, $archive );
    $logger->debug( "Loaded metadatas: " . encode_json($data) ) if $data;

    my @tags = get_all_tags( $data, $archive->basename, $params );
    @tags = map { lc } @tags if ( $params->{use_lowercase} );

    my $language = trim( $params->{assume_language} );
    if ($language) {
        push( @tags, "language:$language" ) unless ( grep { $_ =~ /language:/ } @tags );
    }

    my %hashdata = ( tags => join( ', ', @tags ) );

    if ( $params->{replace_title} ) {
        my $title = get_archive_title( $data, $archive->basename );
        $hashdata{title} = $title if ($title);
    }

    if ( $params->{get_summary} ) {
        my $summary_field = lc( trim( $params->{get_summary_from} ) || $DEFAULT_SUMMARY_FIELD );
        my $summary       = get_archive_summary( $data, $archive->basename, $summary_field );
        $hashdata{summary} = $summary if ($summary);
    }

    $logger->info( "Sending the following tags to LRR: " . $hashdata{tags} );
    return %hashdata;
}

sub load_metadata {
    my ( $params, $archive ) = @_;

    my $folder        = $archive->dirname;
    my $sidecar       = $archive->basename( $archive->extname ) . "yaml";
    my $data_dir      = $ENV{LRR_DATA_DIRECTORY} || '/';
    my $metafile_name = $params->{meta_filename} || $DEFAULT_METAFILE;
    my $embedded_name = $params->{meta_embedded} || $DEFAULT_METAFILE;

    my %data;
    $data{sidecar}  = load_metadatas_from_yaml_file("$folder/$sidecar");
    $data{embedded} = load_metadata_from_archive( "$archive", $embedded_name ) if ( $params->{get_embedded} );
    my $count = 0;
    do {
        $data{ "dir" . $count++ } = load_metadatas_from_yaml_file("$folder/$metafile_name");
        $folder = dirname($folder);
    } while ( $params->{check_parent} && $folder ne $data_dir );

    delete $data{sidecar}{Files};    # remove the list of images because we have no use for it at the moment

    return lowercase_keys( \%data );
}

sub load_metadatas_from_yaml_file {
    my ($yamlfile) = @_;
    if ( -f $yamlfile ) {
        return LoadFile($yamlfile);
    }
    return {};
}

sub load_metadata_from_archive {
    my ( $archive, $yamlfile ) = @_;
    if ( is_file_in_archive( $archive, $yamlfile ) ) {
        return LoadFile( extract_file_from_archive( $archive, $yamlfile ) );
    }
    return {};
}

sub get_all_tags {
    my ( $data, $filename, $params ) = @_;
    my @tags = map { get_tags_from_metadata( $_, $filename, $params ) } values %$data;
    return uniq(@tags);
}

sub get_tags_from_metadata {
    my ( $data, $filename, $params ) = @_;
    my @tags;

    while ( my ( $k, $v ) = each %$data ) {
        next if ( !$v );
        my $v_type = ref $v;

        if ( $k eq 'files' && $v_type eq 'HASH' ) {
            $k = 'archives';
            my $logger = get_plugin_logger();
            $logger->warn("The use of the 'files' key as a hash is deprecated. Use 'archives' instead.");
        } elsif ( $k eq 'files' && $v_type eq 'ARRAY' ) {
            next;    # skip the list of internal files
        }

        # order does matter!
        if    ( $k =~ /^(?:description|summary)$/ ) { next; }
        elsif ( $k eq 'archives' )   { push( @tags, get_metadata_associated_to_file( $filename, $v, $params ) ) if ($filename); }
        elsif ( $k eq 'url' )        { push( @tags, get_urls( $v, $params ) ) }
        elsif ( $v_type eq 'HASH' )  { next; }    # skip any unknown structure
        elsif ( $k eq 'tags' )       { push( @tags, @$v ); }
        elsif ( $v_type eq 'ARRAY' ) { push( @tags, get_array_with_namespace( $k, $v ) ); }
        elsif ( $k eq 'title' )      { next; }
        elsif ( $k eq 'released' )   { push( @tags, get_timestamp_as_epoch($v) ); }
        else                         { push( @tags, "$k:$v" ); }
    }
    return @tags;
}

sub get_metadata_associated_to_file {
    my ( $filename, $files_data, $params ) = @_;
    my $metadata = $files_data->{$filename} || $files_data->{ strip_extension($filename) };
    return get_tags_from_metadata( $metadata, undef, $params );
}

sub strip_extension {
    my ($filename) = @_;
    ( my $filename_no_ext = $filename ) =~ s/\.[^.]+$//;
    return $filename_no_ext;
}

sub get_array_with_namespace {
    my ( $namespace, $list ) = @_;
    return map { "$namespace:$_" } @$list;
}

sub get_archive_title {
    my ( $data, $filename ) = @_;
    my $title = $data->{embedded}{title};
    $title = $data->{sidecar}{title}                                         if ( !$title );
    $title = $data->{dir0}{archives}{ lc $filename }{title}                  if ( !$title );
    $title = $data->{dir0}{archives}{ lc strip_extension($filename) }{title} if ( !$title );
    $title = $data->{dir0}{title}                                            if ( !$title );
    return $title;
}

sub get_archive_summary {
    my ( $data, $filename, $summary_field ) = @_;
    my $summary = $data->{embedded}{$summary_field};
    $summary = $data->{sidecar}{$summary_field}                                         if ( !$summary );
    $summary = $data->{dir0}{archives}{ lc $filename }{$summary_field}                  if ( !$summary );
    $summary = $data->{dir0}{archives}{ lc strip_extension($filename) }{$summary_field} if ( !$summary );
    $summary = $data->{dir0}{$summary_field}                                            if ( !$summary );
    return $summary;
}

sub get_urls {
    my ( $urls, $params ) = @_;
    my @tags;
    my $use_dotnotation = $params->{dotnotation_url} || 0;
    my $namespace       = ($use_dotnotation) ? "url" : "source";
    if ( ref($urls) eq 'ARRAY' ) {
        @tags = map { "$namespace:$_" } @$urls;
    } elsif ( ref($urls) eq 'HASH' && $use_dotnotation ) {
        while ( my ( $k, $v ) = each %$urls ) {
            push( @tags, "$namespace.$k:$v" ) if ($v);
        }
    } elsif ( ref($urls) eq 'HASH' && !$use_dotnotation ) {
        @tags = map { "$namespace:$_" } values %$urls;
    } else {
        push( @tags, "$namespace:$urls" );
    }
    return @tags;
}

sub get_timestamp_as_epoch {
    my ($released) = @_;
    my $epoch = $released;
    if ( $released =~ /^\d{4}-\d{2}-\d{2}/ ) {
        $epoch = Time::Piece->strptime( $released, "%Y-%m-%d" )->epoch;
    }    # otherwise, we assume it's already an epoch timestamp
    return "timestamp:$epoch";
}

sub lowercase_keys {
    my $data = shift;

    if ( ref($data) eq 'HASH' ) {
        my %lowercase_hash;
        for my $key ( keys %$data ) {
            my $lower_key = lc($key);
            $lowercase_hash{$lower_key} = lowercase_keys( $data->{$key} );
        }
        return \%lowercase_hash;
    } elsif ( ref($data) eq 'ARRAY' ) {
        return [ map { lowercase_keys($_) } @$data ];
    }

    return $data;
}

1;
