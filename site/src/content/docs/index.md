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

## Add ocx with one line {#add-one-line}

Add the feature reference `ghcr.io/ocx-sh/devcontainer-features/ocx:1` to the `features` object of your `devcontainer.json`.
Rebuild the container.
Open a terminal and run `ocx version`.

This documentation is for developers and platform teams who add the feature to a `devcontainer.json`.
The [Dev Containers specification](https://containers.dev/) defines how a feature reaches your container.

## What it does on create {#what-it-does}

When the container builds and starts, the feature does four things:

- It installs the `ocx` binary for every user of the container.
- It restores the toolchain pinned in the `ocx.toml` of your workspace.
  A workspace without an `ocx.toml` is left alone.
- It activates the project tools in the shell, so a new terminal finds them on its path.
- It adds the VS Code extension `ocx-sh.ocx`, which understands `ocx.toml`.

The tag `:1` keeps the feature on major version 1, so a rebuild takes minor and patch releases without an edit to your file.

## Look it up {#look-it-up}

- [Source and issues](https://github.com/ocx-sh/devcontainer-features) for the feature on GitHub
- [The ocx project](https://github.com/ocx-sh/ocx) for the package manager the feature installs
