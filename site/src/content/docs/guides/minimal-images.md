---
title: Use ocx on a minimal base image
description: Install ocx on Alpine, Debian slim, Red Hat minimal and Wolfi images, choose the libc build and move the binary to another directory.
sidebar:
  order: 4
---
<!-- doc_type: how-to -->
<!-- doc_tier: everyday -->

This page shows how to add the ocx feature to a small base image that lacks tools such as `curl`, `tar` or CA certificates.
The same one-line feature entry works on these images.

## Know what the install needs {#needs}

The install runs as root at image build and needs these tools:

- a downloader, either `curl` or `wget`
- `tar` and a way to unpack gzip archives
- a SHA-256 tool, one of `sha256sum`, `shasum` or `openssl`
- `mktemp`
- a CA certificate bundle

The [supported images](../reference/supported-images.md) page lists the tested bases.
The feature installs whatever is missing through the package manager of the image.
It supports `apt-get`, `apk`, `dnf`, `microdnf`, `yum`, `zypper` and `pacman`.
On Arch it runs `pacman -Syu --needed`, which upgrades the image's packages as part of the install.
It prints one line that names the missing tools.

```console
ocx-feature: installing missing prerequisites: curl-or-wget ca-bundle
```

An image with no package manager and a missing tool stops the build with exit code 2.
The message lists the missing tools and asks you to install them in the base image.

## Add ocx to Alpine {#alpine}

Use the same entry.
Alpine has BusyBox `wget`, so the feature uses it and prints a warning.

<!-- doc: image-alpine -->
```jsonc
{
  "image": "alpine:3",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

```console
ocx-feature: warning: BusyBox wget: no TLS floor and the server certificate may go unchecked; install curl for a verified download
ocx-feature: installed ocx 0.6.8 (x86_64-unknown-linux-musl) at /usr/local/bin/ocx
```

To get a verified download, add `curl` to the image before the feature runs.
The archive checksum is verified in either case.

The same entry works on `debian:stable-slim`.
It installs `curl` and the CA certificates first, as the prerequisites line above shows.

<!-- doc: image-debian-slim -->
```jsonc
{
  "image": "debian:stable-slim",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

Packages that exist only for glibc do not install on Alpine.
For example, locking Node.js on Alpine stops with this message.

<!-- doc-norun: the output was recorded from a real run of ocx lock on alpine:3 -->
```console
error: no 'linux/amd64+libc.musl' leaf for binding 'node' at the locked version; run `ocx update` to re-resolve if it has since been added
```
<!-- /doc-norun -->

## Add ocx to a minimal Red Hat image {#ubi-minimal}

The `ubi9/ubi-minimal` image has `microdnf` and no `tar` or `gzip`.
The feature installs both and then installs ocx.

<!-- doc: image-ubi-minimal -->
```jsonc
{
  "image": "registry.access.redhat.com/ubi9/ubi-minimal",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

```console
ocx-feature: installing missing prerequisites: tar gzip
```

## Add ocx to Wolfi or BusyBox {#wolfi-busybox}

On `cgr.dev/chainguard/wolfi-base` the feature installs `curl` through `apk`, and the entry is the same as above.

<!-- doc: image-wolfi -->
```jsonc
{
  "image": "cgr.dev/chainguard/wolfi-base",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

On Wolfi, ocx itself does not detect glibc.
Install a glibc-only package there with `--platform linux/<arch>+libc.glibc`.

A bare `busybox` image has no package manager and no CA bundle.
Point the [`caBundle` option](../reference/options.md#opt-caBundle) at a PEM file that you copy into the image, and install the other tools yourself.
[Build behind a proxy and a custom CA](../integrate/proxy-and-custom-ca.md#ca-build) shows the `COPY` line.

## Choose the libc build {#libc}

The [`libc` option](../reference/options.md#opt-libc) picks the build of the ocx binary.

| Value | Binary | Use |
|---|---|---|
| `musl` | Static, runs on every Linux image | The default |
| `gnu` | Needs glibc 2.28 or newer | Images with a current glibc |
| `auto` | `gnu` when the image has glibc 2.28 or newer, otherwise `musl` | Images that vary |

On a Debian image with the default value, `ldd /usr/local/bin/ocx` prints `statically linked`.
With `gnu` on a Debian image, it lists the system libraries instead.
If the image lacks glibc 2.28, `gnu` stops the build with exit code 7 and the hint to use `musl` or `auto`.

<!-- doc: libc-gnu -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "libc": "gnu"
    }
  }
}
```

## Install to another directory {#install-dir}

The [`installDir` option](../reference/options.md#opt-installDir) sets the directory that receives the binary.
The directory must be on `PATH` for every user.

<!-- doc: install-dir -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "installDir": "/usr/local/sbin"
    }
  }
}
```

In this container `command -v ocx` prints `/usr/local/sbin/ocx`.
With a directory that is not on `PATH`, such as `/opt/ocx/bin`, the shell prints `ocx: not found`.
The binary then runs only through its full path, `/opt/ocx/bin/ocx version`.

## Next steps {#next-steps}

- [Add ocx to a dev container](../quickstart.md) is the first-run walk-through.
- [Pin or upgrade the ocx version](pin-or-upgrade-version.md) sets the ocx version on any image.
- [Fix a failed feature install](../troubleshooting/install-errors.md#missing-prerequisite) matches the missing-tool message to its fix.
