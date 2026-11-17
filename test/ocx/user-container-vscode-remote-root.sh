#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (c), reverse: containerUser vscode, remoteUser root.
. "$(dirname "$0")/scenario.sh"

user_case root /root

finish
