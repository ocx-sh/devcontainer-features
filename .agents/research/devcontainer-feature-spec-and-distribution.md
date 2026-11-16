Retrieved: 2026-11-16

# Dev Container Features: spec, distribution, discoverability

Scope: authoring and shipping a single-purpose Feature (install `ocx`). No feature code here. Each claim carries a source tag; URLs are in the "Sources" table at the end (S1 ... S20). "Run" means I executed it locally on 2026-11-16 (CLI 0.90.0 `--help`).

## 1. Repo layout and `devcontainer-feature.json`

Layout (S1, S2, S6): one git repo = one "collection" = one OCI namespace. Each Feature lives in `src/<id>/` with at least `devcontainer-feature.json` and `install.sh`; the directory name must equal `id`. Tests mirror it in `test/<id>/test.sh`. Files outside `src/<id>/` are not packaged (S2). Optional: root `README.md`, `.github/workflows/`, `.devcontainer/`, `LICENSE`. Starter repo shape (S6): `src/{hello,color}/`, `test/`, `.github/workflows/{release,test}.yaml`. Other files inside `src/<id>/` are packaged with the Feature and sit next to `install.sh` at install time (S1).

Schema source of truth: `schemas/devContainerFeature.schema.json` in devcontainers/spec (S12). It has `additionalProperties: false` (unknown keys are rejected) and the action validates against it unless `disable-schema-validation` is set (S7).

Properties (S1 unless noted):

| Property | Type | Notes |
|---|---|---|
| `id` | string, required | unique in the repo; must equal the directory name |
| `version` | string, required | semver; drives republish (S2) |
| `name` | string, required | display name |
| `description` | string | schema advises no markdown/HTML (S12) |
| `documentationURL`, `licenseURL` | string | |
| `keywords` | string[] | search terms |
| `options` | object | key = option id. Per option: `type` (`boolean` or `string`), `default` (string or boolean), `description`, and either `proposals` (suggestions, free text allowed) or `enum` (strict). Never both. |
| `containerEnv` | object | set/override env vars; added as `ENV` before the Feature runs (S1) |
| `installsAfter` | string[] | soft ordering; Feature IDs without version tags; not recursive; ignored unless the other Feature is already queued; cannot carry options/version pins |
| `dependsOn` | object | hard deps, same shape as `features` in devcontainer.json; must be OCI ref, tarball URI or local; recursive; failure aborts container creation; same Feature with different options counts as different |
| `legacyIds` | string[] | old IDs after a rename |
| `deprecated` | boolean | tooling highlights it |
| `mounts` | see below | Docker `--mount` format; `${devcontainerId}` allowed |
| `capAdd`, `securityOpt` | string[] | concatenated across Features |
| `privileged`, `init` | boolean | applied if any Feature sets them |
| `entrypoint` | string | script run at container start |
| `customizations` | object | per-tool namespaces (e.g. `vscode`); objects merged per namespace, arrays unioned |
| `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand` | string / array / object | stored in image metadata; run in Feature install order, one at a time, blocking; always before the user's devcontainer.json commands; object form runs its members in parallel; run from the workspace folder |

Discrepancy: the spec page types `mounts` as "object" (S1) while the JSON schema types it as an array of `Mount` (S12). Use the array form and validate with the action.

Option env var name (S1, S5): `str.replace(/[^\w_]/g,'_').replace(/^[\d_]+/g,'_').toUpperCase()`. So `version` -> `VERSION`, `install-dir` -> `INSTALL_DIR`, `2fast` -> `_FAST`. A bare string in a user's `features` entry is shorthand for `version` (S1), so name the main option `version` if you want `"…/ocx:1": "0.5.0"` style to work.

Renaming (S1): change folder and `id`, add old id to `legacyIds`, keep the semver sequence (do not restart at 1.0.0), republish.

## 2. How `install.sh` runs

All from S1, S5 (spec), S3 (CLI source `containerFeaturesConfiguration.ts`, line numbers as of main on 2026-11-16):

- Build time, during image build, one Docker layer per Feature. Runs as `root` (S1: "Feature scripts run as the `root` user"; S5: "should be executed as `root` during a container image build"). A Feature that must act as the user does `su "${_REMOTE_USER}" -c ...` (S1).
- Interpreter: not forced. Spec says set the execute bit and invoke directly so the shebang decides; default to a shell present on the distro (bash on Debian/Ubuntu/Fedora, `sh` on Alpine); bootstrap a shell if needed (S1). Practical consequence: use `#!/bin/sh` POSIX, or `#!/bin/bash` and install bash first when absent. Spec does not guarantee bash on the base image.
- Working dir and wrapper (implementation, not in the spec text): the CLI copies the Feature to `/tmp/dev-container-features/<consecutiveId>` (const `FEATURES_CONTAINER_TEMP_DEST_FOLDER`, S3), generates a `devcontainer-features-install.sh` wrapper there, and runs `chmod +x ./devcontainer-features-install.sh && ./devcontainer-features-install.sh` as a `RUN` (S3 ~L342-355). The wrapper prints a banner, then `set -a; . ../devcontainer-features.builtin.env; . ./devcontainer-features.env; set +a; chmod +x ./install.sh; ./install.sh` (S3 ~L282-287). So cwd is the Feature's own directory (sibling files addressable relatively), and an `EXIT` trap prints a failure/troubleshooting message on non-zero exit. The spec itself states no cwd (S1, S5).
- Env vars: option vars (uppercased, from `devcontainer-features.env`, defaults exported for omitted options; S1, S5), plus builtins from `devcontainer-features.builtin.env`: `_CONTAINER_USER`, `_REMOTE_USER` (= `_CONTAINER_USER` if no `remoteUser`), `_CONTAINER_USER_HOME`, `_REMOTE_USER_HOME` (S1, S5; home resolved via `getent passwd` in S3 ~L302-304). Both `*_USER` names are literal, with the leading underscore.
- Persistent env: use `containerEnv` for static values, or write `/etc/profile.d/*.sh` / shell rc files from `install.sh`. `containerEnv` is emitted as Docker `ENV` before the Feature runs (S1). `containerEnv` cannot reference `$HOME`-style runtime expansion safely; unverified, test it.
- Layer caching: each Feature is its own layer; the layer cache key is the Feature content + options, so pinning an exact Feature version and network downloads inside `install.sh` make the layer cacheable but stale-prone. A floating "latest ocx" resolved at build time is cached until the layer is invalidated (inference from Docker semantics, not stated in the spec).
- Order: tool-defined by default; `dependsOn` (hard) then `installsAfter` (soft) then user `overrideFeatureInstallOrder` (S1). Ties broken by Round Stable Sort: fully qualified name, tag age, number of options, option keys, option values (S1).
- Duplicates: same Feature twice with different options is legal and must not conflict, hence the `duplicate.sh` test (S4, S1 "Feature equality"). OCI equality = same manifest digest and same options.
- Reference forms (S1, S5): `<registry>/<namespace>/<feature>[:<semver>]` (`:latest` implied), `https://…/devcontainer-feature-<id>.tgz`, `./<local-dir>`. Identifiers are case-insensitive, normalised to lowercase (S5).

## 3. Publishing

OCI naming (S2): Feature pushed to `<registry>/<namespace>/<id>[:tag]`, e.g. `ghcr.io/devcontainers/features/go`. Namespace has "no strict rules"; convention is the repo's `<owner>/<repo>`. Tags per publish: `1`, `1.2`, `1.2.3`, `latest`. Existing exact versions are not republished; major/minor tags are moved (S2, S1). The CLI skips blob upload when the manifest digest already exists and just re-tags (S10 push code).

Collection metadata (S2): the tool also pushes `devcontainer-collection.json` to `<registry>/<namespace>` (no feature name), tagged `latest` only. Content: `sourceInformation` plus `features[]` (each Feature's JSON). Each Feature is packaged as `devcontainer-feature-<id>.tgz`. Media types: config `application/vnd.devcontainers`; layer `application/vnd.devcontainers.layer.v1+tar`; collection layer `application/vnd.devcontainers.collection.layer.v1+json`; manifest annotation `dev.containers.metadata` holds the escaped full JSON.

`devcontainers/action@v1` (S7, action.yml read on 2026-11-16; runs on `node24`):

| Input | Default | Meaning |
|---|---|---|
| `publish-features` | `false` | publish Features; cannot be combined with `publish-templates` |
| `base-path-to-features` | `''` | folder holding Features, e.g. `./src` |
| `generate-docs` | `false` | generate `README.md` per Feature and commit |
| `oci-registry` | (CLI default `ghcr.io`) | registry host |
| `features-namespace` | source repo name (action text) | prefix of published IDs. Caution: the action text says "defaults to the source repo name"; feature-starter docs say `<owner>/<repo>` (S6). Pass explicitly if you need a specific namespace. |
| `disable-schema-validation` | `false` | skip schema check |
| `validate-only` | `false` | validate and exit; cannot combine with publishing |
| `disable-repo-tagging` | `false` | skip the git tag per released Feature |
| `devcontainer-cli-version` | latest on npm | pin CLI (example `0.53.0`) |

Required job permissions (S7, S8): `contents: write`, `pull-requests: write`, `packages: write`; repo setting "Allow GitHub Actions to create and approve pull requests" must be on, or docs PR creation fails (S6, S7). Starter workflow (S8) is `workflow_dispatch`-only, guarded by `github.ref == 'refs/heads/main'`, passes `GITHUB_TOKEN`, and a second step does `git add */**/README.md`, pushes `automated-documentation-update-$GITHUB_RUN_ID`, and `gh pr create`. The action itself fetches the latest CLI and runs `devcontainer features publish` (S7).

Without Actions (S9, S10): `devcontainer features publish -n <owner>/<repo> [-r ghcr.io] ./src`; `-n` is required.

Visibility (S6, S7, S9): GHCR packages default to private; "to stay within the free tier" set each Feature package to public at `https://github.com/users/<owner>/packages/container/<repo>%2F<feature>/settings` (for an org the path is `orgs/<org>/packages/...`; org URL form not in the sources, inferred). Must be done per package after the first publish, including the collection-metadata package (the namespace root, e.g. `ghcr.io/<owner>/<repo>`), since the index crawler pulls it anonymously (S11 requires "downloaded without a login"). Private Features in Codespaces need `customizations.codespaces.repositories.<repo>.permissions` with `packages: read`, `contents: read` (S6).

Version bump semantics: bump `version` in `devcontainer-feature.json`; no bump means no new exact tag (S2). Semver applies per Feature, not per repo. Changing install behaviour without bumping silently publishes nothing new.

Docs generation (S6, S7, S10): `generate-docs: true` (CLI: `devcontainer features generate-docs -n <ns> -r ghcr.io --github-owner --github-repo -p .`) writes `src/<id>/README.md` from the JSON, merging a hand-written `src/<id>/NOTES.md` if present. Do not edit the generated README; edit `NOTES.md`. The generator's exact template (usage snippet, options table) is not documented in the sources I read; not verified.

## 4. Appearing on containers.dev and in tool pickers

Mechanism (S11, S13, S14, S15):
- The public index at containers.dev/features is a table of Features crawled from "each registered collection". Registration = a PR to `_data/collection-index.yml` on the `gh-pages` branch of `devcontainers/devcontainers.github.io`. No Feature-level submission exists; "to report a problem with a feature, contact the registry that hosts it" (S13).
- Entry schema (S14, 327 entries on 2026-11-16, field names read from the file): five string fields, in this order: `name`, `maintainer`, `contact`, `repository`, `ociReference`. Real example (Anthropic):
  ```yaml
  - name: Claude Code Feature
    maintainer: Anthropic
    contact: https://github.com/anthropics/devcontainer-features/issues
    repository: https://github.com/anthropics/devcontainer-features
    ociReference: ghcr.io/anthropics/devcontainer-features/claude-code
  ```
  Note this entry points at one Feature path, while the guide says the `ociReference` "should be the collection namespace root ... not a path to an individual Feature" (S11). Follow the guide (namespace root, e.g. `ghcr.io/ocx-sh/devcontainer-features`). A few existing entries deviate (typos `ocireference`, `ociReferences`, missing key; S14), so mimic the majority.
- Rules from the guide (S11): one entry per repository regardless of Feature count; no URL scheme in `ociReference`; the registry must allow download without login (non-GHCR registries allowed, e.g. `registry.gitlab.com/...` exists in the file); the site auto-discovers all Features from that one entry.
- CI on the PR: only `yamllint` strict on `_data/collection-index.yml` (S15, config `.github/lint-config.yaml`: extends default, line-length/trailing-spaces/document-start disabled). `CODEOWNERS` is `* @devcontainers/maintainers` (S15). No written acceptance criteria exist. The collections page says collections "are continuously crawled for liveness" (S16), so a deleted or private package will drop out.
- Index build: `publish.yml` in the website repo runs on push to `gh-pages`, manually, and daily at 09:00 UTC; it `oras pull`s `ghcr.io/devcontainers/index:latest` (-> `devcontainer-index.json`) and `ghcr.io/devcontainers/control-manifest:latest`, then builds Jekyll (S15). So a new Feature version shows up on the site after the crawler refreshes `ghcr.io/devcontainers/index` plus the next site build (latency up to about a day after that). The crawler that produces `devcontainers/index` is not in any public repo I could locate (org repo list: ci, spec, devcontainers.github.io, cli, images, features, templates, action, feature-starter, template-starter, community, git-lfs-example, .github).
- Consumers (S6, S16): the same index is what "VS Code Dev Containers and GitHub Codespaces surface ... for their dev container creation UI" (S6: "This index is from where supporting tools ... surface Features"). So listing there is what makes `ocx` appear in the VS Code "Dev Containers: Configure Container Features..." / "Add Dev Container Feature" quick pick and the Codespaces feature picker; not listing = still usable by full reference, just not searchable.
- Displayed fields on the site table: Feature name, Maintainer, Reference, Latest version (S13 page source). Search uses `name`, so `name`, `description` and `keywords` in each `devcontainer-feature.json` are what users see/search (keywords: tool-side search behaviour in VS Code not verified).
- Not verified: whether VS Code/Codespaces pickers read `keywords`, `documentationURL`, or `deprecated`; whether any minimum quality bar is enforced by maintainers on PRs.

## 5. `devcontainer features test` and CLI

CLI: npm package `@devcontainers/cli`, latest `0.90.0` (npm registry `latest`, 2026-11-16), `engines.node >= 20.0.0` (S17, S18). Install `npm i -g @devcontainers/cli`, or the standalone script `curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh` which bundles Node (S19). Needs Docker for `test`/`build`/`up`.

Commands and flags (Run, CLI 0.90.0 `--help`):
- `features test [target]` flags: `-p/--project-folder` (default `.`; positional `target` is deprecated), `-f/--features` (space-separated, omit = all; not with `--global-scenarios-only`), `--filter <str>` (scenario names containing str; not with `--skip-scenarios`), `--global-scenarios-only`, `--skip-scenarios`, `--skip-autogenerated`, `--skip-duplicated`, `--permit-randomization`, `-i/--base-image` (default `ubuntu:focal`; not used for scenarios), `-u/--remote-user` (not used for scenarios), `--log-level`, `--preserve-test-containers`, `-q`, plus `--oci-auth-hardening`, `--allow-cross-origin-auth-host`.
- `features package <target> [-o ./output] [-f]`: writes tgz files and `devcontainer-collection.json`; target is a `src` dir or a single Feature dir.
- `features publish <target> -n <owner>/<repo> [-r ghcr.io]`.
- `features info <manifest|tags|dependencies|verbose> <featureRef> [--output-format text|json]`: use after publish to verify tags.
- `features generate-docs -n <ns> [-r] [--github-owner] [--github-repo] [-p .]`.

Test contract (S4, test.md in the CLI repo; examples S8 test workflow):
- Auto-generated test: builds a minimal container with `--base-image`, `--remote-user`, and the Feature at default options, then runs `test/<id>/test.sh` inside it. Passes only if the build succeeds and `test.sh` exits 0.
- `scenarios.json` at `test/<id>/scenarios.json`: object keyed by scenario name, value is a `devcontainer.json` fragment (`image`, `features`, `build.dockerfile`, ...). For each scenario the runner looks for `test/<id>/<scenarioName>.sh` and runs it. Base image/remote user flags are NOT applied; set `image` and `remoteUser` inside the scenario. Extra build files go in `test/<id>/<scenarioName>/` and are copied into the generated `.devcontainer`.
- Feature references inside scenarios use the bare local id (`"ocx": {...}`), not the ghcr path (S4 examples).
- `test/_global/`: `scenarios.json` plus scripts for scenarios not tied to one Feature; run alone with `--global-scenarios-only` (S4).
- Duplicate test: if `test/<id>/duplicate.sh` exists (and `--skip-duplicated` is not set) the runner installs the Feature twice (one with random option values, one default) and runs `duplicate.sh`; the random options appear as env vars (`VERSION`), defaults as `VERSION__DEFAULT` (double underscore; S4). `--skip-duplicated` skips these. This is the idempotence test.
- Test lib (S4): `source dev-container-features-test-lib` (injected next to the tests; optional) gives `check "<label>" <cmd> [args]` and `reportResults`. Scripts are `#!/bin/bash` with `set -e`. `reportResults` must be last. Tests run in the built container as the remote user.
- Starter CI (S8): matrix of Feature x base image (`debian:latest`, `ubuntu:latest`, `mcr.microsoft.com/devcontainers/base:ubuntu`) for autogenerated tests with `--skip-scenarios`; scenarios job with `--skip-autogenerated --skip-duplicated`; separate `--global-scenarios-only` job. Starter marks jobs `continue-on-error: true`; do not copy that into a gate.

## 6. Naming for single-vendor repos

Namespace = `<owner>/<repo>`; Feature ID appended. Real index entries (S14, ociReference as written there):

| Vendor | Namespace | Notes |
|---|---|---|
| Spec maintainers | `ghcr.io/devcontainers/features` | reference collection |
| Anthropic | `ghcr.io/anthropics/devcontainer-features` (Feature `claude-code`, README pins `:1.0`) | vendor-owned single-tool repo, closest analogue |
| Grafana Labs | `ghcr.io/grafana/devcontainer-features` | |
| Earthly | `ghcr.io/earthly/devcontainer-features` | |
| Doppler | `ghcr.io/dopplerhq/devcontainer-features` | |
| MathWorks | `ghcr.io/mathworks/devcontainer-features` | |
| PostFinance | `ghcr.io/postfinance/devcontainer-features` | |
| JuliaLang | `ghcr.io/julialang/devcontainer-features` | |
| Stateful (Runme) | `ghcr.io/stateful/devcontainer-features` | |
| aqua | `ghcr.io/aquaproj/devcontainer-features` | |
| Astronomer | `ghcr.io/astronomer/devcontainer-features` | |
| Iterative, Fig | `ghcr.io/iterative/features`, `ghcr.io/withfig/features` | the shorter `features` style |
| Rails | `ghcr.io/rails/devcontainer/features` | nested; repo `devcontainer` |
| Azure Dev CLI | `ghcr.io/azure/azure-dev` | tool repo itself hosts the Feature (needs no separate repo) |

Counting `ociReference` values in the index (S14): the overwhelming pattern is `<owner>/devcontainer-features`, with `<owner>/features` second. For `ocx-sh` the matching choice is repo `ocx-sh/devcontainer-features` -> `ghcr.io/ocx-sh/devcontainer-features/ocx`, which matches this repo's directory name. Note GHCR lowercases references (S5 case-insensitive).

## Checklist for this repo

1. Layout: `src/ocx/{devcontainer-feature.json,install.sh}`, `test/ocx/{test.sh,scenarios.json,duplicate.sh}`, `test/_global/` if any cross-feature scenario, `.github/workflows/{test,release}.yaml`, `LICENSE`, root `README.md`, `src/ocx/NOTES.md` (hand-written notes; `README.md` in `src/ocx` is generated).
2. `devcontainer-feature.json`: `id: "ocx"`, `version: "1.0.0"`, `name`, `description` (plain text), `documentationURL: https://ocx.sh`, `licenseURL`, `keywords` (ocx, package manager, ...). Declare `version` option (type string, `proposals`, default `latest`). Add `installsAfter: ["ghcr.io/devcontainers/features/common-utils"]` (soft, ID without tag). Add `containerEnv`/PATH only if not handled by `/usr/local/bin`.
3. `install.sh`: run as root, shebang decided by what the base image has (POSIX `sh` safest); resolve `_REMOTE_USER`/`_REMOTE_USER_HOME` for any per-user state; be idempotent (second install with other options must not fail); bootstrap `curl`/`ca-certificates` if missing (Alpine, Debian slim); verify checksums; clean package caches.
4. Tests: autogenerated test over a base-image matrix (debian, ubuntu, alpine, `mcr.microsoft.com/devcontainers/base:ubuntu`), scenarios for pinned version and non-root `remoteUser`, `duplicate.sh` for idempotence. Run `devcontainer features test -p . -i <img>` in CI; do not use `continue-on-error`.
5. Release workflow: `devcontainers/action@v1` with `publish-features: "true"`, `base-path-to-features: "./src"`, `generate-docs: "true"`, explicit `features-namespace: ocx-sh/devcontainer-features`, permissions `contents/pull-requests/packages: write`, `GITHUB_TOKEN` env, enable "Allow GitHub Actions to create and approve pull requests" in repo settings. Pin the action by SHA and set `devcontainer-cli-version` to avoid surprise CLI changes.
6. After the first publish: set the `ocx` package AND the namespace-root metadata package to public in GHCR; link packages to the repo; verify with `devcontainer features info tags ghcr.io/ocx-sh/devcontainer-features/ocx` and an anonymous pull.
7. Version discipline: any behaviour change bumps `version`; users reference `ghcr.io/ocx-sh/devcontainer-features/ocx:1`.
8. Index: PR to `devcontainers/devcontainers.github.io` `gh-pages` adding one `collection-index.yml` entry (five fields, `ociReference: ghcr.io/ocx-sh/devcontainer-features`, no scheme, passes `yamllint --strict`). Do this only after the package is public and a 1.x tag exists.
9. Dependabot/Renovate for action versions; optionally a scheduled test run to catch base-image drift.

## Not verified / open

- Where the `ghcr.io/devcontainers/index` crawler lives and its refresh cadence; time from PR merge to first appearance on containers.dev and in VS Code/Codespaces pickers.
- Whether VS Code's Feature picker and Codespaces use `keywords`, `documentationURL`, `deprecated`; any maintainer review criteria on index PRs (none published).
- Exact org-scoped GHCR visibility URL and whether the metadata package needs separate public toggling (inferred from anonymous-download requirement, S11).
- `features-namespace` default: action text says "source repo name", starter README says `<owner>/<repo>`; resolve by passing it explicitly and checking `info`.
- `mounts` type conflict (spec prose says object; schema says array).
- Layer-cache behaviour statements are Docker-semantics inference, not spec text. `install.sh` cwd comes from CLI source, not the spec.
- Pre-release semver tags (`1.0.0-rc.1`) handling by `publish`/action: not checked.
- Generated README template contents; whether `NOTES.md` is appended or placed in a fixed section.
- The `containers.dev/features` page text I fetched was truncated at 100k of 249k chars; feature/collection totals were not read (collection-index.yml itself has 327 entries).

## Sources (all fetched 2026-11-16)

| Tag | URL |
|---|---|
| S1 | https://containers.dev/implementors/features/ |
| S2 | https://containers.dev/implementors/features-distribution/ |
| S3 | https://github.com/devcontainers/cli/blob/main/src/spec-configuration/containerFeaturesConfiguration.ts |
| S4 | https://github.com/devcontainers/cli/blob/main/docs/features/test.md |
| S5 | https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md |
| S6 | https://github.com/devcontainers/feature-starter (README.md) |
| S7 | https://github.com/devcontainers/action and https://github.com/devcontainers/action/blob/main/action.yml |
| S8 | https://github.com/devcontainers/feature-starter/tree/main/.github/workflows (release.yaml, test.yaml) |
| S9 | https://containers.dev/guide/author-a-feature |
| S10 | https://github.com/devcontainers/cli/blob/main/src/spec-configuration/containerCollectionsOCIPush.ts ; `devcontainer features <cmd> --help` run on CLI 0.90.0 |
| S11 | https://containers.dev/guide/author-a-feature (section "Adding Features to the Index") |
| S12 | https://github.com/devcontainers/spec/blob/main/schemas/devContainerFeature.schema.json |
| S13 | https://containers.dev/features ; source https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/features.html |
| S14 | https://github.com/devcontainers/devcontainers.github.io/blob/gh-pages/_data/collection-index.yml |
| S15 | https://github.com/devcontainers/devcontainers.github.io/tree/gh-pages/.github/workflows (publish.yml, lint.yml), `.github/lint-config.yaml`, `CODEOWNERS` |
| S16 | https://containers.dev/collections |
| S17 | https://registry.npmjs.org/@devcontainers/cli/latest |
| S18 | https://github.com/devcontainers/cli/blob/main/package.json |
| S19 | https://github.com/devcontainers/cli (README) |
| S20 | https://github.com/anthropics/devcontainer-features (README) |
