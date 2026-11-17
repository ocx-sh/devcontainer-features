#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option consentPaths: "/workspaces/app" activates that project and not its sibling. Runs as root so the
# two project directories can sit directly under /workspaces.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

check "[shell.consent] lists only /workspaces/app" grep -q '^paths = \["/workspaces/app"\]$' /etc/ocx/config.toml
new_project consent-source || true
for d in /workspaces/app /workspaces/sibling; do
    rm -rf "$d"
    mkdir -p "$d"
    cp "$proj/ocx.toml" "$proj/ocx.lock" "$d/"
    (cd "$d" && sh -c "$state/hook.sh update-content") >/dev/null 2>&1
done
trap 'rm -rf /workspaces/app /workspaces/sibling "$workspace"/*-"$$"-* "$workspace"/*-"$$"' EXIT
proj=/workspaces/app
check "a new shell in /workspaces/app resolves jq from its toolchain" shell_finds jq /workspaces/app/.ocx/toolchain
sibling_not_activated() {
    out=$(cd /workspaces/sibling && new_shell 'command -v jq') || true
    case $out in
        *.ocx/toolchain*)
            printf 'the shell found jq in the toolchain: %s\n' "$out"
            return 1
            ;;
    esac
}
check "a new shell in the sibling project does not resolve jq from the toolchain" sibling_not_activated

finish
