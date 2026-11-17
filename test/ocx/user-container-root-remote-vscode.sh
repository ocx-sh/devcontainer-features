#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (c): containerUser root, remoteUser vscode; the remote user, not the container user, owns the results.
. "$(dirname "$0")/scenario.sh"

user_case vscode /home/vscode

finish
