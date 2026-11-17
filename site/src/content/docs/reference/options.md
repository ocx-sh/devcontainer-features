---
title: Options
description: Every option of the ocx Dev Container Feature with its type, default value and allowed values.
sidebar:
  order: 1
---
<!-- doc_type: reference -->

The ocx Dev Container Feature takes 13 options in the `features` object of `devcontainer.json`.
Each option has a type, a default value and, for some, a closed list of allowed values.
An option you leave out keeps its default, so `"ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}` is a complete configuration.
The build validates every option and stops with exit code 2 on a value it cannot use.

A string option with a control character stops the build, and so does a `managedConfig` or `pullGroups` value that starts with `-`.
[Fix a rejected option or version](../troubleshooting/install-option-errors.md) shows the messages.

Each example below shows one option as a line of the object that follows the feature reference.

The devcontainer CLI passes each option to the install script as an upper-case environment variable, for example `CABUNDLE`.
Boolean options accept `true` and `false`, and also `1`, `0`, `yes` and `no`.
The options that decide what the feature trusts are `consentPaths`, `shellActivation`, `version`, `distUrl` and `managedConfig`, and [What the feature trusts](../concepts/trust-model.md) explains their defaults.

## Option table {#table}

The table is generated from `src/ocx/devcontainer-feature.json` in the feature repository.
A check in the docs gate fails when this region and that file differ.

<!-- generated:options:start -->

| Option | Type | Default | Allowed values | Description |
|---|---|---|---|---|
| [`version`](#opt-version) | string | `pinned` | Any string; suggested `pinned`, `latest` | Which ocx to install. 'pinned' is the ocx version this feature release was tested with, 'latest' is the newest stable release at build time, or give an exact version such as 1.2.3. |
| [`libc`](#opt-libc) | string | `musl` | `musl`, `gnu`, `auto` | C library flavour of the ocx binary. 'musl' runs on every Linux image, 'gnu' needs glibc, 'auto' picks the one the image uses. |
| [`distUrl`](#opt-distUrl) | string | `""` | Any string | HTTPS URL of a release manifest that replaces the bundled one. Empty uses the manifest shipped with this feature. |
| [`mirrorUrl`](#opt-mirrorUrl) | string | `""` | Any string | HTTPS base URL to download release archives from, for networks that cannot reach GitHub. Empty downloads from the official release location. |
| [`caBundle`](#opt-caBundle) | string | `""` | Any string | Path inside the image to a PEM CA bundle. It is used for downloads at build time and by ocx at run time. Empty uses the system certificates. |
| [`managedConfig`](#opt-managedConfig) | string | `""` | Any string | OCI reference of an organisation-managed ocx configuration. Empty installs no managed configuration. |
| [`ocxHome`](#opt-ocxHome) | string | `""` | Any string | Sets OCX_HOME for all users. The directory must exist and be writable by the user who opens the container; the feature does not create it. Empty keeps ~/.ocx for each user. |
| [`installDir`](#opt-installDir) | string | `/usr/local/bin` | Any string | Directory that receives the ocx binary. It must be on PATH. |
| [`noUpdateCheck`](#opt-noUpdateCheck) | boolean | `true` | `true`, `false` | Turn off the ocx update check, so the container makes no network call just to look for a new ocx. |
| [`consentPaths`](#opt-consentPaths) | string | `/workspaces/*` | Any string | Colon-separated absolute paths. A project there activates in new shells and ocx grants consent without a prompt. A trailing /* covers the path and below. Empty activates nothing. |
| [`pull`](#opt-pull) | boolean | `true` | `true`, `false` | Restore the project toolchain from ocx.toml when the container is created. |
| [`pullGroups`](#opt-pullGroups) | string | `""` | Any string | Comma-separated tool groups to restore and to put on PATH in new shells. Empty means the default group only. |
| [`shellActivation`](#opt-shellActivation) | boolean | `true` | `true`, `false` | Put the project toolchain on PATH in new interactive shells, for projects under consentPaths only. |

<!-- generated:options:end -->

## version {#opt-version}

Selects the ocx release the build installs.
`pinned` installs the ocx version the feature release was tested with.
`latest` fetches the live release manifest from `https://setup.ocx.sh/dist.json` at build time and needs network access.
An exact version such as `0.6.8` is looked up in the bundled manifest.
The build fails with exit code 2 when that manifest has no such build.

A release before the first `.tar.gz` release also fails with exit code 2, and the message names the oldest version the feature installs.
`latest` trusts the HTTPS endpoint that serves the manifest, while the default `pinned` verifies the archive against the checksum bundled in the feature.

```jsonc
"version": "latest"
```

## libc {#opt-libc}

Selects the C library flavour of the ocx binary.
`musl` is a static build that runs on every Linux image.
`gnu` needs glibc 2.28 or later and fails with exit code 7 on an image below that.
`auto` installs the `gnu` build when the image has glibc 2.28 or later and the `musl` build otherwise.

```jsonc
"libc": "auto"
```

## distUrl {#opt-distUrl}

Replaces the release manifest bundled with the feature by one fetched from an HTTPS URL.
A URL whose file name is a 64-digit SHA-256 digest followed by `.json` is verified against that digest.
The build refuses a rolling manifest when it can only download through a BusyBox `wget` that does not validate certificates.
It also refuses a manifest that contains a backslash or repeats a key within one row, with exit code 4.
A plain URL trusts the HTTPS endpoint that serves the manifest, and a digest-named file does not.

```jsonc
"distUrl": "https://mirror.example.com/ocx/dist.json"
```

## mirrorUrl {#opt-mirrorUrl}

Downloads the release archive from `<mirrorUrl>/<tag>/<filename>` instead of the URL in the manifest.
The archive checksum from the manifest is still verified, so a mirror cannot substitute a different file.
The value must be an HTTPS URL.

```jsonc
"mirrorUrl": "https://mirror.example.com/ocx-releases"
```

## caBundle {#opt-caBundle}

Names a PEM file of CA certificates inside the image, for example a corporate root certificate.
The build trusts it for every download and fails with exit code 2 when the path is not a readable file.
When the file is at most 32 KiB, the feature also writes it as `extra_ca_certs` in `/etc/ocx/config.toml`, so ocx trusts it at run time.
A larger file produces a warning and ocx is not told about it.

```jsonc
"caBundle": "/usr/local/share/ca-certificates/corp-root.pem"
```

## managedConfig {#opt-managedConfig}

Sets the OCI reference of an organisation-managed ocx configuration.
The feature writes it as `[managed] source` with `required = false`, and the `onCreateCommand` hook runs `ocx config setup --managed-config <reference>` as the remote user.
The reference may contain letters, digits and the characters `. _ : / @ -`, and it must not start with `-`.
A reference pinned to a digest, such as `registry.example.com/ocx/org-config@sha256:<digest>`, keeps the tag from moving.

```jsonc
"managedConfig": "registry.example.com/ocx/org-config:1"
```

## ocxHome {#opt-ocxHome}

Sets `OCX_HOME`, the ocx store directory, for all users.
The value is exported by `/etc/profile.d/ocx.sh` and by the lifecycle hooks.
It must be an absolute path to a directory that exists and that every user of the container can write to.
The feature does not create the directory.
When `ocx pull` cannot write there, the warning names the `ocxHome` directory, as [Run ocx as root, a named user or a split user](../guides/non-root-and-custom-users.md#private-store) shows.

```jsonc
"ocxHome": "/opt/ocx-home"
```

## installDir {#opt-installDir}

Names the directory that receives the `ocx` binary.
The path must be absolute and the directory must be on `PATH`.
The default `/usr/local/bin` is on `PATH` in every common image.

```jsonc
"installDir": "/usr/local/sbin"
```

## noUpdateCheck {#opt-noUpdateCheck}

Writes `[update]` with `self = "manual"` and `toolchain = "manual"` to `/etc/ocx/config.toml`.
With the default `true`, the container makes no network call just to look for a new ocx.
Set it to `false` to omit the section.

```jsonc
{ "features": { "ghcr.io/ocx-sh/devcontainer-features/ocx:1": { "noUpdateCheck": false } } }
```

## consentPaths {#opt-consentPaths}

Lists, separated by colons, the paths whose projects activate in a new shell without a prompt.
The feature writes them as `[shell.consent] paths` in `/etc/ocx/config.toml`, and the shell profile checks them before it activates a project.
Each entry must be an absolute path without `..`.

A plain path matches that directory only.
A path ending in `/*` matches the directory and everything below it.
Any other use of `*` matches nothing.

An empty value activates nothing, and tools then run through `ocx exec -- <command>` or `ocx shell`.
The default `/workspaces/*` is a trust decision, and [What the feature trusts](../concepts/trust-model.md#activation) describes it.

```jsonc
"consentPaths": "/workspaces/*:/home/vscode/src/*"
```

## pull {#opt-pull}

Controls the `updateContentCommand` hook, which runs `ocx pull` as the remote user in the workspace folder.
With `false` the hook does nothing.
A workspace without `ocx.toml` in it or above it is skipped without a message.

```jsonc
{ "features": { "ghcr.io/ocx-sh/devcontainer-features/ocx:1": { "pull": false } } }
```

## pullGroups {#opt-pullGroups}

Lists the tool groups that `ocx pull` restores, as `ocx pull --group=<groups>`.
New shells put the same groups on `PATH`.
Names may contain letters, digits and the characters `. _ -`, separated by commas, and the list must not start with `-`.
An empty value selects the default group only.
A named list replaces the default group, so write `"default,ci"` to keep both.

```jsonc
"pullGroups": "default,test"
```

## shellActivation {#opt-shellActivation}

Adds the project toolchain to `PATH` in new interactive shells that start in a project under `consentPaths`.
The feature writes the logic to `/etc/profile.d/ocx.sh` and sources it from the system rc files that exist.
The shell composes the toolchain once, when it starts, and does not refresh on `cd`.
With `false` the file carries no activation code, and tools run through `ocx exec -- <command>`.

```jsonc
{ "features": { "ghcr.io/ocx-sh/devcontainer-features/ocx:1": { "shellActivation": false } } }
```
