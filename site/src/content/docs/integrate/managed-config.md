---
title: Apply organisation-managed configuration
description: Point every dev container at an organisation-managed ocx configuration with the managedConfig option, and know what happens when it cannot be fetched.
sidebar:
  order: 3
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

This page makes a new container adopt the managed `ocx` configuration your organisation publishes as an OCI package.
A managed configuration is a settings package that a platform team publishes once and every machine follows.
The [ocx documentation on managed configuration](https://github.com/ocx-sh/ocx/blob/main/website/src/content/docs/explanation/managed-configuration.md) explains how to publish one and what it may contain.

## Set the managed configuration {#set}

Give the [`managedConfig`](../reference/options.md#opt-managedConfig) option the OCI reference of the package:

<!-- doc: managed-config -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "managedConfig": "registry.example.com/acme/fleet:1"
    }
  }
}
```

The option accepts letters, digits and the characters `. _ : / @ -`, and it must not start with `-`. Any other value stops the build with exit code 2.
A reference with a digest, such as `registry.example.com/acme/fleet@sha256:<digest>`, passes that check.

The build records the source in the system configuration of `ocx`. The block in `/etc/ocx/config.toml` reads:

```console
[managed]
source = "registry.example.com/acme/fleet:1"
required = false
```

The `required = false` line means a container that cannot reach the source still starts.

## Sync it when the container starts {#sync}

The build only records the source. The package is fetched when the container is created.
The feature's `onCreateCommand` runs this command as the remote user:

```console
$ ocx config setup --managed-config registry.example.com/acme/fleet:1
```

The command downloads the package, stores a snapshot and then records the source as a `[managed]` seed.
It needs a network path to the registry, and the proxy settings from [Build behind a proxy and a custom CA](./proxy-and-custom-ca.md) apply to it.
To read the state afterwards, run `ocx config update --check`. In a container with no managed source it reports `not_configured`:

```console
$ ocx config update --check
Field   Value
Status  not_configured
```

## Set only the variable {#env-only}

`ocx` also reads the source from the environment variable `OCX_MANAGED_CONFIG`. A bare `ocx config setup` uses it when no `--managed-config` flag is given.
Without the `managedConfig` option, the feature runs nothing at creation, so the variable alone fetches nothing:

<!-- doc: managed-config-env -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "containerEnv": {
    "OCX_MANAGED_CONFIG": "registry.example.com/acme/fleet:1"
  },
  "postCreateCommand": "ocx config setup"
}
```

With neither the variable, the flag nor a recorded source, `ocx config setup` exits with code 64:

```console
error: nothing to set up: pass --managed-config <REF>, set OCX_MANAGED_CONFIG, or configure a [managed] seed
```

## When the configuration cannot be fetched {#unsynced}

A source that cannot be fetched does not stop the container. The sync prints one warning and the create step continues.
With `managedConfig` set to an address that serves nothing, the create log shows:

<!-- doc: managed-config-unreachable -->

```console
error: failed to sync the managed-config snapshot: failed to fetch managed config: ... could not connect to 'localhost:9' over https ...
ocx-feature: warning: ocx config setup failed with exit code 75.
  attempted: /usr/local/bin/ocx config setup --managed-config localhost:9/acme/fleet:1
  fix: check the network, mirror and proxy settings, then rerun the container command
```

The exit code names the cause. Code 75 is a network failure, and 69 or 79 mean the registry or the package was not found.
Code 64 means the source was empty. The container runs without the managed settings until a later `ocx config setup` succeeds.

The feature always writes `required = false`. It has no option to make the configuration mandatory.
A container that must not start without the managed settings needs a check of its own. `ocx config update --check` reports the status but exits with 0 even when nothing is configured.
[Fix a restore warning](../troubleshooting/restore-warnings.md#config-not-synced) lists the fixes.

## Know whom you trust {#trust}

A managed configuration changes how `ocx` behaves in every container that adopts it.
Whoever can publish to the reference controls those settings.
Restrict write access to the repository, and pin the reference to a digest where the tag must not move.
[What the feature trusts](../concepts/trust-model.md#pin) lists the other settings to pin.

An `/etc/ocx/config.toml` that the feature did not write is never changed.
The feature then skips the managed source and prints a warning that names it as not applied.

## Next steps {#next-steps}

- [Build behind a proxy and a custom CA](./proxy-and-custom-ca.md) when the registry sits behind a proxy.
- [Install from a mirror or with no internet](./mirror-and-air-gapped.md) for the build-time download.
- [Options](../reference/options.md#opt-managedConfig) describes `managedConfig`.
- [Fix a restore warning](../troubleshooting/restore-warnings.md#config-not-synced) matches the sync warning to its fix.
