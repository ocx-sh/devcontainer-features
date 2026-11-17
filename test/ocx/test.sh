#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# test.sh: the default-options test `devcontainer features test` runs inside the built container
# (as root, or as the -u user). POSIX sh, no bash and no test lib, so it runs on every base image.
# Facts that need the repo (the expected ocx version) are printed as `# key=value` lines; the task
# (test/images/run-image.sh) compares them from outside, because the test dir cannot see src/.
# shellcheck disable=SC2329 # the check functions are called by name through check, which shellcheck cannot see
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=check.sh
. "$here/check.sh"

state=/usr/local/share/ocx-feature
marker='Written by the ocx Dev Container Feature'
rc_begin='# >>> ocx devcontainer feature >>>'
rc_end='# <<< ocx devcontainer feature <<<'

# --- the home-directory check must run first: the real-work checks below create ~/.ocx -------------

# The build writes nothing under a home directory. Whether the lifecycle hooks already ran before
# this script is not guaranteed, so the check names only what the BUILD could have written: the
# feature's own markers or files under /root and /home. A hook (or the real-work checks) only ever
# creates .ocx, which the build never does, so a leftover .ocx is allowed here and everything else
# the feature owns is not.
no_feature_files_in_homes() {
    for d in /root /home/*; do
        [ -d "$d" ] || continue
        found=$(grep -rIl "$marker" "$d" 2>/dev/null | head -n 5)
        [ -z "$found" ] || {
            printf 'feature-owned file in %s: %s\n' "$d" "$found"
            return 1
        }
    done
    return 0
}
check "the build wrote no feature file under a home directory" no_feature_files_in_homes

# --- the binary ---------------------------------------------------------------------------------

is_installed_binary() {
    found=$(command -v ocx)
    facts=$(stat -c '%a %U' /usr/local/bin/ocx)
    # -ef, not string equality: fedora merges /usr/local/sbin into /usr/local/bin, so PATH finds the same file as sbin/ocx.
    [ "$found" -ef /usr/local/bin/ocx ] && [ "$facts" = '755 root' ] || {
        printf 'command -v ocx: %s; stat of /usr/local/bin/ocx (mode owner): %s\n' "$found" "$facts"
        return 1
    }
}
check "ocx is /usr/local/bin/ocx, mode 0755, owned by root" is_installed_binary

version_matches_record() {
    [ -n "$recorded" ] && [ "$(ocx version)" = "$recorded" ]
}
recorded=$(cat "$state/ocx-version" 2>/dev/null || true)
check "ocx version equals $state/ocx-version ($recorded)" version_matches_record

is_semver() {
    case "$recorded" in
        '' | *[!0-9.]* | .* | *. | *..*) return 1 ;;
        *.*.*) return 0 ;;
        *) return 1 ;;
    esac
}
check "the recorded version has the form X.Y.Z" is_semver
# The task compares this with the newest stable release of src/ocx/dist.json.
printf '# ocx-version=%s\n' "$recorded"

# --- state files and config ---------------------------------------------------------------------

mode_is() {
    [ "$(stat -c %a "$2")" = "$1" ]
}
check "$state/hook.sh is mode 0755" mode_is 755 "$state/hook.sh"
for f in feature.env ocx-version dist-digest; do
    check "$state/$f is mode 0644" mode_is 644 "$state/$f"
done

check "/etc/ocx/config.toml carries the feature marker" grep -q "$marker" /etc/ocx/config.toml
check "/etc/ocx/config.toml turns the update check off" grep -q '^self = "manual"$' /etc/ocx/config.toml
check "/etc/ocx/config.toml grants consent to /workspaces/*" grep -q '^paths = \["/workspaces/\*"\]$' /etc/ocx/config.toml
check "/etc/profile.d/ocx.sh exists" test -f /etc/profile.d/ocx.sh

block_once() {
    [ "$(grep -c -x -F "$rc_begin" "$1")" = 1 ] && [ "$(grep -c -x -F "$rc_end" "$1")" = 1 ]
}
for f in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc; do
    [ -f "$f" ] || continue
    check "$f holds the marked block exactly once" block_once "$f"
done

# --- shells -------------------------------------------------------------------------------------

check "sh -lc finds ocx" sh -lc 'command -v ocx'
if command -v bash >/dev/null 2>&1; then
    check "bash -ic finds ocx" bash -ic 'command -v ocx'
fi
profile_is_silent() {
    out=$(sh -c 'set -eu; . /etc/profile.d/ocx.sh' 2>&1) && [ -z "$out" ]
}
check "sourcing /etc/profile.d/ocx.sh under set -eu is silent and returns 0" profile_is_silent

# --- the hook, then real work -------------------------------------------------------------------

hook_is_silent_in_empty_dir() {
    d=$(mktemp -d) && cd "$d" || return 1
    out=$("$state/hook.sh" update-content 2>&1) && [ -z "$out" ]
}
check "hook.sh update-content is silent and exits 0 outside a project" hook_is_silent_in_empty_dir

proj=$(mktemp -d)

# wolfi: the upstream limitation "ocx misdetects glibc" did not reproduce with ocx 0.6.8 and a package
# that ships glibc and musl builds (see test/images/known-limitations.md), so no workaround is needed.
project_setup() {
    cd "$proj" || return 1
    ocx init && ocx add ocx.sh/jqlang/jq:1.8
}
check "ocx init + add jq in a fresh project" project_setup

jq_runs() {
    cd "$proj" || return 1
    out=$(ocx exec -- jq --version) || return 1
    case $out in jq-1.8*) ;; *) printf 'unexpected output: %s\n' "$out" && return 1 ;; esac
}
check "ocx exec runs jq from the project toolchain" jq_runs

hook_restores_in_project() {
    cd "$proj" || return 1
    rm -rf .ocx
    out=$("$state/hook.sh" update-content 2>&1) || return 1
    [ -d .ocx/toolchain ] || {
        printf 'no .ocx/toolchain after the hook; hook output: %s\n' "$out"
        return 1
    }
}
check "hook.sh update-content in a project exits 0 and restores the toolchain links" hook_restores_in_project

finish
