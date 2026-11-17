#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Hook with a locked project on an image without bash: the toolchain is restored and a NEW login
# interactive sh resolves the tool from the project toolchain.
. "$(dirname "$0")/scenario.sh"

check "the image has no bash" sh -c '! command -v bash'
new_project hook-sh || true
rm -rf "$proj/.ocx"
check "hook.sh update-content exits 0" run_hook update-content
check ".ocx/toolchain/links/default/jq exists" test -e "$proj/.ocx/toolchain/links/default/jq"
check "sh -lic in the project resolves jq from the toolchain" shell_finds jq "$proj/.ocx/toolchain"

finish
