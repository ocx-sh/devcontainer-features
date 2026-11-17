#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option shellActivation: false keeps the profile's exports (OCX_HOME, from ocxHome) but drops the
# activation line, so a new interactive shell does not put the project toolchain on PATH.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

check "/etc/profile.d/ocx.sh still exports OCX_HOME" grep -q "^export OCX_HOME='/home/vscode/.ocx-alt'$" /etc/profile.d/ocx.sh
check "/etc/profile.d/ocx.sh has no activation line" sh -c '! grep -q "env --shell" /etc/profile.d/ocx.sh'
check "a new shell sees OCX_HOME" sh -c "[ \"\$(bash -ic 'printf %s \"\$OCX_HOME\"' 2>/dev/null)\" = /home/vscode/.ocx-alt ]"

new_project activation-off || true
rm -rf "$proj/.ocx"
check "hook.sh update-content still restores the toolchain" sh -c "cd '$proj' && $state/hook.sh update-content && [ -d .ocx/toolchain ]"

jq_not_activated() {
    out=$(cd "$proj" && new_shell 'command -v jq') || true
    case $out in
        *.ocx/toolchain*)
            printf 'the shell found jq in the toolchain: %s\n' "$out"
            return 1
            ;;
    esac
}
check "a new shell in the project does not resolve jq from the toolchain" jq_not_activated

# The message the troubleshooting page shows for a tool that is not on PATH (ts-command-not-found).
fmt=$workspace/shfmt-$$
mkdir -p "$fmt"
printf '[tools]\nshfmt = "ocx.sh/shfmt/shfmt:3.13.1"\n' >"$fmt/ocx.toml"
(cd "$fmt" && ocx lock >/dev/null 2>&1 && sh -c "$state/hook.sh update-content" >/dev/null 2>&1)
says_command_not_found() {
    out=$(cd "$fmt" && new_shell 'shfmt --version') || true
    case $out in
        *'bash: shfmt: command not found'*) ;;
        *)
            printf 'a new shell printed: %s\n' "$out"
            return 1
            ;;
    esac
}
check "running shfmt in a new shell prints bash: shfmt: command not found" says_command_not_found

finish
