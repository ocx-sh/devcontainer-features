---
title: Fix a missing tool or failed restore
description: Match a missing tool, a lock error or a restore warning in a running dev container to its cause and fix.
sidebar:
  order: 2
---
<!-- doc_type: troubleshooting -->

The container built, but a tool is missing in the terminal or the create log shows an `ocx-feature: warning:` line.
Find the message below.
Every entry shows the message as ocx or the feature prints it, the cause, and the fix.

The restore runs in two lifecycle commands. `onCreateCommand` applies the managed configuration when `managedConfig` is set.
`updateContentCommand` runs `ocx pull` when `pull` is on. A failure in either prints one warning and the container still starts.
The warning names an exit code:

| Exit code | Meaning |
|---|---|
| 65 | `ocx.lock` is stale |
| 74 | A file or directory belongs to another user |
| 75 | A network or registry request failed |
| 78 | `ocx.lock` is missing, or a package has no build for this platform |

For a failed image build, see [Fix a failed feature install](../install-errors/).

## Error: ocx.lock not found {#lock-missing}

<!-- doc: ts-lock-missing -->

```console
error: ocx.lock not found at /workspaces/demo/ocx.lock; run `ocx lock` to create it
ocx-feature: warning: ocx pull failed with exit code 78.
  attempted: /usr/local/bin/ocx pull
  fix: run "ocx lock" in the project and commit ocx.lock
```

This issue occurs when the workspace has an `ocx.toml` and no `ocx.lock`. The restore installs the versions the lock records, so it has nothing to install.
The container still starts, and no tool from `ocx.toml` is on `PATH`.

To fix it, run `ocx lock` in the workspace and commit the new `ocx.lock`.
`ocx lock` downloads the packages as well, so a new terminal finds the tools afterwards.

```console
$ ocx lock
$ bash -ic 'shfmt --version'
v3.13.1
```

## Error: ocx.lock is stale {#lock-stale}

<!-- doc: ts-lock-stale -->

```console
error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
ocx-feature: warning: ocx pull failed with exit code 65.
  attempted: /usr/local/bin/ocx pull
  fix: run "ocx lock" in the project and commit ocx.lock
```

This issue occurs when `ocx.toml` changed after the lock was written, for example after you add a tool by hand. `ocx pull` refuses to guess which versions you want.
Until the lock is current, a new terminal does not find the new tool:

```console
$ bash -ic 'shfmt --version'
bash: shfmt: command not found
```

To fix it, run `ocx lock` and commit the updated `ocx.lock`.

## Error: command not found in a terminal {#command-not-found}

<!-- doc: ts-command-not-found -->

```console
bash: shfmt: command not found
```

This issue occurs when the terminal did not put the project tools on `PATH`. Three causes are common.
The lock is missing or stale, as the two entries above show.
The terminal started before `ocx lock` or `ocx pull` finished. Or `shellActivation` is `false`, so no shell gets the toolchain.

The feature composes `PATH` once, when an interactive shell starts. A terminal that is already open does not change after `ocx add` or `ocx pull`.

To fix it:

1. Open a new terminal after the lock and the tools are in place.
2. Run the tool through `ocx exec`, which always works: `ocx exec -- shfmt --version`.
3. If the option is off, remove `"shellActivation": false` from `devcontainer.json` and rebuild.

```console
$ bash -ic 'command -v shfmt; ocx exec -- shfmt --version'
v3.13.1
```

With `shellActivation` set to `false`, `command -v shfmt` prints nothing and the command exits with status 1.
The `ocx exec` call still prints `v3.13.1`.
A script run with `sh -lc` is not an interactive shell either, so use `ocx exec` there.

## Error: Permission denied on ocx.lock {#store-permission}

<!-- doc: ts-store-permission -->

```console
error: /workspaces/demo/ocx.lock: I/O error: Permission denied (os error 13)
ocx-feature: warning: ocx pull failed with exit code 74.
  attempted: /usr/local/bin/ocx pull
  fix: check file ownership of ocx.toml, ocx.lock and .ocx in the workspace
```

This issue occurs when another user owns `ocx.lock` or `.ocx`. The usual cause is that `root` ran `ocx pull` in the workspace earlier, for example from `sudo`, and took over the files.
A shared `ocxHome` produces the same exit code when the directory is not writable for the session user:

```console
error: failed to install 2 packages: ... dependency setup failed: internal file error for '/opt/shared-ocx/temp': Permission denied (os error 13)
```

To fix it, give the lock back to the user who opens the container. Check `.ocx` the same way:

```console
$ sudo chown "$(id -un)": ocx.lock
```

For a shared store, make the `ocxHome` directory writable by every user who runs `ocx pull`. Without the option, each user keeps a private store in `~/.ocx`.

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

To fix it, check that the container reaches the registry, then rerun the lifecycle command. [Apply organisation-managed configuration](../../integrate/managed-config/) covers the mechanism.

## Error: no build for this platform {#package-not-for-platform}

<!-- doc: ts-package-not-for-platform -->

```console
error: no 'linux/amd64+libc.musl' leaf for binding 'node' at the locked version; run `ocx update` to re-resolve if it has since been added
```

This issue occurs when a tool in `ocx.toml` ships only a glibc build and the image uses musl, as Alpine does.
The message above comes from `ocx lock` for the `node` package on `mcr.microsoft.com/devcontainers/base:alpine`, and the command exits with code 78.
`ocx` also detects no libc on Wolfi, so there a glibc-only package fails the same way.

To fix it:

1. Use a glibc base image such as Debian or Ubuntu.
2. Or choose a package that ships a musl build.
3. On Wolfi, add `--platform linux/<arch>+libc.glibc` to `ocx lock` and `ocx pull`.

The restore hook cannot pass that flag. Run both commands by hand and commit the lock.
