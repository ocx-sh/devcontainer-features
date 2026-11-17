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
