# Product context: ocx Dev Container Feature

Written 2026-11-17 from the owner discussion of 2026-11-16/17. Evidence for every
claim sits in `.agents/research/`; this file records the decisions.

## What this repo ships

One Dev Container Feature, `ghcr.io/ocx-sh/devcontainer-features/ocx`, that
installs the `ocx` CLI into a dev container, restores the project toolchain, and
adds the VS Code extension. It is a first-party OCX integration alongside
`find_ocx` (CMake), `rules_ocx` (Bazel) and `setup-ocx` (GitHub Actions), and
should feel like them: same option names, same pinning model.

## Who it is for

A developer or platform team that adds one line to `devcontainer.json` and
expects `ocx` and the tools from `ocx.toml` to be ready in the first terminal,
on whatever base image they already use, as whatever user the container runs.

## Decisions

1. **Broad base-image coverage, no bash requirement.** `install.sh` is POSIX
   `sh`. `ocx` ships fully static musl archives, so one binary serves every
   image. The script only falls back to the image's package manager for
   missing prerequisites (a downloader, CA certificates, `tar`). Target set:
   debian, ubuntu, alpine, fedora, rocky, alma, ubi-minimal, amazonlinux,
   opensuse, arch, wolfi, busybox, and the mcr `devcontainers/base` images.
2. **One feature version is one ocx version.** Each feature version vendors a
   locked `dist.json` snapshot (published by `ocx-sh/www-setup` at
   `https://setup.ocx.sh/dist.json`) with sha256 per archive. Option
   `version` defaults to `pinned`; `latest` is an explicit opt-in resolved at
   build time; any `x.y.z` in the vendored history is selectable.
3. **Options cover the installer surface and follow the siblings.** Every
   required or important input of the `www-setup` installer is reachable
   through a feature option: `version`, `distUrl`, `mirrorUrl`, `caBundle`
   (the `OCX_INSTALL_*` family), `libc`, `managedConfig`
   (`OCX_MANAGED_CONFIG`, synced with `ocx config setup`), `ocxHome`,
   `installDir`, `noUpdateCheck`, `consentPaths`, `pull`, `groups`. Ids are
   camelCase, with `enum` for closed value sets and `proposals` for typical
   values. There is no checksum off-switch and no credential option;
   credentials and registry maps stay with the user's `containerEnv` or the
   managed configuration.
4. **Container user and remote user are respected.** The build writes the
   binary to `/usr/local/bin/ocx` and nothing into any home directory. Each
   user keeps a private `~/.ocx`; a shared root-owned `OCX_HOME` is not used.
   Lifecycle work runs as the remote user.
5. **Project state is set up by default.** A lifecycle hook runs `ocx pull`
   when `ocx.toml` exists and is a silent no-op otherwise (`ocx pull` exits 64
   without `ocx.toml`). Option `pull` turns it off.
6. **Editor support included.** `customizations.vscode.extensions` carries
   `ocx-sh.ocx`.
7. **Releases are unattended.** A workflow polls `dist.json` hourly and also
   accepts a dispatch from `www-setup`. On a new snapshot it bumps the feature
   patch version, runs the full test matrix, commits and publishes. A red
   matrix publishes nothing and opens an issue. Feature versions are
   independent semver; a patch bump per ocx release keeps `:1` current.
8. **Quality bar.** shellcheck with every finding fatal; a bats suite with at
   least 90 % line coverage of `install.sh`; a per-image install matrix;
   `devcontainer features test` scenarios; `task run` for an interactive
   throwaway container.
9. **Documentation and announcement are part of the product.** The repo
   adopts `ocx-sh/conventions` and `@ocx-sh/theme`; docs deploy to
   `https://ocx.sh/integrations/devcontainer/`. The integration is announced
   on the ocx site hub, in the ocx docs and roadmap, and listed on
   containers.dev.

## Tooling in this repo

Tools come from `ocx.toml` (node, shellcheck, task; pnpm to be added from
`ocx.sh/pnpm/pnpm`). Skills and rules come from `grimoire.toml`. bats and
`@devcontainers/cli` are pnpm devDependencies because neither is in the ocx
catalog. Tests are bats; automation is `taskfile.yml`.

## Research index

- `research/devcontainer-feature-spec-and-distribution.md`: spec, publishing, index listing, test contract.
- `research/feature-implementation-survey.md`: how existing features are built and tested; base-image inventory.
- `research/ocx-install-surface.md`: installer, release artifacts, linkage, runtime needs.
- `research/ocx-bootstrap-contract.md`: `dist.json`, shared option names, `OCX_*` variables, hook commands.
- `research/website-theme-and-integration-announcement.md`: conventions and theme adoption, deploy, announcement touchpoints.
