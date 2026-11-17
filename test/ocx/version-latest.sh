#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option version: latest installs the newest stable release of the manifest. The runner compares the
# printed fact with src/ocx/dist.json (the test directory cannot see src/).
. "$(dirname "$0")/scenario.sh"

check "ocx runs and equals the recorded version" installed_ok
printf '# ocx-version=%s\n' "$(cat "$state/ocx-version")"

finish
