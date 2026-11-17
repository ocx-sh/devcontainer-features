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

## Supported images

The feature supports Debian, Ubuntu, Alpine and other common Linux base images on amd64 and arm64.
