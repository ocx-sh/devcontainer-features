#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option distUrl in its digest-pinned form https://setup.ocx.sh/dist/<sha256>.json. The runner puts
# the digest of the vendored manifest (src/ocx/dist.json.sha256) into the scenario and into
# dist-digest.expected next to this script, so no release has to edit the scenarios file.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

digest_matches() {
    want=$(cat "$here/dist-digest.expected") || return 1
    [ -n "$want" ] && [ "$(tr -d '[:space:]' <"$state/dist-digest")" = "$want" ] || {
        printf 'recorded %s, expected %s\n' "$(cat "$state/dist-digest")" "$want"
        return 1
    }
}
check "ocx runs" installed_ok
check "the recorded manifest digest is the pinned one" digest_matches

finish
