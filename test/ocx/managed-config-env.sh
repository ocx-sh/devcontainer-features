#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The OCX_MANAGED_CONFIG variable alone (no managedConfig option): the feature writes no [managed] table
# and the onCreateCommand hook fetches nothing, so only the page's own postCreateCommand applies it.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

check "/etc/ocx/config.toml has no [managed] table" sh -c '! grep -q "^\[managed\]" /etc/ocx/config.toml'
on_create_is_silent() {
    d=$(mktemp -d) && cd "$d" || return 1
    out=$(OCX_MANAGED_CONFIG=localhost:9/acme/fleet:1 "$state/hook.sh" on-create 2>&1) || return 1
    [ -z "$out" ] || {
        printf 'hook output: %s\n' "$out"
        return 1
    }
}
check "hook.sh on-create with the variable set exits 0 and prints nothing" on_create_is_silent

finish
