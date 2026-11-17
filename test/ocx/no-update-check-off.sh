#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option noUpdateCheck: false leaves the update keys out of the managed config.
. "$(dirname "$0")/scenario.sh"

check "/etc/ocx/config.toml has no [update] table" sh -c '! grep -q "^\[update\]" /etc/ocx/config.toml'
check "/etc/ocx/config.toml has no self or toolchain key" sh -c '! grep -q -e "^self" -e "^toolchain" /etc/ocx/config.toml'
check "/etc/ocx/config.toml still carries the feature marker" grep -q "$marker" /etc/ocx/config.toml
check "ocx runs" installed_ok

finish
