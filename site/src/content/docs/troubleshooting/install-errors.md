---
title: Fix a failed feature install
description: Match the error in a failed dev container build to its cause and fix, for downloads, checksums, platforms, prerequisites, versions and CA bundles.
sidebar:
  order: 1
---
<!-- doc_type: troubleshooting -->

The feature installs `ocx` while the image builds. When it fails, the build stops and the log shows one `ocx-feature: error:` line.
Find that line below.
Every entry shows the message as the build prints it, the cause, and the fix.

The build log also ends with `did not complete successfully: exit code: N`. The code narrows the cause:

| Exit code | Meaning |
|---|---|
| 2 | A bad option, a missing tool, or a version that is not in the manifest |
| 3 | A download failed |
| 4 | A checksum did not match |
| 5 | The archive could not be extracted |
| 7 | The platform is not supported |

For a failure after the container starts, see [Fix a missing tool or failed restore](../container-errors/).

## Error: failed to download the archive {#download-failed}

<!-- doc: ts-download-failed -->

```text
ocx-feature: download failed (attempt 1/3), retrying in 1s
ocx-feature: download failed (attempt 2/3), retrying in 2s
ocx-feature: error: failed to download https://github.com/ocx-sh/no-such-mirror/v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz
  Check the network, or use the mirrorUrl option.
```

The build exits with code 3.

This issue occurs when the build cannot fetch the release archive. The network may block the host, or the URL may answer with an error status.
The download makes three attempts and sends no credentials, so a mirror that asks for a login fails the same way.
A failed manifest download prints `failed to fetch the release manifest from <url>` instead, followed by the same exit code.

To fix it:

1. Open the URL from the message in a shell on the build host. The status shows whether the host is blocked or the path is wrong.
2. If the network cannot reach GitHub, set `mirrorUrl` to a host that can. The archive must sit at `<mirrorUrl>/<tag>/<filename>`, as [Put the archive on your mirror](../../integrate/mirror-and-air-gapped/#mirror-layout) describes.
3. If a proxy is required, pass it to the build, as [Pass the proxy to the build](../../integrate/proxy-and-custom-ca/#build-proxy) describes.
4. If the host uses a company CA, point `caBundle` at the root certificate, as [Trust the company CA during the build](../../integrate/proxy-and-custom-ca/#ca-build) describes.

## Error: checksum mismatch {#checksum-mismatch}

<!-- doc: ts-checksum-mismatch -->

```text
ocx-feature: error: checksum mismatch for ocx-x86_64-unknown-linux-musl.tar.gz
  expected: 96ddbd85be99542fcc3f73023103b8c0fcabe8d041a4f7e8abac697eba57d40f
  got:      <sha256 of the downloaded file>
```

The build exits with code 4. The text comes from the feature source, and the `got` line carries the real digest of the file the build received.

This issue occurs when the downloaded archive is not the file the release manifest lists. A mirror that holds a different build, a proxy that rewrites the body, or a truncated download all cause it.
The check runs before the archive is extracted, so nothing from the file is installed.

To fix it:

1. Download the archive from the mirror and run `sha256sum` on it. Compare the result with the `expected` line.
2. Replace the file on the mirror with the archive from the [ocx releases](https://github.com/ocx-sh/ocx/releases).
3. If a proxy rewrites downloads, exempt the mirror or the GitHub release host from it.

The feature never skips this check. A mirror that serves modified bytes is refused by design.

## Error: libc gnu needs glibc 2.28 or newer {#unsupported-platform}

<!-- doc: ts-unsupported-platform -->

```text
ocx-feature: error: libc: gnu needs glibc 2.28 or newer, which this image does not have; use libc: musl or auto
```

The build exits with code 7. The message above comes from `libc: "gnu"` on `alpine:3`.

This issue occurs when the options ask for a build the image cannot run. The `gnu` build needs glibc 2.28 at least. Alpine uses musl.
Exit code 7 also covers an operating system other than Linux, a CPU that is neither x86_64 nor aarch64, and an installed binary that does not run.

To fix it, remove the `libc` option or set it to `musl` or `auto`.
The default `musl` build runs on every Linux image.

```jsonc-norun
// A default install, which works on Alpine as well.
"features": {
  "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
}
```

## Error: missing a CA bundle and no package manager {#missing-prerequisite}

<!-- doc: ts-missing-prerequisite -->

```text
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

## Error: no ocx build for that version {#version-not-found}

<!-- doc: ts-version-not-found -->

```text
ocx-feature: error: no ocx 9.9.9 build for x86_64-unknown-linux-musl in the release manifest (newest available: 0.6.8); set version: latest or distUrl to a manifest that has it
```

The build exits with code 2. The message above comes from `version: "9.9.9"`.

This issue occurs when the manifest has no release with that version. The bundled manifest lists the versions released when the feature was published.
A release made after the feature was published is missing from it, and so is a typo.

To fix it:

1. Check the version against the [ocx releases](https://github.com/ocx-sh/ocx/releases).
2. For a recent release, use `version: "latest"`, which reads the live manifest during the build, or update the feature tag.
3. Without access to the live manifest, set `distUrl`, as [Use a version outside the baked list](../../integrate/mirror-and-air-gapped/#dist-url) describes.

## Error: option caBundle is not a readable file {#ca-bundle-missing}

<!-- doc: ts-ca-bundle-missing -->

```text
ocx-feature: error: option caBundle is not a readable file: /usr/local/share/ca-certificates/corp.pem
```

The build exits with code 2.

This issue occurs when `caBundle` names a path that does not exist inside the image at the moment the feature runs.
The option takes a path in the image, not on your machine, and not the certificate text.
Features run after the base image is built, so a Dockerfile step must copy the file first.

To fix it, copy the PEM file into the image with a `COPY` line in the Dockerfile that `devcontainer.json` builds, and use that path.
[Trust the company CA during the build](../../integrate/proxy-and-custom-ca/#ca-build) shows the full setup.

## Error: option libc must be musl, gnu or auto {#invalid-option}

<!-- doc: ts-invalid-option -->

```text
ocx-feature: error: option libc must be musl, gnu or auto (got: glibc)
```

The build exits with code 2. The message above comes from `libc: "glibc"`.

This issue occurs when an option value does not pass the check that runs before anything is downloaded.
The same exit code and a message of the form `option <name> must be ...` cover `version`, `distUrl`, `mirrorUrl`, `managedConfig`, `pullGroups` and the boolean options.

To fix it, correct the value the message names. The description of each option in the feature's `devcontainer-feature.json` lists its allowed values.
