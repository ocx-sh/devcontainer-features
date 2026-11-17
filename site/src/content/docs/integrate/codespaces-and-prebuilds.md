---
title: Prebuild the container in Codespaces and CI
description: Fetch the project tools during a Codespaces prebuild or a CI container build, so a new container opens with the toolchain already in its store.
sidebar:
  order: 4
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

This page makes a prebuilt container open with the tools from `ocx.toml` already fetched.
You prove it by running `ocx exec` with `OCX_OFFLINE=1`, which works only when the store is warm.
The page assumes the repository commits both `ocx.toml` and `ocx.lock`.

## Know what a prebuild runs {#what-runs}

[Lifecycle commands](../reference/environment-and-files.md#lifecycle) lists every command the feature declares.
The feature declares two lifecycle commands, and both run as the remote user in the workspace folder:

| Command | What it does |
|---|---|
| `onCreateCommand` | Applies the managed configuration when `managedConfig` is set |
| `updateContentCommand` | Runs `ocx pull` when `pull` is on, with `-g <pullGroups>` when that option is set |

GitHub states that a prebuild performs setup "up to and including any onCreateCommand and updateContentCommand commands" in the dev container.
See [About GitHub Codespaces prebuilds](https://docs.github.com/en/codespaces/prebuilding-your-codespaces/about-github-codespaces-prebuilds).
So a prebuild runs the restore, which fetches the tools into the store in the home directory of the remote user.
The `devcontainer up --prebuild` command of the Dev Container CLI runs the same two commands and stops, which makes it a local stand-in.

## Warm the store in a Codespaces prebuild {#codespaces}

The defaults already do the work. `pull` is on, so a feature with no options restores the toolchain.
This `devcontainer.json` states the two relevant options for clarity:

```jsonc
// doc: prebuild-devcontainer-json
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "pull": true,
      "noUpdateCheck": true
    }
  }
}
```

Then enable prebuilds for the repository, as [Configuring prebuilds](https://docs.github.com/en/codespaces/prebuilding-your-codespaces/configuring-prebuilds) describes.
Commit `ocx.lock` next to `ocx.toml`. Without it the restore prints exit code 78 and fetches nothing, as [Error: ocx.lock not found](../troubleshooting/container-errors.md#lock-missing) shows.

Pull more than the default group with `pullGroups`, for example `"pullGroups": "lint,docs"`. The option takes comma-separated group names.

## Build the container in CI {#ci}

A CI job can run the same lifecycle commands with the Dev Container CLI.
This workflow builds the container, runs the restore and then checks the store without a network:

<!-- doc-norun: the workflow runs only on a GitHub runner -->

```yaml
name: container
on: pull_request
permissions:
  contents: read
jobs:
  check-container:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install the dev container CLI
        run: npm install --global @devcontainers/cli
      - name: Run the lifecycle commands
        run: devcontainer up --prebuild --workspace-folder .
      - name: Check the store is warm
        run: devcontainer exec --workspace-folder . env OCX_OFFLINE=1 ocx exec -- shfmt --version
```

<!-- /doc-norun -->

Replace `shfmt` with a tool from your `ocx.toml`.
The `actionlint` tool accepts this file.

## Keep prompts and update checks quiet {#quiet}

The options [`noUpdateCheck`](../reference/options.md#opt-noUpdateCheck) and [`consentPaths`](../reference/options.md#opt-consentPaths) keep a prebuilt container free of network calls and prompts at start:

- `noUpdateCheck` is on by default. It writes `self = "manual"` and `toolchain = "manual"` under `[update]` in `/etc/ocx/config.toml`, so `ocx` does not look for a new version.
- `consentPaths` defaults to `/workspaces/*`. A project below that path needs no prompt. The Dev Container CLI mounts the workspace there.

The file in a test container reads:

```console
[update]
self = "manual"
toolchain = "manual"

[shell.consent]
paths = ["/workspaces/*"]
```

## Check the store is warm {#verify}

After `devcontainer up --prebuild` in a project with a committed `ocx.lock`, run the tool with the network switched off for `ocx`:

```console
$ devcontainer exec --workspace-folder . env OCX_OFFLINE=1 ocx exec -- shfmt --version
v3.13.1
```

In a container whose store is empty the same command exits with code 79 and `package not found`, as [Run with no network](./mirror-and-air-gapped.md#offline) shows.
A terminal in the prebuilt container finds the tools on `PATH` as well, because a new interactive shell composes them from the lock when it starts.

## Next steps {#next-steps}

- [Fix a missing tool or failed restore](../troubleshooting/container-errors.md) when the prebuild log shows an `ocx-feature: warning:` line.
- [Build behind a proxy and a custom CA](./proxy-and-custom-ca.md) when the prebuild runner sits behind a proxy.
