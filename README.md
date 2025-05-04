⚠️ **Upgrading to Version 1.0**

If you're upgrading to version 1.0, please refer to the [Breaking Changes](#breaking-changes) section.

# YamlInfo

This is a simple plugin for LANraragi that reads metadata from YAML-formatted files.

- YAML is easier to read and write compared to XML or JSON.
- Unlike other projects that enforce rigid file system structures, this plugin offers flexibility. While LANraragi may not be the best solution for reading chapters in sequence (at least at the time of writing), it provides a more adaptable approach.

I uploaded this in response to request, but it wasn't supposed to be shared because the project to which it refers is based on
a slightly different philosophy for file management, yet it's really flexible and I like it more than others.
So don't expect anything shiny :)

---

# Metadata File Content

The metadata file consists of key-value pairs. The keys are used as namespaces under which the tags are categorized.

You can use any names for the keys, and both scalar and array values will be loaded.

```yaml
---
title: Sword Art Online
summary: Trapped in a deadly VR game, Kirito must fight to survive and escape
  with many other players.
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

### Exceptions

Some keys have specific requirements: `archives`, `description`, `files`, `summary`, `tags`, `title` and `url`.

#### `title`, `description` and `summary`

These keys must always be strings if present. Furthermore `description` and `summary` are mutually exclusive. You can specify which one to import in the plugin settings.

#### `tags`

This key must always be an array. Each item will be added as a tag without a namespace in LANraragi.

Alternatively, you can use `tags` to define namespaced tags, as shown below:

```yaml
---
title: Sword Art Online
summary: Trapped in a deadly VR game, Kirito must fight to survive and escape
  with many other players.
tags: [ serie:Sword Art Online, serie:SAO, author:Kawahara Reki, artist:Nakamura Tamako,
        category:manga, genre:Action, genre:Adventure, genre:Drama, genre:Romance, genre:Sci-Fi,
        genre:Fantasy, genre:Slice of Life, theme:Video Games, demographic:Shounen,
        status:completed, publication:2010, adaptation ]
```

The resulting list of tags in LANraragi will not change.

#### `archives` and `files`

These keys must be hashes.

Starting with version 1.0, `archives` replaces `files`, which is now deprecated.

If you're managing multiple archives with a single metadata file, you can specify archive-specific tags under `archives` without creating separate sidecar files.

A "sidecar" metadata file is a YAML file with the same name as the associated archive but with a `.yaml` extension:

```txt
CAP-0299.5.yaml
CAP-0299.5.zip
```

Example of usage of `archives`:

```yaml
---
title: Fairy Tail
genre: [ Action, Adventure, Comedy, Fantasy ]
themes: [ Magic, Supernatural ]
demographic: Shounen

archives:
  "CAP-0299.5":
    title: ~Welcome to Natsu's house~
    tags: [ extra ]
```

#### `url`

This key stores URLs, which are loaded into LANraragi under the `source` namespace by default.

It can be a scalar, array, or hash:

```yaml
url: http://site1/...

# or

url:
- http://site1/...
- http://site2/...

# or

url:
  site1: http://site1/...
  site2: http://site2/...
```

If using the hash format, you can filter URLs by enabling the "*Use dot notation for the URL field*" parameter.
This way the urls are returned as:

```txt
url.site1: http://site1/...
url.site2: http://site2/...
```

Now you can use LANraragi's "Tag Rules" to handle the different sites. For example with the following set of rules you can discard "site1" and return "site2" under the `source` namespace:

```txt
-url.site1:*
url.site1:* => source:*
```

---

# Recursively Loading Metadata from Parent Folders

The plugin can recursively read metadata files (default: `comic-info.yaml`) from the file system. Tags from these files are merged and passed to LANraragi.

For example, if your folder structure is organized by series:

```txt
|- SAO
   |- 01-SAO-Aincrad
   |- 02-SAO-Fairy Dance
   |- ...
```

You can configure metadata files like this:

`SAO/comic-info.yaml`

```yaml
---
serie: Sword Art Online
category: manga
genre: [ Action, Adventure, Drama, Romance, Sci-Fi, Fantasy, Slice of Life ]
```

`SAO/01-SAO-Aincrad/comic-info.yaml`

```yaml
---
author: Kawahara Reki
artist: Nakamura Tamako
status: completed
publication: 2010
category: adaptation
theme: [ Video Games ]
```

`SAO/02-SAO-Fairy Dance/comic-info.yaml`

```yaml
---
author: Kawahara Reki
artist: Hazuki Tsubasa
status: ongoing
publication: 2012
category: adaptation
theme: [ Video Games ]
```

In this example, the `category` namespace will include both `manga` (from the parent folder) and `adaptation` (from the subfolder). The only metadata that can be overridden are `title`, `description` and `summary`, in the following order of priority:

1. Embedded metadata (if enabled in preferences)
2. Sidecar metadata
3. Folder metadata

---

# Breaking Changes

Version 1.0 introduces two breaking changes to improve compatibility with the YAML format used by CCDC06. I decided to support it because it's the only source of metadata in YAML I discovered so far.

1. **Default File Extension**

   The default file extension is now `.yaml` instead of `.yml` (as recommended by YAML specifications).
   To use the old file name, set `comic-info.yml` in the plugin parameters ("*Custom metadata file name*").
   Alternatively, rename all metadata files using the following command (should work from inside the container if you don't have the volume mounted readonly):

   ```bash
   # remove "echo" only if you know what you are doing!
   find content/ -depth -name "*.yml" -exec sh -c 'echo mv -vi "$1" "${1%.yml}.yaml"' _ {} \;
   ```

   If you have metadata files inside the archives, you have to edit them manually or you can specify the old file name using the parameter "*Custom metadata embedded file name*".

   Be cautious when renaming files inside archives, as this may alter their hash.

2. **Deprecation of `files` Key**

   The `files` key is now deprecated in favor of `archives`. While `files` is still supported, it is recommended to update existing metadata to use `archives`.
