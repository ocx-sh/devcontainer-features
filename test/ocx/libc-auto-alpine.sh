#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option libc: auto on alpine (musl) picks the musl build.
. "$(dirname "$0")/scenario.sh"

check "the binary is the musl build" is_libc musl
check "ocx runs" installed_ok

finish
