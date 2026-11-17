#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (a) on the Dev Containers Ubuntu image, the example of guides/non-root-and-custom-users:
# remoteUser root; the hook runs as root and the store is /root/.ocx.
. "$(dirname "$0")/scenario.sh"

user_case root /root

finish
