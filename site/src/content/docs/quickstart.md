---
title: Add ocx to a dev container
description: Add the ocx feature to devcontainer.json, check the installed version, then add a tool to your project and run it.
---
<!-- doc_type: how-to -->
<!-- doc_tier: first-steps -->

This page takes you from a plain `devcontainer.json` to a container where `ocx` is installed and one project tool runs through it.

## Before you start {#before}

You need Docker, the Dev Containers extension for VS Code or the `devcontainer` command-line tool, and network access to GitHub and the ocx registry.

## Add the feature {#add-the-feature}

Add the feature reference to the `features` object of `.devcontainer/devcontainer.json`.

<!-- doc: qs-feature-json -->
```jsonc-run
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

## Rebuild and check ocx {#check-ocx}

Rebuild the container. In VS Code, run **Dev Containers: Rebuild Container** from the command palette. With the command-line tool, run `devcontainer up --workspace-folder . --remove-existing-container`.

Open a terminal in the container and print the version.

<!-- doc: qs-ocx-version -->
```bash-run
ocx version
```

The output is the ocx version this feature release was tested with.

```text
0.6.8
```

## Add a tool {#add-a-tool}

Create a project file, add the `jq` tool to it, and run it through `ocx exec`.
The `ocx add` command fetches the tool and writes `ocx.lock`, which pins the exact build.

<!-- doc: qs-add-tool -->
```bash-run
ocx init
ocx add jqlang/jq:1.8
ocx exec -- jq --version
```

The last command prints the version of the pinned tool.

```text
jq-1.8.2
```

`ocx init` writes `ocx.toml` into the current folder, and `ocx add` records the tool in it.

```toml
[tools]
jq = "ocx.sh/jqlang/jq:1.8"
```

The command `ocx exec -- <command>` always finds the project tools.
A terminal that starts after the add also has them on its path, so `jq` runs without the prefix there.

## Commit the project files {#commit}

Commit `ocx.toml` and `ocx.lock` to your repository.
The next time the container is created, the feature reads both files and fetches the locked tools before you open a terminal.
The `.ocx/toolchain` folder holds its own `.gitignore`, so it stays out of your commits.

## Next steps {#next-steps}

- [Restore the project toolchain on create](guides/restore-toolchain.md) covers the groups, the opt-out and the failure warnings.
- [Pin or upgrade the ocx version](guides/pin-or-upgrade-version.md) shows how to freeze or follow the ocx release.
- [Run ocx as root, a named user or a split user](guides/non-root-and-custom-users.md) explains the user setups.
- [Use ocx on a minimal base image](guides/minimal-images.md) covers Alpine and other small images.
