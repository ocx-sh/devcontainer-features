---
title: Installer variables and feature options
description: How each variable of the official ocx install script maps to an option of the Dev Container Feature, or why it has none.
sidebar:
  order: 3
---
<!-- doc_type: reference -->

The feature installs ocx with its own download code, not by running the official install script from `setup.ocx.sh`.
This page lists every variable of that script and the feature option that replaces it, or the reason it has none.
The table is generated from `src/ocx/installer-parity.json` in the feature repository, which is checked against the live script (`task parity:check`).
The script source is [`install.sh` in ocx-sh/www-setup](https://github.com/ocx-sh/www-setup/blob/main/src/install.sh).

## Status values {#status}

Each variable carries one of three status values.

| Status | Meaning |
|---|---|
| `exposed` | A feature option sets the same behaviour. |
| `fixed` | The feature sets the variable to one value and offers no option. |
| `not-exposed` | The feature does not need the variable, and the note says why. |

## Installer variables {#variables}

<!-- generated:parity-variables:start -->

| Installer variable | Status | Feature option | Behaviour |
|---|---|---|---|
| `OCX_BIN_SUBPATH` | not-exposed | none | This is an internal constant of the installer, not a setting, so there is nothing to expose. |
| `OCX_EXTRA_CA_CERTS` | exposed | [`caBundle`](options.md#opt-caBundle) | The installer derives it from the CA bundle. The feature sets it from caBundle so ocx trusts that bundle at run time. |
| `OCX_HOME` | exposed | [`ocxHome`](options.md#opt-ocxHome) | The ocxHome option sets it for all users. Empty keeps the default ~/.ocx of each user. |
| `OCX_INSTALL_CA_BUNDLE` | exposed | [`caBundle`](options.md#opt-caBundle) | The caBundle option names a PEM file inside the image that is trusted for every download. |
| `OCX_INSTALL_DIST_URL` | exposed | [`distUrl`](options.md#opt-distUrl) | The distUrl option replaces the bundled release manifest with one fetched over HTTPS. |
| `OCX_INSTALL_DOWNLOADER` | not-exposed | none | The feature probes for curl first and falls back to wget, so no choice is needed. |
| `OCX_INSTALL_FORCE` | not-exposed | none | An image layer is always a fresh install, so there is never an existing version to replace. |
| `OCX_INSTALL_MIRROR_URL` | exposed | [`mirrorUrl`](options.md#opt-mirrorUrl) | The mirrorUrl option downloads release archives from your own host. Checksums are still enforced. |
| `OCX_INSTALL_NO_SETUP` | fixed | none | Always on: the feature never runs ocx self setup, which would write the build user's profiles and store. The shellActivation option covers shell setup. |
| `OCX_INSTALL_NO_SMOKETEST` | fixed | none | Always off: the feature smoke-tests the installed binary every time, so a broken install fails the build. |
| `OCX_INSTALL_PRINT_PATH` | not-exposed | none | A feature build has no consumer for the printed path, and the installDir option already states it. |
| `OCX_INSTALL_QUIET` | not-exposed | none | The build log is the only feedback channel in a container build, so the output stays on. |
| `OCX_INSTALL_REPO` | not-exposed | none | The distUrl and mirrorUrl options cover alternative sources and keep checksum verification enforced. |
| `OCX_INSTALL_VERSION` | exposed | [`version`](options.md#opt-version) | The version option takes an exact version, pinned or latest. The upstream default is the latest release, here it is pinned. |
| `OCX_MANAGED_CONFIG` | exposed | [`managedConfig`](options.md#opt-managedConfig) | The managedConfig option sets the OCI reference of an organisation-managed ocx configuration. |
| `OCX_NO_MODIFY_PATH` | fixed | none | Always on: no per-user profile is modified at build time. Setting shellActivation to false is the equivalent switch for the project toolchain. |

<!-- generated:parity-variables:end -->

## Deliberately absent {#absent}

No option turns off checksum verification of the release archive.
No option passes registry credentials to the build.
A build that needs a mirror or a private manifest uses the [`mirrorUrl`](options.md#opt-mirrorUrl) and [`distUrl`](options.md#opt-distUrl) options, and checksums stay enforced.

## Options with no installer counterpart {#feature-only}

<!-- generated:parity-feature-only:start -->

| Feature option | Difference from the installer |
|---|---|
| [`libc`](options.md#opt-libc) | The upstream installer detects the C library itself, while the feature defaults to musl, which runs on every Linux image. |
| [`installDir`](options.md#opt-installDir) | The installer uses the per-user store, while the feature places the binary in one directory that is on PATH. |
| [`noUpdateCheck`](options.md#opt-noUpdateCheck) | The installer has no counterpart, while the feature turns off the ocx update check by default so the container makes no needless network call. |
| [`consentPaths`](options.md#opt-consentPaths) | The installer has no counterpart, while the feature lets projects under the listed paths activate without a prompt. |
| [`pull`](options.md#opt-pull) | The installer only installs ocx, while the feature can also restore the project toolchain when the container is created. |
| [`pullGroups`](options.md#opt-pullGroups) | The installer has no toolchain step, while the feature restores the listed tool groups when pull is on. |
| [`shellActivation`](options.md#opt-shellActivation) | The installer edits shell profiles itself, while the feature puts the project toolchain on PATH in new shells on request. |

<!-- generated:parity-feature-only:end -->
