# ocx bootstrap contract and option surface (for the Dev Container Feature)

Date: 2026-11-16

Commit SHA inspected per repo (shallow clones of `main` HEAD, 2026-11-16, plus two local checkouts):

| Repo | SHA |
|---|---|
| `ocx-sh/find_ocx` | `f99a38c5f3272dc4a14671174841da609810aa0e` |
| `ocx-sh/rules_ocx` | `e311b99cc83bb334edabfc82e7fffced63ca2339` |
| `ocx-sh/www-setup` | `1a91542af9e0cb928187ad2b0a006a4596a17884` |
| `ocx-sh/setup-ocx` | `eaeb6788da6191868a1310cc2bba93233b586369` |
| `ocx-sh/conventions` | `fe887c6c8af73e8f5ce3f80f7bd807e06f846371` |
| `ocx-sh/vscode-ocx` | `aadb2d55a9157553a0a7a401d7917aa5e940091f` |
| local `/home/mherwig/dev/ocx-sh/ocx` | `36ce3ca68d6f2d9550674aba8e0abc64af92c422` |
| local `/home/mherwig/dev/ocx-sh/website` | `a9dd6af515bb6244063c8ddab0ce5508b6d7e5a2` |

Installed CLI used for behavioural checks: `ocx 0.6.8`, which is also the newest stable release (`https://setup.ocx.sh/dist.json`, `latest`). Live checks (marked **[tested]**) were run 2026-11-16 on Linux x86_64 against `ocx.sh` with a scratch `OCX_HOME`.

Path shorthand: `WS` = `ocx-sh/www-setup`, `FO` = `ocx-sh/find_ocx`, `RO` = `ocx-sh/rules_ocx`, `SO` = `ocx-sh/setup-ocx`, `CV` = `ocx-sh/conventions`, `VS` = `ocx-sh/vscode-ocx`, `DOCS` = `/home/mherwig/dev/ocx-sh/ocx/website/src/content/docs`. The installer script and release artifacts are covered in `ocx-install-surface.md` (same directory) and not repeated here, except where the option table needs them.

## 1. `dist.json`

**What it is.** A Node-`dist`-style manifest listing every published ocx CLI release x build target with an inline sha256 and a download URL (`WS/scripts/gen-dist.sh:7-14`). It exists so installers resolve the version and the checksum from a different origin than the archive, with no GitHub API and no token on the install path (`WS/scripts/gen-dist.sh:14-22`).

**Where published.** `https://setup.ocx.sh/dist.json` (rolling, overwritten), `https://setup.ocx.sh/dist.json.sha256` (sha256sum-format sidecar), `https://setup.ocx.sh/dist/<sha256>.json` (immutable, append-only snapshot named by its own digest) (`WS/scripts/publish-dist.sh:9-21`; `WS/site/src/content/docs/reference.mdx:62-69`; snapshots cached one year). `/dist` and legacy `/releases` also serve it. Hosting is Bunny Edge Storage (`publish-dist.sh:9-10`). Live state: `schema` 1, `latest` = `{"version":"0.6.8","channel":"stable"}`, `latest_next` null, 304 rows, 10 targets, all rows `stable`, sidecar digest `ded01b4ba0550838860d6f846ce1e37e24ed5a64d81418c4d882b8a52b234f82`.

**Schema** (`WS/scripts/gen-dist.sh:29-47`, confirmed against the live file):

```
{ "schema": 1,
  "latest":      {"version":"0.6.8","channel":"stable"},   // newest stable, or null
  "latest_next": null,                                      // newest prerelease ("next" channel), or null
  "releases": [   // newest-first, targets sorted within a release
    {"version","channel","tag","target","filename","sha256","url"} ... ] }
```

Row example: `{"version":"0.6.8","channel":"stable","tag":"v0.6.8","target":"x86_64-unknown-linux-musl","filename":"ocx-x86_64-unknown-linux-musl.tar.gz","sha256":"<64 hex>","url":"https://github.com/ocx-sh/ocx/releases/download/v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz"}`. Targets present live: `{x86_64,aarch64}-unknown-linux-{gnu,musl}`, `{x86_64,aarch64}-apple-darwin`, `{x86_64,aarch64}-pc-windows-{gnullvm,msvc}` (older releases carry msvc, 0.6.8 carries gnullvm). Rows and the two `latest*` pointers are flat objects on purpose so jq-free shell parsers can `grep -o '{[^{}]*}'` them (`gen-dist.sh:24-27`). Targets are derived from each release's `sha256.sum` filenames, never hard-coded (`gen-dist.sh:41-43`).

**No signatures.** The schema has no signature, key or attestation field. The only integrity data is the per-archive sha256; its trust comes from being served from `setup.ocx.sh` while the bytes come from GitHub (`WS/src/install.sh:7`; `FO/ocx.cmake` header "Trust and mirrors"). A manifest URL of the form `.../dist/<sha256>.json` is verified against the digest in its own name (installer, `find_ocx`, `rules_ocx`); any other manifest URL is trusted as far as its transport (`FO/ocx.cmake:504-511`; `RO/ocx/private/download.bzl:36-38`; `WS/site/src/content/docs/mirrors.mdx:106-113`).

**Who generates it.** `WS/scripts/gen-dist.sh` reads the GitHub Releases API of `ocx-sh/ocx` (override `OCX_RELEASES_REPO`) plus each release's `sha256.sum` asset; skips drafts; any fetch failure exits 3 and prints nothing, never a partial manifest (`gen-dist.sh:49-52`). `WS/scripts/publish-dist.sh` retries generation 3x, then uploads manifest, sidecar and snapshot; it aborts before upload on failure so the live file is never clobbered (`publish-dist.sh:32-37,81-101`). Trigger: `WS/.github/workflows/update-dist.yml:3-8` runs on `repository_dispatch: ocx-released`, manual dispatch and hourly cron `17 * * * *`. The dispatch is sent by `ocx-sh/ocx` `.github/workflows/release.yml:567-593` (job `post-setup-dist`; its comment says the cron "in practice fires every ~7 hours"). Pre-releases are listed too (that is what `latest_next` is for).

**How each integration consumes it.**

| Integration | Reads `dist.json`? | How |
|---|---|---|
| `www-setup` installers | yes, live | `OCX_INSTALL_DIST_URL` default `https://setup.ocx.sh/dist.json`; latest = first row whose channel is `stable`; row gives sha256 + url (`WS/src/install.sh:83-98,572-628`; verification `:495-511`). |
| `find_ocx` | yes, **vendored copy** | Embedded in `FO/ocx.cmake:165-463` between `BEGIN/END OCX DIST SNAPSHOT` markers as `__OCX_DIST_JSON`; 288 rows, newest 0.6.6. Replaceable by `OCX_INSTALL_DIST_URL` or `ocx_bootstrap(DIST_MANIFEST ...)` (`ocx.cmake:504-511`). |
| `rules_ocx` | yes, **vendored copy** | `RO/dist/dist.json` (280 rows, newest 0.6.5), label default of `ocx.download(dist_manifest=)`; env `OCX_INSTALL_DIST_URL` replaces it (`RO/ocx/extensions.bzl:22-25`; `ocx/private/download.bzl:36-44`). |
| `setup-ocx` | no | Latest via `GET https://api.github.com/repos/ocx-sh/ocx/releases/latest` (`SO/src/version.ts:54`), archive and `<archive>.sha256` sidecar from the GitHub release (`SO/src/download.ts:127-138`, `src/constants.ts:147`). Same origin for bytes and checksum. |
| `conventions` setup action | no | Delegates to `setup-ocx` pinned by SHA with a fixed `version: 0.6.6` (`CV/.github/actions/setup/action.yml:52-58`). |
| `vscode-ocx` | no | Does not install ocx; needs it on PATH (topic 4). |

**Vendored locked copies: yes, two (`find_ocx`, `rules_ocx`).** Both treat the snapshot as the trust root for the CLI download: archive sha256 comes from the in-repo row, not from the network (`FO/ocx.cmake` "Trust and mirrors": "The module checks every archive against its row before extraction, whichever URL served the bytes"; `RO/agent-config/dist-snapshot.md:44-47`: "the sha256 values are the security boundary (mirrors can relocate artifacts, never alter them)"). Precision on "one release = one ocx version": each integration release has exactly **one default pin** (`FO/ocx.cmake:162` `__OCX_PIN_VERSION "0.6.6"`; `RO/ocx/private/versions.bzl:15` `DEFAULT_OCX_VERSION = "0.6.5"`), but the snapshot is the **whole historical manifest**, not only the pinned version, because a consumer may select any row (`rules_ocx` `ocx.download(version=...)`, `find_ocx` `OCX_INSTALL_VERSION`) (`RO/agent-config/dist-snapshot.md:16-22`). The pin is deliberate: "The ocx CLI declares no stability for its command-line surface across versions; ... therefore pins an exact version and is tested against exactly that version" (`FO/ocx.cmake:157-161`; `RO/versions.bzl:5-9`). `rules_ocx` also keeps a floor `MIN_OCX_VERSION = "0.6.1"` checked before any download (`versions.bzl:18`, `extensions.bzl:29-33`).

**Refresh mechanism (not Renovate).** A scheduled workflow plus a guarded script opens a PR; a human merges.
- `FO/.github/workflows/update-dist.yml:3-8` (cron `23 4 * * 1`, `workflow_dispatch`, `repository_dispatch: ocx-released`) runs `python3 scripts/update_dist.py` then `--check`; `peter-evans/create-pull-request` on branch `chore/update-dist` with PAT `DIST_UPDATE_TOKEN` (needed so CI runs on the PR and so the workflow files under `.github/workflows/` can change) (`update-dist.yml:30-51`).
- `RO/.github/workflows/update-dist.yml` (cron `17 4 * * 1`, same dispatch type) runs `scripts/bump_ocx.py`, same PR action and token.
- Both scripts move the snapshot, the pin and every `ocx-sh/setup-ocx` `version:` pin in the repo's workflows together, or none (`FO/scripts/update_dist.py:3-8`; `RO/.github/workflows/update-dist.yml:30-40`). Guards: refresh may only add rows (no rewrite, drop, duplicate, new column), `latest` must be `stable`, pin only moves forward, every row needs a 64-hex sha256 and a URL that allowlist-matches `https://github.com/ocx-sh/ocx/releases/download/<tag>/<filename>`, and a bump may not drop a target the outgoing pin covers; no override flag by design (`FO/scripts/update_dist.py:18-37`; `RO/agent-config/dist-snapshot.md:20-43,55-72`). PR bodies say "Do not merge on green alone": read the ocx changelog because the CLI is version-unstable.
- Observed lag, 2026-11-16: `rules_ocx` PR #34 "refresh dist.json and bump the ocx pin" open (pin 0.6.5, latest 0.6.8); `find_ocx` pin 0.6.6, no open PR (`gh pr list --head chore/update-dist`). The `ocx-released` dispatch type is declared in both workflows, but the only sender found is `ocx` -> `www-setup` (`ocx/.github/workflows/release.yml:587` posts only to `ocx-sh/www-setup`), so in practice both run on the weekly Monday cron. Whether another sender exists outside the six repos was not verified.
- Renovate is separate: the shared preset (`CV/renovate/default.json`) bumps `ocx.toml` tool pins (regex manager, `ocx.sh/<org>/<pkg>:X.Y.Z`, looked up on `ghcr.io/ocx-contrib/...`, `ocx.sh/ocx/cli` on `ghcr.io/ocx-sh/ocx/cli`) with `postUpgradeTasks: ["ocx lock"]` (`CV/renovate/default.json:29-39,170-191`; `CV/docs/contract.md:216-218`). It does not touch dist snapshots.

**How integration releases are cut.** Not automated off ocx releases: the update PR is merged by a human, then a release is a manual tag.
- `find_ocx`: tag `v*` triggers `release.yml`, which checks the tag equals `__OCX_MODULE_VERSION` in `ocx.cmake`, writes `SHA256SUMS` over `Findocx.cmake` and `ocx.cmake`, runs `git-cliff --latest`, publishes those three files (`FO/.github/workflows/release.yml:1-55`). Release v0.4.0 (2026-11-15) while the pin is 0.6.6: module version is independent of ocx version.
- `rules_ocx`: `git-cliff --bump`, edit `MODULE.bazel` version, tag `vX.Y.Z`; `release.yml` builds the BCR source archive and `integrity.txt`; BCR submission manual (`RO/agent-config/release.md:1-12`; release v0.5.1 assets: `rules_ocx-v0.5.1.tar.gz`, `integrity.txt`).
- `setup-ocx`: tag `v*` builds nothing new; creates the GitHub release with git-cliff notes and force-moves the major tag (`v1`) (`SO/.github/workflows/release.yml`). Current v1.4.1.

## 2. Option and env surface

"-" means the integration has no such knob. Source for each cell is in the notes under the table.

| Concept | www-setup installer (env / flag) | find_ocx (CMake cache var / kw) | rules_ocx (module-extension attr / env) | setup-ocx (action input) |
|---|---|---|---|---|
| Version pin | `OCX_INSTALL_VERSION`, `--version V` | `OCX_INSTALL_VERSION`, `ocx_bootstrap(VERSION)`; default = module pin | `ocx.download(version=)`; default `DEFAULT_OCX_VERSION`, floor 0.6.1 | `version` (default `latest`) |
| "latest" | empty = newest **stable** in `dist.json`, never a prerelease | none: always an exact pin (floating only for `find_ocx` itself via `ocx_self_update`) | none: exact pin | `latest` = GitHub `releases/latest` |
| Dist manifest override | `OCX_INSTALL_DIST_URL` (default `https://setup.ocx.sh/dist.json`) | `OCX_INSTALL_DIST_URL`, `ocx_bootstrap(DIST_MANIFEST)` | env `OCX_INSTALL_DIST_URL`, attr `dist_manifest` (label) | - |
| Download mirror | `OCX_INSTALL_MIRROR_URL` -> `<mirror>/<tag>/<filename>` | `OCX_INSTALL_MIRROR_URL`, same rewrite | env `OCX_INSTALL_MIRROR_URL`, same rewrite | - |
| Checksum / signature toggle | none; fail closed (exit 4 on mismatch) | none; checked before extraction | none; `sha256=` passed to `ctx.download` | none; `.sha256` sidecar always |
| Platform / libc | auto (gnu vs musl by evidence, exit 7 if undecidable) | `TRIPLE` kw, `OCX_DEFAULT_PLATFORM` | `triple` attr | `libc` = `gnu`\|`musl`, auto-detect |
| Install location | `OCX_HOME` (default `~/.ocx`); `OCX_INSTALL_NO_SETUP=1` copies binary into `$OCX_HOME/symlinks/ocx.sh/ocx/cli/current/content/bin` | `OCX_BOOTSTRAP_CACHE` (default `$XDG_CACHE_HOME/find_ocx`, `%LOCALAPPDATA%/find_ocx`) | repo `@ocx_tool` in Bazel output base | `RUNNER_TOOL_CACHE/ocx/<version>`; output `ocx-path` |
| `OCX_HOME` | `OCX_HOME` | `OCX_HOME` (site class, snapshotted) | `OCX_HOME` (site class); attr `isolated_home` = repo-local store | `ocx-home` (default `~/.ocx`), exported as `OCX_HOME` |
| `OCX_MANAGED_CONFIG` | env read by `ocx self setup`; embedded value passed as `--managed-config` only when env unset | site class, forwarded to every ocx call | site class, forwarded; attr `no_config` blocks the tier | input `managed-config` -> `ocx config setup --managed-config <ref>`; also fires when ambient env is non-empty |
| Registry mirrors / index | - (only managed config) | `OCX_MIRRORS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`, `OCX_INSECURE_REGISTRIES`, `OCX_PATCHES`; `ocx_index()` | same names as site env; attrs `index`, `config`, `patch_snapshot` | - |
| Offline / frozen | - (needs network) | `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_BOOTSTRAP=OFF` (no download) | `OCX_OFFLINE`, `OCX_FROZEN` (site env) | - |
| Auth / token | none on install path (anonymous read) | none for downloads (anonymous); `OCX_AUTH_<REG>_{TYPE,USER,TOKEN}` forwarded to ocx, never cached | none for downloads; `OCX_AUTH_*` forwarded | `github-token` (default `github.token`) for API + release download |
| CA / proxy | `OCX_INSTALL_CA_BUNDLE` (PEM path or inline); also exports `OCX_EXTRA_CA_CERTS`/`SSL_CERT_FILE` to `ocx self setup` | `OCX_INSTALL_CA_BUNDLE` (path); `OCX_EXTRA_CA_CERTS` | `OCX_EXTRA_CA_CERTS` only; download CA bundle is a documented gap | - (runner proxy env) |
| Verification policy of packages | - | `ocx_policy(ALLOW_UNVERIFIED ALLOW_YANKED SIGSTORE_TRUSTED_ROOT)` -> `OCX_NO_VERIFY`, `OCX_ALLOW_YANKED`, `OCX_SIGSTORE_TRUSTED_ROOT` | `ocx.policy(allow_unverified, allow_yanked, sigstore_trusted_root)` | - |
| Project sync | - | `ocx_project(TOML LOCK GROUPS BINS PULL)`, `OCX_PROJECT_FILE`, `OCX_PULL` | `ocx.project(ocx_toml, ocx_lock, groups, bins, platform)` | `project` (default `ocx.toml`; empty disables), `groups`, `working-directory` |
| Cache | - | - | - | `cache` (default true), `cache-suffix` |
| Behaviour knobs | `OCX_INSTALL_NO_SETUP`, `OCX_INSTALL_NO_SMOKETEST`, `OCX_INSTALL_FORCE`, `OCX_INSTALL_QUIET`, `OCX_INSTALL_PRINT_PATH`, `OCX_INSTALL_DOWNLOADER`, `OCX_NO_MODIFY_PATH`, `OCX_INSTALL_REPO` | `OCX_BOOTSTRAP` = `ON`\|`ALWAYS`\|`OFF`, `OCX_ALLOW_FLOATING`, `OCX_REFRESH`, `OCX_SELF_UPDATE_VERSION`, `OCX_SELF_UPDATE_URL` | `isolated_home`, `no_config`, `bins` (lazy launchers) | outputs `version`, `ocx-path`, `cache-hit`, `project-loaded`, `project-cache-hit`, `managed-config-adopted` |

Table sources.
- Installer: names and the naming grammar at `WS/src/install.sh:70-125` (header comment: tier 1 shared OCX env `OCX_HOME`, `OCX_NO_MODIFY_PATH`, `OCX_MANAGED_CONFIG`; tier 2 installer-only `OCX_INSTALL_*` with "bare nouns" for values, `_URL` for endpoints, `NO_` for opt-outs, bare verbs for opt-ins); CA bundle `:116,249,389-390` and `:802-842`; managed-config forwarding `:116-122`; libc detection `:255-284`; exit codes `:6`. Embedded-config placeholders `@OCX_INSTALL_DIST_URL@`, `@OCX_INSTALL_CA_BUNDLE@`, ... let an operator bake defaults into a served copy of the script (`WS/site/src/content/docs/mirrors.mdx:39-53`; `install.sh:55`).
- `find_ocx`: `FO/ocx.cmake:489-625` (`.. variable::` blocks), "Environment classes" table `:625-660` and rows `:672-714`, bootstrap order `OCX_EXECUTABLE` > `PATH` > pinned CLI. Variables follow a snapshot pattern: env value copied into the CMake cache at first configure, `-DVAR=` overrides, `-DVAR=` (empty) clears (`ocx.cmake:480-488,667-672`).
- `rules_ocx`: tag classes `RO/ocx/extensions.bzl:19-211`; env classes `RO/ocx/private/repo_utils.bzl:44-98` (`OCX_MIRRORS`, `OCX_INSECURE_REGISTRIES`, `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_REMOTE`, `OCX_JOBS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`, `OCX_MANAGED_CONFIG`, `OCX_EXTRA_CA_CERTS` as "site"); download envs `RO/ocx/private/download.bzl:36-44`. Mirror auth gap and CA-bundle gap: `RO/agent-config/mirror-auth.md`.
- `setup-ocx`: `SO/action.yml:7-65`; validation `SO/src/setup.ts:25-36`; exports `OCX_NO_UPDATE_CHECK=1` always and `OCX_LOG=debug` when debug is on (`setup.ts:45-50`); `OCX_HOME` export `SO/src/project.ts:43-46,111`; groups join `-g a,b` (`project.ts:131-137`).
- `conventions` setup action inputs: `groups`, `bazel-cache`, `cache-read-auth`, `cache-write-auth`, `otel-auth`, `report`, `suite` (`CV/.github/actions/setup/action.yml:11-47`); it passes only `version` (hard-pinned 0.6.6) and `groups` to `setup-ocx`. Not relevant to a devcontainer beyond `groups`.
- `vscode-ocx` settings (`VS/package.json` `contributes.configuration`): `ocx.path.executable` (default `ocx`, machine-overridable), `ocx.enable`, `ocx.project`, `ocx.watchForChanges`, `ocx.restart.automatic`, `ocx.env.applyToTerminals` (default false), `ocx.groups`, `ocx.extraEnv` (extra env for the ocx child, e.g. `OCX_HOME`, credentials).

**Names consistent across integrations (the feature should reuse them).**
1. `OCX_INSTALL_VERSION`, `OCX_INSTALL_DIST_URL`, `OCX_INSTALL_MIRROR_URL`, `OCX_INSTALL_CA_BUNDLE`: identical meaning in installer, `find_ocx`, `rules_ocx` (the first two plus mirror in `rules_ocx`). `find_ocx` states "The setup.ocx.sh installer has the same variable" (`FO/ocx.cmake:525,536`); `rules_ocx` notes "Keep the knob naming aligned across all three" (`RO/agent-config/mirror-auth.md`).
2. Mirror URL rewrite shape is always `<mirror>/<tag>/<filename>`, mirror must allow anonymous read, and the manifest sha256 stays the trust boundary ("a mirror can move bytes but cannot change them", `FO/ocx.cmake:513-516`). `ocx-mirror dist sync` produces the layout (`WS/site/src/content/docs/mirrors.mdx:13-14`).
3. ocx's own env (read by the binary, forwarded unchanged by every integration as the "site" class): `OCX_HOME`, `OCX_MANAGED_CONFIG`, `OCX_MIRRORS`, `OCX_INDEX`, `OCX_DEFAULT_REGISTRY`, `OCX_INSECURE_REGISTRIES`, `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_EXTRA_CA_CERTS`, `OCX_AUTH_<REGISTRY>_*`.
4. "Pinned class" values that every build-tool integration forces on its own ocx calls: `OCX_NO_CONSENT=1`, `OCX_SELF_UPDATE=manual`, `OCX_NO_CONFIG_REFRESH=1`, `OCX_QUIET=0`, `OCX_NO_PROJECT=1`, `OCX_PROJECT` unset (`FO/ocx.cmake:702-714`; `RO/repo_utils.bzl:79-98`). `setup-ocx` instead exports `OCX_NO_UPDATE_CHECK=1` (`SO/src/setup.ts:46`); the official Docker images bake `OCX_NO_UPDATE_CHECK=1` (`ocx-install-surface.md` topic 6).
5. `version` (input/attr) and `groups` (comma list in `setup-ocx`/`conventions`, `GROUPS` in `find_ocx`, `groups` in `rules_ocx`, `ocx.groups` in `vscode-ocx`) are the stable user-facing names. `libc` (`gnu|musl`) exists in `setup-ocx` only; `find_ocx`/`rules_ocx` use the full target triple.
6. Boolean grammar: ocx reads truthy spellings in any case (`1 true yes on ...`); `OCX_OFFLINE`, `OCX_FROZEN`, `OCX_NO_CONSENT`, `OCX_NO_VERIFY` exit 78 on any other value (`DOCS/reference/environment.md:8-18`). Installer truthy set is `1 true yes TRUE YES True Yes` (`WS/src/install.sh:101-106`).

**`OCX_MANAGED_CONFIG` exactly.**
- Meaning: an OCI reference (e.g. `ocx.sh/acme/fleet`) to a "managed-config" package, one `config.toml` published with `ocx config push`, that the organization wants every host to converge to (mirror map, patch registry, trust policy). It sits as the `[managed]` tier in ocx's config chain, merged above the user config, with zero network on ordinary commands (`DOCS/guides/manage-config-centrally.mdx:15,49-53`; `DOCS/reference/environment.md:367-379`).
- What ocx does differently when it is set: it overrides `[managed].source` for that invocation and everything it spawns (forwarded to children), is never written back to disk, and **resolving the tier never fetches**: pair it with an explicit `ocx config update` (or `ocx config setup`) to sync (`environment.md:367-379`; guide line 49). `OCX_NO_CONFIG=1` suppresses it, and `OCX_NO_CONFIG_REFRESH=1` kills the background refresh (`environment.md:418-446`). A required-but-unsynced managed config makes commands exit 78 (`FO/ocx.cmake:997`: "run 'ocx config update' for a managed config that was never synced (or set OCX_NO_CONFIG=1 ...)"; `RO/extensions.bzl:79-85`).
- Who sets it: the operator, per environment. Precedence for adoption is flag, then `OCX_MANAGED_CONFIG`, then existing seed in `$OCX_HOME/config.toml` (`ocx config setup --help` **[tested]**, 0.6.8). Ephemeral runners set the env var and sync once at job start; long-lived hosts adopt a persistent seed with `ocx config setup --managed-config <ref>` or `ocx self setup --managed-config <ref>` (`manage-config-centrally.mdx:45-53`). `ocx config setup` with nothing configured at any level exits 64 (`ocx config setup --help` **[tested]**); a bare `ocx config update` with no managed config reports `Status not_configured` and exits 0 **[tested]**. Re-sync once a synced copy exists is best-effort (fetch failure warns, exit 0).
- Integrations: `setup-ocx` runs `ocx config setup [--managed-config REF]` before project activation when the input or ambient env is non-empty, requires ocx >= 0.4.3, hard-fails on non-zero (`SO/src/managed-config.ts:7-62`). `find_ocx` and `rules_ocx` forward it and expose an opt-out (`NO_CONFIG` kw / `no_config` attr). The installer forwards the embedded value only (`install.sh:116-122`).
- Trust scope: the registry hosting the config package is a trust anchor equal to `[mirrors]`/`[patches]` registries (`manage-config-centrally.mdx:150-156`).

## 3. `OCX_*` variables the ocx CLI reads

Source of truth: the Rust env registry (`ocx/crates/ocx_env/src/`, with call sites in `crates/ocx_config`, `ocx_cli`, `ocx_shell`, `ocx_oci`, `ocx_trust`, `ocx_sign`) and the generated reference `DOCS/reference/environment.md` (headings at lines 20-770; `OCX_*` names there match the names found by grepping `"OCX_...` literals in `crates/`, apart from test fixtures and the withdrawn spellings in `crates/ocx_env/src/retired.rs`). Withdrawn and ignored: `OCX_GLOBAL` (use `--global`; a set value prints one notice), `OCX_LOG`, `OCX_NO_COMPLETIONS`, `OCX_REGISTRY_DEFAULT`, `OCX_VERIFY` (retired; tests only, `retired.rs:100,108`; `context.rs:3001-3123`).

Legend for the container column: **B** = sensible to set at image build (`containerEnv`), **U** = leave to the user/org at runtime, **-** = do not set.

| Variable | Meaning | Container |
|---|---|---|
| `OCX_HOME` | Data root (store, index, locks, config), else `~/.ocx` (`environment.md:229`). Must be readable by every user of the store; a root-created home is unusable by another uid until `chmod -R a+rwX` (`ocx-install-surface.md` topic 3, tested) | B only if one user; else leave default per-user |
| `OCX_NO_UPDATE_CHECK` | Kill switch for background self-update and drift checks; also off when `CI` truthy, stderr not a tty, `OCX_OFFLINE` set (`:512`) | B (`1`), as the official images do |
| `OCX_NO_CONSENT` | Commands that stamp shell-activation consent (`add remove lock update upgrade pull exec init`) write none; set in pipelines/images, never an interactive profile, else a lock that grows leaves the project inert (`:450`; `DOCS/integration/unattended-ci.mdx:32-40`) | **U** for a dev container (the developer wants the stamp); B only for CI images |
| `OCX_CONSENT_PATHS` | `PATH`-style list of project dirs (trailing `/*` = subtree) the shell hook may activate without a stamp (`:164`); e.g. `/workspaces/*` | B (feature option) |
| `OCX_CONSENT_NAMESPACES` | Comma list `<registry>/<ns>[/*]`; a project whose whole lock names sources inside activates without grant (`:148`) | U |
| `OCX_NO_HOOK` | Disables the per-prompt shell hook; `ocx self activate` still runs (`:466`) | U |
| `OCX_NO_COMPLETION` | `ocx self activate` skips completion block (`:404`) | U |
| `OCX_NO_MODIFY_PATH` | `ocx self setup` edits no profile; mirrors `--no-modify-path` (`:482`) | B when baking a binary-only install |
| `OCX_MANAGED_CONFIG` | See topic 2 (`:367`) | U (org policy) or B in an org-specific base image |
| `OCX_NO_CONFIG` / `OCX_CONFIG` | Skip discovered config chain (also drops managed tier) / explicit config file highest tier (`:134,418`) | U; `OCX_NO_CONFIG` is hermetic-CI only |
| `OCX_NO_CONFIG_REFRESH` | Kill switch for managed-config background refresh (`:433`) | U |
| `OCX_DEFAULT_REGISTRY` | Registry for bare identifiers, default `ocx.sh` (`:175`) | U |
| `OCX_MIRRORS` | JSON map upstream host -> mirror string or `{"registry"?,"index"?}` (`:381`) | U (org) |
| `OCX_INDEX` | Local index directory replacing `$OCX_HOME/index/`; "meant for a bundled copy in a GitHub Action, Bazel rule or devcontainer" (`:259`) | B only if the feature ships an index snapshot (offline use) |
| `OCX_REMOTE` | Use remote index by default (`:635`) | U |
| `OCX_OFFLINE` | No network; resolve from local index/store only (`:540`). A cold store exits 79 under `--offline` **[tested]** | U |
| `OCX_FROZEN` | Tag-only reference missing from local index errors instead of fetching; digest pins still fetch (`:203`) | U |
| `OCX_INSECURE_REGISTRIES` | Comma `host[:port]` allowed over plain HTTP (`:274`) | U |
| `OCX_EXTRA_CA_CERTS` | Extra CA roots (path or inline PEM) for registry, index, forge, Sigstore clients (`:188`); ocx ships `webpki-root-certs` so no CA package is needed (`ocx-install-surface.md` topic 2) | U (corporate proxy CA) |
| `OCX_AUTH_<REGISTRY>_TYPE/_USER/_TOKEN` | Per-registry credentials; slug = non-alphanumerics replaced by `_` (`:72-104`) | **U, never bake** |
| `OCX_JOBS` | Max parallel root-package pulls (`:290`) | U |
| `OCX_PROJECT`, `OCX_NO_PROJECT`, `OCX_CEILING_PATH` | Explicit project file; skip project discovery; stop the cwd walk for `ocx.toml` (`:579,498,122`) | U |
| `OCX_TOOLCHAIN_DIR`, `OCX_TOOLCHAIN_ACTIVATE` (`env`/`bin`/`none`), `OCX_TOOLCHAIN_PINNED`, `OCX_TOOLCHAIN_UPDATE` | Where project toolchain homes render; activation mode; digest-pinned composed paths; drift-check policy (`:710,696,720,737`) | U (`OCX_TOOLCHAIN_DIR` outside `$HOME`/`$OCX_HOME` is refused with 78, `RO/repo_utils.bzl:93-97`) |
| `OCX_LAZY_MODE` (`never`/`always`), `OCX_LAZY_REPORT` (`silent`/`progress`) | Eager vs shim-on-first-use materialization; not forwarded (`:320,336`) | U |
| `OCX_SELF_UPDATE` (`notify`/`apply`/`manual`), `OCX_UPDATE_CHECK_INTERVAL` | Self-update policy and throttle; not forwarded (`:649,753`) | U (`OCX_NO_UPDATE_CHECK=1` covers images) |
| `OCX_NO_VERIFY`, `OCX_ALLOW_YANKED` | Skip policy-gated auto-verify; allow yanked index entries (`:526,20`); weaken posture | **U, never bake** |
| `OCX_SIGSTORE_TRUSTED_ROOT` | Trusted-root JSON for `ocx package verify` (`:680`) | U |
| `OCX_PATCHES`, `OCX_PATCH_SNAPSHOT` | JSON `[patches]` config; frozen patch digests (`:555,563`) | U |
| `OCX_NO_CODESIGN` | Skip ad-hoc macOS codesign (`:396`) | - (macOS only) |
| `OCX_LOG_LEVEL`, `OCX_LOG_CONSOLE`, `OCX_QUIET`; fallback `RUST_LOG` | Logging and stdout report (`:359,351,595,1103`) | U |
| `OCX_RECORDS_DIR`, `OCX_RECORDS_NAME` | Execution-record sink and filename template (`:603,618`) | U |
| `OCX_BINARY_PIN` | Set by ocx on every spawn: absolute path of the running ocx (`:106`) | - (written by ocx) |
| `OCX_KEY_PASSWORD`, `OCX_SIGNING_KEY`, `OCX_IDENTITY_TOKEN` | Signing key password, key PEM, OIDC token (publishers only) (`:305,665,244`) | **U, never bake** |
| `OCX_ANNOUNCE_TOKEN`, `OCX_ANNOUNCE_GIT_TOKEN`, `OCX_ANNOUNCE_GIT_USERNAME` | Forge credentials for `ocx package announce`/`claim` (`:57,32,47`) | **U, never bake** |
| `__OCX_ENV_STATE`, `__OCX_ENV_PWD`, `__OCX_ENV_STOOD_DOWN`, `__OCX_CREDENTIAL_HELPER` | Internal plumbing between the shell hook, parent and child ocx (`:771-818`) | - |

External variables ocx reads that matter in a container: `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`/`NO_PROXY` (and lower-case), `CI`, `NO_COLOR`, `TMPDIR`, `HOME`, `XDG_*`, `ZDOTDIR` (`environment.md:820-1250`). Installer-only (not read by the binary): `OCX_INSTALL_*` (topic 2).

## 4. `vscode-ocx`

- **Published, both registries.** VS Code Marketplace: `ocx-sh.ocx` version **0.1.3**, last updated 2026-08-11T21:25Z, validated/public, 176 installs (gallery `extensionquery` for `ocx-sh.ocx` **[tested]**, 2026-11-16). Open VSX: `https://open-vsx.org/api/ocx-sh/ocx`, versions 0.0.1 through 0.1.3, 1928 downloads, signed (`.sigzip`) **[tested]**. Publish workflow `VS/.github/workflows/release.yml:68-74` (`vsce publish --azure-credential`, `ovsx publish` with `OVSX_PAT`).
- **Exact ID: `ocx-sh.ocx`** (publisher `ocx-sh`, name `ocx`; `VS/package.json` `publisher`, `name`; version 0.1.3). Display name "OCX". Requires VS Code `^1.96.0`. Repo `https://github.com/ocx-sh/vscode-ocx`, commit `aadb2d55` (2026-08-11).
- **What it does** (`VS/README.md`, `VS/package.json`): activates on `workspaceContains:**/ocx.toml`; runs `ocx --format json --project <ocx.toml> env [--group ...]` via `execFile` (`VS/src/ocx.ts:97-115`) and injects the composed `PATH`/variables into the extension host (so language servers find ocx-managed tools) and, opt-in (`ocx.env.applyToTerminals`, default false), into new terminals and tasks. Prompts to restart extensions when the env changes. Live reload on `ocx.toml`/`ocx.lock` changes. Commands: `OCX: Reload/Reset Environment`, `Restart Extensions`, `Show Output`, `Initialize ocx.toml` (`ocx init`), `Resolve Lockfile` (`ocx lock`), `Pull Tools` (`ocx pull`, forwards `ocx.groups`), `Upgrade Tools` (`ocx upgrade`), `Clean Object Store` (`ocx clean`). Runs only in trusted workspaces (README).
- **Needs from the environment:** an `ocx` executable reachable as `ocx.path.executable` (default `ocx`, resolved on `PATH`; absent -> status shows not-found, `VS/src/ocx.ts:112-114,223`). It never installs ocx. `ocx env` composes from the lock and installed packages, so `ocx pull` must have run for tools to resolve (**not tested** whether `ocx env` auto-installs missing tools: the docs say `exec`/`env` auto-install on demand, `environment.md:526-538`). `ocx.groups` needs an ocx whose `ocx env` accepts `--group` (`VS/src/ocx.ts:121-131`). Env for the child can be set via `ocx.extraEnv` (e.g. `OCX_HOME`).
- **Recommendation for `customizations.vscode.extensions`:** include `ocx-sh.ocx`. It is harmless without an `ocx.toml` (activates only on `**/ocx.toml`), published on Marketplace and Open VSX, and complements a feature that puts `ocx` on PATH. Suggested companion settings from the feature: none required; document `ocx.env.applyToTerminals` as user opt-in. Caveat: version 0.1.x, 176 Marketplace installs, only the maintainers' releases, and the extension host sees `ocx` only if it is on the PATH of the server process (a `/usr/local/bin/ocx` install satisfies that).

## 5. Project-state commands for lifecycle hooks

All behaviour **[tested]** on ocx 0.6.8 in a scratch dir with `OCX_HOME` pointed at an empty directory, `OCX_NO_UPDATE_CHECK=1`, unless a doc is cited.

| Command | Purpose | No `ocx.toml` | Missing `ocx.lock` | Network | Idempotent |
|---|---|---|---|---|---|
| `ocx pull [-g GROUPS] [-p PLATFORM] [NAME...]` | Fetch the digest-pinned `ocx.lock` entries of the selected groups (default group without `-g`; `-g all` = every group) into the store, then render `<project>/.ocx/toolchain` | exit **64**: `no ocx.toml found in <cwd> or any parent; run 'ocx init'` | exit **78**: `ocx.lock not found ...; run 'ocx lock'` | yes for cold store; `--offline pull` works with a warm store (rc 0), cold store exits 79 `package not found` | yes: second and third run rc 0; only cached content skipped |
| `ocx pull --dry-run` | Preview cached vs would-fetch, writes nothing (`ocx pull --help`) | 64 | 78 | none beyond local index | read-only |
| `ocx lock` | Resolve tags in `ocx.toml` to digests, write `ocx.lock` | 64 | creates it | yes (resolves tags) | yes |
| `ocx lock --check` | Verify lock matches toml; no network, no write | 64 | 78 (`unattended-ci.mdx:46-48`); stale lock 65 | no | read-only |
| `ocx env --shell=bash` / `ocx --offline env --shell=bash` | Print eval-safe exports for the project toolchain (`ocx env --ci=github` writes the CI channel) | 64 | - | none for installed packages; auto-install on demand otherwise | read-only |
| `ocx exec [-g G] -- cmd` (alias `x`) | Run a command in the composed environment | 64 | 78 / 65 stale | auto-installs on demand | yes |
| `ocx config update` | Sync the managed-config snapshot | `Status not_configured`, exit **0** | n/a | yes when configured | yes |
| `ocx init` | Create a minimal `ocx.toml` | creates it, exit 0 | - | no | not tested on an existing file |

Exit-code meanings relevant to hooks: 64 usage/no project, 65 stale lock or yanked entry, 78 config/missing lock, 79 not found/offline, 81 unknown tag under `--frozen` (`unattended-ci.mdx:46-52`; `environment.md:20-30`).

**Recommended hook: `ocx pull`** (default group; add `-g all` or the project's groups to pre-warm more). It is the command documented for devcontainers and Docker: `postCreateCommand` runs `ocx pull` then wires the shell with `eval "$(ocx --offline env --shell=bash)"` (`DOCS/integration/devcontainers-and-editors.mdx:76-84`, via `ocx-install-surface.md` topic 4), and `RUN ocx pull` after `COPY ocx.toml ocx.lock` in Dockerfiles (`DOCS/integration/docker.mdx:64-76`). Because it exits 64 when no project exists, a hook must guard: `[ -f ocx.toml ] && ocx pull || true`, or `ocx pull ... || [ $? -eq 64 ]`. Consent side effect: `ocx pull` stamps shell-activation consent for the project unless `OCX_NO_CONSENT=1`/`--no-consent`; in a dev container the stamp is usually wanted, so the shell hook activates on next prompt (`environment.md:450-465`).

**How the other integrations invoke project sync.**
- `setup-ocx`: if `project` file exists (default `ocx.toml` in `working-directory`): `ocx --project <file> pull [-g a,b]` then `ocx --project <file> env --ci=github` (explicit `=github`, so no provider autodetect exit 64); skips quietly when the file is absent, warns if `ocx.lock` is missing (`SO/src/project.ts:54-97,131-147`). Floor: ocx >= 0.3.5 (`SO/src/setup.ts:14`). Cache key hashes `ocx.lock` + ocx version + libc (`SO/src/project.ts:114-122`).
- `conventions` setup action: no ocx call of its own; relies on `setup-ocx` project auto-load with `groups`. The repo task `setup` (`CV/src/taskfiles/baseline.taskfile.yml:15-33`; `CV/docs/contract.md:30`) runs `ocx pull` (all groups, as the task defines), `grim install`, and hook install, guarded by a `status:` check `[ -z "$(ocx pull --dry-run 2>/dev/null | tail -n +2 | grep -v " cached$")" ]`; `lock:check` = `ocx lock --check`. Renovate then runs `ocx lock` as a post-upgrade task.
- `find_ocx`: `ocx_project(...)` runs `ocx` at configure time with the pinned env (`OCX_NO_CONSENT=1`, `OCX_NO_PROJECT=1`); stale or missing lock -> configure error text points to `ocx lock` (`FO/ocx.cmake:997`). `rules_ocx`: `ocx --project ... pull`/`exec --pinned` with the same pinned env class.

## 6. Test and release patterns worth mirroring

- **`setup-ocx`**: unit tests (bun), `verify-basic` on ubuntu including a `libc: musl` leg, `verify-deep` matrix `ubuntu / ubuntu+musl / macos / windows` x `version: latest` with warm-cache then cache-hit verification (`SO/.github/workflows/verify-deep.yml:16-30,63-84`). Dependabot weekly for npm and actions (`SO/.github/dependabot.yml`).
- **`find_ocx`**: CI matrix `ubuntu / macos / windows` x CMake 3.25 / 3.31 / 4.4 against the live ocx.sh registry plus per-example runs (`FO/.github/workflows/ci.yml:38-92`); bootstrap tests with a local mirror fixture (`tests/fixtures/mirror/`); Renovate weekly (actions SHA-pinned, `ci(deps)`), dist refresh by the guarded workflow.
- **`rules_ocx`**: `verify-basic` on ubuntu, `verify-deep` on `ubuntu / macos / windows` (`RO/.github/workflows/verify-deep.yml:25-32`); `task dist:check` (offline `bump_ocx.py --check`) runs in `task lint` on every PR so a hand-edited snapshot row fails CI (`RO/agent-config/dist-snapshot.md:62-72`). Renovate via the shared conventions preset (`RO/renovate.json`).
- **`www-setup`** (the installer a feature would wrap): per-installer smoke matrix `alpine / fedora / ubuntu` x `amd64 / arm64 (QEMU)` and an activation matrix per shell (`WS/.github/workflows/test-docker-matrix.yml:35-139`), nightly to catch upstream distro image breakage; bats tests with a local HTTPS fixture server for env knobs (`WS/tests/install/env-knobs.bats`). A devcontainer feature should mirror: musl + glibc legs, amd64 + arm64, alpine + debian/ubuntu bases, a mirror/offline fixture test, and a "latest" leg separate from the "pinned" leg.
- **Pinning discipline common to all:** exact pin of the ocx CLI per integration release, tested only against that version, bumped by PR with human changelog review; actions SHA-pinned; Renovate preset from `conventions` (weekly Monday, `minimumReleaseAge: 7 days`, `chore(deps)` / `ci(deps)`, `CV/renovate/default.json`); conventional commits + `git-cliff` for notes; tag `v*` triggers release.
- **Release cadence:** not automated end to end (see topic 1). All three wrapper integrations lag the latest ocx by days to weeks (`rules_ocx` pin 0.6.5, `find_ocx` pin 0.6.6, `conventions` pin 0.6.6, latest 0.6.8).

## Implications for the feature

**Proposed options** (feature option ids are camelCase; the devcontainer runner uppercases them to env names, `version` -> `VERSION`, `distUrl` -> `DISTURL`, per `devcontainer-feature-spec-and-distribution.md:38`; `install.sh` maps them to the `OCX_INSTALL_*` names that the installer, `find_ocx` and `rules_ocx` already share):

| Option id | Type / default | Maps to | Notes |
|---|---|---|---|
| `version` | string, default `pinned`; proposals `pinned`, `latest`, `X.Y.Z` | `OCX_INSTALL_VERSION` semantics | `pinned` = the ocx version baked into this feature release (matches `find_ocx`/`rules_ocx` default); `latest` = newest stable row of live `dist.json` (matches installer; unlike `setup-ocx`, never a prerelease); explicit `X.Y.Z` resolved from the baked snapshot first |
| `distUrl` | string, default `` | `OCX_INSTALL_DIST_URL` | replaces the baked snapshot; a `https://setup.ocx.sh/dist/<sha256>.json` URL is self-verifying, others only as trusted as transport |
| `mirrorUrl` | string, default `` | `OCX_INSTALL_MIRROR_URL` | rewrite to `<mirror>/<tag>/<filename>`, anonymous read, sha256 still enforced |
| `caBundle` | string (path inside image, build context cannot carry host paths) | `OCX_INSTALL_CA_BUNDLE` | for TLS-intercepting proxies during build; also persist as `OCX_EXTRA_CA_CERTS` in `containerEnv` only if the user asks |
| `libc` | string enum `auto\|gnu\|musl`, default `auto` | `setup-ocx` `libc` | prefer musl on glibc < 2.34 (`ocx-install-surface.md` open item) |
| `managedConfig` | string, default `` | `OCX_MANAGED_CONFIG` | sets `containerEnv.OCX_MANAGED_CONFIG` and runs `ocx config setup --managed-config <ref>` at first start (needs network), as `setup-ocx` does; ocx >= 0.4.3 |
| `ocxHome` | string, default `` (use per-user `~/.ocx`) | `OCX_HOME` | only set `containerEnv.OCX_HOME` when explicitly given; root-created homes are unusable by `remoteUser` |
| `installDir` | string, default `/usr/local/bin` | binary location | system-wide binary like the documented `COPY ... /usr/local/bin/ocx` recipe |
| `noUpdateCheck` | boolean, default `true` | `OCX_NO_UPDATE_CHECK=1` | as the official Docker images |
| `consentPaths` | string, default `/workspaces/*` | `OCX_CONSENT_PATHS` | lets the shell hook activate a fresh checkout without a stamp |
| `syncOnCreate` | boolean, default `true` | `postCreateCommand` | run guarded `ocx pull` (topic 5) as `remoteUser` |
| `groups` | string, default `` | `ocx pull -g` | comma list, same name and format as `setup-ocx`/`ocx.groups` |
| `installVsCodeExtension` is not an option | - | `customizations.vscode.extensions: ["ocx-sh.ocx"]` | static in `devcontainer-feature.json` |

Do not expose: checksum off-switch (no integration has one), tokens/credentials (`OCX_AUTH_*`, `OCX_NO_VERIFY`, `OCX_ALLOW_YANKED` stay user-side), registry/mirror maps (`OCX_MIRRORS` etc. are org config; delivered via `managedConfig` or the user's `containerEnv`). Env passthrough of ocx's own `OCX_*` variables needs no feature option: they are plain `containerEnv`/`remoteEnv`.

**Verdict: ship a locked snapshot per feature version and republish on every ocx release, with `latest` as an explicit opt-in resolved live.** Default `version=pinned`.

- *For the locked snapshot (default):* it is the pattern both build-tool integrations already use and justify ("tested against exactly that version", baked sha256 as the trust root, no dependence on `setup.ocx.sh` at image-build time beyond the GitHub download) (`FO/ocx.cmake:157-161`; `RO/agent-config/dist-snapshot.md`). Devcontainer images are rebuilt rarely and reproducibility matters; features are versioned OCI artifacts, so a user pinning `ghcr.io/ocx-sh/devcontainer-features/ocx:1.2` gets one ocx version and baked checksums (`Dependabot`'s devcontainer feature support can then bump it, not verified). The CLI "declares no stability for its command-line surface", so an unattended jump on rebuild can break `ocx pull`/`env` hooks.
- *Against:* every ocx release needs a feature release (observed lag in the siblings is days to weeks because the refresh is weekly cron plus human review; ocx dispatches only to `www-setup`), a stale feature installs an old ocx, and the snapshot grows (288 rows, 91 KB in `find_ocx`). Mitigations: copy `update_dist.py`/`bump_ocx.py` including the additions-only and URL-allowlist guards; add the missing `ocx-released` dispatch from `ocx` to this repo (needs a token in `ocx-sh/ocx`; not available to this research); vendor only Linux rows (`{x86_64,aarch64}-unknown-linux-{gnu,musl}`) or keep the full manifest for parity (full manifest is only ~90 KB); schedule at least weekly.
- *Resolving `latest` at build time only:* simplest and always fresh, same as the official one-liner and `setup-ocx` `latest`; checksum comes from live `https://setup.ocx.sh/dist.json` so it still verifies, but two builds of the same Dockerfile differ, an outage of `setup.ocx.sh` or GitHub fails the build, and the live manifest can add rows silently. Keep it as `version=latest` (and `distUrl` for mirrors/air-gap), not the default.
- *Feature versioning:* decouple feature semver from the ocx version (as `find_ocx` 0.4.0 pins ocx 0.6.6) and record the pinned ocx version in the changelog and in a baked `/usr/local/share/ocx-feature/ocx-version` file or label for inspection.
- *Install mechanism:* do not use `ocx self setup` at build time (writes the build user's profiles, needs registry, per-user result; `ocx-install-surface.md` implications 1 and 3). Verify the archive against the row yourself (as `find_ocx` does), install the `-musl` or `-gnu` binary to `/usr/local/bin/ocx`, then let the user's first shell or `postCreateCommand` do `ocx pull`.

## Not verified / open

- Whether anything other than `ocx` -> `www-setup` dispatches `ocx-released`. Only that one sender was found in `ocx/.github` (`release.yml:587`); `find_ocx`/`rules_ocx` declare the trigger but rely on weekly cron in practice. Whether the `ocx` release workflow is supposed to fan out to them is unknown.
- Why `find_ocx` has no open `chore/update-dist` PR while its pin (0.6.6) trails 0.6.8; the 2026-11-16 scheduled run succeeded (`gh run list`), so either a guard declined or the PR was merged/closed (`gh pr list --head chore/update-dist` shows only PR #1 merged and #3 closed, both July). Not investigated.
- `ocx env` behaviour when the lock has packages not yet in the store (documented as auto-install on demand, `environment.md:526-538`; not run); needed to decide if `vscode-ocx` works in a freshly created container before `ocx pull` finishes.
- `ocx init` overwrite behaviour; `ocx update`/`upgrade` as hook candidates; `ocx pull` consent-stamp side effect inside a dev container (documented, not observed).
- Devcontainer feature mechanics (option env naming, `installsAfter`, `containerEnv` merging, Dependabot support for feature bumps) rely on `devcontainer-feature-spec-and-distribution.md`, not re-verified here.
- Windows rows, macOS rows and arm64 behaviour of the vendored `dist.json` copies were not exercised; only the Linux x86_64 live manifest and `ocx 0.6.8` were run.
- `setup-ocx`'s proxy/CA handling and the `conventions` Renovate `ocx.lock` post-upgrade task were read, not run. `setup-ocx` has no mirror, dist, or CA inputs; whether the Node HTTP client honours `HTTPS_PROXY` was not checked.
- vscode-ocx 0.1.3 behaviour in a remote/dev-container window (UI vs workspace extension host, `extensionKind` is unset in `package.json`) was not tested; whether it installs correctly via `customizations.vscode.extensions` was not tested.
- `https://ocx.sh/` currently serves an expired TLS certificate according to the sibling file `ocx-install-surface.md`; this research used `https://setup.ocx.sh/` and GitHub only and did not re-check.
