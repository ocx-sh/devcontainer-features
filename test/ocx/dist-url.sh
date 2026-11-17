#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option distUrl: the live manifest at setup.ocx.sh replaces the vendored one. The build recorded the
# digest of the manifest it used, which is a sha256, and ocx runs.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

is_sha256() {
    case $(cat "$state/dist-digest") in
        *[!0-9a-f]* | '') return 1 ;;
    esac
    [ "$(wc -c <"$state/dist-digest" | tr -d ' ')" -ge 64 ]
}
check "ocx runs" installed_ok
check "the recorded manifest digest is a sha256" is_sha256

finish
