#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# bump-feature-version.sh: raise the top-level feature "version" in src/ocx/devcontainer-feature.json.
# Usage: bump-feature-version.sh [patch|minor|major]   (default patch)
# Prints "<old> -> <new>"; with GITHUB_OUTPUT set also writes old_version and new_version.
# Only that one line changes; the rest of the file is copied through untouched.
# Exit: 0 ok, 2 usage or malformed current version.
set -eu

die() {
    echo "bump-feature-version: $1" >&2
    exit 2
}

level=${1:-patch}
[ $# -le 1 ] || die "usage: bump-feature-version.sh [patch|minor|major]"
case "$level" in patch | minor | major) ;; *) die "unknown level $level" ;; esac

file=$(cd "$(dirname "$0")/.." && pwd)/src/ocx/devcontainer-feature.json
# Top-level "version" sits at two-space indent; option names are indented deeper.
old=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$file" | head -n 1)
case "$old" in
    '' | *[!0-9.]* | *..* | .* | *.) die "current version '$old' is not x.y.z" ;;
esac
IFS=. read -r maj min pat extra <<EOT
$old
EOT
[ -n "$pat" ] && [ -z "$extra" ] || die "current version '$old' is not x.y.z"
case "$level" in
    major) new="$((maj + 1)).0.0" ;;
    minor) new="$maj.$((min + 1)).0" ;;
    patch) new="$maj.$min.$((pat + 1))" ;;
esac

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
awk -v new="$new" '!done && /^  "version": ".*",$/ { print "  \"version\": \"" new "\","; done = 1; next } { print }' "$file" >"$tmp"
cat "$tmp" >"$file"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "old_version=$old"
        echo "new_version=$new"
    } >>"$GITHUB_OUTPUT"
fi
echo "$old -> $new"
