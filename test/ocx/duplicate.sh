#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The CLI's duplicate test: the feature is installed twice in one image, once with randomized option
# values and once with the defaults (the last install wins). Nothing may double up.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

block_once() {
    [ "$(grep -c -x -F '# >>> ocx devcontainer feature >>>' "$1")" = 1 ]
}

check "ocx runs and equals the recorded version" installed_ok
check "/etc/ocx/config.toml has the feature marker once" sh -c "[ \"\$(grep -c '$marker' /etc/ocx/config.toml)\" = 1 ]"
check "/etc/profile.d/ocx.sh has the feature marker once" sh -c "[ \"\$(grep -c '$marker' /etc/profile.d/ocx.sh)\" = 1 ]"
for f in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc; do
    [ -f "$f" ] || continue
    check "$f holds the marked block exactly once" block_once "$f"
done
check "sh -lc finds ocx" sh -lc 'command -v ocx'

finish
