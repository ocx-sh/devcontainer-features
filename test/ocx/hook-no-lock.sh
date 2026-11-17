#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Hook with ocx.toml and no ocx.lock: container creation must not fail (exit 0) and the user gets
# exactly one warning that names exit 78 and the fix, `ocx lock`.
# shellcheck disable=SC2329 # check calls the functions by name
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

finish
