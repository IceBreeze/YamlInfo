# YamlInfo
A simple plugin for LANraragi to read metadata from YAML formatted files.

- because YAML is simpler to read and write if compared to XML and JSON
- because I don't like how other projects force me to work with a rigid file system structure, 
  even if I know that LANraragi it's not the best solution, at least at the time I'm writing this, to read chapters in sequence.

I uploaded this in response to request, but it wasn't supposed to be shared because the project to which it refers is based on
a slightly different philosophy for file management, yet it's really flexible and I like it more than others.
So don't expect anything shiny :)

# The metadata file content

The content of the metadata file is basically a list of tags.

Every tag must have a namespace and there is no restriction on the namespaces you can use.

Every namespace can be a string or an array.

There are only three special (lets call them) `keywords`:

- `title` : if present, must always be a string
- `tags` : if present, must always be an array and every item under this "namespace" will end up as a tag without namespace in LANraragi
- `files` : if present, must be an hash. It's used to append additional tags or force titles to the archive in the same folder of the YAML file

With YAML rules, you can format your file in different ways. For example, the following expressions are equivalent:

```yaml
---
title: Sword Art Online
serie: [ Sword Art Online, SAO ]
author: Kawahara Reki
artist: Nakamura Tamako
category: manga
genre: [ Action, Adventure, Drama, Romance, Sci-Fi, Fantasy, Slice of Life ]
theme: [ Video Games ]
demographic: Shounen 
status: completed
publication: 2010
tags: [ adaptation ]
```

```yaml
---
title: Sword Art Online
serie:
    - Sword Art Online
    - SAO
author: Kawahara Reki
artist: Nakamura Tamako
category: manga
genre:
    - Action
    - Adventure
    - Drama
    - Romance
    - Sci-Fi
    - Fantasy
    - Slice of Life
theme: Video Games
demographic: Shounen 
status: completed
publication: 2010
tags:
    - adaptation
```

`tags` also let you express a list of tags like you would in LANraragi, so the above list could also be written as:

```yaml
---
title: Sword Art Online
tags: [ serie:Sword Art Online, serie:SAO, author:Kawahara Reki, artist:Nakamura Tamako,
        category:manga, genre:Action, genre:Adventure, genre:Drama, genre:Romance, genre:Sci-Fi,
        genre:Fantasy, genre:Slice of Life, theme:Video Games, demographic:Shounen,
        status:completed, publication:2010, adaptation ]
```

The plugin allows you to read metadata files (by default `comic-info.yml`) recursively from the file system. The tags loaded from the
YAML files are merged together and passed to LANraragi.

For example, if you like to organize your folders by "series" like this:

```txt
|- SAO
   |- 01-SAO-Aincrad
   |- 02-SAO-Fairy Dance
   |- ...
```

you can configure your metadata files like this:

`SAO/comic-info.yml`

```yaml
---
serie: Sword Art Online
category: manga
genre: [ Action, Adventure, Drama, Romance, Sci-Fi, Fantasy, Slice of Life ]
```

`SAO/01-SAO-Aincrad/comic-info.yml`

```yaml
---
author: Kawahara Reki
artist: Nakamura Tamako
status: completed
publication: 2010
category: adaptation
theme: [ Video Games ]
```

`SAO/02-SAO-Fairy Dance/comic-info.yml`

```yaml
---
author: Kawahara Reki
artist: Hazuki Tsubasa
status: ongoing
publication: 2012
category: adaptation
theme: [ Video Games ]
```

The namespace `category` in the example above contains `manga` in the parent folder and `adaptation` in the last folder.
The resulting `category` will have both.

The only metadata that can be overwritten is `title`. Titles will be loaded in this order:

```txt
- embedded metadata (if enabled in the preferences)
- sidecar metadata
- folder metadata
- parent folder (recursively)
```

A "sidecar" metadata file, is a YAML file with the same name of the associated archive, but with extension `.yml`:

```txt
CAP-0299.5.yml
CAP-0299.5.zip
```

A "folder" metadata file is a YAML file in the same folder of the archives that you can use to specify additional
tags for some or all the archives present in place of the sidecar file (I wasn't sure which one I would rather use, so I left all the options).
Anyway this is where you would use the last keyword `files`.

As previously said, `files` is an hash and its keys are the names of the archives (with or without the extension) in the same folder,
while the value is another hash containing additional tags.

For example:

```yaml
---
title: Fairy Tail
genre: [ Action, Adventure, Comedy, Fantasy ] 
themes: [ Magic, Supernatural ]
demographic: Shounen 

files:

    # force the title and add additional tags

    "CAP-0299.5":
        title: ~Welcome to Natsu's house~
        tags: [ extra ]
```

