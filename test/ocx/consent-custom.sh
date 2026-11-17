#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option consentPaths: two colon-separated paths become two entries of the consent array.
. "$(dirname "$0")/scenario.sh"

check "[shell.consent] lists both paths" grep -q '^paths = \["/workspaces/\*", "/srv/projects/\*"\]$' /etc/ocx/config.toml
check "ocx runs" installed_ok

finish
