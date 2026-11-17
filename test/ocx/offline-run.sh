#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The offline example of integrate/mirror-and-air-gapped (OCX_OFFLINE=1): ocx exec works from a warm
# store and fails with exit 79 from a cold one. The commands set the variable themselves, so the check
# does not depend on how the test harness passes containerEnv.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

check "containerEnv sets OCX_OFFLINE=1 in the container" test "${OCX_OFFLINE:-}" = 1
# locking needs the network, so this script leaves the offline mode and sets it per command
unset OCX_OFFLINE
new_project offline || true
rm -rf "$proj/.ocx" "$HOME/.ocx"
cold_exits_79() {
    rc=0
    (cd "$proj" && OCX_OFFLINE=1 ocx exec -- jq --version) >/dev/null 2>&1 || rc=$?
    [ "$rc" = 79 ] || {
        printf 'a cold store with OCX_OFFLINE=1 exited %s, expected 79\n' "$rc"
        return 1
    }
}
check "a cold store with OCX_OFFLINE=1 exits 79" cold_exits_79
check "ocx pull warms the store" sh -c "cd '$proj' && env -u OCX_OFFLINE ocx pull >/dev/null 2>&1"
check "a warm store runs the tool with OCX_OFFLINE=1" sh -c "cd '$proj' && OCX_OFFLINE=1 ocx exec -- jq --version"

finish
