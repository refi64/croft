# CroFT

*<b>C</b>h<b>ro</b>mium <b>F</b>latpak <b>Toolkit</b>*

CroFT is a utility for managing a Chromium source tree tied to a Flatpak
manifest, actively used for maintaining the primary Chromium Flatpak. The end
goal is to be able to, in theory, have this tool (and the workflows it supports)
shared amongst anyone else who wants to maintain some source-based Chromium
derivative Flatpak, in order to streamline routine maintenance.

## Downloads

Binary releases of this will periodically be posted to
[the releases page](https://github.com/refi64/croft/releases).

## Building

Install the Dart SDK, then run:

```
$ dart pub get
$ dart run build_runner build
$ dart2native bin/croft.dart -o croft
```

then move the `croft` binary to wherever you want.

## Configuration

CroFT requires a `~/.config/croft.yaml` to work, using the following format:

```yaml
# Map of Chromium-based Flatpak projects
projects:
  chromium:
    # Directory containing the Flatpak manifest and related files
    manifest-dir: ~/manifests/chromium
    # Filename of the Flatpak manifest
    manifest-name: org.chromium.Chromium.yaml
    # Module in the Flatpak manifest that builds the Chromium project itself
    main-module: chromium
    # Directory containing the Chromium source tree
    chromium-source-root: ~/code/chromium/src
# (optional) Default project name in the projects map above
default-project: chromium
# (optional, defaults to 'docker') The docker or podman command to run
docker-command: docker
```

## Basic terms

- "Component" is referring to either the root Chromium repository ("chromium")
  or the FFmpeg repository inside ("ffmpeg").
- "Upstream revision" is the last revision that's part of upstream, i.e. the
  revision right before any locally added commits.

## Workflow to update Chromium

### Updating the local source tree

First off, downloading the new sources. In your Chromium source tree, `git fetch
--tags`, then checkout the tag corresponding to the latest release, and `gclient
sync`. Note that, if any commits are present in the FFmpeg repository, this will
fail. You can work around that by resetting it first via `croft
destructive-reset ffmpeg upstream`, but note that **this will discard any work
in the FFmpeg repository**.

Now, the current patches in the manifest can be applied to Chromium and FFmpeg
via `croft apply-patches chromium` and `croft apply-patches ffmpeg`,
respectively. `croft apply-patches` is a thin wrapper over `git am -3`, so on
any patch conflicts, you can make changes as needed and then do `git am
--continue`.

If the upstream FFmpeg configuration was updated, it will conflict with our
FFmpeg configuration patch, so that one can be skipped via `git am --skip` and
recreated later (see below). If you already know there will be a conflict, you
can skip the configuration patch altogether via `croft apply-patches ffmpeg
--skip-ffmpeg-config`.

### Updating the FFmpeg configuration

If the FFmpeg configuration was updated and needs to be regenerated (see above),
use `croft generate-ffmpeg-config` to regenerate and commit the new
configuration. This command requires Docker or Podman in order to work.

### Exporting the patches

Once all patches are updated, run `croft export-patches chromium` and `croft
export-patches ffmpeg` to export the patches back to the manifest folder, then
you can commit and push those as desired.

## Workflow for modifying & creating patches

### Working with the upstream revision

You can use `croft get-upstream-revision` to print out the upstream revision.

`croft rebase-on-upstream chromium|ffmpeg` will open an interactive rebase
targeting said upstream revision, allowing you to rebase just the patch commits
as needed.

### Building Chromium

In order to access the Flatpak build environment, use `croft build-shell`, which
will build all the modules in the manifest *before* the main one, then open up
a shell in the resulting build environment (using `flatpak-builder --run`).

If you want to run an *entire* manifest build, you can use `croft
build-release`, which will build the entire Flatpak manifest, from top to
bottom. Due to the large size of the Chromium sources, this will also delete any
previous Chromium build directories left over in your Flatpak cache before it
starts.
