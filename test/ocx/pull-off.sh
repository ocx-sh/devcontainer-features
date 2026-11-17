#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option pull: false makes the hook do nothing even with ocx.toml and ocx.lock present.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

new_project pull-off || true
rm -rf "$proj/.ocx"
check "the project has ocx.toml and ocx.lock" sh -c "[ -s '$proj/ocx.toml' ] && [ -s '$proj/ocx.lock' ]"
check "feature.env records OCXF_PULL='0'" grep -q "^OCXF_PULL='0'$" "$state/feature.env"

hook_does_nothing() {
    out=$(run_hook update-content 2>&1) || return 1
    [ -z "$out" ] || {
        printf 'hook output: %s\n' "$out"
        return 1
    }
    [ ! -e "$proj/.ocx" ] || {
        printf 'the hook created %s/.ocx\n' "$proj"
        return 1
    }
}
check "hook.sh update-content is silent, exits 0 and restores nothing" hook_does_nothing

finish
