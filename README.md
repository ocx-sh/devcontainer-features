<!-- doc_type: readme -->

# ocx Dev Container Feature

This repository ships a Dev Container Feature that installs the [`ocx`](https://github.com/ocx-sh/ocx) package manager in a dev container and restores the tools your project pins in `ocx.toml`.
It is for developers who work in dev containers or Codespaces, and for platform teams that standardise those containers.

## Usage

Add one line to the `features` object of your `devcontainer.json`, then rebuild the container.

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/ocx-sh/devcontainer-features/ocx:1": {}
  }
}
```

Each feature release pins one ocx version, so the tag `:1` follows ocx and `:1.0.0` freezes it.
The feature installs on common Debian, Ubuntu, Alpine, Fedora, Red Hat, SUSE, Arch and Wolfi images for amd64 and arm64.
[`test/images.txt`](test/images.txt) lists the tested base images.

## Documentation

The documentation lives at <https://ocx.sh/integrations/devcontainer/>.
The pages are Markdown files under [`site/src/content/docs`](https://github.com/ocx-sh/devcontainer-features/tree/main/site/src/content/docs), so you can read them on GitHub as well.
Start with the quickstart, then see the options reference and the page on what the feature trusts.

## Development

Every command runs through `ocx exec`, which provides the pinned tools.
Docker is required for the image and scenario tests.

```sh
ocx exec -- task setup                          # pull the tools and arm the git hooks
ocx exec -- task lint                           # ShellCheck and shfmt
ocx exec -- task test:unit                      # unit suite on dash, busybox sh and bash
ocx exec -- task test:image IMAGE=alpine        # one base image from test/images.txt
ocx exec -- task test:images                    # every base image
ocx exec -- task test:scenarios                 # the scenario suite
ocx exec -- task test                           # unit, images and scenarios
ocx exec -- task run IMAGE=debian RUN_AS=vscode # throwaway container with the local feature
```

`IMAGE` is an alias from `test/images.txt`, and `RUN_AS` is the user of the interactive shell.
`ocx exec -- task verify` runs the same gate as CI.
[`AGENTS.md`](AGENTS.md) describes the layout.

## Releases

A scheduled workflow checks for a new ocx release and, when there is one, publishes one new feature version that pins it.
No person starts or approves the release.
The [changelog](CHANGELOG.md) lists every feature version and the ocx version it pins.

## License

Apache License 2.0, see [`LICENSE`](LICENSE).
