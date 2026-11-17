#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option libc: auto on debian (glibc) picks the gnu build.
. "$(dirname "$0")/scenario.sh"

check "the binary is the gnu build" is_libc gnu
check "ocx runs" installed_ok

finish
