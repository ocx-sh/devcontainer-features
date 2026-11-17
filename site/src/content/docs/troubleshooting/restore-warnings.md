---
title: Fix a restore warning
description: Match a skipped restore, an unsynced managed configuration or a package with no build for the platform to its cause and fix.
sidebar:
  order: 4
---
<!-- doc_type: troubleshooting -->

The lifecycle commands run the restore when the container is created. These entries cover a restore that is skipped, a managed configuration that does not sync and a package that has no build for the image.
Find the message below.
Every entry shows the message as ocx or the feature prints it, the cause, and the fix.

For a missing lock, a stale lock or a missing tool in the terminal, see [Fix a missing tool or failed restore](./container-errors.md).

## Warning: not pulling, the project belongs to another user {#root-owned}

<!-- doc: ts-root-owned -->

```console
ocx-feature: warning: not pulling: /workspaces/demo is owned by another user and this hook runs as root, which would take over ocx.lock and the toolchain links; run ocx pull as that user
```

This issue occurs when the lifecycle hook runs as `root` and the workspace belongs to someone else. This happens when `remoteUser` is `root` on a workspace owned by a regular user.
The hook skips the restore on purpose, so `root` does not take over the lock and the links.
The container still starts and no tool is fetched.

To fix it, either set `remoteUser` to the user who owns the workspace, or run `ocx pull` once as that user.

## Warning: the managed configuration did not sync {#config-not-synced}

<!-- doc: ts-config-not-synced -->

```console
error: failed to sync the managed-config snapshot: failed to fetch managed config: ... could not connect to 'localhost:9' over https ...
ocx-feature: warning: ocx config setup failed with exit code 75.
  attempted: /usr/local/bin/ocx config setup --managed-config localhost:9/acme/fleet:1
  fix: check the network, mirror and proxy settings, then rerun the container command
```

This issue occurs when `managedConfig` is set and the container cannot reach the registry that holds the configuration package.
The message above comes from an address that serves nothing. Exit code 75 means a network failure, and 69 or 79 mean the package was not found.
The feature writes the reference with `required = false`, so the container starts without the managed settings.

To fix it, check that the container reaches the registry, then rerun the lifecycle command. [Apply organisation-managed configuration](../integrate/managed-config.md) covers the mechanism.

## Error: no build for this platform {#package-not-for-platform}

<!-- doc: ts-package-not-for-platform -->

```console
error: no 'linux/amd64+libc.musl' leaf for binding 'node' at the locked version; run `ocx update` to re-resolve if it has since been added
```

This issue occurs when a tool in `ocx.toml` ships only a glibc build and the image uses musl, as Alpine does.
The message above comes from `ocx lock` for the `node` package on `mcr.microsoft.com/devcontainers/base:alpine`, and the command exits with code 78.
`ocx` also detects no libc on Wolfi, so there a glibc-only package fails the same way.

[Wolfi and glibc detection](../reference/supported-images.md#wolfi) covers that image.

To fix it:

1. Use a glibc base image such as Debian or Ubuntu.
2. Or choose a package that ships a musl build.
3. On Wolfi, add `--platform linux/<arch>+libc.glibc` to `ocx lock` and `ocx pull`.

The restore hook cannot pass that flag. Run both commands by hand and commit the lock.
