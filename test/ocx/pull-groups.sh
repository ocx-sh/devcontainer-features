#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option pullGroups: with "extra" the hook restores that group only. On disk that is a link under
# .ocx/toolchain/links/extra and none under links/default.
. "$(dirname "$0")/scenario.sh"

new_project pull-groups '[group.extra.tools]
shfmt = "ocx.sh/shfmt/shfmt:3.13.1"' || true
rm -rf "$proj/.ocx"
check "hook.sh update-content exits 0" run_hook update-content
check "the extra group is linked" test -e "$proj/.ocx/toolchain/links/extra/shfmt"
check "the default group is not linked" sh -c "[ ! -e '$proj/.ocx/toolchain/links/default' ]"

finish
