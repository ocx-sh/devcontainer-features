#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Hook without any ocx.toml above the working directory: silent and exit 0, in both phases.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

silent() {
    d=$(mktemp -d) && cd "$d" || return 1
    out=$("$state/hook.sh" "$1" 2>&1) && [ -z "$out" ] || {
        printf 'hook %s printed: %s\n' "$1" "$out"
        return 1
    }
}
check "on-create is silent and exits 0" silent on-create
check "update-content is silent and exits 0" silent update-content

finish
