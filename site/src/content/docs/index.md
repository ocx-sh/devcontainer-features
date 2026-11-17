---
title: Use ocx in a dev container
description: Add the ocx Dev Container Feature with one line in devcontainer.json and start with ocx and your project toolchain ready.
---
<!-- doc_type: landing -->
<!-- doc_tier: first-steps -->

The ocx Dev Container Feature installs the `ocx` command-line tool in a dev container and restores the tools your project pins in `ocx.toml`.

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```
<!-- doc: index-feature-line -->

## Add ocx with one line {#add-one-line}

Add the feature reference `ghcr.io/ocx-sh/devcontainer-features/ocx:1` to the `features` object of your `devcontainer.json`, then rebuild the container.
Open a terminal and run `ocx version`.
The [quickstart](quickstart.md) walks through the first run and adds a tool.

This documentation is for developers and platform teams who add the feature to a `devcontainer.json`.
The tag `:1` keeps the feature on major version 1, so a rebuild takes minor and patch releases without an edit to your file.

## Pick a goal {#pick-a-goal}

- [Add ocx and run a first tool](quickstart.md)
- [Pin the ocx version or follow the newest release](guides/pin-or-upgrade-version.md)
- [Restore the project toolchain when the container is created](guides/restore-toolchain.md)
- [Run ocx as root, a named user or a split user](guides/non-root-and-custom-users.md)
- [Use ocx on Alpine and other minimal images](guides/minimal-images.md)

## Look it up {#look-it-up}

- [Supported images](reference/supported-images.md) lists the base images and architectures the feature installs on
- [Options](reference/options.md) describes every option and its default
- [How the install works](concepts/how-the-install-works.md) explains what the build does
- [Changelog](changelog.md) lists the feature releases and the ocx version each one pins
- [Source and issues](https://github.com/ocx-sh/devcontainer-features) for the feature on GitHub
- [The ocx project](https://github.com/ocx-sh/ocx) for the package manager the feature installs
- [The Dev Containers specification](https://containers.dev/) for how a feature reaches your container
