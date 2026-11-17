---
title: Fix a tool missing from the terminal
description: Match a project tool that is not on PATH in a new terminal to its cause, a project outside consentPaths or an activation that has not run, and fix it.
sidebar:
  order: 4
---
<!-- doc_type: troubleshooting -->

The container started and the restore worked, but a project tool is missing from `PATH` in a terminal.
Find the message below.
Every entry shows the message as the shell prints it, the cause, and the fix.

A new interactive shell activates a project only when the project lies under a [`consentPaths`](../reference/options.md#opt-consentPaths) entry.
The shell reads the project once, when it starts.
`ocx exec -- <command>` finds the project tools in every case.
For a warning printed during container creation, see [Fix a lock or permission error](./container-errors.md) or [Fix a restore warning](./restore-warnings.md).

## Error: the tool is not on PATH outside consentPaths {#outside-consent-paths}

<!-- doc: ts-outside-consent-paths -->
```console
bash: shfmt: command not found
```

This issue occurs when the project directory is not under a `consentPaths` entry.
The default entry is `/workspaces/*`, so a project in `/tmp`, in your home directory or in a mount elsewhere does not activate.
The shell runs no `ocx` command for it and leaves `PATH` unchanged.
The tools are still locked and present, and `ocx exec` runs them:

```console
$ ocx exec -- shfmt --version
v3.13.1
```

To fix it, use one of these:

- Run the tool through `ocx exec -- <command>`, or open a shell in the project environment with `ocx shell`.
- Move the project below `/workspaces`.
- Add the project path to `consentPaths` and rebuild the container.

A plain path matches that directory only, and `dir/*` matches the directory and everything below it.
Any other use of `*` matches nothing, and an empty `consentPaths` activates nothing.
This setting lets the project's `ocx.toml` shape every new shell in that directory, so [What the feature trusts](../concepts/trust-model.md#activation) says what to weigh first.

<!-- doc: ts-consent-paths-added -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "consentPaths": "/workspaces/*:/tmp/proj"
    }
  }
}
```

After the rebuild, a new terminal started in `/tmp/proj` finds the tool.

```console
$ bash -ic 'shfmt --version'
v3.13.1
```

## Error: command not found in a terminal inside the project {#command-not-found}

<!-- doc: ts-command-not-found -->
```console
bash: shfmt: command not found
```

This issue occurs when the project is under `consentPaths` but the shell did not compose the tools.
Three causes are common.
The lock is missing or stale, as [Error: ocx.lock not found](./container-errors.md#lock-missing) and [Error: ocx.lock is stale](./container-errors.md#lock-stale) show.
The terminal started before `ocx lock` or `ocx pull` finished, or before the project existed.
Or `shellActivation` is `false`, so no shell gets the toolchain.

The feature composes `PATH` once, when an interactive shell starts in the project.
A terminal that is already open does not change after `ocx add` or `ocx pull`, and `cd` into the project does not activate it.
With `pullGroups` set, only those groups are on `PATH`, and a named list replaces the default group.

To fix it:

1. Open a new terminal after the lock and the tools are in place.
2. Run the tool through `ocx exec`, which always works: `ocx exec -- shfmt --version`.
3. If the option is off, remove `"shellActivation": false` from `devcontainer.json` and rebuild.

```console
$ ocx exec -- shfmt --version
v3.13.1
```

With `shellActivation` set to `false`, `command -v shfmt` prints nothing and exits with status 1, while the `ocx exec` call still prints `v3.13.1`.
A script run with `sh -lc` is not an interactive shell either, so use `ocx exec` there.
