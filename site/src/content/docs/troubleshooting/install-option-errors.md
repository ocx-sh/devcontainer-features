---
title: Fix a rejected option or version
description: Match a build error about an option value, a version or a CA bundle path to its cause and fix.
sidebar:
  order: 2
---
<!-- doc_type: troubleshooting -->

The feature checks its options before it downloads anything. A bad value stops the build with exit code 2 and one `ocx-feature: error:` line.
Find that line below.
Every entry shows the message as the build prints it, the cause, and the fix.

For a download, checksum or platform failure, see [Fix a failed feature install](./install-errors.md).

## Error: no ocx build for that version {#version-not-found}

<!-- doc: ts-version-not-found -->

```console
ocx-feature: error: no ocx 9.9.9 build for x86_64-unknown-linux-musl in the release manifest (newest available: 0.6.8); set version: latest or distUrl to a manifest that has it
```

The build exits with code 2. The message above comes from `version: "9.9.9"`.

This issue occurs when the manifest has no release with that version. The bundled manifest lists the versions released when the feature was published.
A release made after the feature was published is missing from it, and so is a typo.

To fix it:

1. Check the version against the [ocx releases](https://github.com/ocx-sh/ocx/releases).
2. For a recent release, use `version: "latest"`, which reads the live manifest during the build, or update the feature tag.
3. Without access to the live manifest, set `distUrl`, as [Use a version outside the baked list](../integrate/mirror-and-air-gapped.md#dist-url) describes.

## Error: option caBundle is not a readable file {#ca-bundle-missing}

<!-- doc: ts-ca-bundle-missing -->

```console
ocx-feature: error: option caBundle is not a readable file: /usr/local/share/ca-certificates/corp.pem
```

The build exits with code 2.

This issue occurs when `caBundle` names a path that does not exist inside the image at the moment the feature runs.
The option takes a path in the image, not on your machine, and not the certificate text.
Features run after the base image is built, so a Dockerfile step must copy the file first.

To fix it, copy the PEM file into the image with a `COPY` line in the Dockerfile that `devcontainer.json` builds, and use that path.
[Trust the company CA during the build](../integrate/proxy-and-custom-ca.md#ca-build) shows the full setup.

## Error: option libc must be musl, gnu or auto {#invalid-option}

<!-- doc: ts-invalid-option -->

```console
ocx-feature: error: option libc must be musl, gnu or auto (got: glibc)
```

The build exits with code 2. The message above comes from `libc: "glibc"`.

This issue occurs when an option value does not pass the check that runs before anything is downloaded.
The same exit code and a message of the form `option <name> must be ...` cover `version`, `distUrl`, `mirrorUrl`, `managedConfig`, `pullGroups` and the boolean options.

To fix it, correct the value the message names. [Options](../reference/options.md) lists every option with its allowed values.
