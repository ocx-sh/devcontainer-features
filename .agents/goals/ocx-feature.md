# Goal: "ocx Dev Container Feature: built, tested, auto-released, documented, announced"

Source: owner discussion 2026-11-16/17, `.agents/product-context.md` · Written: 2026-11-17

## Definition of done

Each item is met only with evidence: the commit, command output, run URL or PR URL.

### Feature

- [ ] "Feature exists" — `src/ocx/devcontainer-feature.json` and a POSIX `sh`
  `install.sh`; reference `ghcr.io/ocx-sh/devcontainer-features/ocx`.
- [ ] "Options" — every required or important input of the `www-setup`
  installer and of the sibling integrations is reachable through a feature
  option. Baseline set, from `research/ocx-bootstrap-contract.md`
  § Implications: `version` (default `pinned`; proposals `pinned`, `latest`,
  `X.Y.Z`), `distUrl`, `mirrorUrl`, `caBundle`, `libc` (enum), `managedConfig`,
  `ocxHome`, `installDir`, `noUpdateCheck`, `consentPaths`, `pull` (default
  on), `groups`. Option ids are camelCase. An option with a closed value set
  uses `enum`; one with typical values uses `proposals`. Each option is
  documented and exercised by a test.
- [ ] "Installer parity table" — every `OCX_INSTALL_*` variable of
  `www-setup/src/install.sh` (`VERSION`, `DIST_URL`, `MIRROR_URL`,
  `CA_BUNDLE`, `NO_SETUP`, `DOWNLOADER`, `FORCE`, `NO_SMOKETEST`,
  `PRINT_PATH`, `QUIET`, `REPO`, and any added since) is either mapped to an
  option or listed with the reason it is not exposed. No checksum off-switch
  and no credential option exist. The table is published in the docs.
- [ ] "Locked install" — vendored `dist.json` snapshot; the archive sha256 is
  verified before extraction; static musl archive; binary at
  `/usr/local/bin/ocx`; missing downloader, CA certificates or `tar` are
  installed through the image's package manager.
- [ ] "Hooks and editor" — a lifecycle hook runs `ocx pull` when `ocx.toml`
  exists and is a no-op otherwise; `customizations.vscode.extensions`
  contains `ocx-sh.ocx`.
- [ ] "User handling" — for root, an existing non-root user, a `containerUser`
  that differs from `remoteUser`, and `_REMOTE_USER` unset: the build writes
  nothing into any home directory, `ocx` runs as the remote user, `~/.ocx`
  and `.ocx/toolchain` are owned by the remote user, and the hook runs as the
  remote user.

### Quality

- [ ] "`task lint`" — shellcheck over every script, `--shell=sh` for the
  feature scripts, any finding at any severity fails; no inline disable
  without a reason comment.
- [ ] "`task test:unit`" — bats suite against `install.sh` with stubbed
  commands, run under dash, busybox `sh` and `bash --posix`; line coverage of
  `install.sh` is at least 90 %, measured with kcov on the bash leg and
  enforced as a gate.
- [ ] "CLI-native layout" — the repository is the standard devcontainer CLI
  shape (`src/ocx/`, `test/ocx/test.sh`, `test/ocx/scenarios.json`, scenario
  scripts, the duplicate test), so `devcontainer features test`, `package`,
  `publish` and `info` work on it unmodified. Every image, scenario and run
  task is a thin wrapper over one devcontainer CLI command; no parallel
  `docker run` harness. The CLI is a pinned pnpm devDependency. `test.sh` and
  the scenario scripts are POSIX `sh` so they run on images without bash.
- [ ] "`task test:image`" — runs `devcontainer features test` for the feature
  against one base image. `IMAGE` is a required variable with the image list
  as its enum; `.taskrc.yml` sets `interactive: true`, so a terminal run
  without `IMAGE` shows a selection and a non-terminal run fails naming the
  allowed values (verified on Task 3.54.0). Images: debian, ubuntu, alpine,
  fedora, rocky, alma, ubi-minimal, amazonlinux, opensuse, arch, wolfi,
  busybox, and the mcr `devcontainers/base` images. An image the devcontainer
  CLI itself cannot drive is listed in the docs as unsupported, with the
  failing output as evidence.
- [ ] "`task test:images`" — umbrella over every image in the list; each image
  runs and reports its own result, and one failure does not hide the others.
- [ ] "`task test:scenarios`" — the `scenarios.json` suite through
  `devcontainer features test`: option combinations, the four user cases, the
  hook, and the idempotence run.
- [ ] "`task run`" — `IMAGE` and `USER` are required variables with the same
  selection prompt. Builds a throwaway dev container with the local feature
  through `devcontainer up`, opens an interactive shell as that user through
  `devcontainer exec`, and removes the container on exit.
- [ ] "`task test`" — umbrella over lint, unit, images and scenarios.
- [ ] "CI green" — `task test` green on amd64 and arm64; no
  `continue-on-error` on test jobs.

### Release

- [ ] "Unattended release" — one workflow, triggered by an hourly poll and by a
  dispatch from `ocx-sh/www-setup`: verify `dist.json` against
  `dist.json.sha256`, update the vendored copy, bump the feature patch
  version, run the test matrix, commit, publish to GHCR. A red matrix
  publishes nothing and opens an issue. Proven by one real run.
- [ ] "Dispatch wired" — `www-setup` dispatches after its `dist.json` publish;
  evidence is the `www-setup` PR and a received dispatch run here.
- [ ] "`main` protected" — a default-branch ruleset mirroring the siblings, with
  the release workflow still able to land its commit.
- [ ] "Published and listed" — GHCR packages public; the feature resolves with
  `devcontainer features info`; the `collection-index.yml` PR against
  `devcontainers/devcontainers.github.io` is open (merged is the upstream
  maintainers' call).

### Documentation and announcement

- [ ] "Conventions adopted" — `ocx-sh/conventions` template applied and the
  `fleet.toml` entry PR open.
- [ ] "Docs site" — `@ocx-sh/theme` site in this repo, deployed to
  `https://ocx.sh/integrations/devcontainer/`; `ocx-site check`, Lighthouse
  and link checks pass.
- [ ] "Docs quality" — planned with `docs-plan` (user needs, page inventory,
  coverage table), every page graded with `docs-review` with no MUST finding
  left, checks wired with `docs-instrument`. Every runnable example is backed
  by a test in the gate.
- [ ] "Use-case pages" — at least: quickstart; pin or upgrade the ocx
  version; restore the project toolchain on create; non-root and custom
  users; minimal images (Alpine, distroless-like); corporate proxy and custom
  CA; mirror and air-gapped installs; organisation-managed configuration;
  Codespaces and prebuilds; troubleshooting by symptom; an options reference
  that cannot drift from `devcontainer-feature.json` (generated or checked).
- [ ] "Feature README" — `src/ocx/README.md` and `NOTES.md` as the
  devcontainer tooling expects, so the feature reads well on containers.dev
  and in the VS Code picker.
- [ ] "Announced" — PRs open on `ocx-sh/website` (`nav.json` claim
  `/integrations/devcontainer/` and hub entry) and `ocx-sh/ocx`
  (`roadmap.md`, `integration/devcontainers-and-editors.mdx`,
  `integration/index.md`).

## Autonomy

- Prompting: never. No question waits for the owner; a doubt is resolved by
  the research files and the product context, then recorded under
  § Decisions taken.
- Granted by the owner (2026-11-17), on `ocx-sh/devcontainer-features`:
  full autonomy. That covers the first commit, commits and pushes to any
  branch including `main`, opening and merging pull requests, the `main`
  ruleset, repository settings and environments, workflow dispatch, rerun and
  cancel, publishing the feature to GHCR and setting its package visibility,
  and issues and labels.
- Granted by the owner (2026-11-17), on other repositories: open and update
  one pull request each on `ocx-sh/website`, `ocx-sh/ocx`, `ocx-sh/www-setup`,
  `ocx-sh/conventions` and `devcontainers/devcontainers.github.io`, from a
  branch or fork. Never merge there, never push to their default branches,
  never push the theme release tag. The upstream `devcontainers` pull request
  is opened only after the feature is published and its packages are public.
- Never, anywhere: force-push a shared branch, delete a published package
  version, change or read secret values, touch a repository not named here.

## Decisions taken

- Hub category for the `nav.json` entry: `build` (owner, 2026-11-17).
- Dispatch token: reuse the org-level `OCX_ANNOUNCE_TOKEN` in `www-setup`. If
  its scope excludes this repo, the hourly poll carries releases and the gap
  is reported in the final summary.

## Stop conditions

- Every item above is checked with evidence, or
- an item is blocked by something only the owner or an upstream maintainer can
  do. Then finish everything else and report the blocked items in one list.
