#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The one-line feature on the Dev Containers Ubuntu image, the setup the quickstart and the guides show.
# The commands below are the ones the docs print (doc keys qs-ocx-version, qs-add-tool, version-check,
# restore-activation, how-install-files, ts-outside-consent-paths); test/docs/bindings.json binds them.
# shellcheck disable=SC2329,SC2016 # check calls the functions by name; the sh -c text is for the inner shell
. "$(dirname "$0")/scenario.sh"

check "ocx version prints the version the feature recorded" sh -c '[ "$(ocx version)" = "$(cat /usr/local/share/ocx-feature/ocx-version)" ]'
check "ocx is mode 755 and owned by root" test "$(stat -c '%a %U' /usr/local/bin/ocx)" = '755 root'
check "ocx about runs" sh -c 'ocx about >/dev/null'

# quickstart: a fresh project, one tool, run it
qs=$workspace/qs-$$
mkdir -p "$qs"
check "ocx init creates the project" sh -c "cd '$qs' && ocx init"
check "ocx add jqlang/jq:1.8 adds the tool" sh -c "cd '$qs' && ocx add jqlang/jq:1.8"
jq_runs() {
    out=$(cd "$qs" && ocx exec -- jq --version) || return 1
    case $out in jq-1.8*) ;; *) printf 'unexpected output: %s\n' "$out" && return 1 ;; esac
}
check "ocx exec -- jq --version prints jq-1.8" jq_runs
check "the .ocx directory in the home belongs to the user who runs ocx" test "$(stat -c %U ~/.ocx)" = "$(id -un)"

# restore: a locked project is restored by the hook, and a new shell in it finds the tool
new_project restore || true
rm -rf "$proj/.ocx"
check "hook.sh update-content exits 0 in the locked project" run_hook update-content
activated() {
    out=$(cd "$proj" && bash -ic 'command -v jq' 2>&1 | grep -v -e 'cannot set terminal process group' -e 'no job control')
    case $out in
        *"$proj/.ocx/toolchain/links/default/jq/content/"*) ;;
        *) printf 'command -v jq printed: %s\n' "$out" && return 1 ;;
    esac
}
check "bash -ic 'command -v jq' in the project resolves jq from the project toolchain" activated

# trust model: a project outside consentPaths (the default /workspaces/*) does not activate, ocx exec still works
# (shfmt, because the Ubuntu image already ships jq)
outside=$(mktemp -d /tmp/ocx-outside.XXXXXX)
printf '[tools]\nshfmt = "ocx.sh/shfmt/shfmt:3.13.1"\n' >"$outside/ocx.toml"
(cd "$outside" && ocx lock >/dev/null 2>&1 && ocx pull >/dev/null 2>&1)
not_activated() {
    out=$(cd "$outside" && bash -ic 'shfmt --version' 2>&1 | grep -v -e 'cannot set terminal process group' -e 'no job control')
    case $out in
        *'bash: shfmt: command not found'*) ;;
        *) printf 'a shell outside consentPaths printed: %s\n' "$out" && return 1 ;;
    esac
}
check "outside consentPaths a new shell prints bash: shfmt: command not found" not_activated
check "outside consentPaths ocx exec still runs the tool" sh -c "cd '$outside' && ocx exec -- shfmt --version"
rm -rf "$outside"

finish
