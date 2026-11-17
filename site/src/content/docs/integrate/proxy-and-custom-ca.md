---
title: Build behind a proxy and a custom CA
description: Pass a proxy to the image build, trust a company root certificate, and set the proxy for ocx at run time on a network that inspects TLS.
sidebar:
  order: 1
---
<!-- doc_type: how-to -->
<!-- doc_tier: integration -->

This page makes the feature install and `ocx pull` succeed on a network with a proxy.
The network may also inspect TLS with a company certificate authority.
The build and the running container are separate network clients, so each gets its own setting.

## Know what needs the network {#traffic}

The image build contacts one host for the default install. With `version: "pinned"` the feature uses the release manifest bundled with it, so the only request is the release archive.
A test build through a proxy logged these two tunnels:

```console
CONNECT github.com:443
CONNECT release-assets.githubusercontent.com:443
```

The version `latest` and the `distUrl` option add a manifest download. Allow `setup.ocx.sh` for `latest`.
If a prerequisite such as `curl` or the CA certificates is missing, the image's package manager downloads it too, through its own proxy settings.

When the container runs, `ocx pull` fetches the tools in `ocx.toml` from the registry named in each entry. A test run with entries from `ocx.sh` logged tunnels to `ghcr.io:443` and `pkg-containers.githubusercontent.com:443`.

## Pass the proxy to the build {#build-proxy}

The install script sets no proxy of its own. It calls `curl`, which reads the proxy variables from the build environment.
Pass them as build arguments in a `devcontainer.json` that builds from a Dockerfile:

<!-- doc-norun: the build args take effect only behind a proxy, and the gate has none -->
<!-- doc: proxy-build-args -->
```jsonc
{
  "build": {
    "dockerfile": "Dockerfile",
    "args": {
      "HTTPS_PROXY": "http://proxy.example.com:3128",
      "NO_PROXY": "localhost,127.0.0.1"
    }
  },
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```
<!-- /doc-norun -->

Docker treats `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` as predefined build arguments, so the Dockerfile needs no `ARG` line for them.
The `Dockerfile` here holds one line, such as `FROM mcr.microsoft.com/devcontainers/base:ubuntu`.

## Trust the company CA during the build {#ca-build}

A proxy that inspects TLS answers with a certificate signed by your company root.
The download then fails with this line, repeated on each of the three attempts.
A connection that never opens or stalls ends the attempt after 30 to 60 seconds, so a blocked host fails fast.

```console
curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)
```

The [`caBundle`](../reference/options.md#opt-caBundle) option takes a path inside the image to a PEM file.
Feature options cannot carry a path on your machine, so copy the file into the image first.
Put the certificate next to `devcontainer.json`, name it `corp-ca.pem`, and add a `COPY` line to the Dockerfile:

```dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu
COPY corp-ca.pem /usr/local/share/ca-certificates/corp-ca.pem
```

Then name the copied path in the option:

<!-- doc: ca-bundle -->
```jsonc
{
  "build": { "dockerfile": "Dockerfile" },
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {
      "caBundle": "/usr/local/share/ca-certificates/corp-ca.pem"
    }
  }
}
```

The feature runs `curl` with `--cacert` for every download, so the file replaces the system certificates for that download.
It must therefore hold the root that signs the certificates your proxy presents.
A path that does not exist in the image stops the build with exit code 2, as [Error: option caBundle is not a readable file](../troubleshooting/install-option-errors.md#ca-bundle-missing) shows.

## Trust it when the container runs {#ca-runtime}

The same option tells `ocx` to trust the file at run time. The feature writes the path into the system configuration of `ocx`:

```console
$ cat /etc/ocx/config.toml
# Written by the ocx Dev Container Feature (id: ocx). Edits are overwritten on rebuild.

extra_ca_certs = "/usr/local/share/ca-certificates/corp-ca.pem"

[update]
self = "manual"
toolchain = "manual"

[shell.consent]
paths = ["/workspaces/*"]
```

`ocx` rejects a file larger than 32 KiB. When the bundle is larger, the build prints a warning and skips this setting, and the build-time download still uses the file.
Reduce the file to the root certificates your network needs.

An `/etc/ocx/config.toml` that the feature did not write stays untouched. In that case the feature exports `OCX_EXTRA_CA_CERTS` with the same path instead, and warns about the settings it could not apply.
The [ocx proxy and CA guide](https://github.com/ocx-sh/ocx/blob/main/website/src/content/docs/integration/proxy-and-ca.mdx) describes both settings and how they combine.

## Set the proxy for tools {#proxy-runtime}

At run time `ocx` reads the standard proxy variables: `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY` and `NO_PROXY`.
There is no ocx-specific proxy setting.
The build arguments above do not reach the running container, so set the variables in `containerEnv`:

<!-- doc-norun: the containerEnv proxy takes effect only behind a proxy, and the gate has none -->
<!-- doc: proxy-runtime-env -->
```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  },
  "containerEnv": {
    "HTTPS_PROXY": "http://proxy.example.com:3128",
    "NO_PROXY": "localhost,127.0.0.1"
  }
}
```
<!-- /doc-norun -->

## Check it works {#verify}

Build the container and read the last line of the feature output:

```console
ocx-feature: installed ocx 0.6.8 (x86_64-unknown-linux-musl) at /usr/local/bin/ocx
```

Then run the restore in the container. In a project with an `ocx.toml`, `ocx lock` fetches every tool and prints its digest:

```console
$ ocx lock
Binding     Group    Digest
shellcheck  default  sha256:3981b442fff3f6bf9ae93e4c293e53322ffc9135e0b654620bc800464bdaf379
```

The access log of the proxy shows a `CONNECT` line for each host the build and the restore reached.
If a step fails, see [Fix a failed feature install](../troubleshooting/install-errors.md) and [Fix a lock or permission error](../troubleshooting/container-errors.md).

## Next steps {#next-steps}

- [Install from a mirror or with no internet](./mirror-and-air-gapped.md) for a network that cannot reach GitHub at all.
- [Apply organisation-managed configuration](./managed-config.md) to roll these settings out to every container.
