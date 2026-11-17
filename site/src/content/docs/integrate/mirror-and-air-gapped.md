---
title: Install from a mirror or with no internet
description: Host the ocx release archive on an internal server, point the feature at it with mirrorUrl or distUrl, and run the container without a network.
sidebar:
  order: 2
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

This page makes a build whose runner reaches only an internal host install the same verified `ocx` binary.
You host the release archive on that host and set `mirrorUrl`.
The checksum check still runs against the digest in the release manifest.

## Know what leaves the network {#traffic}

With the default `version: "pinned"`, the build makes one request: the release archive.
The release manifest is bundled in the feature. A mirror log from a build with `mirrorUrl` set showed exactly this:

```console
GET /v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz
```

Two options add a manifest download before the archive request:

- `version: "latest"` fetches `https://setup.ocx.sh/dist.json`.
- `distUrl` fetches the manifest from the URL you give.

The base image's package manager may download missing prerequisites such as `curl` or the CA certificates. Add them to the image to avoid that traffic.
A running container fetches tools from the registries named in `ocx.toml`, which the feature does not mirror. See [Run with no network](#offline).

## Put the archive on your mirror {#mirror-layout}

The feature builds the archive URL as `<mirrorUrl>/<tag>/<filename>`.
`tag` and `filename` come from the release manifest, and the mirror serves the file over HTTPS without a login.
The build sends no credentials, and a trailing slash on `mirrorUrl` is ignored.

For ocx 0.6.8 the files are:

| Platform | Path on the mirror |
|---|---|
| x86_64, musl (default) | `v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz` |
| aarch64, musl (default) | `v0.6.8/ocx-aarch64-unknown-linux-musl.tar.gz` |

Copy the archives from the [ocx releases](https://github.com/ocx-sh/ocx/releases) for the version your feature release pins, under the tag directory.
Add the `gnu` archives, named `ocx-<arch>-unknown-linux-gnu.tar.gz`, only when you set `libc` to `gnu` or `auto`.
Serve both architectures if developers use Apple silicon machines.

## Point the build at the mirror {#mirror-url}

Set `mirrorUrl` to the base URL:

```jsonc
// doc: mirror-url
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "mirrorUrl": "https://mirror.example.com/ocx"
    }
  }
}
```

If the mirror uses a company certificate, add `caBundle` as [Trust the company CA during the build](../proxy-and-custom-ca/#ca-build) describes.
The build prints the installed version when it succeeds:

```console
ocx-feature: installed ocx 0.6.8 (x86_64-unknown-linux-musl) at /usr/local/bin/ocx
```

The archive is checked against the digest in the manifest before extraction. A mirror that serves other bytes fails the build with exit code 4:

```console
ocx-feature: error: checksum mismatch for ocx-x86_64-unknown-linux-musl.tar.gz
  expected: 96ddbd85be99542fcc3f73023103b8c0fcabe8d041a4f7e8abac697eba57d40f
  got:      20e7eddb5f587805593ddf99d049d3feb5cc9c32b5ed596f71032db4bd6e28e8
```

## Use a version outside the baked list {#dist-url}

The bundled manifest lists the releases known when the feature was published.
To install another release, host a manifest that lists it and set `distUrl`.
Copy the official manifest from `https://setup.ocx.sh/dist.json` and keep its shape. The top level holds `schema`, `latest`, `latest_next` and a `releases` list. Each row looks like this:

```json
{"version":"0.6.8","channel":"stable","tag":"v0.6.8","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"96ddbd85be99542fcc3f73023103b8c0fcabe8d041a4f7e8abac697eba57d40f","url":"https://mirror.example.com/ocx/v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz"}
```

The `url` of each row is the archive location, and `mirrorUrl` replaces it when set.
With `version: "pinned"` or `"latest"` the feature takes the first stable release the manifest lists. A value such as `"0.6.8"` selects that row.
Name the manifest after its own SHA-256 digest, and the build verifies it:

```jsonc
// doc: dist-url
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "distUrl": "https://mirror.example.com/ocx/a1bb7073094f008534be3cff654ace0995e738121b1e115857ffe48b4a428dbd.json"
    }
  }
}
```

A file name of 64 hexadecimal digits plus `.json` pins the manifest to that digest.
A manifest under any other name, such as `dist.json`, installs without a digest check, so it is as trusted as the connection that delivers it.
A pinned name whose digest does not match fails with exit code 4:

```console
ocx-feature: error: checksum mismatch for dist.json
  expected: 0000000000000000000000000000000000000000000000000000000000000000
  got:      a1bb7073094f008534be3cff654ace0995e738121b1e115857ffe48b4a428dbd
```

Both the manifest and the archive requests were visible in the mirror log of a test build with a pinned `distUrl`.

## Run with no network {#offline}

The feature needs the archive during the build, so the build host still needs the mirror.
After the image is built, the container itself can run without a network when the tools are already in the store.

Set `OCX_OFFLINE=1` in `containerEnv` to stop `ocx` from contacting any registry:

```jsonc
// doc: offline-run
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "containerEnv": {
    "OCX_OFFLINE": "1"
  }
}
```

With a warm store, `ocx exec` works. In a test container, `OCX_OFFLINE=1 ocx exec -- shfmt --version` printed `v3.13.1` and exited with 0.
With a cold store, the same command fails with exit code 79:

```console
Package 'ocx.sh/shellcheck/shellcheck:0.11.0@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379' not found in package store; attempting offline re-assembly from cache.
error: failed to find 2 packages:  ocx.sh/shellcheck/shellcheck:0.11.0@sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379 — package not found  ocx.sh/shfmt/shfmt:3.13.1@sha256:3af504ea2ef5fc6aa0b911cf19768a1287fd7bd3bc9d975216e1cee7395e09c9 — package not found
```

A store is warm once `ocx pull` has run in it, so fill it before the network goes away.
[Prebuild the container in Codespaces and CI](../codespaces-and-prebuilds/) shows how to do that when the container is created.

## Know what stays verified {#verified}

- The release archive is always checked against a SHA-256 digest from the manifest, on every mirror.
- The bundled manifest is checked against a digest recorded in the feature, and a mismatch stops the build.
- A manifest named `<sha256>.json` is checked against its own name. Any other manifest name is not checked.
- With `version: "latest"` or an unpinned `distUrl`, BusyBox `wget` cannot validate TLS, and the feature then refuses the manifest. Install `curl` or use a pinned name.

The mirror therefore cannot swap the archive for other bytes unless it also controls the manifest.
Tool packages come from the registries in `ocx.toml`, and this feature does not mirror them. [Apply organisation-managed configuration](../managed-config/) describes the configuration an organisation can apply to `ocx`.

## Next steps {#next-steps}

- [Build behind a proxy and a custom CA](../proxy-and-custom-ca/) for a network that allows GitHub only through a proxy.
- [Fix a failed feature install](../../troubleshooting/install-errors/) when the build stops with exit code 3 or 4.
