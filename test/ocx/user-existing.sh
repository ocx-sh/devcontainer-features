#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (b): an existing non-root user (vscode) is the remote user.
. "$(dirname "$0")/scenario.sh"

user_case vscode /home/vscode

finish
