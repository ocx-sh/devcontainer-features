---
title: Fix a failed feature install
description: Match the error in a failed dev container build to its cause and fix, for downloads, checksums, platforms, prerequisites, versions and CA bundles.
sidebar:
  order: 1
---
<!-- doc_type: troubleshooting -->

The feature installs `ocx` while the image builds. When it fails, the build stops and the log shows one `ocx-feature: error:` line.
Find that line below or on [Fix a rejected option or version](./install-option-errors.md).
Every entry shows the message as the build prints it, the cause, and the fix.

The build log also ends with `did not complete successfully: exit code: N`. The code narrows the cause. [Install exit codes](../reference/environment-and-files.md#exit-codes) lists them all:

| Exit code | Meaning |
|---|---|
| 2 | A bad option, a missing tool, or a version that is not in the manifest or is too old |
| 3 | A download failed, or a redirect left HTTPS |
| 4 | A checksum did not match, or the manifest is not in the expected plain form |
| 5 | The archive could not be extracted |
| 7 | The platform is not supported |

After the container starts, see [Fix a lock or permission error](./container-errors.md), [Fix a restore warning](./restore-warnings.md) or [Fix a tool missing from the terminal](./shell-activation-errors.md).

## Error: failed to download the archive {#download-failed}

<!-- doc: ts-download-failed -->

```console
ocx-feature: download failed (attempt 1/3), retrying in 1s
ocx-feature: download failed (attempt 2/3), retrying in 2s
ocx-feature: error: failed to download https://github.com/ocx-sh/no-such-mirror/v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz
  Check the network, or use the mirrorUrl option.
```

The build exits with code 3.

This issue occurs when the build cannot fetch the release archive. The network may block the host, or the URL may answer with an error status.
The download makes three attempts and sends no credentials, so a mirror that asks for a login fails the same way.
A failed manifest download prints `failed to fetch the release manifest from <url>` instead, followed by the same exit code.
A connection that does not open within 30 seconds, or a transfer that stalls, ends an attempt without waiting for the network.

A server that redirects an HTTPS URL to a plain `http://` URL stops the build at once with exit code 3 and the message `refusing a redirect to a non-https URL`.
Point `mirrorUrl` or `distUrl` at the final HTTPS address to fix that.

A certificate the image does not trust adds a `curl` line to each attempt:

<!-- doc: ts-download-untrusted-ca -->

```console
curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)
```

In that case set `caBundle`.

To fix it:

1. Open the URL from the message in a shell on the build host. The status shows whether the host is blocked or the path is wrong.
2. If the network cannot reach GitHub, set `mirrorUrl` to a host that can. The archive must sit at `<mirrorUrl>/<tag>/<filename>`, as [Put the archive on your mirror](../integrate/mirror-and-air-gapped.md#mirror-layout) describes.
3. If a proxy is required, pass it to the build, as [Pass the proxy to the build](../integrate/proxy-and-custom-ca.md#build-proxy) describes.
4. If the host uses a company CA, point `caBundle` at the root certificate, as [Trust the company CA during the build](../integrate/proxy-and-custom-ca.md#ca-build) describes.

## Error: checksum mismatch {#checksum-mismatch}

<!-- doc: ts-checksum-mismatch -->

```console
ocx-feature: error: checksum mismatch for ocx-x86_64-unknown-linux-musl.tar.gz
  expected: 96ddbd85be99542fcc3f73023103b8c0fcabe8d041a4f7e8abac697eba57d40f
  got:      20e7eddb5f587805593ddf99d049d3feb5cc9c32b5ed596f71032db4bd6e28e8
```

The build exits with code 4. The `got` line is the digest of the file the build received, here a mirror archive with one extra byte.

This issue occurs when the downloaded archive is not the file the release manifest lists. A mirror that holds a different build, a proxy that rewrites the body, or a truncated download all cause it.
The check runs before the archive is extracted, so nothing from the file is installed.

To fix it:

1. Download the archive from the mirror and run `sha256sum` on it. Compare the result with the `expected` line.
2. Replace the file on the mirror with the archive from the [ocx releases](https://github.com/ocx-sh/ocx/releases).
3. If a proxy rewrites downloads, exempt the mirror or the GitHub release host from it.

The feature never skips this check. A mirror that serves modified bytes is refused by design.
A `distUrl` manifest that contains a backslash or repeats a key in one row also exits with code 4 and the message `release manifest is not in the expected plain form`.
Serve the manifest unchanged from the official one to fix that.

## Error: libc gnu needs glibc 2.28 or newer {#unsupported-platform}

<!-- doc: ts-unsupported-platform -->

```console
ocx-feature: error: libc: gnu needs glibc 2.28 or newer, which this image does not have; use libc: musl or auto
```

The build exits with code 7. The message above comes from `libc: "gnu"` on `alpine:3`.

This issue occurs when the options ask for a build the image cannot run. The `gnu` build needs glibc 2.28 at least. Alpine uses musl.
[Supported images](../reference/supported-images.md) lists the images that work.

Exit code 7 also covers a system other than Linux and a CPU that is neither x86_64 nor aarch64.
It covers an installed binary that does not run as well.

To fix it, remove the `libc` option or set it to `musl` or `auto`.
The default `musl` build runs on every Linux image.

<!-- doc-norun: the snippet is a fragment of a devcontainer.json, not a runnable file -->

```jsonc
// A default install, which works on Alpine as well.
"features": {
  "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
}
```

<!-- /doc-norun -->

## Error: missing a CA bundle and no package manager {#missing-prerequisite}

<!-- doc: ts-missing-prerequisite -->

```console
ocx-feature: installing missing prerequisites: ca-bundle
ocx-feature: error: missing: ca-bundle, and no supported package manager was found; install them in the base image
```

The build exits with code 2. The message above comes from the `busybox:musl` image.

This issue occurs when the image lacks a tool the install needs and has no package manager to add it.
The feature needs a downloader (`curl` or `wget`), `tar`, `gzip`, a SHA-256 tool, `mktemp` and a CA bundle.
On Debian, Ubuntu, Alpine, Fedora and other images with a package manager it installs what is missing. A bare `busybox` image has none.
The list after `missing:` names what is absent.

To fix it, choose one of these:

- Use a base image that has a package manager, such as `debian` or `alpine`.
- Add the missing tools to the image before the feature runs.
- For a missing CA bundle, copy a PEM file into the image and set `caBundle` to its path.
