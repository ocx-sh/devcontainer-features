#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option consentPaths: "/workspaces/*:/tmp/proj" keeps the default entry and adds /tmp/proj, so a project
# there activates in a new shell (troubleshooting/shell-activation-errors).
. "$(dirname "$0")/scenario.sh"

check "[shell.consent] lists the default entry and /tmp/proj" grep -q '^paths = \["/workspaces/\*", "/tmp/proj"\]$' /etc/ocx/config.toml
new_project consent-source || true
src=$proj
rm -rf /tmp/proj
mkdir -p /tmp/proj
cp "$src/ocx.toml" "$src/ocx.lock" /tmp/proj/
proj=/tmp/proj
check "hook.sh update-content exits 0 in /tmp/proj" run_hook update-content
check "a new shell in /tmp/proj resolves jq from its toolchain" shell_finds jq /tmp/proj/.ocx/toolchain
rm -rf /tmp/proj

finish
