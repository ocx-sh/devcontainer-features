#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# readme.sh: regenerate src/ocx/README.md from devcontainer-feature.json and NOTES.md with the
# devcontainer CLI's generate-docs; --check regenerates into a scratch copy and fails when the
# committed README differs. Edit NOTES.md, never the README.
# Usage: readme.sh [--check]
# Repo tooling: needs the devcontainer CLI on PATH (run it as `pnpm exec sh scripts/readme.sh`).
# Exit: 0 ok, 1 README is stale (--check), 2 usage or missing tool.
set -eu

NAMESPACE=ocx-sh/devcontainer-features

die() {
    echo "readme: $1" >&2
    exit "${2:-2}"
}

mode=regen
case "${1:-}" in
    '') ;;
    --check) mode=check ;;
    *) die "usage: readme.sh [--check]" ;;
esac
dc=$(command -v devcontainer) || die "devcontainer CLI not found (run under pnpm exec)"
case "$dc" in /*) ;; *) dc=$PWD/$dc ;; esac

root=$(cd "$(dirname "$0")/.." && pwd)
# pnpm puts a relative node_modules/.bin on PATH, hence the resolved $dc after the cd.
# The README footer links to the -p path, so run from the project folder with the relative path src.
gen() {
    cd "$1" && "$dc" features generate-docs -n "$NAMESPACE" -p src --github-owner "${NAMESPACE%%/*}" --github-repo "${NAMESPACE#*/}" >/dev/null
}

if [ "$mode" = regen ]; then
    (gen "$root")
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/src"
cp -R "$root/src/." "$tmp/src/"
(gen "$tmp")
if ! cmp -s "$root/src/ocx/README.md" "$tmp/src/ocx/README.md"; then
    echo "readme: src/ocx/README.md is stale; run: task feature:readme" >&2
    exit 1
fi
