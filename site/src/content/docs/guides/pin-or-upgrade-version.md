---
title: Pin or upgrade the ocx version
description: Choose which ocx version the feature installs, with the default pin, an exact version, the current release or a frozen feature tag.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

This page shows how to set the ocx version a dev container installs and how to read the installed version back.
The [`version` option](../reference/options.md#opt-version) takes `pinned`, an exact `X.Y.Z` or `latest`.

## Know what the default installs {#default-pin}

The default is `"version": "pinned"`.
It installs the ocx version that the feature release was tested with, so each feature version maps to one ocx version ([why](../concepts/how-the-install-works.md#one-version)).
Feature 1.0.0 installs ocx 0.6.8.

<!-- doc: version-default -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

A new feature patch version is released for every ocx release.
The tag `:1` therefore follows ocx, and a rebuild takes the highest patch.

## Pin an exact version {#exact}

Set `version` to an `X.Y.Z` value.
The feature installs that release from the release manifest bundled with it, which lists past ocx releases.

<!-- doc: version-exact -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "version": "0.6.7"
    }
  }
}
```

A version that the bundled manifest does not list stops the build with exit code 2.
The message names the highest version it has.

<!-- doc: version-unknown -->
```console
ocx-feature: error: no ocx 9.9.9 build for x86_64-unknown-linux-musl in the release manifest (newest available: 0.6.8); set version: latest or distUrl to a manifest that has it
```

A value that is not `pinned`, `latest` or three dot-separated numbers also fails with exit code 2.
For example, `banana` stops with `option version must be pinned, latest or X.Y.Z (got: banana)`.
To install a version that the bundled manifest lacks, point `distUrl` at a manifest that lists it.

## Follow the current release {#latest}

Set `version` to `latest`.
The build reads the live release manifest from `setup.ocx.sh` and installs the highest stable release.
That read needs network access at build time, and two builds on different days can install different versions.

<!-- doc: version-follow -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "version": "latest"
    }
  }
}
```

If the manifest cannot be fetched, the build stops with exit code 3.

## Pin the feature tag {#feature-tag}

The feature tag decides which feature release, and so which default ocx version, a rebuild gets.
A full tag freezes the feature and the ocx version it pins.

<!-- doc-norun: tag resolution belongs to the Dev Containers tooling, and the tags exist only after publication -->
```jsonc
{
  "features": {
    // follows every minor and patch release of major version 1
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {},
    // follows patch releases of 1.0
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1.0": {},
    // stays on this exact feature release
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1.0.0": {}
  }
}
```
<!-- /doc-norun -->

## Upgrade on purpose {#upgrade}

To move to another ocx version, change the value and rebuild the container.

- With `pinned`, move to a higher feature tag or release.
- With an exact version, edit the `version` value.
- With `latest`, rebuild the container.

## Check the installed version {#check-version}

Run `ocx version` in the container.
The feature also records the version it installed in a file.

<!-- doc: version-check -->
```bash
ocx version
cat /usr/local/share/ocx-feature/ocx-version
```

Both commands print the same version, for example `0.6.7` after the exact pin above.

## Next steps {#next-steps}

- [Add ocx to a dev container](../quickstart.md) is the first-run walk-through.
- [Use ocx on a minimal base image](minimal-images.md) covers images without the usual tools.
- [Changelog](../changelog.md) lists the ocx version each feature release pins.
