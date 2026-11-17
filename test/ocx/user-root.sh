#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (a): root only, no remoteUser; the hook runs as root.
. "$(dirname "$0")/scenario.sh"

user_case root /root

finish
