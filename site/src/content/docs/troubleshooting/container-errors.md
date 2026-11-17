---
title: Fix a lock or permission error
description: Match a missing or stale ocx.lock, or a permission error during the restore of a dev container, to its cause and fix.
sidebar:
  order: 3
---
<!-- doc_type: troubleshooting -->

The container built, but the restore failed and the create log shows an `ocx-feature: warning:` line.
Find the message below.
Every entry shows the message as ocx or the feature prints it, the cause, and the fix.

The restore runs in two lifecycle commands, listed under [Lifecycle commands](../reference/environment-and-files.md#lifecycle). `onCreateCommand` applies the managed configuration when `managedConfig` is set.
`updateContentCommand` runs `ocx pull` when `pull` is on. A failure in either prints one warning and the container still starts.
The warning names an exit code:

| Exit code | Meaning |
|---|---|
| 65 | `ocx.lock` is stale |
| 74 | A file or directory belongs to another user, or the `ocxHome` directory is not writable |
| 75 | A network or registry request failed |
| 78 | `ocx.lock` is missing, or a package has no build for this platform |

For a failed image build, see [Fix a failed feature install](./install-errors.md). For a skipped restore, a managed configuration warning or a package with no build for the platform, see [Fix a restore warning](./restore-warnings.md). For a tool that is missing from the terminal, see [Fix a tool missing from the terminal](./shell-activation-errors.md).
[Lifecycle commands](../reference/environment-and-files.md#lifecycle) say when each warning appears, and [Install exit codes](../reference/environment-and-files.md#exit-codes) lists the build codes.

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
With `ocxHome` set, the warning names the directory in its fix line: `the ocxHome directory <path> must exist and be writable by the user who opens the container; the feature does not create it`.
