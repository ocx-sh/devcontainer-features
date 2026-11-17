#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# run-workspace.sh <alias> <user>: a throwaway dev container of one base image from test/images.txt
# with the LOCAL feature (src/ocx), the remote user <user> (created when the image lacks it), and a
# sample project (ocx.toml + ocx.lock with jq). Opens a login interactive shell as that user, or runs
# CMD in one and exits with its status. Everything it made (container, images, workspace) is removed
# on exit, also on Ctrl-C or failure. Run from the repo root inside `ocx exec -g all --`
# (the `run` task does): it needs pnpm, node and ocx.
#   OPTIONS='{"version":"latest"}'  extra options of the feature, as JSON
#   CMD='ocx version'               run this instead of a shell
# Exit: the command's status, 2 usage, 1 setup failed.
# shellcheck disable=SC2329,SC2310,SC2016 # cleanup runs from a trap; image_line is tried in a condition; the inner script is for the container shell
set -eu

# shellcheck disable=SC2034 # OUT is read by run-image.sh when sourced
__OCXF_RUN_IMAGE_SOURCE_ONLY=1
# shellcheck source=run-image.sh
. test/images/run-image.sh

[ $# -eq 2 ] || {
    echo "usage: run-workspace.sh <alias> <user>" >&2
    exit 2
}
alias=$1
user=$2
case $user in
    root | [a-z][a-z0-9_-]*) ;;
    *)
        echo "run-workspace: bad user name '$user'" >&2
        exit 2
        ;;
esac
line=$(image_line "$alias")
[ -n "$line" ] || {
    echo "run-workspace: unknown image alias '$alias' (see test/images.txt)" >&2
    exit 2
}
# shellcheck disable=SC2086 # the line is whitespace-separated fields
set -- $line
ref=$2
only=${3:-}
if [ -n "$only" ] && [ "$only" != "$(host_arch)" ]; then
    echo "run-workspace: $alias is published for $only only, this host is $(host_arch)" >&2
    exit 2
fi

dir=$(pwd)/target/run/$alias-$user
built=
cleanup() {
    docker ps -aq --filter "label=devcontainer.local_folder=$dir" | xargs -r docker rm -f >/dev/null 2>&1 || :
    docker image ls -q --filter "reference=vsc-$alias-$user-*" | sort -u | xargs -r docker rmi -f >/dev/null 2>&1 || :
    [ -z "$built" ] || docker rmi -f "$built" >/dev/null 2>&1 || :
    rm -rf "$dir"
    rmdir target/run 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

rm -rf "$dir"
mkdir -p "$dir/.devcontainer"
cp -R src/ocx "$dir/.devcontainer/ocx"

case $ref in
    ocx-test/*)
        # a tag of its own: another run may use the :local one at the same time
        echo "run: building $ref from test/images/$(basename "${ref%%:*}")"
        built=${ref%%:*}:run-$$
        docker build -q -t "$built" "test/images/$(basename "${ref%%:*}")" >/dev/null
        ref=$built
        ;;
esac

# The user is created in a generated Dockerfile, before the feature runs, so it works on every
# image: useradd where it exists, busybox adduser otherwise. An image that has the user keeps it.
cat >"$dir/.devcontainer/Dockerfile" <<EOF
FROM $ref
RUN id $user >/dev/null 2>&1 || useradd -m -s /bin/sh $user 2>/dev/null || adduser -D $user
EOF
opts=${OPTIONS:-}
[ -n "$opts" ] || opts='{}'
cat >"$dir/.devcontainer/devcontainer.json" <<EOF
{
  "name": "ocx-run-$alias-$user",
  "build": { "dockerfile": "Dockerfile" },
  "remoteUser": "$user",
  "features": { "./ocx": $opts }
}
EOF
printf '[tools]\njq = "ocx.sh/jqlang/jq:1.8"\n' >"$dir/ocx.toml"
(cd "$dir" && ocx lock >/dev/null 2>&1) || {
    echo "run-workspace: ocx lock failed for the sample project" >&2
    exit 1
}
# The workspace is a bind mount of the host user's files; a root hook refuses a project owned by
# another user, so for USER=root the sample project is visible but not restored.

DC=${OCXF_DEVCONTAINER:-pnpm exec devcontainer}
# shellcheck disable=SC2086 # DC is a command line of several words on purpose
$DC up --workspace-folder "$dir" --mount-workspace-git-root false --remove-existing-container >"$dir/up.log" 2>&1 || {
    echo "run-workspace: devcontainer up failed; last lines of its log:" >&2
    tail -n 25 "$dir/up.log" >&2
    exit 1
}
grep -E 'ocx-feature: (warning|installed)' "$dir/up.log" || :

# a login interactive shell: bash when the image has it, else sh; activation needs the interactive part.
inner='s=sh; command -v bash >/dev/null 2>&1 && s=bash; if [ -n "$1" ]; then exec "$s" -lic "$1"; else exec "$s" -li; fi'
rc=0
# shellcheck disable=SC2086 # DC is a command line of several words on purpose
$DC exec --workspace-folder "$dir" --mount-workspace-git-root false sh -c "$inner" _ "${CMD:-}" || rc=$?
exit "$rc"
