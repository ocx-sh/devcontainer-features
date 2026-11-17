---
title: Files, environment and exit codes
description: The files the ocx Dev Container Feature writes, the environment a new shell sees, the lifecycle commands and the exit codes of the install.
sidebar:
  order: 2
---
<!-- doc_type: reference -->

The feature writes a fixed set of files at build time and sets no container environment variables.
The listings below come from a container built from `debian:stable-slim` and one built from `alpine:3`, both with default options.

## Files {#files}

The build runs as root and writes only under `/usr/local`, `/etc` and the `installDir` directory.
It writes nothing into a home directory.
A built image contains no `/root/.ocx`.

| Path | Mode and owner | Content |
|---|---|---|
| `/usr/local/bin/ocx` | `755 root:root` | The ocx binary. The directory is the `installDir` option. |
| `/usr/local/share/ocx-feature/ocx-version` | `644 root:root` | The installed ocx version, for example `0.6.8`. |
| `/usr/local/share/ocx-feature/dist-digest` | `644 root:root` | SHA-256 of the release manifest the build used. |
| `/usr/local/share/ocx-feature/feature.env` | `644 root:root` | The option values the lifecycle hooks read. |
| `/usr/local/share/ocx-feature/hook.sh` | `755 root:root` | The script behind both lifecycle commands. |
| `/etc/ocx/config.toml` | `644 root:root` | The system-wide ocx configuration. |
| `/etc/profile.d/ocx.sh` | `644 root:root` | Shell activation and optional `OCX_HOME` and `OCX_EXTRA_CA_CERTS` exports. |

The feature also adds one marked block to each of these system rc files that exists: `/etc/bash.bashrc`, `/etc/bash/bashrc`, `/etc/bashrc`, `/etc/zsh/zshrc` and `/etc/zshrc`.
`debian:stable-slim` has `/etc/bash.bashrc`, and `alpine:3` has none of them.
The block on Debian reads as follows.

```console
# >>> ocx devcontainer feature >>>
[ -r /etc/profile.d/ocx.sh ] && . /etc/profile.d/ocx.sh
# <<< ocx devcontainer feature <<<
```

A rebuild replaces the block in place.
On Alpine, login shells reach `/etc/profile.d/ocx.sh` through `/etc/profile`.

### The system configuration {#config-toml}

With default options `/etc/ocx/config.toml` holds this text.
The first line is a marker.
A file that lacks the marker is treated as not written by the feature and is left untouched, with a warning.

```toml
# Written by the ocx Dev Container Feature (id: ocx). Edits are overwritten on rebuild.

[update]
self = "manual"
toolchain = "manual"

[shell.consent]
paths = ["/workspaces/*"]
```

The options map to this file as follows.
`noUpdateCheck` writes `[update]`, `consentPaths` writes `[shell.consent]`, `managedConfig` writes `[managed]` with `required = false`, and `caBundle` writes a top-level `extra_ca_certs`.

### The shell profile {#profile}

With default options `/etc/profile.d/ocx.sh` holds the text below, shortened where a comment says so.
The outer `case` makes it a no-op in non-interactive shells.
The omitted code finds the project directory in `__ocxf_d`, from `OCX_PROJECT` or from the nearest `ocx.toml` above the working directory.

The inner `case` runs `ocx env` only when that directory matches a `consentPaths` entry, here `/workspaces` and everything below it.
A project outside the list runs no `ocx` command and leaves `PATH` unchanged.
The `consentPaths` option controls the patterns in that `case`, and `pullGroups` adds `--group=<groups>` to the command.

```sh
# Written by the ocx Dev Container Feature (id: ocx). Edits are overwritten on rebuild.
case $- in
*i*)
    if [ -x '/usr/local/bin/ocx' ]; then
        # ... sets __ocxf_d to the resolved project directory, or to nothing ...
        case $__ocxf_d in
        '/workspaces' | '/workspaces'/*)
            # ... picks __ocxf_sh: bash, zsh or sh ...
            eval "$('/usr/local/bin/ocx' --offline env --shell="$__ocxf_sh" 2>/dev/null)" || :
            ;;
        esac
        unset __ocxf_d __ocxf_sh
    fi
    ;;
esac
```

### Files created at run time {#runtime-files}

These files are created by the remote user, not by the build.
The user's own `~/.ocx` store appears when a command such as `ocx env` or `ocx about` first runs.
`ocx.lock` and `.ocx/toolchain` appear in the project when `ocx lock` and `ocx pull` run, and they belong to the user who ran those commands.

## Environment variables the feature sets {#env}

The feature declares no `containerEnv` entries, so a container started from the image has no `OCX_*` variable from the feature.
Two options add exports to `/etc/profile.d/ocx.sh`: `ocxHome` adds `export OCX_HOME=<path>`, and a `caBundle` adds, when `/etc/ocx/config.toml` already exists and the feature did not write it, `export OCX_EXTRA_CA_CERTS=<path>`.
The lifecycle hooks export the same values for their own run.

In a new interactive bash shell inside a project that pins one tool, `shfmt`, the environment differs from the image default in `PATH` only.
The profile evaluates the output of `ocx --offline env --shell=bash`, which prepends the project link directory to `PATH`.

The resulting `PATH` starts with the project link directory.

```console
/workspaces/ws-debian/.ocx/toolchain/links/default/shfmt/content:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Outside a project, and in a project outside `consentPaths`, `PATH` stays unchanged.
Non-interactive shells, including `sh -lc`, run no activation code.
The shell reads the project once, when it starts, so a later `cd` changes nothing.

## Lifecycle commands {#lifecycle}

The feature declares two lifecycle commands in `devcontainer-feature.json`.
Both run as the remote user with the workspace folder as the working directory.

| Command | Runs | Condition |
|---|---|---|
| `onCreateCommand` | `/usr/local/share/ocx-feature/hook.sh on-create` | Runs `ocx config setup --managed-config <reference>` when `managedConfig` is set. |
| `updateContentCommand` | `/usr/local/share/ocx-feature/hook.sh update-content` | Runs `ocx pull`, with `--group=<pullGroups>` when set, when `pull` is `true` and an `ocx.toml` exists in or above the workspace. |

The hooks never fail the container.
A failing ocx command produces one warning and the hook exits 0.
This is the warning for a project that has an `ocx.toml` and no `ocx.lock`.

```console
ocx-feature: warning: ocx pull failed with exit code 78.
  attempted: /usr/local/bin/ocx pull
  fix: run "ocx lock" in the project and commit ocx.lock
```

| ocx exit code | Meaning | Fix named in the warning |
|---|---|---|
| 78, 65 | No `ocx.lock`, or a stale one. | Run `ocx lock` and commit `ocx.lock`. |
| 75, 69, 79 | Network failure or package not found. | Check the network, mirror and proxy settings. |
| 74 | File ownership problem, or an `ocxHome` directory the user cannot write. | With `ocxHome` set, the warning names that directory, which must exist and be writable. Otherwise check ownership of `ocx.toml`, `ocx.lock` and `.ocx`. |
| 64 | An unknown group in `pullGroups`, or no managed config source. | Correct the option. |

When the hook runs as root and the project directory, `ocx.lock`, `.ocx` or the `OCX_PROJECT` path belongs to another user, it pulls nothing and warns instead.
This applies when `remoteUser` is `root` on a workspace owned by a regular user.

```console
ocx-feature: warning: not pulling: /workspaces/ws-debian is owned by another user and this hook runs as root, which would take over ocx.lock and the toolchain links; run ocx pull as that user
```

## Install exit codes {#exit-codes}

The install script at build time exits with one of these codes.
A non-zero code fails the image build.

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | Generic failure. |
| 2 | Usage error, invalid option value, a release older than the first `.tar.gz` build, or a missing tool the build could not install. |
| 3 | Network failure, or a redirect to a URL that is not `https://`. |
| 4 | Checksum mismatch, or a release manifest that is not in the expected plain form. |
| 5 | Extraction failure. |
| 7 | Unsupported platform, or the installed binary does not run. |

## Variables you set yourself {#user-env}

The feature reads or sets these ocx variables and leaves the rest to ocx.
`OCX_HOME` sets the store directory, and the `ocxHome` option exports it for you.
`OCX_PROJECT` names the project directory or file, and the update hook treats a set value as a project even when no `ocx.toml` lies above the workspace.
`OCX_EXTRA_CA_CERTS` names a PEM file ocx trusts, and the `caBundle` option sets it when needed.

`ocx --help` lists the remaining ones, among them `OCX_OFFLINE`, `OCX_CONFIG` and `OCX_NO_PROJECT`.
A variable of your own goes into `containerEnv` or `remoteEnv` of `devcontainer.json`.
