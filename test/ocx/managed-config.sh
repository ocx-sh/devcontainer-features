#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option managedConfig: no public managed configuration exists, so the reference cannot be fetched.
# The config file still carries the [managed] keys, and the on-create hook warns once and exits 0.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

ref=ghcr.io/ocx-sh/devcontainer-features-test/no-such-managed-config:1
check "/etc/ocx/config.toml has the [managed] table" grep -q '^\[managed\]$' /etc/ocx/config.toml
check "[managed] source is the reference" grep -q "^source = \"$ref\"$" /etc/ocx/config.toml
check "[managed] required is false" grep -q '^required = false$' /etc/ocx/config.toml

one_warning() {
    d=$(mktemp -d) && cd "$d" || return 1
    rc=0
    "$state/hook.sh" on-create >"$d/out" 2>&1 || rc=$?
    n=$(grep -c '^ocx-feature: warning:' "$d/out" || true)
    [ "$rc" = 0 ] && [ "$n" = 1 ] || {
        printf 'exit %s, %s warnings; output:\n' "$rc" "$n"
        cat "$d/out"
        return 1
    }
    grep -q 'ocx config setup failed with exit code' "$d/out"
}
check "hook.sh on-create exits 0 with exactly one warning naming the failed config setup" one_warning

finish
