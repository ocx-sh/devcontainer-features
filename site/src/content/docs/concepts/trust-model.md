---
title: What the feature trusts
description: What the ocx Dev Container Feature trusts at build time and in new shells, what the defaults allow, and how to tighten them.
sidebar:
  order: 2
---
<!-- doc_type: explanation -->

This page explains which sources the ocx Dev Container Feature trusts, what the defaults allow and how to tighten them.
It matters when the repositories you open are not all yours, or when a build must be reproducible.

## What activates without a prompt {#activation}

A new interactive shell puts a project's tools on `PATH` only when the project directory lies under one of the [`consentPaths`](../reference/options.md#opt-consentPaths) entries.
Activation also applies the `[env]` table of the project's `ocx.toml`, so the project file decides what a shell gets.
The default entry is `/workspaces/*`, so every project under the workspace mount activates without a prompt.

The dev container already runs the workspace repository's own lifecycle commands, so this grants that repository nothing new.
It also covers any other repository you clone below `/workspaces`.
Its `ocx.toml` then shapes every new shell that starts inside it.
Outside the listed paths nothing activates, and you run tools with `ocx exec -- <command>` or open a shell with `ocx shell`.

## Tighten activation {#tighten}

Three settings narrow the grant, from a smaller list to none:

- A narrower `consentPaths` list names only the projects you trust.
- An empty `consentPaths` activates nothing.
- `shellActivation: false` writes no activation code at all.

A plain path matches that directory only, and `dir/*` matches `dir` and everything below it.
Any other use of `*` matches nothing.
This example trusts one project directory and nothing else under `/workspaces`.

<!-- doc: trust-narrow-consent -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "consentPaths": "/workspaces/app"
    }
  }
}
```

A tool that stays off `PATH` for this reason is the subject of [Error: the tool is not on PATH outside consentPaths](../troubleshooting/shell-activation-errors.md#outside-consent-paths).

## What the install trusts {#install}

The default `version: "pinned"` verifies the archive against a checksum bundled in the feature.
The trust anchor is the feature package you pulled, so the next section says how to pin it.
The bundled manifest also carries its own digest, but that digest ships in the same package.
It detects corruption and cannot detect a swapped package.

Two options move the trust anchor to a web server:

- `version: "latest"` reads the live manifest from `https://setup.ocx.sh/dist.json`.
- A plain `distUrl` reads the manifest from the URL you give.

Both trust the HTTPS endpoint that serves the manifest, because the archive checksum comes from that manifest.
A `mirrorUrl` changes only where the archive comes from, and the checksum still comes from the manifest.
[How the install works](how-the-install-works.md#verification) lists the checks the build runs on every download.

## Pin the supply chain {#pin}

Where the supply chain matters, remove every moving part:

- Pin the feature by an exact version such as `ocx:1.0.0`, or by digest with `ocx@sha256:<digest>`.
- Name a `distUrl` manifest after its own SHA-256 digest, as [Use a version outside the baked list](../integrate/mirror-and-air-gapped.md#dist-url) shows.
- Pin `managedConfig` to a digest with `@sha256:<digest>`, as [Apply organisation-managed configuration](../integrate/managed-config.md#trust) shows.

## Related pages {#related}

- [Options](../reference/options.md) describes every setting named here.
- [How the install works](how-the-install-works.md) lists what the build does and never does.
- [Files, environment and exit codes](../reference/environment-and-files.md#profile) shows the generated shell profile.
