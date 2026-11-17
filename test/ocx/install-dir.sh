#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option installDir: the binary lands in the custom directory (on PATH on debian), not in /usr/local/bin,
# and the hook still finds it through the recorded OCXF_BIN.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

is_in_custom_dir() {
    [ "$(command -v ocx)" -ef /usr/local/sbin/ocx ] && [ ! -e /usr/local/bin/ocx ]
}
check "ocx is /usr/local/sbin/ocx and /usr/local/bin/ocx does not exist" is_in_custom_dir
check "sh -lc finds ocx" sh -lc 'command -v ocx'
check "feature.env records the binary" grep -q "^OCXF_BIN='/usr/local/sbin/ocx'$" "$state/feature.env"
new_project install-dir || true
rm -rf "$proj/.ocx"
check "the hook restores the toolchain through the recorded binary" sh -c "cd '$proj' && $state/hook.sh update-content && [ -d .ocx/toolchain ]"

finish
