#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Hook with ocx.toml and no ocx.lock: container creation must not fail (exit 0) and the user gets
# exactly one warning that names exit 78 and the fix, `ocx lock`.
# shellcheck disable=SC2329,SC2016 # check calls the functions by name; the backticks are text of ocx's message, not command substitution
. "$(dirname "$0")/scenario.sh"

proj=$workspace/no-lock-$$
mkdir -p "$proj"
printf '[tools]\njq = "ocx.sh/jqlang/jq:1.8"\n' >"$proj/ocx.toml"

one_warning() {
    rc=0
    run_hook update-content >"$proj/out" 2>&1 || rc=$?
    n=$(grep -c '^ocx-feature: warning:' "$proj/out" || true)
    [ "$rc" = 0 ] && [ "$n" = 1 ] || {
        printf 'exit %s, %s warnings; output:\n' "$rc" "$n"
        cat "$proj/out"
        return 1
    }
}
check "hook.sh update-content exits 0 with exactly one warning" one_warning
check "the warning names exit code 78" grep -q 'failed with exit code 78' "$proj/out"
check "the warning names ocx lock" grep -q 'run "ocx lock"' "$proj/out"
check "nothing was restored" sh -c "[ ! -e '$proj/.ocx/toolchain' ]"

# The three lines the docs quote (restore-no-lock, ts-lock-missing) and the ocx error above them.
check "the warning line" grep -F -q 'ocx-feature: warning: ocx pull failed with exit code 78.' "$proj/out"
check "the attempted line" grep -F -q 'attempted: /usr/local/bin/ocx pull' "$proj/out"
check "the fix line" grep -F -q 'fix: run "ocx lock" in the project and commit ocx.lock' "$proj/out"
check "ocx reports the missing lock" grep -F -q 'error: ocx.lock not found at ' "$proj/out"
check "ocx names the command that creates it" grep -F -q '/ocx.lock; run `ocx lock` to create it' "$proj/out"

# A lock that no longer matches ocx.toml: the same warning with exit 65 (ts-lock-stale).
new_project stale-lock || true
printf '\n[group.extra.tools]\nshfmt = "ocx.sh/shfmt/shfmt:3.13.1"\n' >>"$proj/ocx.toml"
rm -rf "$proj/.ocx"
run_hook update-content >"$proj/out" 2>&1 || true
check "ocx reports the stale lock" grep -F -q 'error: ocx.lock is stale (it does not match ocx.toml); run `ocx lock`' "$proj/out"
check "the stale warning line" grep -F -q 'ocx-feature: warning: ocx pull failed with exit code 65.' "$proj/out"
check "the stale attempted line" grep -F -q 'attempted: /usr/local/bin/ocx pull' "$proj/out"
check "the stale fix line" grep -F -q 'fix: run "ocx lock" in the project and commit ocx.lock' "$proj/out"

finish
