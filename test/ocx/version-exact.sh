#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option version: an exact release (0.6.7, older than the pinned one) is installed, not the pinned one.
. "$(dirname "$0")/scenario.sh"

check "ocx version and the record are 0.6.7" version_is 0.6.7

finish
