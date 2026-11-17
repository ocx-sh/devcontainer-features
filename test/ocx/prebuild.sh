#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The prebuild example of integrate/codespaces-and-prebuilds: pull and noUpdateCheck set explicitly.
# The hook fills a cold store, and once it has, ocx exec needs no network (OCX_OFFLINE=1).
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

check "/etc/ocx/config.toml turns the update check off" grep -q '^self = "manual"$' /etc/ocx/config.toml
check "feature.env records OCXF_PULL='1'" grep -q "^OCXF_PULL='1'$" "$state/feature.env"
new_project prebuild || true
rm -rf "$proj/.ocx" "$HOME/.ocx"
check "hook.sh update-content exits 0 and fills the cold store" run_hook update-content
check "OCX_OFFLINE=1 ocx exec runs the tool from the warm store" sh -c "cd '$proj' && OCX_OFFLINE=1 ocx exec -- jq --version"

finish
