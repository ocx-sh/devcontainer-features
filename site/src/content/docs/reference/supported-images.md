---
title: Supported base images
description: The base images the ocx Dev Container Feature is tested on, the prerequisites it installs on each family, and the two known limits.
sidebar:
  order: 4
---
<!-- doc_type: reference -->

The feature installs on Linux images for `amd64` and `arm64` that have a POSIX shell.
It installs the tools it needs through the image's package manager when they are missing.
The images below make up the test matrix of the feature repository.

## Supported images {#supported}

The table is generated from `test/images.txt` in the feature repository, which lists one image per line.
A platform in the last column means the image is published for that architecture only.

<!-- generated:images:start -->

| Alias | Image | Architectures |
|---|---|---|
| `debian` | `debian:stable-slim` | amd64 and arm64 |
| `ubuntu` | `ubuntu:24.04` | amd64 and arm64 |
| `alpine` | `alpine:3` | amd64 and arm64 |
| `fedora` | `fedora:45` | amd64 and arm64 |
| `rocky` | `rockylinux:9-minimal` | amd64 and arm64 |
| `alma` | `almalinux:9` | amd64 and arm64 |
| `ubi-minimal` | `registry.access.redhat.com/ubi9/ubi-minimal` | amd64 and arm64 |
| `amazonlinux` | `amazonlinux:2023` | amd64 and arm64 |
| `opensuse` | `opensuse/leap:15` | amd64 and arm64 |
| `arch` | `archlinux:latest` | amd64 only |
| `wolfi` | `cgr.dev/chainguard/wolfi-base` | amd64 and arm64 |
| `busybox` | `ocx-test/busybox-ca:local` | amd64 and arm64 |
| `devcontainers-ubuntu` | `mcr.microsoft.com/devcontainers/base:ubuntu` | amd64 and arm64 |
| `devcontainers-debian` | `mcr.microsoft.com/devcontainers/base:debian` | amd64 and arm64 |
| `devcontainers-alpine` | `mcr.microsoft.com/devcontainers/base:alpine` | amd64 and arm64 |

<!-- generated:images:end -->

### Prerequisites by image family {#prerequisites}

The feature needs a downloader (`curl` or `wget`), `tar`, `gzip`, a SHA-256 tool, `mktemp` and a CA certificate bundle.
It installs only what is missing, through the first package manager it finds, in the order `apt-get`, `apk`, `dnf`, `microdnf`, `yum`, `zypper`, `pacman`.
The build log names what it installs in a line that starts with `ocx-feature: installing missing prerequisites:`.

| Image family | Package manager | Packages the feature can add |
|---|---|---|
| Debian, Ubuntu, Dev Containers Debian and Ubuntu | `apt-get` | `curl`, `tar`, `gzip`, `coreutils`, `ca-certificates` |
| Alpine, Wolfi, Dev Containers Alpine | `apk` | the same names |
| Fedora, Amazon Linux | `dnf` | the same names |
| Rocky Linux minimal, Red Hat UBI minimal | `microdnf` | the same names |
| openSUSE Leap | `zypper` | the same names |
| Arch Linux | `pacman` | the same names, installed with `pacman -Syu --needed` |
| BusyBox | none | nothing, see [bare BusyBox](#busybox) |

On `debian:stable-slim` the build adds `curl` and the CA certificates.
On `alpine:3` it adds nothing, because the image has a BusyBox `wget`, `tar`, `gzip` and a CA bundle.
The build then prints a warning that BusyBox `wget` does not check the server certificate.
On `apt-get` images the feature runs `apt-get update` when the package lists are empty and removes them again afterwards.

## Unsupported images {#unsupported}

Two limits apply to images in the matrix or close to it.

### Bare BusyBox {#busybox}

A plain `busybox` image has no package manager and no CA bundle.
The build stops with exit code 2.

```console
ocx-feature: installing missing prerequisites: ca-bundle
ocx-feature: error: missing: ca-bundle, and no supported package manager was found; install them in the base image
```

The [`caBundle`](options.md#opt-caBundle) option names a PEM file in the image and satisfies the CA requirement.
The matrix therefore tests a BusyBox image with a CA bundle added.

### Wolfi and glibc detection {#wolfi}

On Wolfi the feature installs the static `musl` build of ocx.
ocx itself does not detect glibc on Wolfi, so it selects `musl` packages.
A package that exists only for glibc needs an explicit platform, such as `--platform linux/amd64+libc.glibc` or `--platform linux/arm64+libc.glibc`.

## Architectures {#architectures}

The feature supports `x86_64` and `aarch64` Linux.
Another CPU architecture or another operating system stops the build with exit code 7.
The `libc` option chooses between the `musl` and the `gnu` build for each architecture.
