#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# verify-assets.sh <old dist.json> <new dist.json>: a hash that only setup.ocx.sh vouches for is trust on
# first use. Require the sha256 of every new or changed row, and of the four Linux rows of the new pin,
# to equal the digest GitHub recorded for that release asset of ocx-sh/ocx.
# Repo tooling: needs gh (GH_TOKEN; the job token with contents: read is enough for a public repo) and jq.
# Exit: 0 ok, 2 usage or missing tool, 5 a row has no asset, no digest or a different digest (each printed).
set -eu

die() {
    echo "verify-assets: $1" >&2
    exit "${2:-2}"
}

[ $# -eq 2 ] || die "usage: verify-assets.sh <old dist.json> <new dist.json>"
for t in gh jq; do
    command -v "$t" >/dev/null 2>&1 || die "$t not found"
done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Rows to check, one per line: tag, filename, sha256, "version target". Tag and filename are
# re-validated here because they end up in an API path and a jq filter.
jq -r --slurpfile old "$1" '
    . as $n
    | [ (.releases[] | select(. as $r | ($old[0].releases | any(. == $r)) | not)),
        (.releases[] | select(.version == $n.latest.version and (.target | test("-unknown-linux-")))) ]
    | unique | .[]
    | [.tag, .filename, .sha256, "\(.version) \(.target)"] | join("\t")
' "$2" >"$tmp/rows" || die "cannot read the manifests" 2

bad=0
while IFS="	" read -r tag file sha name; do
    case "$tag$file" in *[!A-Za-z0-9._+-]*) die "$name: unsafe tag or filename" 5 ;; esac
    digest=$(gh api "repos/ocx-sh/ocx/releases/tags/$tag" --jq ".assets[] | select(.name == \"$file\") | .digest") || digest=
    if [ -z "$digest" ]; then
        echo "verify-assets: $name: no digest recorded for asset $file of release $tag" >&2
        bad=1
    elif [ "$digest" != "sha256:$sha" ]; then
        echo "verify-assets: $name: manifest sha256 $sha differs from the GitHub asset digest $digest" >&2
        bad=1
    fi
done <"$tmp/rows"
[ "$bad" -eq 0 ] || exit 5
echo "verify-assets: $(wc -l <"$tmp/rows" | tr -d ' ') rows match the GitHub asset digests"
