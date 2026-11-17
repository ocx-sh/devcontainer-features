#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Idempotence: running install.sh a second time in the built container (the runner copies src/ocx to
# feature-src/ next to this script) leaves every file the feature owns byte-identical.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

fingerprint() {
    for f in /etc/ocx/config.toml /etc/profile.d/ocx.sh /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc \
        "$state"/feature.env "$state"/ocx-version "$state"/dist-digest "$state"/hook.sh /usr/local/bin/ocx; do
        [ -f "$f" ] && cksum "$f"
    done
    return 0
}

block_once() {
    [ "$(grep -c -x -F '# >>> ocx devcontainer feature >>>' "$1")" = 1 ]
}

check "feature-src/install.sh was staged next to the scenario" test -f "$here/feature-src/install.sh"
before=$(fingerprint)
check "the fingerprint covers the binary, config, profile, rc files and state" sh -c "[ \"\$(printf '%s\n' '$before' | wc -l)\" -ge 8 ]"
check "install.sh a second time exits 0" sh "$here/feature-src/install.sh"
after=$(fingerprint)
check "every file the feature owns is unchanged" test "$before" = "$after"
for f in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc; do
    [ -f "$f" ] || continue
    check "$f still holds the marked block exactly once" block_once "$f"
done
check "ocx runs" installed_ok

finish
