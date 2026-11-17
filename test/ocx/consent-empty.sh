#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option consentPaths: the empty string writes no consent table; every project asks first.
. "$(dirname "$0")/scenario.sh"

check "/etc/ocx/config.toml has no [shell.consent] table" sh -c '! grep -q "shell.consent" /etc/ocx/config.toml'
check "/etc/ocx/config.toml carries the feature marker" grep -q "$marker" /etc/ocx/config.toml
check "ocx runs" installed_ok

finish
