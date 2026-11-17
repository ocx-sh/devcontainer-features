
# ocx (ocx)

Installs the ocx package manager and restores the project toolchain from ocx.toml.

## Example Usage

```json
"features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Which ocx to install. 'pinned' is the ocx version this feature release was tested with, 'latest' is the newest stable release at build time, or give an exact version such as 1.2.3. | string | pinned |
| libc | C library flavour of the ocx binary. 'musl' runs on every Linux image, 'gnu' needs glibc, 'auto' picks the one the image uses. | string | musl |
| distUrl | HTTPS URL of a release manifest that replaces the bundled one. Empty uses the manifest shipped with this feature. | string | - |
| mirrorUrl | HTTPS base URL to download release archives from, for networks that cannot reach GitHub. Empty downloads from the official release location. | string | - |
| caBundle | Path inside the image to a PEM CA bundle. It is used for downloads at build time and by ocx at run time. Empty uses the system certificates. | string | - |
| managedConfig | OCI reference of an organisation-managed ocx configuration. Empty installs no managed configuration. | string | - |
| ocxHome | Sets OCX_HOME for all users. Empty keeps the default ~/.ocx for each user. | string | - |
| installDir | Directory that receives the ocx binary. It must be on PATH. | string | /usr/local/bin |
| noUpdateCheck | Turn off the ocx update check, so the container makes no network call just to look for a new ocx. | boolean | true |
| consentPaths | Colon-separated absolute paths. A project there activates in new shells and ocx grants consent without a prompt. A trailing /* covers the path and below. Empty activates nothing. | string | /workspaces/* |
| pull | Restore the project toolchain from ocx.toml when the container is created. | boolean | true |
| pullGroups | Comma-separated tool groups to restore and to put on PATH in new shells. Empty means the default group only. | string | - |
| shellActivation | Put the project toolchain on PATH in new interactive shells, for projects under consentPaths only. | boolean | true |

## Customizations

### VS Code Extensions

- `ocx-sh.ocx`

## What it does

This feature installs the `ocx` package manager into your dev container.
It then restores the toolchain declared in your project's `ocx.toml`.

## Usage

```jsonc
"features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
}
```

Each feature release pins one tested ocx version. See <https://ocx.sh/integrations/devcontainer/> for every option and example.

## Trust

Shell activation applies a project's `[env]` table and tool paths, so it only runs for projects under `consentPaths`.
The default `/workspaces/*` activates every project under the workspace mount without a prompt.
The dev container already runs that repository's own lifecycle commands, so this grants the workspace repository nothing new.
It also covers other repositories cloned below `/workspaces`.
Set `consentPaths` to a narrower path, or to empty, to tighten this. Elsewhere, run `ocx exec`, `ocx shell` or `ocx shell allow`.
When the supply chain matters, pin the feature by digest and prefer a digest-pinned `distUrl` and `managedConfig`.
`version: latest` and a plain `distUrl` trust the HTTPS endpoint that serves the manifest.

## Supported images

The feature supports Debian, Ubuntu, Alpine and other common Linux base images on amd64 and arm64.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ocx-sh/devcontainer-features/blob/main/src/ocx/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
