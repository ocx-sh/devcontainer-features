# Goal: "ocx Dev Container Feature: built, tested, auto-released, documented, announced"

Source: owner discussion 2026-11-16/17, `.agents/product-context.md` · Written: 2026-11-17

## Definition of done

Each item is met only with evidence: the commit, command output, run URL or PR URL.

### Feature

- [x] "Feature exists" — `src/ocx/devcontainer-feature.json` and a POSIX `sh`
  `install.sh`; reference `ghcr.io/ocx-sh/devcontainer-features/ocx`.
  Evidence 2026-11-17: manifest [f0cc669](https://github.com/ocx-sh/devcontainer-features/commit/f0cc669) ([#3](https://github.com/ocx-sh/devcontainer-features/pull/3)), `install.sh` [0bc701e](https://github.com/ocx-sh/devcontainer-features/commit/0bc701e) ([#6](https://github.com/ocx-sh/devcontainer-features/pull/6), `#!/bin/sh`, 235 unit tests green on dash, busybox sh and `bash --posix`). `devcontainer up` with the local feature on `mcr.microsoft.com/devcontainers/base:debian`: `ocx version` prints `0.6.8`.
- [x] "Options" — every required or important input of the `www-setup`
  installer and of the sibling integrations is reachable through a feature
  option. Baseline set, from `research/ocx-bootstrap-contract.md`
  § Implications: `version` (default `pinned`; proposals `pinned`, `latest`,
  `X.Y.Z`), `distUrl`, `mirrorUrl`, `caBundle`, `libc` (enum), `managedConfig`,
  `ocxHome`, `installDir`, `noUpdateCheck`, `consentPaths`, `pull` (default
  on), `groups`. Option ids are camelCase. An option with a closed value set
  uses `enum`; one with typical values uses `proposals`. Each option is
  documented and exercised by a test.
  Evidence 2026-11-17: 13 camelCase options in `src/ocx/devcontainer-feature.json` (`libc` is an `enum`, `version` has `proposals`; the group option is `pullGroups`, see Decisions taken; `shellActivation` added). Every option is exercised by a scenario ([#15](https://github.com/ocx-sh/devcontainer-features/pull/15): version-exact, version-latest, libc-gnu, libc-auto-alpine, libc-auto-debian, dist-url, dist-url-digest, mirror-url, ca-bundle, managed-config, ocx-home, install-dir, no-update-check-off, consent-custom, consent-empty, pull-off, pull-groups, shell-activation-off) and documented in `site/src/content/docs/reference/options.md`, whose table is generated from the manifest. Own run `task test:scenarios`: 34 of 34 pass; a unit test fails when `install.sh` and the manifest disagree on options or defaults.
- [x] "Installer parity table" — every `OCX_INSTALL_*` variable of
  `www-setup/src/install.sh` (`VERSION`, `DIST_URL`, `MIRROR_URL`,
  `CA_BUNDLE`, `NO_SETUP`, `DOWNLOADER`, `FORCE`, `NO_SMOKETEST`,
  `PRINT_PATH`, `QUIET`, `REPO`, and any added since) is either mapped to an
  option or listed with the reason it is not exposed. No checksum off-switch
  and no credential option exist. The table is published in the docs.
  Partial 2026-11-17: `src/ocx/installer-parity.json` and `scripts/check-installer-parity.sh` in [98f1af0](https://github.com/ocx-sh/devcontainer-features/commit/98f1af0) ([#4](https://github.com/ocx-sh/devcontainer-features/pull/4)); own run `task parity:check` prints `parity ok: 16 installer variables match` against the live installer. Open: the docs page.
  Evidence 2026-11-17: `src/ocx/installer-parity.json` ([#4](https://github.com/ocx-sh/devcontainer-features/pull/4)) lists all 16 `OCX_*` variables of the official installer as exposed, fixed or not exposed, with reasons; `task parity:check` against the live installer prints `parity ok: 16 installer variables match`; published as `site/src/content/docs/reference/installer-parity.md`, generated from the JSON ([#8](https://github.com/ocx-sh/devcontainer-features/pull/8)). The manifest has no checksum switch and no credential option.
- [x] "Locked install" — vendored `dist.json` snapshot; the archive sha256 is
  verified before extraction; static musl archive; binary at
  `/usr/local/bin/ocx`; missing downloader, CA certificates or `tar` are
  installed through the image's package manager.
  Evidence 2026-11-17: vendored `src/ocx/dist.json` + `.sha256` ([416c577](https://github.com/ocx-sh/devcontainer-features/commit/416c577)); checksum before extraction (unit test `checksum mismatch exits 4 and tar is never called`); default `libc: musl`; `test/ocx/test.sh` asserts `ocx is /usr/local/bin/ocx, mode 0755, owned by root` on all 15 base images, including `debian:stable-slim` and `ubuntu:24.04`, where the build installs `curl` and CA certificates through apt (own run `task test:images`: 15 of 15 pass; CI [44004846343](https://github.com/ocx-sh/devcontainer-features/actions/runs/44004846343) on amd64 and arm64).
- [x] "Hooks and editor" — a lifecycle hook runs `ocx pull` when `ocx.toml`
  exists and is a no-op otherwise; `customizations.vscode.extensions`
  contains `ocx-sh.ocx`.
  Evidence 2026-11-17: [9b168d3](https://github.com/ocx-sh/devcontainer-features/commit/9b168d3), [6711892](https://github.com/ocx-sh/devcontainer-features/commit/6711892) ([#5](https://github.com/ocx-sh/devcontainer-features/pull/5)); manifest carries `customizations.vscode.extensions: ["ocx-sh.ocx"]`, `onCreateCommand` and `updateContentCommand`. Own run on `devcontainers/base:debian`, `remoteUser: vscode`: `Running the updateContentCommand from Feature './ocx'` pulled `jq` into `/home/vscode/.ocx`; a new `bash -i` resolves `/workspaces/e2e1/.ocx/toolchain/links/default/jq/content/jq`. No `ocx.toml`: unit tests in `test/unit/hook.bats` (silent, exit 0).
- [x] "User handling" — for root, an existing non-root user, a `containerUser`
  that differs from `remoteUser`, and `_REMOTE_USER` unset: the build writes
  nothing into any home directory, `ocx` runs as the remote user, `~/.ocx`
  and `.ocx/toolchain` are owned by the remote user, and the hook runs as the
  remote user.
  Evidence 2026-11-17 ([#15](https://github.com/ocx-sh/devcontainer-features/pull/15), own run of the scenario suite, all pass; CI [44019884487](https://github.com/ocx-sh/devcontainer-features/actions/runs/44019884487) on amd64 and arm64): `user-root`, `user-existing` (vscode), `user-container-root-remote-vscode`, `user-container-vscode-remote-root`, `user-created-later` (common-utils creates `dev`, the feature installs after it) each assert that the build wrote no feature file under a home directory, that `ocx` runs as the remote user and that `~/.ocx`, `.ocx/toolchain` and `ocx.lock` belong to that user after the hook; `up-proof` shows a real `devcontainer up` running the hook as `vscode`. `_REMOTE_USER` empty, numeric, `root` and unknown are unit tests in `test/unit/install.bats`.

### Quality

- [x] "`task lint`" — shellcheck over every script, `--shell=sh` for the
  feature scripts, any finding at any severity fails; no inline disable
  without a reason comment.
  Evidence 2026-11-17: `scripts/lint.sh` runs `shellcheck --severity=style --shell=<sh|bash>` plus shfmt and a reasoned-disable check ([58fa457](https://github.com/ocx-sh/devcontainer-features/commit/58fa457), [#3](https://github.com/ocx-sh/devcontainer-features/pull/3)). `ocx exec -g all -- task lint` exits 0 on [2a0bac0](https://github.com/ocx-sh/devcontainer-features/commit/2a0bac0); CI job `lint` green on [#7](https://github.com/ocx-sh/devcontainer-features/pull/7).
- [x] "`task test:unit`" — bats suite against `install.sh` with stubbed
  commands, run under dash, busybox `sh` and `bash --posix`; line coverage of
  `install.sh` is at least 90 %, measured with kcov on the bash leg and
  enforced as a gate.
  Evidence 2026-11-17 on [2a0bac0](https://github.com/ocx-sh/devcontainer-features/commit/2a0bac0): `ocx exec -- task test:unit` gives `dash: 276 tests, 0 failures`, `busybox: 276 tests, 0 failures`, `bash: 276 tests, 0 failures`; coverage `install.sh` 349/381 91.6 %, `configure.sh` 92.0 %, `hook.sh` 95.2 %, `lib.sh` 100 %, total 92.3 %; gate at 90 % per file and total. Coverage tool differs from the item text, see Decisions taken. arm64 result is tracked under "CI green".
- [x] "CLI-native layout" — the repository is the standard devcontainer CLI
  shape (`src/ocx/`, `test/ocx/test.sh`, `test/ocx/scenarios.json`, scenario
  scripts, the duplicate test), so `devcontainer features test`, `package`,
  `publish` and `info` work on it unmodified. Every image, scenario and run
  task is a thin wrapper over one devcontainer CLI command; no parallel
  `docker run` harness. The CLI is a pinned pnpm devDependency. `test.sh` and
  the scenario scripts are POSIX `sh` so they run on images without bash.
  Partial 2026-11-17: `test/ocx/test.sh` and `check.sh` are POSIX `sh`; image runs go through `devcontainer features test` ([#10](https://github.com/ocx-sh/devcontainer-features/pull/10)); `devcontainer features package ./src` packs the feature. Open: `scenarios.json`, scenario scripts, duplicate test.
  Evidence 2026-11-17: `src/ocx/`, `test/ocx/test.sh`, `test/ocx/scenarios.json`, one POSIX `sh` script per scenario, `test/ocx/duplicate.sh` ([#10](https://github.com/ocx-sh/devcontainer-features/pull/10), [#15](https://github.com/ocx-sh/devcontainer-features/pull/15)). Image, scenario and run tasks call `devcontainer features test` or `devcontainer up`/`exec`; `devcontainer features package` is exercised by `task release:rehearse` in `ci:test`; `publish` and `info` by the release run. `@devcontainers/cli` 0.90.0 is a pinned devDependency.
- [x] "`task test:image`" — runs `devcontainer features test` for the feature
  against one base image. `IMAGE` is a required variable with the image list
  as its enum; `.taskrc.yml` sets `interactive: true`, so a terminal run
  without `IMAGE` shows a selection and a non-terminal run fails naming the
  allowed values (verified on Task 3.54.0). Images: debian, ubuntu, alpine,
  fedora, rocky, alma, ubi-minimal, amazonlinux, opensuse, arch, wolfi,
  busybox, and the mcr `devcontainers/base` images. An image the devcontainer
  CLI itself cannot drive is listed in the docs as unsupported, with the
  failing output as evidence.
  Evidence 2026-11-17: [#10](https://github.com/ocx-sh/devcontainer-features/pull/10). `task test:image IMAGE=alpine` passes; `task test:image </dev/null` prints `missing required variables: IMAGE (allowed values: [debian ubuntu alpine fedora rocky alma ubi-minimal amazonlinux opensuse arch wolfi busybox devcontainers-ubuntu devcontainers-debian devcontainers-alpine])`; `.taskrc.yml` sets `interactive: true`; `test/unit/images.bats` fails when the enum and `test/images.txt` differ. Every image is drivable by the devcontainer CLI, so none is listed as unsupported. `busybox` is `busybox:1.37-musl` plus a CA bundle; bare busybox is asserted to fail with a message naming `caBundle`.
- [x] "`task test:images`" — umbrella over every image in the list; each image
  runs and reports its own result, and one failure does not hide the others.
  Evidence 2026-11-17: own run `ocx exec -g all -- task test:images` ends with a 15-row table, all `pass`, 53 s; each image writes `target/reports/junit/image-<alias>.xml` and its own log, and a failure does not stop the others (`test/images/run-all.sh`). CI [44004846343](https://github.com/ocx-sh/devcontainer-features/actions/runs/44004846343): amd64 15 pass; arm64 14 pass and `arch | skipped` (no arm64 image published).
- [x] "`task test:scenarios`" — the `scenarios.json` suite through
  `devcontainer features test`: option combinations, the four user cases, the
  hook, and the idempotence run.
  Evidence 2026-11-17: [#15](https://github.com/ocx-sh/devcontainer-features/pull/15); own run `ocx exec -g all -- task test:scenarios`: 34 rows, all `pass`, 3 min 37 s (18 option scenarios, 5 user cases plus `up-proof`, 3 hook cases, `reinstall`, `duplicate`, 5 `fail-*` build failures asserted by message and exit code). CI [44019884487](https://github.com/ocx-sh/devcontainer-features/actions/runs/44019884487): 34 pass on each architecture.
- [x] "`task run`" — `IMAGE` and `USER` are required variables with the same
  selection prompt. Builds a throwaway dev container with the local feature
  through `devcontainer up`, opens an interactive shell as that user through
  `devcontainer exec`, and removes the container on exit.
  Evidence 2026-11-17 ([#15](https://github.com/ocx-sh/devcontainer-features/pull/15)), own runs: `task run IMAGE=devcontainers-debian RUN_AS=vscode CMD='id -un; command -v jq; ocx version'` prints `vscode`, `/workspaces/devcontainers-debian-vscode/.ocx/toolchain/links/default/jq/content/jq`, `0.6.8`; `task run IMAGE=alpine RUN_AS=root CMD='ocx version'` prints `0.6.8`; afterwards `target/run/` is empty and no `vsc-*` container is left. `task run IMAGE=alpine </dev/null` fails with `missing required variables: RUN_AS (allowed values: [root vscode node])`. The variable is `RUN_AS`, not `USER`, see Decisions taken. Not verified by me: the selection prompt in a real terminal (a pseudo-terminal capture showed the UI start but no text).
- [x] "`task test`" — umbrella over lint, unit, images and scenarios.
  Evidence 2026-11-17: own run `ocx exec -g all -- task test` on the tree of [0778584](https://github.com/ocx-sh/devcontainer-features/commit/0778584): lint clean, unit 357 tests on each of three shells, 15 of 15 images, 34 of 34 scenarios, 9 min 25 s, exit 0.
- [x] "CI green" — `task test` green on amd64 and arm64; no
  `continue-on-error` on test jobs.
  Partial 2026-11-17: [44004846343](https://github.com/ocx-sh/devcontainer-features/actions/runs/44004846343) on `main`: unit suite 285 tests per shell and the image matrix green on `ubuntu-latest` and `ubuntu-24.04-arm`. Open: scenarios in the deep tier.
  Evidence 2026-11-17: verify-deep [44019884487](https://github.com/ocx-sh/devcontainer-features/actions/runs/44019884487) on `main` at [0778584](https://github.com/ocx-sh/devcontainer-features/commit/0778584): `ci:deep` (unit, image matrix, scenarios) green on `ubuntu-latest` (49 pass) and `ubuntu-24.04-arm` (48 pass, `arch` skipped: no arm64 image). No `continue-on-error` in `release.yml`; lint runs in verify-basic on every pull request.

### Release

- [x] "Unattended release" — one workflow, triggered by an hourly poll and by a
  dispatch from `ocx-sh/www-setup`: verify `dist.json` against
  `dist.json.sha256`, update the vendored copy, bump the feature patch
  version, run the test matrix, commit, publish to GHCR. A red matrix
  publishes nothing and opens an issue. Proven by one real run.
  Partial 2026-11-17: workflow and scripts in [2a0bac0](https://github.com/ocx-sh/devcontainer-features/commit/2a0bac0) ([#7](https://github.com/ocx-sh/devcontainer-features/pull/7)). Dry run [43999898334](https://github.com/ocx-sh/devcontainer-features/actions/runs/43999898334): detect, prepare and amd64 test green, arm64 test red (19 unit tests on the busybox leg assume x86_64), publish skipped as designed. Open: arm64 fix, then one real run.
  Partial 2026-11-17: first real run [44020879363](https://github.com/ocx-sh/devcontainer-features/actions/runs/44020879363) (`publish_current`): detect, prepare, lint, unit, image and scenario matrix on amd64 and arm64, publish and registry verification green. Open: a real run of the update path (new manifest, bump, commit). A rehearsal with a snapshot one version behind showed that 20 unit tests assume the pin is 0.6.8, so the matrix would have blocked the next ocx release; fix in progress.
  Evidence 2026-11-17: real run [44030810449](https://github.com/ocx-sh/devcontainer-features/actions/runs/44030810449) from a vendored manifest one ocx release behind ([#20](https://github.com/ocx-sh/devcontainer-features/pull/20)): detect saw the newer manifest, prepare updated the vendored copy to digest `ded01b4b…`, bumped the feature to 1.0.1 and wrote the changelog entry, the matrix passed on amd64 and arm64, publish pushed [7e8673a](https://github.com/ocx-sh/devcontainer-features/commit/7e8673a) (`chore(release): ocx 0.6.8, feature 1.0.1`, by `github-actions[bot]`) and tag `v1.0.1`, published `ocx:1.0.1` (digest `sha256:d290b8c5708050a7c5baa06c8d3da78826e04fd663286317a2a6b16e3bce3fbe`, also `:1`) and verified the pushed layer against `src/ocx`. Red matrix proven too: run [44028287563](https://github.com/ocx-sh/devcontainer-features/actions/runs/44028287563) failed its unit tests on the bumped tree, skipped publish and opened [#21](https://github.com/ocx-sh/devcontainer-features/issues/21), which the green run closed. Both defects that run chain exposed are fixed ([#19](https://github.com/ocx-sh/devcontainer-features/pull/19), [#22](https://github.com/ocx-sh/devcontainer-features/pull/22)). Schedule proven: the first cron-started run [44067670846](https://github.com/ocx-sh/devcontainer-features/actions/runs/44067670846) (event `schedule`, 2026-11-17T10:44Z) ran detect with the job token and printed `nothing to do: vendored manifest matches setup.ocx.sh (ded01b4ba055)`. Dispatch proven: [44034946408](https://github.com/ocx-sh/devcontainer-features/actions/runs/44034946408).
- [ ] "Dispatch wired" — `www-setup` dispatches after its `dist.json` publish;
  evidence is the `www-setup` PR and a received dispatch run here.
  Partial 2026-11-17: [ocx-sh/www-setup#43](https://github.com/ocx-sh/www-setup/pull/43) open (59 checks pass; the 2 Windows smoke jobs fail the same way on that repository's `main`). Open: a received dispatch run, which needs the owner to merge that pull request.
  Receiver proven 2026-11-17: a `dist-updated` repository dispatch in the payload shape of `scripts/dispatch-dist-updated.sh` (`version`, `sha256`, `url`), sent with `gh api -X POST repos/ocx-sh/devcontainer-features/dispatches`, started run [44034946408](https://github.com/ocx-sh/devcontainer-features/actions/runs/44034946408): detect validated the payload, asked the registry with the job token and printed `nothing to do: vendored manifest matches setup.ocx.sh (ded01b4ba055)` and `woken by dist-updated for ocx 0.6.8`; prepare, test and publish skipped. Blocked on the owner: the sender, which needs [ocx-sh/www-setup#43](https://github.com/ocx-sh/www-setup/pull/43) merged and `OCX_ANNOUNCE_TOKEN` scoped to this repository.
  Sender merged 2026-11-17: [ocx-sh/www-setup#43](https://github.com/ocx-sh/www-setup/pull/43) is on `main` (9ed5cd6); its `update-dist` workflow notifies this repository after every publish step. Open: the first dispatch sent by `www-setup` itself, which arrives with its next `update-dist` run (hourly cron, throttled by GitHub).
  Blocked on the owner 2026-11-17: the sender runs and is refused. `update-dist` run [44088583376](https://github.com/ocx-sh/www-setup/actions/runs/44088583376) on `ocx-sh/www-setup` reached the notify step, and GitHub answered the dispatch with `404 Not Found`, so the step warned `dist-updated dispatch to ocx-sh/devcontainer-features failed; the receiver's hourly poll covers it`. `OCX_ANNOUNCE_TOKEN` does not cover this repository (the hazard the prompt names). Needed: add `ocx-sh/devcontainer-features` to the token's repository access with Contents read and write. Until then the hourly poll carries releases; it is proven (see "Unattended release").
  Cause isolated 2026-11-17: the merged sender itself is correct. `scripts/dispatch-dist-updated.sh` from `ocx-sh/www-setup` `main` (9ed5cd6), run locally against `https://setup.ocx.sh/dist.json` with a token that has access to this repository, printed `dispatch-dist-updated: notified ocx-sh/devcontainer-features (0.6.8, ded01b4ba055…)` and started run [44091081537](https://github.com/ocx-sh/devcontainer-features/actions/runs/44091081537) here (`woken by dist-updated for ocx 0.6.8`, `nothing to do`). Script, payload and receiver work end to end; only the repository access of the `OCX_ANNOUNCE_TOKEN` secret is missing. The box stays open, because its evidence is a dispatch sent by the `www-setup` workflow with its own secret, and changing a secret is outside every grant.
- [x] "`main` protected" — a default-branch ruleset mirroring the siblings, with
  the release workflow still able to land its commit.
  Partial 2026-11-17: ruleset 27418948 active (deletion and non-fast-forward blocked). Open: the release workflow landing its commit in a real run.
  Evidence 2026-11-17: ruleset 27418948 active on the default branch (deletion and non-fast-forward blocked; bypass for organisation admins and the admin role), tag ruleset 27427935 on `refs/tags/v*`. The release workflow landed its commit under it: `9dbae02..7e8673a  HEAD -> main` in the publish job of [44030810449](https://github.com/ocx-sh/devcontainer-features/actions/runs/44030810449).
- [x] "Published and listed" — GHCR packages public; the feature resolves with
  `devcontainer features info`; the `collection-index.yml` PR against
  `devcontainers/devcontainers.github.io` is open (merged is the upstream
  maintainers' call).
  Evidence 2026-11-17: release run [44020879363](https://github.com/ocx-sh/devcontainer-features/actions/runs/44020879363) published `ghcr.io/ocx-sh/devcontainer-features/ocx` 1.0.0 (tags `1`, `1.0`, `1.0.0`, `latest`; digest `sha256:19c3baa86d5e74107c060dba6b3085fdc5959b5b310efa6ce083298c1a29e5fd`) and the collection metadata, and pushed tag `v1.0.0` on [0778584](https://github.com/ocx-sh/devcontainer-features/commit/0778584). Both packages are public: an anonymous token pulls `ocx/manifests/1.0.0` and the collection `manifests/latest` with HTTP 200. Own runs: `devcontainer features info manifest ghcr.io/ocx-sh/devcontainer-features/ocx:1.0.0` resolves; `devcontainer up` with an empty Docker config, `mcr.microsoft.com/devcontainers/base:ubuntu` and `ghcr.io/ocx-sh/devcontainer-features/ocx:1` ends in `outcome: success`, `ocx version` prints `0.6.8` as `vscode`. Listing: [devcontainers/devcontainers.github.io#754](https://github.com/devcontainers/devcontainers.github.io/pull/754) open, from the fork `ocx-sh/devcontainers.github.io`.

### Documentation and announcement

- [x] "Conventions adopted" — `ocx-sh/conventions` template applied and the
  `fleet.toml` entry PR open. Evidence 2026-11-17: template v0.3.5 landed in
  [#1](https://github.com/ocx-sh/devcontainer-features/pull/1) (merged, all
  checks green at 245b2ec; `task verify` and `task baseline:check` exit 0
  locally); fleet entry
  [ocx-sh/conventions#35](https://github.com/ocx-sh/conventions/pull/35) open.
- [x] "Docs site" — `@ocx-sh/theme` site in this repo, deployed to
  `https://ocx.sh/integrations/devcontainer/`; `ocx-site check`, Lighthouse
  and link checks pass.
  Partial 2026-11-17: site scaffold, `site:build`, `site:check` and the Lighthouse gate merged in [#2](https://github.com/ocx-sh/devcontainer-features/pull/2); CI job `docs` green. Open: deploy, blocked on the owner chain (website claim merge, theme release, conventions pin).
  Blocked on the owner 2026-11-17: the deploy run [44018301662](https://github.com/ocx-sh/devcontainer-features/actions/runs/44018301662) fails with `nav.json: ocx-sh/devcontainer-features owns no claim`, because the template pins the deploy action at v0.3.0 and the newest theme release v0.6.0 predates the merged claim. Needed: a theme release tag that contains the claim, then the conventions pin bump. `ocx-site check`, link checks and Lighthouse pass in the `docs` job of every pull request.
  Evidence 2026-11-17: deployed by run [44064261757](https://github.com/ocx-sh/devcontainer-features/actions/runs/44064261757) (`uploaded 96 files`) after [#24](https://github.com/ocx-sh/devcontainer-features/pull/24) moved the baseline to conventions v0.3.6 and the site to the released `@ocx-sh/theme` 0.7.0. Through public DNS, `https://ocx.sh/integrations/devcontainer/`, `/quickstart/`, `/reference/options/` and `/troubleshooting/install-errors/` answer 200 (title `Use ocx in a dev container | ocx Dev Container Feature`), the Pagefind entry is served and the hub page `https://ocx.sh/integrations/` lists "Dev Containers". `ocx-site check`, lychee (0 errors) and Lighthouse pass in the `docs` job of #24. The chain behind it, done under the widened grant: theme release [ocx-sh/website v0.7.0](https://github.com/ocx-sh/website/releases/tag/v0.7.0) ([ocx-sh/website#54](https://github.com/ocx-sh/website/pull/54), [ocx-sh/website#55](https://github.com/ocx-sh/website/pull/55)), conventions v0.3.6 ([ocx-sh/conventions#35](https://github.com/ocx-sh/conventions/pull/35), [ocx-sh/conventions#36](https://github.com/ocx-sh/conventions/pull/36)).
- [x] "Docs quality" — planned with `docs-plan` (user needs, page inventory,
  coverage table), every page graded with `docs-review` with no MUST finding
  left, checks wired with `docs-instrument`. Every runnable example is backed
  by a test in the gate.
  Evidence 2026-11-17: plan in `.agents/discovery/` (`use-cases.yaml`, `writer-inventory.md` with the page inventory and coverage table, four friction logs). Every page reviewed with `docs-review` in [#17](https://github.com/ocx-sh/devcontainer-features/pull/17) (per-page MUST/SHOULD table in the pull request body, none left; declined SHOULDs listed there). Gate wired with `docs-instrument` in [#18](https://github.com/ocx-sh/devcontainer-features/pull/18): declaration, prose, page-type, landing, example and raw-link scripts, markdownlint, the generator stale check and `site/scripts/check-doc-bindings.mjs` run in `task site:docs` (pull request job `docs`), lychee in `site:check`, Lighthouse in `site:lighthouse`. Own runs on the merged tree: `task site:docs` exit 0; `check-doc-bindings: 0 findings`; a planted unbound example key makes it exit 1. `test/docs/bindings.json` binds all 57 example keys: 35 to scenarios, 8 to build-failure entries, 7 to unit tests, 4 to image tests, 3 are `norun` with a reason (two proxy examples and one TLS-inspection message need a corporate proxy). The checker compares fence content with the test (options, message text, commands). Own run `task test:scenarios`: 47 of 47 pass; unit 362 tests on each of three shells; CI verify-deep [44024558748](https://github.com/ocx-sh/devcontainer-features/actions/runs/44024558748) green on amd64 and arm64.
- [x] "Use-case pages" — at least: quickstart; pin or upgrade the ocx
  version; restore the project toolchain on create; non-root and custom
  users; minimal images (Alpine, distroless-like); corporate proxy and custom
  CA; mirror and air-gapped installs; organisation-managed configuration;
  Codespaces and prebuilds; troubleshooting by symptom; an options reference
  that cannot drift from `devcontainer-feature.json` (generated or checked).
  Partial 2026-11-17: 20 pages merged in [#8](https://github.com/ocx-sh/devcontainer-features/pull/8), [#11](https://github.com/ocx-sh/devcontainer-features/pull/11), [#12](https://github.com/ocx-sh/devcontainer-features/pull/12); the options, installer parity, supported images and changelog regions are generated and checked by `site/scripts/generate-docs.mjs --check` in the `docs` job. Open: update after the hardening changes, cross-links, review pass.
  Evidence 2026-11-17: 22 pages in `site/src/content/docs` ([#8](https://github.com/ocx-sh/devcontainer-features/pull/8), [#11](https://github.com/ocx-sh/devcontainer-features/pull/11), [#12](https://github.com/ocx-sh/devcontainer-features/pull/12), [#17](https://github.com/ocx-sh/devcontainer-features/pull/17)): quickstart; guides pin-or-upgrade-version, restore-toolchain, non-root-and-custom-users, minimal-images; integrate proxy-and-custom-ca, mirror-and-air-gapped, managed-config, codespaces-and-prebuilds; five troubleshooting pages by symptom; concepts how-the-install-works and trust-model; reference options (table generated from `devcontainer-feature.json`, stale check in the `docs` job), installer-parity, environment-and-files, supported-images; changelog.
- [x] "Feature README" — `src/ocx/README.md` and `NOTES.md` as the
  devcontainer tooling expects, so the feature reads well on containers.dev
  and in the VS Code picker.
  Partial 2026-11-17: `src/ocx/README.md` generated from the manifest and `NOTES.md` with `devcontainer features generate-docs`, stale check in `ci:lint` ([47c7652](https://github.com/ocx-sh/devcontainer-features/commit/47c7652), [#7](https://github.com/ocx-sh/devcontainer-features/pull/7)). Open: final `NOTES.md` wording after the docs pages land.
  Evidence 2026-11-17: `src/ocx/NOTES.md` and the generated `src/ocx/README.md` ([#7](https://github.com/ocx-sh/devcontainer-features/pull/7), final wording [#17](https://github.com/ocx-sh/devcontainer-features/pull/17)); `task feature:readme:check` runs in `ci:lint` and passes.
- [x] "Announced" — PRs open on `ocx-sh/website` (`nav.json` claim
  `/integrations/devcontainer/` and hub entry) and `ocx-sh/ocx`
  (`roadmap.md`, `integration/devcontainers-and-editors.mdx`,
  `integration/index.md`).
  Partial 2026-11-17: [ocx-sh/website#53](https://github.com/ocx-sh/website/pull/53) open. Open: the `ocx-sh/ocx` pull request.
  [ocx-sh/ocx#740](https://github.com/ocx-sh/ocx/pull/740) open, 34 checks pass, 4 skipped.
  Evidence 2026-11-17: [ocx-sh/website#53](https://github.com/ocx-sh/website/pull/53) (claim `/integrations/devcontainer/`, hub category `build`) merged by the owner 2026-11-16T23:49Z; [ocx-sh/ocx#740](https://github.com/ocx-sh/ocx/pull/740) open with `roadmap.md`, `integration/devcontainers-and-editors.mdx` and `integration/index.md`, 34 checks pass and 4 skipped, to be merged by the owner after the first publish.

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
- Own download logic, not a wrapper around the official installer: its
  `assert_https_url` refuses any non-HTTPS `OCX_INSTALL_DIST_URL`, so it
  cannot read the vendored `dist.json`. The feature ports the installer's
  functions (libc and target detection, downloader probe, checksum, safe
  extraction, manifest row lookup) and keeps its exit codes.
- `main` ruleset mirrors `find_ocx` exactly (deletion and non-fast-forward
  blocked, bypass for organisation admins and repository role 2): ruleset id
  27418948, created 2026-11-17. It requires no pull request, so the release
  workflow can commit with `GITHUB_TOKEN`.
- Tool groups: node and pnpm sit in the default `ocx.toml` group because the
  template's test job pulls `default,test` and a tool cannot be in two groups.
- Website claim: [ocx-sh/website#53](https://github.com/ocx-sh/website/pull/53)
  opened 2026-11-17 (claim `/integrations/devcontainer/`, hub category
  `build`). Until it is merged and a theme release is tagged, the docs site
  builds against a pinned commit of that branch.
- Conventions pins the deploy action at v0.3.0 (template-owned
  `deploy-site.yml`); the action aborts on a Pagefind mismatch with theme
  0.6.0. Resolved at docs deploy time, not by hand-editing the template file
  unless the deploy proves the mismatch.

- `libc` defaults to `musl` (enum `auto`, `gnu`, `musl`). The spike
  (`research/runtime-contract.md` § 1) shows the platform is detected from
  the host at run time, so the static musl build resolves glibc packages on
  glibc hosts and runs on every tested image; `auto` follows the official
  installer (gnu when glibc >= 2.28, else musl).
- The tool-groups option is `pullGroups`, not `groups`: where `/bin/sh` is
  bash the variable `GROUPS` is special and the option value is lost
  (fedora shows `GROUPS=0`, `research/runtime-contract.md` § 6).
- Shell activation composes the project environment once at shell start with
  the documented `ocx --offline env` recipe, from `/etc/profile.d/ocx.sh` and
  one line in the system bashrc and zshrc files. The per-prompt hook is not
  shipped: `ocx self activate` only works from a per-user `ocx self setup`
  layout, and faking that layout relies on an undocumented path. Upgrade when
  ocx offers a system-binary activation mode. Option `shellActivation` turns
  it off.
- Lifecycle: managed configuration is applied in `onCreateCommand`, the
  toolchain restore runs in `updateContentCommand`, so Codespaces prebuilds
  include the tools. Both run as the remote user. A missing `ocx.toml` is a
  silent no-op; any other failure warns and exits 0, so a stale lock or no
  network never blocks opening the container.
- Option-dependent settings go to `/etc/ocx/config.toml` (update check,
  consent paths, managed source); only `OCX_HOME` needs an environment
  variable. An existing system config is never overwritten.
- `caBundle` is used for the build-time download and is also exported as
  `OCX_EXTRA_CA_CERTS` for run time, so one option covers a TLS-intercepting
  proxy end to end.
- `busybox` has no package manager and no CA bundle. The matrix tests a
  busybox image with a CA bundle added; bare busybox is documented as
  needing `caBundle`, and the build fails there with a clear message.
- First published feature version is `1.0.0`, so documentation can use `:1`.
- CI mapping (template-owned workflows): `verify-basic` runs `ci:lint`,
  `ci:test` and `ci:docs` on amd64 for every pull request; `verify-deep`
  runs `ci:deep` on amd64 and arm64 and carries the full image matrix.
- Dispatch contract from `www-setup`
  ([ocx-sh/www-setup#43](https://github.com/ocx-sh/www-setup/pull/43)):
  `repository_dispatch` type `dist-updated`, payload `{version, sha256, url}`.
- Coverage is measured with a `PS4`/`BASH_XTRACEFD` line tracer on the
  `bash --posix` leg, not with kcov: kcov recorded no lines for `#!/bin/sh`
  scripts run under bats. The gate is the same (90 % per file and in total)
  and covers every `src/ocx/*.sh`, not only `install.sh`.
- The task that builds the unit-test image is `test:unit:image`; `test:image`
  is the per-base-image task the goal names.
- Correction to the `caBundle` decision above: ocx reads the run-time CA
  bundle from the top-level `extra_ca_certs` key of `/etc/ocx/config.toml`
  and rejects a file over 32 KiB. The feature writes that key for a readable
  file within the limit and warns otherwise; `OCX_EXTRA_CA_CERTS` is exported
  only when a foreign system config blocks the write.
- The hook does not call `ocx` at all when no `ocx.toml` exists in or above
  the workspace, so no ocx error text reaches the log.
- The release keeps a hand-prepended `CHANGELOG.md` (feature version, ocx
  version, date). The template's git-cliff release tasks are commit-driven
  and gated on verify-deep, so they do not fit a manifest-driven release.
- Release workflow shape: `detect` (sidecar digest compare, the hourly fast
  path), `prepare`, `test` on amd64 and arm64, `publish` (commit, tag
  `v<feature version>`, GHCR publish, registry verify), `report` (one
  `release-blocked` issue). Inputs `publish_current` and `dry_run`.
- arm64 cannot run locally (no emulation installed, nothing is installed on
  the host), so arm64 is proven in CI only.
- Hardening review 2026-11-17 (two independent reviewers, findings triaged
  here). Release path: the jq guard and the installer's text parser could
  disagree about a manifest row (critical), new hashes were trusted on first
  use, a pushed but unpublished release was not recovered, plus smaller
  items. Installer: shell activation ignored consent (high), a guard bypass
  through `OCX_PROJECT`, and smaller items. Fixes land test-first in two
  pull requests.
- Shell activation is gated on `consentPaths`: the profile snippet activates
  only a project under one of the configured paths, and never when the
  option is empty. The default `/workspaces/*` stays, because the dev
  container already runs the workspace repository's lifecycle commands; the
  docs state that it also covers other repositories cloned below
  `/workspaces`.
- Repository settings tightened 2026-11-17: default workflow token read-only,
  workflows cannot approve pull requests, actions must be pinned by SHA,
  environment `release` limited to `main` for the publish job, tag ruleset
  27427935 (`v*`: no deletion, no update).
- Troubleshooting is four pages, not two: the page-type check allows at most
  four entries per troubleshooting page.
- The interactive container task takes `RUN_AS`, not `USER`: every shell
  exports `USER`, Task 3.54.0 reads it as the value and reports "invalid
  value" instead of prompting. A unit test rejects `requires` variables
  named after exported shell variables.
- Parallel `devcontainer features test` runs share a work directory when they
  start in the same millisecond (the CLI names it by `Date.now()` under
  `os.tmpdir()`). Every CLI run gets its own `TMPDIR`; each staged scenario
  carries its name and the script refuses to run under another.
- Hand-written docs pages keep the ocx version they were written with
  (`0.6.8`) in example output; the release does not rewrite it. Two of the
  occurrences are historical ("Feature 1.0.0 installs ocx 0.6.8", a manifest
  row with its digest), so a blind rewrite would make them false. The example
  checker normalises versions.
- The fork for the containers.dev pull request lives in the organisation
  (`ocx-sh/devcontainers.github.io`), not in a personal account, and its
  commit was made through the GitHub API.
- Feature 1.0.1 has the same content as 1.0.0. It exists because the update
  path (new manifest, bump, commit to `main`, publish) had never run for
  real: `main` was set one ocx release back in
  [#20](https://github.com/ocx-sh/devcontainer-features/pull/20) and the
  release workflow brought it forward. The rehearsal first exposed 20 unit
  tests that assumed the pin was 0.6.8 and would have blocked the next ocx
  release ([#19](https://github.com/ocx-sh/devcontainer-features/pull/19)).
- The hourly cron is throttled by GitHub: `ocx-sh/www-setup` has the same
  `17 * * * *` schedule and its runs arrive 4 to 8 hours apart. The dispatch
  from `www-setup` is the fast path; the poll is the safety net.
- Owner message of 2026-11-17 widens the grant: merge the claim, release the
  website (theme release tag), release the conventions and merge the
  `www-setup` dispatch pull request. This lifts "never merge there" and "never
  push the theme release tag" for these steps. The three repositories require
  one approving review; with a single human account the merges use the
  organisation-admin bypass of their rulesets.
- The expired certificate on `https://ocx.sh/` was a local artefact: this
  machine's `/etc/hosts` maps `ocx.sh` to itself. Through public DNS the site
  answers 200 with a valid certificate. The hazard in the prompt file does not
  apply to users.
- The `/integrations/devcontainer/` claim made `section` the seventh value of
  the root search filter. Pagefind UI keeps a lone filter open only up to six
  values, so the filter rendered collapsed and the website deep tier failed
  (`search.spec.ts:32`; green on v0.6.0). Fixed in the theme with
  `openFilters: ['section']`
  ([ocx-sh/website#55](https://github.com/ocx-sh/website/pull/55)) before the
  v0.7.0 tag. Two unrelated flaky tests showed up on the way
  (`deploy.test.ts` "keeps the phase order when some files are skipped",
  e2e `motion-controls.spec.ts:56` and `sidebar-deferred.spec.ts:96`).

## Stop conditions

- Every item above is checked with evidence, or
- an item is blocked by something only the owner or an upstream maintainer can
  do. Then finish everything else and report the blocked items in one list.
