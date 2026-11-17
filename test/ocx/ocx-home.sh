#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option ocxHome: OCX_HOME is set for new shells and the hook stores packages there. The directory is
# inside the remote user's home, so the user can create it without any image preparation.
. "$(dirname "$0")/scenario.sh"

alt=/home/vscode/.ocx-alt
check "a new shell sees OCX_HOME=$alt" sh -c "[ \"\$(bash -ic 'printf %s \"\$OCX_HOME\"' 2>/dev/null)\" = $alt ]"
new_project ocx-home || true
rm -rf "$proj/.ocx"
check "hook.sh update-content exits 0" run_hook update-content
check "the packages are under $alt" test -d "$alt/packages"
check "the default ~/.ocx holds no packages" sh -c '[ ! -e /home/vscode/.ocx/packages ]'
check "the alternative home is owned by vscode" owned_by vscode "$alt"

finish
