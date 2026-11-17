#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option mirrorUrl: the archive is fetched from <base>/<tag>/<filename>. The upstream release location
# has exactly that layout, so the real base is the only HTTPS mirror that can be used; a successful
# build proves the layout and the checksum check against the vendored manifest.
. "$(dirname "$0")/scenario.sh"

check "ocx runs" installed_ok

finish
