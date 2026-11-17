#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# User case (b) on the Dev Containers Ubuntu image, the example of guides/non-root-and-custom-users:
# remoteUser vscode owns the store, the lock and the toolchain links. The commands of the page's verify
# step (doc key user-verify) run as written.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

user_case vscode /home/vscode

check "id -un prints vscode" test "$(id -un)" = vscode
check "ocx version runs as vscode" sh -c 'ocx version >/dev/null'
every_owner_is_vscode() {
    out=$(cd "$proj" && stat -c '%U %n' ~/.ocx .ocx/toolchain ocx.lock) || return 1
    [ "$(printf '%s\n' "$out" | grep -c '^vscode ')" = 3 ] || {
        printf 'stat printed:\n%s\n' "$out"
        return 1
    }
}
check "stat -c '%U %n' ~/.ocx .ocx/toolchain ocx.lock names vscode three times" every_owner_is_vscode

finish
