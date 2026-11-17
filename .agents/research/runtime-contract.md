# Runtime contract for the ocx Dev Container Feature (experiments)

Date: 2026-11-17
Tested: `ocx` 0.6.8 (x86_64 `-gnu` and `-musl` archives, sha256 verified against `https://setup.ocx.sh/dist.json`), `@devcontainers/cli` 0.90.0, Docker 29.9.3 (amd64 only; aarch64 not exercised). `ocx` docs = `/home/mherwig/dev/ocx-sh/ocx/website/src/content/docs`. Source = `/home/mherwig/dev/ocx-sh/ocx` (`crates/...`).

Claims below were each run; output is trimmed. Not repeated: what `ocx-install-surface.md` and `ocx-bootstrap-contract.md` already prove. Lab: two throwaway images (`debian:stable-slim` + bash/zsh/dash, `alpine:3` + bash/zsh) with `/usr/local/bin/ocx` = musl binary, user `dev` uid 1000, `/workspaces/demo/ocx.toml` = one `shellcheck` tool. Everything created was removed afterwards.

Two cross-cutting findings that change the design, found while testing and detailed in the sections:

- A project's `.ocx/toolchain/links/*` and `ocx.lock` are shared mutable state. Whichever user last ran `ocx pull` owns them. Root running `ocx pull` in a workspace that `dev` pulled makes `ocx.lock` root-owned mode 0600, and `dev` then fails with exit 74 (section 2).
- The devcontainer CLI probes the user's login interactive shell (`userEnvProbe`) and injects the result into `devcontainer exec` and lifecycle hooks. So `/etc/profile.d` and `/etc/bash.bashrc` exports do reach CLI and VS Code processes; `/etc/environment` does not (section 6).

---

## 1. libc and platform selection

### 1a. Platform detection is a property of the host at run time, not of the binary

Both binaries print the same libc on the same host:

```
$ docker run --rm -v $B:/o:ro debian:stable-slim /o/ocx-musl about | grep -E 'Platforms|Libc'
Platforms: linux/amd64
Libc:      libc.glibc
$ ... debian:stable-slim /o/ocx-gnu about   -> Libc: libc.glibc
$ ... alpine:3           /o/ocx-musl about  -> Libc: libc.musl
```

Source: `crates/ocx_oci/src/host_capabilities.rs` probes the loaders on disk (`/lib64/ld-linux-x86-64.so.2`, `/lib/x86_64-linux-gnu/...`, `/lib/ld-musl-x86_64.so.1`, ...) by running `<loader> --version` and classifying the banner. The result is cached in `$OCX_HOME/state/host/capabilities.json` (TTL 24 h). A host with both loaders reports both.

Project with `node = "ocx.sh/nodejs/node:26"` (glibc only) and `shellcheck` (both libcs), musl binary:

```
debian:stable-slim: lock rc=0, pull rc=0, `ocx exec -- shellcheck --version` -> 0.11.0
                    node resolved to the glibc build (it then needs libatomic1: "libatomic.so.1: cannot open shared object file")
alpine:3:           lock rc=78  error: no 'linux/amd64+libc.musl' leaf for binding 'node' at the locked version
                    shellcheck alone: rc=0
```

No env var or config key overrides libc. Only `--platform linux/amd64+libc.glibc` (per command, not persistable).

Finding (wolfi): on `cgr.dev/chainguard/wolfi-base` (glibc 2.44) ocx 0.6.8 detects no libc at all (`Platforms: linux/amd64`, no `Libc:` line). A glibc-only package then fails: `error: no 'linux/amd64' leaf for binding 'node'` (rc 78). The shellcheck-only project works. `lock --platform linux/amd64+libc.glibc` and `pull --platform ...` work. busybox:musl (static, no loader) also reports no libc, same node failure, which is correct there.

### 1b. gnu build minimum glibc

`objdump -T ocx-gnu`: highest symbol version is `GLIBC_2.28` (needs 2.2.5 ... 2.25, 2.27, 2.28).

```
rockylinux:8 / almalinux:8 (2.28)  ocx-gnu version -> 0.6.8
debian:10 (2.28)                   -> 0.6.8
amazonlinux:2 (2.26)               /o/ocx-gnu: /lib64/libc.so.6: version `GLIBC_2.27' not found (required by /o/ocx-gnu)
ubuntu:18.04 (2.27)                /o/ocx-gnu: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.28' not found
                                   symbol statx version GLIBC_2.28 not defined in file libc.so.6
alpine:3                           sh: /o/ocx-gnu: not found   (rc 127, musl has no glibc loader)
wolfi-base (2.44)                  -> 0.6.8
```

The musl binary is `statically linked` (`ldd`) and ran (`version` = 0.6.8) on amazonlinux:2, ubuntu:18.04, debian:10, rockylinux:8, fedora, archlinux, busybox:musl, alpine, debian:stable-slim, wolfi.

Sizes: gnu 64.6 MB, musl 67.1 MB.

### 1c. Detecting glibc and its version in POSIX sh without `ldd`

`getconf GNU_LIBC_VERSION` works where `getconf` is the glibc one (`glibc 2.41`, `glibc 2.28`, `glibc 2.26`, `glibc 2.27`); on alpine and busybox it fails (`getconf: GNU_LIBC_VERSION: unknown variable`); wolfi has no usable getconf. `ld.so --version` works on newer loaders and on wolfi (`ld.so (glibc-2.44-r20) stable release version 2.44.`) but not on old ones (debian:10, AL2, ubuntu:18.04 treat `--version` as a library name), so it is the fallback, not the primary. This function ran under dash (`dash -n` clean) on the images below:

```sh
glibc_version() {
  v=$(getconf GNU_LIBC_VERSION 2>/dev/null) && case $v in glibc\ *) echo "${v#glibc }"; return 0;; esac
  for l in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /usr/lib/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 \
           /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-aarch64.so.1 /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /usr/lib/ld-linux-aarch64.so.1; do
    [ -x "$l" ] || continue
    v=$("$l" --version 2>&1 | sed -n '1s/.*release version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  return 1
}
```

Result with `maj*1000+min >= 2028` => gnu else musl: debian:stable-slim 2.41 gnu; debian:10 2.28 gnu; ubuntu:18.04 2.27 musl; amazonlinux:2 2.26 musl; rockylinux:8 2.28 gnu; alpine:3 none musl; busybox:musl none musl; wolfi-base 2.44 gnu; archlinux 2.44 gnu; ubi9-minimal 2.34 gnu.

**Conclusion.** The proposed `libc: auto|gnu|musl` default is confirmed as safe (`auto` = gnu on glibc >= 2.28, else musl, nothing found = musl), but the experiment found no functional reason to prefer gnu: the musl binary runs on every image tested, resolves packages by host libc exactly like the gnu one, and is 2.5 MB larger. Simplest correct default is `musl` for every host; keep `gnu` as an opt-in for users who want a glibc-linked binary (resolver and NSS behaviour of a static musl binary under corporate DNS was not tested, see Not verified). The libc of the feature binary never decides which packages the user gets; that is decided by the host loader as ocx sees it, and wolfi shows ocx can mis-detect it.

---

## 2. System-wide shell activation without touching a home directory

### 2a. What the ocx commands do

`ocx self setup --dry-run` (root, debian, system binary at `/usr/local/bin/ocx`):

```
Status        completed
Bootstrap     would pull 0.6.8
Shims         /root/.ocx/env.sh  env.fish  env.ps1  env.nu  env.elv
Profiles      /root/.profile /root/.bashrc /root/.zprofile /root/.zshrc (completed)
Session PATH  /root/.config/environment.d/ocx.conf (written)
warning: another ocx at /usr/local/bin/ocx shadows the one ocx self setup just installed
```

Real run (`--profile /tmp/prof`): pulls `ocx.sh/ocx/cli` into `~/.ocx` (a 70 MB copy; `du ~/.ocx` = 84 MB for a user that has done nothing else), writes the five `env.*` shims, the managed block below to the given profile, and `~/.config/environment.d/ocx.conf`. `--no-modify-path` skips profiles and environment.d but still pulls ocx and writes `~/.ocx/env.sh`; a second run reports `no_op`.

```
# >>> ocx v1 0fe65b70 >>>
if [ -f "${OCX_HOME:-$HOME/.ocx}/env.sh" ]; then
    . "${OCX_HOME:-$HOME/.ocx}/env.sh"
fi
# <<< ocx <<<
```

`env.sh` evaluates `ocx self activate --shell=<bash|zsh|sh> --no-completion --interactive|--no-interactive`, then completions.

`ocx self activate --shell=X [--hook]` (emits shell code; needs `=`):

- bash and zsh: two PATH prepends (`$OCX_HOME/symlinks/ocx.sh/ocx/cli/current/content/bin`, `$OCX_HOME/toolchain/active/bin`), `eval "$(<that ocx> --global env --shell=bash)"`, an `__OCX_ENV_STATE` export, a `__ocx_prompt_hook` function registered on `PROMPT_COMMAND` (bash) or `precmd` (zsh), and an `ocx()` wrapper function. The hook calls `ocx --offline self activate --reconcile ...` and project activation happens there.
- ash, dash, sh, ksh: only the PATH prepends and `--global env`. No hook and no project composition (docs: "no append-safe prompt-hook point exists").
- Every emitted ocx path is `$OCX_HOME/symlinks/ocx.sh/ocx/cli/current/content/bin/ocx`, guarded by `[ -x ... ]`. The hook does nothing unless that file exists. Without it `ocx shell state` says "the shell integration has never been installed here: no env.sh under ~/.ocx".

`ocx env --shell=bash|sh` prints exports for the nearest project's toolchain once. No consent check. Pulls missing packages into the calling user's store unless `--offline`. Outside a project: `error: no ocx.toml found in / or any parent` rc 64, empty stdout.

`ocx direnv init` writes `.envrc` (`watch_file ocx.toml ocx.lock` / `eval "$(ocx direnv export)"`); `export` prints bash lines. Needs direnv; not used.

`ocx shell` opens a subshell in the project environment (fixed project); not an activation mechanism.

### 2b. No clean system-wide mechanism exists; least-bad one (tested)

`ocx self setup` is per user and heavy (network, 84 MB, writes into `$HOME`). `ocx self activate` has no system-binary mode: its hook insists on the per-user `$OCX_HOME/symlinks/.../bin/ocx`. The least-bad mechanism, tested end to end, is one file `/etc/profile.d/ocx.sh` that lazily creates that one symlink (to `/usr/local/bin/ocx`) in the invoking user's `OCX_HOME` and evals `ocx self activate`. Nothing is written at image build time; the per-user `~/.ocx` appears at the first interactive shell. It relies on an undocumented path layout, so it needs a test against each ocx release.

Content (the file used in all tests below):

```sh
# /etc/profile.d/ocx.sh
case $- in *i*) ;; *) return 0 ;; esac
[ -x /usr/local/bin/ocx ] || return 0
if [ -n "${BASH_VERSION-}" ]; then _ocx_sh=bash
elif [ -n "${ZSH_VERSION-}" ]; then _ocx_sh=zsh
else _ocx_sh=sh; fi
_ocx_b="${OCX_HOME:-$HOME/.ocx}/symlinks/ocx.sh/ocx/cli/current/content/bin"
[ -x "$_ocx_b/ocx" ] || { mkdir -p "$_ocx_b" && ln -s /usr/local/bin/ocx "$_ocx_b/ocx"; } 2>/dev/null
eval "$(/usr/local/bin/ocx self activate --shell="$_ocx_sh" --no-completion --interactive 2>/dev/null)"
[ "$_ocx_sh" = sh ] && eval "$(/usr/local/bin/ocx --offline env --shell=sh 2>/dev/null)"   # dash/ash: no hook, compose once at start
unset _ocx_sh _ocx_b
```

Wiring (single line `. /etc/profile.d/ocx.sh` where the shell does not already read profile.d):

| Shell | File that is read | Line needed |
|---|---|---|
| any login shell (bash, dash, busybox ash) | `/etc/profile` sources `/etc/profile.d/*.sh` on Debian, Ubuntu, Alpine, RHEL, Arch, openSUSE | none, the file in `profile.d` is enough |
| bash interactive non-login, Debian/Ubuntu/Arch/openSUSE | `/etc/bash.bashrc` (Debian's starts with `[ -z "${PS1-}" ] && return`; append at the end) | `. /etc/profile.d/ocx.sh` |
| bash interactive non-login, Alpine | `/etc/bash/bashrc`, which sources `/etc/bash/*.sh` | `. /etc/profile.d/ocx.sh` appended |
| bash interactive non-login, RHEL family | `bash -i` reads nothing system-wide itself. The skeleton `~/.bashrc` sources `/etc/bashrc` (tested: `/root/.bashrc` on fedora does) | `. /etc/profile.d/ocx.sh` appended to `/etc/bashrc`; only effective if the user's `~/.bashrc` sources it |
| zsh (login and not) | Debian `/etc/zsh/zshrc`, Alpine `/etc/zsh/zshrc`, Arch `/etc/zsh/zshrc`, RHEL `/etc/zshrc` (all four tested) | `. /etc/profile.d/ocx.sh` appended |
| dash / busybox ash, non-login interactive | nothing is read (no `ENV`) | none possible; login only |

Double sourcing (Debian login bash reads `/etc/profile.d` and then `/etc/bash.bashrc`) is harmless: PATH edits are idempotent and the hook function and `PROMPT_COMMAND` entry are guarded.

### 2c. Test results

Matrix: debian and alpine, users `dev` (uid 1000) and `root`. A new interactive shell (stdin fed, `-i`), then `cd /workspaces/demo`, one prompt, then `command -v shellcheck`. "start in project" = the shell starts with cwd = project.

| Shell | debian dev | debian root* | alpine dev | alpine root* |
|---|---|---|---|---|
| `bash -i` | ok | ok | ok | ok |
| `bash -l -i` | ok | ok | ok | ok |
| `zsh -i`, `zsh -l -i` | ok | ok | ok | ok |
| `dash -l -i` / `sh -l -i` (ash), start in project | ok | ok | ok | ok |
| `dash -l -i` started in `/` then `cd project` | not found (no hook) | not found | not found | not found |
| `dash -i` / `sh -i` non-login | not found (no rc file read) | not found | not found | not found |

\* root only after root has its own populated store (see 2e). With a cold root store everything printed `NO-SHELLCHECK`, even with consent.

### 2d. Consent

`ocx pull` and `ocx lock` write a per-user consent stamp for that project (`ocx shell state`: "granted by: a consent stamp, present (written 11 seconds ago ...)"). Without a stamp, a project is inert until a grant exists. Results with `bash -i` as `dev`, hook shell, project start in the project:

| Project state | no `OCX_CONSENT_PATHS` | `OCX_CONSENT_PATHS=/workspaces/*` |
|---|---|---|
| `/workspaces/demo`, `ocx pull` ran as dev | active (stamp) | active |
| `/workspaces/clone`, `ocx.toml` + `ocx.lock` copied, never pulled by this user | inert: `ocx: /workspaces/clone is not activated; run \`ocx shell allow\` to consent, or \`ocx shell state\` to see why` | active |
| `/workspaces/fresh`, `ocx.toml` only | inert (same message) | inert and silent (no lock to compose) |

Root, project pulled only by dev, no consent: same message. Root with consent: active (once root's store is populated). `OCX_CONSENT_PATHS` is PATH-separated (colon), `/workspaces/*` covers `/workspaces` subtree. The static `ocx env --shell=sh` path used for dash/ash ignores consent entirely.

### 2e. Per-user store hazard

The project's `.ocx/toolchain/links/<group>/<tool>` are symlinks into the store of the user who ran the last `ocx pull` or `ocx env`. `ocx.lock` is rewritten by `ocx pull` as the running user.

```
dev:  ocx pull  -> ocx.lock  -rw------- dev dev ; link -> /home/dev/.ocx/packages/...
root: ocx pull  -> ocx.lock  -rw------- root root ; link -> /root/.ocx/packages/...
dev:  ocx pull  -> error: /workspaces/demo/ocx.lock: I/O error: Permission denied (os error 13)   rc=74
root: ocx env --shell=sh -> repoints the link to /root/.ocx (lock stays dev-owned)
```

Also `.ocx` is mode 0700 and `ocx.lock` is 0600. A second user must `ocx pull` into their own store, which re-steals the links and (for `pull`) the lock. The feature must therefore run `ocx pull` only as the remote user, never as root when the remote user is not root.

### 2f. Cost

Measured as dev, debian, bash:

- steady-state prompt (hook is a shell-only guard, no process): 0.19 to 0.23 ms per prompt, inside and outside a project.
- a prompt that really reconciles (first prompt, a `cd` across projects): one `ocx --offline self activate --reconcile` process, 8.8 ms.
- extra shell start time for sourcing the file (`bash -i -c exit` with versus without it): about 21 ms (22 ms against 1 ms).

**Conclusion.** ocx has no system-wide activation mechanism: `ocx self setup` is per user and writes into `$HOME`. The least-bad one is a single `/etc/profile.d/ocx.sh` that lazily creates the per-user symlink and evals `ocx self activate` (bash, zsh get the per-prompt hook; dash and ash get shell-start composition only, login shells only), wired into `/etc/bash.bashrc`, `/etc/bash/bashrc`, `/etc/bashrc` and the zshrc files with one `.` line. Consent comes from a stamp (set by the remote user's `ocx pull`) or from `OCX_CONSENT_PATHS` / `[shell.consent]`.

---

## 3. System config

### 3a. `/etc/ocx/config.toml`

Documented tier (`reference/configuration.md`): system = `/etc/ocx/config.toml`, then user (`$XDG_CONFIG_HOME/ocx/config.toml`), then `$OCX_HOME/config.toml`, then `OCX_CONFIG`/`--config`. A file over 64 KiB exits 78.

Keys tested through the system file:

| Need | Key | Test |
|---|---|---|
| update check off | `[update] self = "manual"` and `toolchain = "manual"` | with `OCX_NO_UPDATE_CHECK` unset, under a pty: `Update check skipped: [update] self = "manual"` and `Toolchain drift check skipped: [update] toolchain = "manual"`. Without the file: `Update check skipped: bootstrap mode — subprocess version query failed` and `state/update-check` is written. With the env var: `Update check skipped: OCX_NO_UPDATE_CHECK is set`. Source confirms `manual` skips before touching the throttle state |
| consent paths | `[shell.consent] paths = ["/workspaces/*"]` | `ocx shell state` -> `granted by: [shell.consent] paths`, entry `/workspaces/*`; shells activated a never-pulled clone (section 2d) |
| managed config source | `[managed] source = "<ref>"` (also `required`, `refresh`, `interval`) | accepted; `required = true` default and no snapshot: `error: managed config snapshot required for source '...' but absent; run \`ocx config update\`` rc 78. `required = false`: `ocx pull` rc 0. A digest-pinned source plus `ocx config update` as an ordinary user: `Status updated`, snapshot written to `$OCX_HOME/state/managed-config/`, no seed written to `$OCX_HOME/config.toml` |
| mirrors | `[mirrors."ghcr.io"] registry = "..."`, `[mirrors."index.ocx.sh"] index = "..."` | `ocx config test file`: `Mirrors ghcr.io`, `Mirrors index.ocx.sh`. Traffic through a mirror not tested |
| index | `[registries."ocx.sh"] index = "<url>"` (`""` = no index), `[registry] default` | `ocx config test`: `Default registry ocx.sh`, `Registries ocx.sh` |
| hook / completions | `[shell] hook`, `completions` | documented, not separately tested |

Note: `ocx config test` takes the file as a positional argument and rejects `[managed]` in it (payload validator); the system file may still carry `[managed]`. A config with `[registries."ocx.sh"] index = ""` and an unreachable mirror made a plain `ocx lock` hang past 2 minutes; test configs with real endpoints.

### 3b. Which variables are env-only

- `OCX_HOME`: env only (it locates the config files, so it cannot be a key).
- `OCX_NO_UPDATE_CHECK`: has the file equivalent `[update]` above (the file form is two keys, `self` and `toolchain`).
- `OCX_CONSENT_PATHS` (and `OCX_CONSENT_NAMESPACES`): file equivalent `[shell.consent]`. They union.
- `OCX_MANAGED_CONFIG`: file equivalent `[managed] source`; the env var overrides for one invocation and is never written back.

Anything in `/etc/ocx/config.toml` is read by every ocx process of every user, in any shell or none (`docker exec`, hooks, IDE), so the option-dependent values go there, not into the environment.

### 3c. Visibility of env vars (debian, alpine; `echo` of a marker var set in each file)

| Process | `/etc/environment` | `/etc/profile.d/x.sh` | `/etc/bash.bashrc` (alpine `/etc/bash/bashrc`) |
|---|---|---|---|
| `docker exec sh -c` / `bash -c` | no | no | no |
| `docker exec bash -lc` / `sh -lc` (login) | no | yes | no |
| `docker exec bash -ic` (interactive non-login) | no | no | yes |
| `docker exec zsh -ic` | no | no | no |
| `su -l dev -c` (PAM) | debian yes, alpine no | yes | no |
| `devcontainer exec` / lifecycle hooks (default `userEnvProbe`) | no | yes | yes |

`/etc/environment` is not honoured without PAM, as expected. The last row is the CLI's `userEnvProbe` (section 6). `OCX_HOME` can only reach every process through `containerEnv`/`remoteEnv` (static JSON, cannot depend on option values), or through `/etc/profile.d` plus `/etc/bash.bashrc` for devcontainer-CLI/VS Code processes, or through a wrapper script at `/usr/local/bin/ocx` that exports it before `exec`ing the real binary (not tested).

**Conclusion.** Yes: `/etc/ocx/config.toml` is a supported tier and carries update-check-off (`[update]`), consent paths, managed source, mirrors and index. Only `OCX_HOME` is env-only. Put option-dependent values in that file; use `/etc/profile.d` plus the bashrc files for `OCX_HOME` (reaches the CLI via `userEnvProbe`, not raw `docker exec`).

---

## 4. Managed config

Local `registry:2` on a docker network (`ocxreg:5000`, `OCX_INSECURE_REGISTRIES=ocxreg:5000`). The ocx repo's `ocx config push` publishes a payload, so a fixture was made locally; no public test config package was found, so the happy path was tested against the local registry only.

```
$ ocx config push -i ocxreg:5000/corp/ocx-config:user-1.0.0 --cascade corp.toml
... sha256:afb58545...  Tags user-1.0,user-1,user      rc=0
$ ocx config setup                                  (nothing configured)   rc=64  error: nothing to set up: pass --managed-config <REF>, set OCX_MANAGED_CONFIG, or configure a [managed] seed
$ ocx config setup --managed-config 'NOT A REF!!'   rc=78  error: managed config source ... is not a valid OCI identifier: ... repository must be lowercase
$ ocx config setup --managed-config ocxreg:5000/corp/nope:user   rc=79  error: failed to sync the managed-config snapshot: ... not found in registry
$ (unreachable host)                                rc=75  error: ... transient registry failure: error sending request for url (http://nohost.invalid:5000/v2/)
$ ocx config setup --dry-run --managed-config <ref> rc=0   Managed config  would adopt
$ OCX_MANAGED_CONFIG=<ref> ocx config setup          rc=0   Managed config  adopted (sha256:afb58545...)
$ ocx config setup                                  rc=0   Managed config  already adopted (sha256:...)
$ ocx config update                                 rc=0   Status already_current
$ ocx config update --check                         rc=0   Drift false, Tag user
```

Files written (per `$OCX_HOME`, i.e. per user): `$OCX_HOME/config.toml` gets a fenced seed

```
# >>> ocx managed v1 99978c95 >>>
[managed]
source = "ocxreg:5000/corp/ocx-config:user"
required = true
refresh = "notify"
interval = "1d"
# <<< ocx managed <<<
```

and `$OCX_HOME/state/managed-config/{config.toml,snapshot.json}`. A failed run (bad ref, not found, unreachable) wrote no seed (only `state/` host capabilities). Idempotent on rerun. With the registry down and a snapshot present: `ocx config update` rc 75; `ocx config setup` rc 0 (`refresh unavailable, keeping sha256:...`). The sync is per user; root and the remote user each need their own, or the system file carries a digest-pinned `[managed] source` with `required = false` and each user runs `ocx config update`.

Trust rule seen live: a payload carrying `[shell.consent]` is ignored with a warning unless the source is digest-pinned (`warning: ... carries [shell.consent] but the [managed] source is not digest-pinned; the grant was ignored`).

**Conclusion.** `OCX_MANAGED_CONFIG` + `ocx config setup` writes a per-user seed and snapshot under `$OCX_HOME`, exits 64/78/79/75 on no source/bad ref/missing/no network, and is idempotent; the feature should write `[managed]` into `/etc/ocx/config.toml` or run `ocx config setup` as the remote user, not as root. Only failure paths and a local-registry fixture were exercised.

---

## 5. `ocx pull` as a lifecycle hook (uid 1000, debian)

```
(a) no ocx.toml                       rc=64  error: no ocx.toml found in /tmp/p5 or any parent; run `ocx init` to create one
(b) ocx.toml, no ocx.lock             rc=78  error: ocx.lock not found at /tmp/p5/ocx.lock; run `ocx lock` to create it
(c) stale lock (ocx.toml edited)      rc=65  error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`
    same with --offline and --frozen  rc=65
(d) healthy, cold store               rc=0   stderr: "pulling count=1" and "no trust policy covers '...'; installing '...' without signature verification"
(e) second run                        rc=0   same stderr lines; `ocx --offline pull` rc=0
(f) no network, cold store, lock      rc=75 (--offline: rc=79 "package not found")
    no network, cold store, no lock   `ocx lock` rc=69 "registry unreachable ..."
    no network, warm store (copied)   `ocx pull` rc=0, no --offline flag needed
```

Groups (`ocx.toml` with `[tools]`, `[group.extra.tools]`, `[group.docs.tools]`):

```
ocx pull -g extra,docs        rc=0  pulls 2 entries (comma list works; also repeatable)
ocx pull -g all               rc=0  pulls 3 (default + every group)
ocx pull -g nosuch            rc=64 error: unknown group 'nosuch' in --group filter
ocx pull -g extra,nosuch      rc=64 same, nothing pulled
ocx pull -g ''                rc=64 error: empty group segment in --group value; check for stray commas
ocx pull (no -g)              default `[tools]` only
```

`ocx pull` walks up: run from `/tmp/p5/sub/deep` it found `/tmp/p5/ocx.toml` (rc 0). With the toolchain `node:26 + shellcheck + task` (300 MB): cold store 4.9 s, warm 55 to 75 ms (also warm offline). The command always prints the trust-policy line on stderr, even warm.

Exit codes for a hook: 64 (no ocx.toml) is the only "nothing to do" case. 78 and 65 need `ocx lock` first (the hook should not lock; a lock rewrite is a project change). 75/79/69 are network. A hook that must not fail the container creation should treat 64 as success and decide for 65/78/75 whether to warn.

**Conclusion.** Run `ocx pull` as the remote user; 64 = no project (silent no-op), 78/65 = unlocked or stale (warn, do not lock), 75 = no network with a cold store; warm-store `ocx pull` is offline-capable and takes under 100 ms; `-g a,b` works and an unknown group is an immediate rc 64.

---

## 6. devcontainer CLI mechanics (`@devcontainers/cli` 0.90.0)

Run as `ocx exec -- npx --yes @devcontainers/cli@0.90.0 ...` from the repo (node via ocx). Probe feature in the scratchpad: options `version`, `distUrl`, `groups`, `pull`; `install.sh` dumps `id`, `pwd`, `$0`, `readlink /proc/$$/exe`, a shipped file `extra.txt`, and `env`; four feature lifecycle hooks plus four user hooks in `devcontainer.json`, each appending `user, cwd, timestamp`.

### 6a. Option env names and `groups`

Options arrive as upper-cased names: `VERSION`, `DISTURL`, `GROUPS`, `PULL` (booleans as `true`/`false`). `distUrl` and `groups` lower/camel case are unset. Written to `devcontainer-features.env` next to `install.sh`.

```
debian (dash):    VERSION=1.2.3 DISTURL=https://x.invalid/d.json GROUPS=a,b PULL=true
alpine (busybox): ... GROUPS=a,b
fedora (/bin/sh = bash):  VERSION=1.2.3 DISTURL=... GROUPS=0 PULL=true     <- "a,b" lost, value is bash's own group id
```

On bash `GROUPS` is a special read-only-ish array; the assignment is silently discarded. `/bin/sh` is bash on fedora, ubi, amazonlinux:2023, opensuse, archlinux (ran as `/usr/bin/bash`). Dash and busybox are fine. Bash-special names among the planned options: only `groups`. The others upper-cased (`VERSION`, `DISTURL`, `MIRRORURL`, `CABUNDLE`, `LIBC`, `MANAGEDCONFIG`, `OCXHOME`, `INSTALLDIR`, `NOUPDATECHECK`, `CONSENTPATHS`, `PULL`) collide with no bash special variable.

Verdict: `groups` is lost on bash-as-sh images. Rename to `pullGroups`.

### 6b. User variables (all runs; install always runs as root)

| devcontainer.json | image | `_CONTAINER_USER` | `_CONTAINER_USER_HOME` | `_REMOTE_USER` | `_REMOTE_USER_HOME` | hooks run as |
|---|---|---|---|---|---|---|
| none | debian:stable-slim | root | /root | root | /root | root |
| none | alpine:3, fedora, busybox, ubi, amzn2023, leap15, arch | root | /root | root | /root | root |
| none | mcr `devcontainers/base:{debian,ubuntu,alpine}` | root | /root | vscode | /home/vscode | vscode |
| `remoteUser: dev` (exists) | debian, alpine | root | /root | dev | /home/dev | dev |
| `containerUser: dev` | debian | dev | /home/dev | dev | /home/dev | dev |
| `containerUser: dev, remoteUser: root` | debian | dev | /home/dev | root | /root | root |
| `remoteUser: root` | mcr debian | root | /root | root | /root | root |
| `remoteUser: ghost` (does not exist) | debian | root | /root | ghost | (empty) | `up` fails |
| none | wolfi-base | 0 | /root | 0 | /root | root |

`remoteUser: ghost`: the build succeeds; `up` exits 1 at start: `Error response from daemon: unable to find user ghost: no matching entries in passwd file`. The feature sees `_REMOTE_USER=ghost`, `_REMOTE_USER_HOME=` empty. On wolfi the variables hold the numeric `0`, not a name (image config user is `0`), so `_REMOTE_USER` can be a uid string.

### 6c. Lifecycle hooks

Order per phase, all four phases (`onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`), identical on every image:

```
feature onCreate -> USER onCreate -> feature updateContent -> USER updateContent -> feature postCreate -> USER postCreate -> feature postStart -> USER postStart
```

Feature hooks run before the user's own hook in each phase. User = remote user (`user=dev`, `user=vscode`, `user=root` as in 6b). cwd = `/workspaces/<folder>` (the workspace). The hook environment has only the CLI's probed environment: with the default probe it is `HOME=/home/dev`, `PATH=/usr/local/sbin:/usr/local/bin:...`, `PWD`. No `USER`, no `LOGNAME`, no `SHELL`. A hook string is run by `sh -c`.

### 6d. Extra files next to `install.sh`

Yes. cwd of `install.sh` is `/tmp/dev-container-features/<id>_<n>` (e.g. `/tmp/dev-container-features/probe_0`), `$0` is `./install.sh`. `cat ./extra.txt` and `cat "$(dirname "$0")/extra.txt"` both work; the directory also holds `devcontainer-feature.json`, `devcontainer-features.env`, `devcontainer-features-install.sh`. The shipped `/bin/sh` is dash on debian/ubuntu/mcr, busybox on alpine/wolfi, `/bin/sh` busybox on busybox:musl, bash on the rest.

### 6e. Images the CLI can drive (`devcontainer up` and `devcontainer exec`, trivial `#!/bin/sh` feature)

All six candidates worked, up rc 0 and `exec` ran:

```
busybox:musl                       up ok, exec ok (`id -un` root); install ran under /bin/sh (busybox)
cgr.dev/chainguard/wolfi-base      ok; _CONTAINER_USER=0 numeric
registry.access.redhat.com/ubi9/ubi-minimal  ok (no tar, no gzip; the CLI itself did not need them)
amazonlinux:2023                   ok
opensuse/leap:15                   ok
archlinux:latest                   ok
```

Also ok: debian:stable-slim, alpine:3, fedora:latest, ubuntu (mcr), the three mcr base images. No image the CLI cannot drive was found. `devcontainer features test` on busybox:musl prints a non-fatal `Command in container failed: (cat /etc/os-release || cat /usr/lib/os-release)` message (no os-release) and passes.

### 6f. `devcontainer features test` on bare images and non-root

`-i/--base-image` and `-u/--remote-user` apply only to the autogenerated `test.sh` run, not to scenarios.

```
-i debian:stable-slim               Passed; TESTSH user=root
-i busybox:musl                     Passed (os-release message above); sh=/bin/sh
-i debian:stable-slim -u ghost      rc=1  Error response from daemon: unable to find user ghost: no matching entries in passwd file
-i ocxlab-debian (prebuilt user) -u dev   Passed; user=dev uid=1000
```

On a bare image there is no `dev` user, so `-u` cannot name one. Two ways that worked as scenarios (`test/<feature>/scenarios.json`):

```json
"user-prebuilt":  { "image": "<image that has user dev>", "remoteUser": "dev", "features": { "probe": {} } }
"user-via-common-utils": { "image": "debian:stable-slim", "remoteUser": "vscode",
   "features": { "ghcr.io/devcontainers/features/common-utils:2": { "username": "vscode", "installZsh": false }, "probe": {} } }
```

Both passed (`SCEN user=dev uid=1000`, `user=vscode uid=1000`). A scenario with `"build": {"dockerfile": "Dockerfile.alpine"}` failed: `ENOENT: no such file or directory, open '/tmp/devcontainercli/container-features-test/<id>/.devcontainer/Dockerfile.alpine'` (the test dir copy does not carry the Dockerfile). `common-utils` is the practical way to get a non-root user on a bare image (needs ghcr network and installs packages).

### 6g. Interactive TTY

From this non-interactive parent a real pty was provided with `script -qec "<cmd>" /dev/null`. With the pty: `devcontainer exec ... bash -i` gave a prompt, `tty` printed `/dev/pts/0`, `[ -t 0 ]` yes, `SHELL=/bin/bash`, prompt as user `dev` in `/workspaces/<folder>`. Without a pty (stdin `/dev/null`): `tty` -> `not a tty`, `[ -t 0 ]` no, `SHELL` unset. `bash` exec'd this way is not a login shell (`login=no`); its env comes from the CLI's probe. Not tested: a human typing at a real terminal, signal and resize behaviour, VS Code integrated-terminal login flags.

`userEnvProbe` (default `loginInteractiveShell`, flag `--default-user-env-probe`): the CLI runs the user's shell as login-interactive and injects its environment into `exec` and hooks. A marker exported from `/etc/profile.d/zz.sh` and one from `/etc/bash.bashrc` were both visible to `devcontainer exec sh -c`; with `--default-user-env-probe none` neither; `/etc/environment` never. This also means every `devcontainer exec` runs the ocx profile snippet once.

### 6h. Removal

There is no `down`/`rm`/`stop` command (commands: `up`, `set-up`, `build`, `run-user-commands`, `read-configuration`, `outdated`, `upgrade`, `features`, `templates`, `exec`). Remove with Docker. Containers carry `devcontainer.local_folder=<abs path>` and `devcontainer.config_file=<abs path>` (absent when `--id-label` is used, then only your label), and `devcontainer.metadata`:

```
docker ps -aq --filter label=devcontainer.local_folder=<abs workspace> | xargs -r docker rm -f
```

`up --id-label k=v` lets a test own its label (`docker ps -aq --filter label=k=v`). `--remove-existing-container` replaces a container on `up`. Images built per workspace are named `vsc-<folder>-<hash>-features` and `-features-uid`; remove with `docker rmi`. `devcontainer features test` removes its containers itself unless `--preserve-test-containers`; it leaves `vsc-<epoch>-<hash>-features[-uid]` images and `/tmp/devcontainercli/container-features-test/` behind.

**Conclusion.** Options arrive upper-cased (`DISTURL`); `groups` is lost under bash-as-`/bin/sh` (`GROUPS=0` on fedora) so rename to `pullGroups`; install runs as root with `_REMOTE_USER` possibly numeric, a non-existent name, or with empty home; feature hooks precede user hooks and run as the remote user in the workspace; every probed image is drivable.

---

## 7. Prerequisites per image

Probed with `docker run --entrypoint /bin/sh <image> < prereq.sh` as root. `(bb)` = busybox applet. `ca` = first present bundle. Libc from `getconf GNU_LIBC_VERSION` (glibc) or musl loader.

| Image | /bin/sh | curl | wget | tar | gzip | sha256 tool | CA bundle | mktemp | install | id | getent | libc | pkg manager |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| debian:stable-slim | dash | - | - | yes | yes | sha256sum | none | yes | yes | yes | yes | glibc 2.41 | apt-get |
| ubuntu:24.04 | dash | - | - | yes | yes | sha256sum | none | yes | yes | yes | yes | glibc 2.39 | apt-get |
| alpine:3 | busybox | - | yes (bb) | yes (bb) | yes (bb) | sha256sum (bb) | /etc/ssl/certs/ca-certificates.crt | yes (bb) | yes (bb) | yes (bb) | yes | musl | apk |
| fedora:latest | bash | yes | - | yes | yes | sha256sum | /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem (+ /etc/ssl/certs/ca-certificates.crt) | yes | yes | yes | yes | glibc 2.44 | dnf, microdnf, yum |
| rockylinux:9-minimal | bash | yes | - | **no** | yes | sha256sum, openssl | /etc/pki/tls/certs/ca-bundle.crt | yes | yes | yes | yes | glibc 2.34 | microdnf |
| almalinux:9 | bash | yes | - | yes | yes | sha256sum, openssl | /etc/pki/tls/certs/ca-bundle.crt | yes | yes | yes | yes | glibc 2.34 | dnf, yum |
| ubi9/ubi-minimal | bash | yes | - | **no** | **no** | sha256sum | /etc/pki/tls/certs/ca-bundle.crt | yes | yes | yes | yes | glibc 2.34 | microdnf |
| amazonlinux:2023 | bash | yes | - | **no** | **no** | sha256sum | /etc/pki/tls/certs/ca-bundle.crt | yes | yes | yes | yes | glibc 2.34 | dnf, yum |
| opensuse/leap:15 | bash | yes | - | **no** | **no** | sha256sum, openssl | /etc/ssl/ca-bundle.pem | yes | yes | yes | yes | glibc 2.38 | zypper |
| archlinux:latest | bash | yes | - | yes | yes | sha256sum, openssl | /etc/ssl/certs/ca-certificates.crt | yes | yes | yes | yes | glibc 2.44 | pacman |
| cgr.dev/chainguard/wolfi-base | busybox | - | - | yes (bb) | yes (bb) | sha256sum (bb) | /etc/ssl/certs/ca-certificates.crt | yes (bb) | yes (bb) | yes (bb) | **no** | glibc 2.44 (no getconf var) | apk |
| busybox:musl | busybox | - | yes (bb) | yes (bb) | yes (bb) | sha256sum (bb) | **none** | yes | yes | yes | **no** | none (static) | **none** |
| mcr base:ubuntu | dash | yes | yes | yes | yes | sha256sum, shasum, openssl | /etc/ssl/certs/ca-certificates.crt | yes | yes | yes | yes | glibc 2.43 | apt-get |
| mcr base:debian | dash | yes | yes | yes | yes | sha256sum, shasum, openssl | /etc/ssl/certs/ca-certificates.crt | yes | yes | yes | yes | glibc 2.41 | apt-get |
| mcr base:alpine | busybox | yes | yes | yes (bb) | yes (bb) | sha256sum, shasum | /etc/ssl/certs/ca-certificates.crt | yes | yes | yes | yes | musl | apk |

Whether `wget` is busybox or GNU: only alpine and busybox have a busybox wget (the older installer finding: it works over TLS with the CA bundle present). Debian/Ubuntu slim have no downloader at all, no CA bundle, and no `openssl`/`shasum` (but `sha256sum`).

Install the missing items:

| Manager | Command |
|---|---|
| apt-get | `apt-get update && apt-get install -y --no-install-recommends curl ca-certificates tar gzip` |
| apk | `apk add --no-cache curl ca-certificates tar gzip` (busybox wget exists on alpine; wolfi has none) |
| dnf / yum | `dnf install -y curl tar gzip ca-certificates` |
| microdnf (ubi-minimal, rocky-minimal) | `microdnf install -y tar gzip` (curl and CA already present); `microdnf clean all` |
| zypper | `zypper --non-interactive install tar gzip` |
| pacman | `pacman -Sy --noconfirm curl tar gzip ca-certificates` |
| none (busybox:musl) | cannot install; no CA bundle, so a TLS download fails; the feature must say so (see section 8) |

Observed gaps: no `tar` on rocky-minimal, ubi-minimal, amazonlinux:2023, leap:15; no `gzip` on ubi-minimal, amazonlinux:2023, leap:15; no `getent` on wolfi and busybox (the CLI's `_REMOTE_USER_HOME` still worked there, it falls back to `/etc/passwd`); no CA bundle on debian, ubuntu, busybox.

**Conclusion.** The installer needs: a downloader (curl, else wget), `tar` + `gzip` (missing on four images), a sha256 tool (`sha256sum` everywhere), and CA certificates (missing on debian, ubuntu, busybox:musl). `mktemp`, `install`, `id` are present everywhere; `getent` is not (wolfi, busybox).

---

## Contract for the implementer

1. **libc.** Default `libc: auto`, but both resolutions install the musl build unless `gnu` is requested and the glibc check passes. `auto` => gnu if `glibc_version` (section 1c, getconf then loader banner) >= 2.28, else musl; nothing detected, detection error, or busybox static => musl. Ubuntu 18.04 (2.27) and AL2 (2.26) must get musl. `libc` never changes which packages the user gets (host loader decides). A host where ocx misdetects glibc (wolfi) needs `ocx ... --platform linux/amd64+libc.glibc` per command; document, do not try to fix in the feature.
2. **Activation.** One file `/etc/profile.d/ocx.sh` (content in 2b). `. /etc/profile.d/ocx.sh` appended to `/etc/bash.bashrc` (Debian, Ubuntu, Arch, openSUSE), `/etc/bash/bashrc` (Alpine), `/etc/bashrc` (RHEL family; only works if the user's `~/.bashrc` sources it), and `/etc/zsh/zshrc` (Debian, Alpine, Arch) or `/etc/zshrc` (RHEL), whichever exists. Hook only on bash and zsh; dash and ash compose the project once at login-shell start (start cwd must be the project). Non-login `dash`/`sh -i` is not coverable. Cost: ~21 ms per shell start, 0.2 ms per prompt, 9 ms on a reconcile.
3. **Home directories.** The build writes nothing under any home. The per-user symlink under `$OCX_HOME/symlinks/.../bin/ocx` is created by the profile file at the first interactive shell and relies on an undocumented layout: pin it to the tested ocx version and keep a test.
4. **Option-dependent config.** Write `/etc/ocx/config.toml` at build: `[update] self="manual" toolchain="manual"` when `noUpdateCheck`; `[shell.consent] paths=[...]` for `consentPaths`; `[managed] source=...` (digest-pinned if consent is expected from it, `required=false` so a cold user is not locked out). `OCX_HOME` (option `ocxHome`) is the only env-only one: write it to `/etc/profile.d/ocx.sh` and the bashrc files (CLI/VS Code get it through `userEnvProbe`). `containerEnv` stays empty or static. Never rely on `/etc/environment`.
5. **Hooks.** Use the feature's `postCreateCommand`; it runs before the user's `postCreateCommand`, as the remote user, in the workspace. Do not run `ocx pull` at build or as root unless the remote user is root (root pull takes over `ocx.lock` and the links). Policy: exit 64 is a silent no-op; 78 and 65 (unlocked or stale) warn and do not lock; 75/79/69 (no network, cold store) warn and exit 0 so container creation is not blocked. `-g` takes a comma list; an unknown group is exit 64 and must not be passed blindly. A warm-store pull works offline in under 100 ms. Consent for the remote user's own pull is automatic (stamp); consent for other users needs the paths grant.
6. **Option env names.** Upper-cased option ids: `VERSION`, `DISTURL`, `MIRRORURL`, `CABUNDLE`, `LIBC`, `MANAGEDCONFIG`, `OCXHOME`, `INSTALLDIR`, `NOUPDATECHECK`, `CONSENTPATHS`, `PULL`, plus `PULLGROUPS`. `groups` verdict: lost on bash-as-sh (fedora: `GROUPS=0`); rename to `pullGroups`. Booleans arrive as the strings `true`/`false`.
7. **User variables.** `_REMOTE_USER`, `_REMOTE_USER_HOME`, `_CONTAINER_USER`, `_CONTAINER_USER_HOME` are always set; install runs as root. `_REMOTE_USER` can be a name, `root`, a numeric uid (wolfi: `0`), or a name with empty `_REMOTE_USER_HOME` when the user does not exist at build time (then `up` fails later with `unable to find user`). With `containerUser` differing from `remoteUser`, hooks run as the remote user. Do not write into `_REMOTE_USER_HOME` at build.
8. **Shipping files.** Extra files next to `install.sh` are available at `./` (cwd is `/tmp/dev-container-features/<id>_<n>`). Use `./` or `dirname "$0"`.
9. **Image support** (all driven by the CLI with a `#!/bin/sh` feature, up and exec):

| Image | CLI | Prerequisites the installer must add |
|---|---|---|
| debian:stable-slim, ubuntu:24.04 | ok | curl, ca-certificates (apt-get) |
| alpine:3 | ok | none for busybox wget + CA present; install `curl` if `OCX_INSTALL_DOWNLOADER` is curl |
| fedora:latest, almalinux:9 | ok | none (curl, tar, gzip, CA present) |
| rockylinux:9-minimal | ok | tar (microdnf) |
| ubi9/ubi-minimal, amazonlinux:2023, opensuse/leap:15 | ok | tar, gzip |
| archlinux:latest | ok | none |
| wolfi-base | ok | curl or wget (apk); no getent; ocx cannot detect glibc |
| busybox:musl | ok | none installable: no package manager and no CA bundle; unsupported for network installs unless `caBundle` or a mirror with plain trust is given |
| mcr base ubuntu/debian/alpine | ok | none |

10. **Tests.** `devcontainer features test -i <image>` runs as root unless `-u` names an existing user; for non-root on a bare image use a scenario with `image` + `remoteUser` + `common-utils` (or a prebuilt image). Scenario `build.dockerfile` does not work. Clean up with `docker ps -aq --filter label=devcontainer.local_folder=<dir> | xargs -r docker rm -f` and `docker rmi` the `vsc-*` images.

---

## Not verified / open

- aarch64: only x86_64 archives and amd64 containers were exercised. ocx `-gnu` minimum glibc for aarch64 was not checked.
- A static musl binary's DNS and NSS behaviour (search domains, `/etc/hosts` edge cases, corporate resolvers, mDNS) against the gnu build. Not tested; this is the only plausible reason to prefer gnu.
- Whether the lazily created `~/.ocx/symlinks/.../bin/ocx` symlink survives `ocx self update`, `ocx self setup` in the same home, or later ocx versions; the layout is undocumented.
- A real terminal session in VS Code (integrated terminal login flags, `terminal.integrated.defaultProfile`, remote server env), `devcontainer exec` with human input, resize and signals.
- The vscode-ocx extension in a remote window.
- Mirror and index overrides in `/etc/ocx/config.toml` were only accepted by `ocx config test`; traffic redirection was not tested. A system-tier `[managed]` with `required = true` and a stale lock-out for a new user was seen (rc 78) but not combined with the hook.
- No public managed-config test package was found; the success path was tested against a local `registry:2` only. Digest-pinned managed consent grant was reasoned from the warning text, not exercised end to end.
- Behaviour of two different users sharing one workspace beyond the root/dev case (for example with `containerUser` != `remoteUser` and a hook that also runs as the container user).
- `devcontainer up` on podman or rootless Docker; Docker Desktop on macOS/Windows file ownership of `/workspaces`.
- fish, nushell, elvish, ksh, tcsh were not tested; `ocx self activate` supports the first four.
- `userEnvProbe` cost: it runs the ocx profile snippet at every `devcontainer exec` and hook; the aggregate cost on slow disks was not measured.
