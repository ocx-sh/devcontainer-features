---
title: Run ocx as root, a named user or a split user
description: Set the dev container users so that ocx works for the session user and the user's store, lock file and toolchain belong to that user.
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

This page shows how to set `remoteUser` and `containerUser` so that `ocx` works for the user of your terminal, and the user's `~/.ocx` store belongs to that user.
It covers root, a named user and a split between build and session users.

## Pick the session user {#remote-user}

The feature installs the `ocx` binary once, for every user, at `/usr/local/bin/ocx`.
It writes nothing into any home directory during the build.
Each user gets a private store in `~/.ocx` the first time ocx needs it.

The restore after container creation runs as the remote user.
So `~/.ocx`, `ocx.lock` and `.ocx/toolchain` belong to that user.
The sections below differ only in which user that is.

## Run as root {#root}

Set `remoteUser` to `root`.
The store is `/root/.ocx`.

<!-- doc: user-root -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "remoteUser": "root"
}
```

When the workspace files belong to another user, the restore does not run as root.
Otherwise root would take over `ocx.lock` and the toolchain links.
The container prints this warning and starts.

```console
ocx-feature: warning: not pulling: /workspaces/u1 is owned by another user and this hook runs as root, which would take over ocx.lock and the toolchain links; run ocx pull as that user
```

Run `ocx pull` as the owner of the files, or choose that user as the remote user.

## Run as a named user {#named-user}

Set `remoteUser` to a user that exists in the image.
The Dev Containers base images define `vscode`.
The store is `/home/vscode/.ocx`, and the user owns the lock file and the toolchain.

<!-- doc: user-named -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "remoteUser": "vscode"
}
```

## Build as one user and run as another {#split-users}

Set `containerUser` to `root` for the container processes and `remoteUser` to the user of your session.
The feature install always runs as root at image build.
The restore still runs as the remote user, so the files in the workspace stay with that user.

<!-- doc: user-split -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "containerUser": "root",
  "remoteUser": "vscode"
}
```

## Set the remote user when none is set {#remote-user-unset}

An image without a `remoteUser` setting and without a default user runs the session as root.
This happens, for example, on `debian:stable-slim`.
If the workspace files belong to a non-root host user, the root warning above appears and no tools are restored.

<!-- doc: user-remote-unset -->
```jsonc
{
  "image": "debian:stable-slim",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

The `id -un` command prints `root` in this container.
To change that, set `remoteUser` to a user that the image has, or create a user in the image first.

## Keep one store per user {#private-store}

By default each user keeps a separate store, so two users download the same package twice.
The [`ocxHome` option](../reference/options.md#opt-ocxHome) sets one `OCX_HOME` for all users instead.

The feature does not create that directory or change its owner.
The directory must exist and be writable by every user who runs ocx.
Otherwise the restore fails with exit code 74, and the hint names file ownership.

```console
ocx-feature: warning: ocx pull failed with exit code 74.
  attempted: /usr/local/bin/ocx pull
  fix: check file ownership of ocx.toml, ocx.lock and .ocx in the workspace
```

## Check ownership {#verify}

In the terminal of the session user, print the version and the owners of the user's files.

<!-- doc: user-verify -->
```bash
id -un
ocx version
stat -c '%U %n' ~/.ocx .ocx/toolchain ocx.lock
```

Every line of the `stat` output starts with the name that `id -un` printed.
The `~/.ocx` directory exists once ocx has run a command that needs it, such as `ocx pull`.

## Next steps {#next-steps}

- [Restore the project toolchain on create](restore-toolchain.md) describes the restore and its warnings.
- [Use ocx on a minimal base image](minimal-images.md) covers images with few tools.
