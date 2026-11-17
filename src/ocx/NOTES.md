## What it does

This feature installs the `ocx` package manager into your dev container.
When the container is created, it restores the toolchain that your project's `ocx.toml` and `ocx.lock` declare.
New interactive shells in a project put those tools on `PATH`, and `ocx exec -- <command>` runs them anywhere.

## Usage

```jsonc
"features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
}
```

Each feature release pins one tested ocx version, so `ocx:1` follows ocx and `ocx:1.0.0` freezes it.
The pages at <https://ocx.sh/integrations/devcontainer/> describe every option and example.

The options most projects look at:

- `version` selects `pinned` (the default), `latest` or an exact ocx version.
- `pullGroups` restores more than the default tool group, for example `"default,ci"`.
- `consentPaths` lists the paths whose projects activate in new shells.
- `caBundle`, `mirrorUrl` and `distUrl` serve networks with a company certificate, a mirror or no GitHub access.
- `managedConfig` applies an organisation-managed ocx configuration.

## Trust

Shell activation applies a project's `[env]` table and tool paths, so it only runs for projects under `consentPaths`.
The default `/workspaces/*` activates every project under the workspace mount without a prompt.
The dev container already runs that repository's own lifecycle commands, so this grants the workspace repository nothing new.
It also covers other repositories cloned below `/workspaces`.
Set `consentPaths` to a narrower path, or to empty, to tighten this. Elsewhere, run `ocx exec`, `ocx shell` or `ocx shell allow`.
`shellActivation: false` removes the activation code entirely.

The default pinned install verifies the archive against the checksum bundled in the feature.
`version: latest` and a plain `distUrl` trust the HTTPS endpoint that serves the manifest.
The bundled manifest's own digest check only detects corruption.
When the supply chain matters, pin the feature by version or digest, and prefer a digest-pinned `distUrl` and `managedConfig`.

## Supported images

The feature supports Debian, Ubuntu, Alpine, Fedora, Red Hat, SUSE, Arch and Wolfi base images on amd64 and arm64.
It installs a missing downloader, `tar`, `gzip` and CA certificates through the image's package manager.

## Limits

- A bare `busybox` image has no package manager and no CA bundle, so it needs the `caBundle` option and the other tools in the image.
- Activation happens only in new interactive shells, once at shell start. An open terminal does not refresh after `ocx add`.
- Non-interactive shells such as `sh -lc` get no activation, so use `ocx exec -- <command>` there.
- On Wolfi, ocx does not detect glibc, so a glibc-only package needs `--platform linux/<arch>+libc.glibc`.
