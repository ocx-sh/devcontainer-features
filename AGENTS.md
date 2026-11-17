# devcontainer-features

This repository builds, tests, documents and releases the `ocx` Dev Container Feature, `ghcr.io/ocx-sh/devcontainer-features/ocx`.
The feature installs the `ocx` package manager into a dev container image and restores the project toolchain from `ocx.toml`.
Developers and platform teams add it to a `devcontainer.json`, and maintainers work in this repository.

## Purpose

The repository owns the feature scripts, their tests, the docs site and the unattended release.
One feature version pins one ocx version, and a scheduled workflow publishes a new feature version for each ocx release.
Out of scope are the ocx CLI itself (`ocx-sh/ocx`), the official installer (`ocx-sh/www-setup`) and the site theme (`ocx-sh/website`).
User documentation lives in `site/src/content/docs` and follows the docs-quality rules in `.claude/rules/docs-quality.md`.

## Setup

```sh
ocx exec -- task setup
```

Pulls every tool from `ocx.toml`, installs the grim client directories and arms the git hooks. Re-running it is a no-op.

## Verify

```sh
ocx exec -- task verify
```

The same gate CI runs: `ci:lint`, `ci:test` and `ci:docs`. Only `ci:build` is still a stub in `taskfile.yml`, because the feature has no build step.

## Layout

- `src/ocx`: the feature itself, `devcontainer-feature.json`, `install.sh`, `configure.sh`, `hook.sh`, `lib.sh`, the vendored `dist.json` and the `NOTES.md` that feeds the generated `README.md`.
- `test/unit`: Bats unit tests that run on dash, busybox sh and bash.
- `test/ocx`: the `test.sh` that `devcontainer features test` runs inside the built container, plus its assertion helper.
- `test/docs`: `bindings.json`, one binding per `<!-- doc: key -->` example on a page, naming the test that backs it. `site/scripts/check-doc-bindings.mjs` fails on an unbound key, a missing test or a fence that drifted from its test, and runs in `task site:docs`.
- `test/images`: the base-image matrix runner, a BusyBox image with a CA bundle and the known limits. `test/images.txt` lists the images.
- `scripts`: maintenance scripts for lint, the README, the manifest update, the version bump and the installer parity check.
- `scripts/release`: the unattended release steps, which detect, prepare, verify, publish and report.
- `site`: the Astro and Starlight docs site. Pages are in `site/src/content/docs`.
- `taskfiles`: the task definitions, included flat from `taskfile.yml`.
- `.github/workflows`: CI verify, release and site deploy workflows.
- `.agents`: agent working files such as goals, discovery notes and retro entries. They are not published.

## Baseline

This repo follows the [ocx-sh/conventions](https://github.com/ocx-sh/conventions) baseline, rendered by copier (`.copier-answers.yml`).
Template-owned files (`taskfiles/baseline.taskfile.yml`, `.pre-commit-config.yaml`, `cliff.toml`, `renovate.json`, `CLAUDE.md`, `.github/workflows/verify-*.yml`, ...) must never be hand-edited: change ocx-sh/conventions, then run `ocx exec -- task copier:update`. `task baseline:check` fails on drift.
