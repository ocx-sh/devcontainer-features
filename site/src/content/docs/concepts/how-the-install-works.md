---
title: How the feature installs ocx
description: What the ocx Dev Container Feature does at image build and at container creation, how it verifies what it downloads, and what it never does.
sidebar:
  order: 1
---
<!-- doc_type: explanation -->

This page explains what the ocx Dev Container Feature does to an image and to a container.
It lets a reviewer list the files the feature writes, the checks it runs and the things it never does.
[What the feature trusts](trust-model.md) covers the trust decisions behind them.
The excerpts come from real runs against `debian:stable-slim` and `alpine:3` with default options.
Every option named here is described on the [options page](../reference/options.md), and every path on the [files page](../reference/environment-and-files.md).

## What happens at build time {#build}

The devcontainer CLI adds the feature as one layer on top of the base image.
It runs `install.sh` as root with the options as upper-case environment variables, and it prints them first.
The log starts with this banner.

```console
Feature       : ocx
Description   : Installs the ocx package manager and restores the project toolchain from ocx.toml.
Version       : 1.0.0
Options       :
    VERSION="pinned"
    LIBC="musl"
    DISTURL=""
    MIRRORURL=""
    CABUNDLE=""
    MANAGEDCONFIG=""
    OCXHOME=""
    INSTALLDIR="/usr/local/bin"
    NOUPDATECHECK="true"
    CONSENTPATHS="/workspaces/*"
    PULL="true"
    PULLGROUPS=""
    SHELLACTIVATION="true"
```

The script then works through fixed phases.
It validates every option and stops with exit code 2 on a bad value.
It chooses the build target from the CPU architecture and the `libc` option.
It checks the tools it needs: a downloader (`curl` or `wget`), `tar`, `gzip`, a SHA-256 tool, `mktemp` and a CA certificate bundle.

When something is missing, the script installs it through the image's package manager (`apt-get`, `apk`, `dnf`, `microdnf`, `yum`, `zypper` or `pacman`) and checks again.
On Arch the command is `pacman -Syu --needed`, because a partial upgrade can break the image.
On Debian the log shows one line before the package manager output.

```console
ocx-feature: installing missing prerequisites: curl-or-wget ca-bundle
```

`alpine:3` already has everything, so the same build installs nothing.
It prints a warning, because Alpine ships a BusyBox `wget` that does not check the server certificate.

```console
ocx-feature: warning: BusyBox wget: no TLS floor and the server certificate may go unchecked; install curl for a verified download
```

The script then picks the release row for the target from the release manifest.
It downloads the archive over HTTPS, verifies it, extracts it and runs the binary once.
The last line of a successful build names the result.

```console
ocx-feature: installed ocx 0.6.8 (x86_64-unknown-linux-musl) at /usr/local/bin/ocx
```

Finally the script writes the configuration files, the shell profile and the hook files.
The layer ends there, and no command in it touches a home directory.

## One feature version is one ocx version {#one-version}

The feature carries a snapshot of the ocx release manifest, `dist.json`, and a file with its SHA-256 digest.
With `version: "pinned"` the build uses that snapshot and selects the stable release with the highest version.
The feature version and the ocx version therefore move together.

A scheduled workflow in the feature repository checks the live manifest every hour.
For a new ocx release it vendors the manifest, raises the feature patch version and regenerates the README and the changelog.
It then runs the full test suite on both architectures and publishes the new feature version with no human step.
The reference `ocx:1` follows every such release, and `ocx:1.0.0` stays on one.

`version: "latest"` skips the snapshot and fetches the live manifest at build time, so two builds on different days can install different ocx versions.
An exact version is looked up in the snapshot and fails when the snapshot has no such release.

## How the archive is verified {#verification}

Two checks protect the install, and neither has an off switch.
The script compares the SHA-256 of the bundled snapshot with the recorded one before it uses the snapshot.
A mismatch stops the build with exit code 4.
Both files travel in the same feature package, so this check detects corruption and not a swapped package.

The release row names the SHA-256 of the archive, and the script compares it with the downloaded file before it extracts anything.
A mismatch stops the build with exit code 4 and prints both values.

A manifest that the script reads as plain text must also look plain.
A backslash anywhere in the manifest, or a repeated key in one row, stops the build with exit code 4.
That check runs before the script trusts any row.
A release that ships as anything but a `.tar.gz` archive stops the build with exit code 2 before the download.

Extraction runs in two passes.
The first pass rejects absolute paths and `..` members.
The second pass rejects links that point outside the target directory.
Only then does `tar` extract, without the archive's owner or permissions.
The binary is staged next to its destination, run once to confirm that it reports the expected version, and moved into place only after that.

The download accepts only `https://` URLs and passes `--proto '=https'` and a TLS 1.2 floor to `curl` when `curl` supports them.
It refuses a redirect to a URL that is not `https://` and exits with code 3.
The script retries a failed attempt twice with a growing delay before it exits with code 3.

Timeouts bound each attempt.
With `curl`, a connection that takes longer than 30 seconds to open ends the attempt.
So does a transfer that stays below 1 KiB per second for 60 seconds.
With `wget`, a 30-second timeout bounds each wait.

A `mirrorUrl` changes where the archive comes from and nothing else, because the checksum still comes from the manifest.
[What the feature trusts](trust-model.md#install) says which sources a given option set depends on.

## What the feature never does {#never}

The feature never runs `ocx self setup`, which would write profile files and a store for the build user.
It never writes into `/root`, `/home` or any other home directory at build time.
It never turns off checksum verification and offers no option for it.
It never edits a system rc file that does not already exist, and it never modifies a file in `/etc/ocx` that it did not write.
It never fails container creation from a lifecycle hook.

The download and checksum code is the feature's own port of the official installer's functions, with the feature's prefixes and options.
That keeps the build free of the official installer's profile edits and its interactive paths.
The [installer parity page](../reference/installer-parity.md) lists every variable of that installer and what became of it.

## Where state lives {#state}

The image holds the binary and a handful of files in `/usr/local/share/ocx-feature`.
It also holds `/etc/ocx/config.toml`, `/etc/profile.d/ocx.sh` and one marked block per existing rc file.
Everything else belongs to the user who runs ocx.
Each user has a private store in `~/.ocx`, which commands such as `ocx about` and `ocx env` create for that user.
The project's `ocx.lock` and `.ocx/toolchain` belong to the user who ran the restore.

<!-- doc: how-install-files -->
```bash
stat -c '%a %U' /usr/local/bin/ocx
cat /usr/local/share/ocx-feature/ocx-version
ocx about >/dev/null
stat -c %U ~/.ocx
```

```console
755 root
0.6.8
root
```

The `ocxHome` option moves the store to one shared directory.
That works only when every user can write to it.

## What runs when the container is created {#create}

Image build and container creation are separate events.
The container starts from the finished image, and the devcontainer CLI then runs the lifecycle commands of the feature as the remote user.
The log shows them in this order.

```console
Container started
Running the onCreateCommand from Feature './ocx'...
Running the updateContentCommand from Feature './ocx'...
pulling count=1
no trust policy covers 'ocx.sh/shfmt/shfmt'; installing 'ocx.sh/shfmt/shfmt:3.13.1@sha256:3af504ea2ef5fc6aa0b911cf19768a1287fd7bd3bc9d975216e1cee7395e09c9' without signature verification
Downloading layer sha256:59beb4b92c81 to /root/.ocx/temp/b36e7cad6980628560f12ba6f9f81923
```

The `onCreateCommand` line is silent here because `managedConfig` is empty.
The `updateContentCommand` runs `ocx pull`, which prints the lines below it and restores the tools that `ocx.lock` pins.
A Codespaces prebuild runs both commands, so a prebuild contains the tools.
Without an `ocx.toml` in or above the workspace the hook prints nothing.

A failure in either hook becomes one warning with the ocx exit code and a fix, and the container still starts.
A hook that runs as root pulls nothing when the project, `ocx.lock`, `.ocx` or the `OCX_PROJECT` path belongs to another user.

New interactive shells read `/etc/profile.d/ocx.sh`.
When the project lies under a [`consentPaths`](../reference/options.md#opt-consentPaths) entry, the shell puts the project toolchain on `PATH` once, when it starts.
It does not refresh on `cd`, and a project outside those paths activates nothing.
[What the feature trusts](trust-model.md#activation) explains why the activation has that gate.
