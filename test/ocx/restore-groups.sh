#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option pullGroups: "default,ci" restores both groups, the default one and the named one.
. "$(dirname "$0")/scenario.sh"

check "feature.env records the groups" grep -q "^OCXF_PULL_GROUPS='default,ci'$" "$state/feature.env"
new_project restore-groups '[group.ci.tools]
shfmt = "ocx.sh/shfmt/shfmt:3.13.1"' || true
rm -rf "$proj/.ocx"
check "hook.sh update-content exits 0" run_hook update-content
check "the default group is linked" test -e "$proj/.ocx/toolchain/links/default/jq"
check "the ci group is linked" test -e "$proj/.ocx/toolchain/links/ci/shfmt"

finish
