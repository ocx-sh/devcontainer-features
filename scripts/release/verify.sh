#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# verify.sh: prove the published feature is the one in this tree. The version must resolve with the
# devcontainer CLI, and the published layer, unpacked, must equal src/ocx file for file and byte for byte.
# Repo tooling: needs curl, jq, tar, diff, sha256sum, devcontainer.
# env: FEATURE_VERSION, OCX_VERSION, REPO (owner/repo), GH_TOKEN, ACTOR, GITHUB_STEP_SUMMARY (when set)
# Exit: 0 ok, 1 not published or content differs, 3 network.
set -eu

die() {
    echo "verify: $1" >&2
    exit "${2:-1}"
}

root=$(cd "$(dirname "$0")/../.." && pwd)
v=${FEATURE_VERSION:?}
repo=${REPO:?}
ref=ghcr.io/$repo/ocx
api=https://ghcr.io

devcontainer features info manifest "$ref:$v" >/dev/null || die "$ref:$v does not resolve"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'user = "%s:%s"\n' "${ACTOR:?}" "${GH_TOKEN:?}" |
    curl -fsS --retry 3 --retry-all-errors -K - "$api/token?service=ghcr.io&scope=repository:$repo/ocx:pull" >"$tmp/token.json" ||
    die "cannot get a registry token" 3
printf 'Authorization: Bearer %s\n' "$(jq -r .token "$tmp/token.json")" >"$tmp/auth"
curl -fsS --retry 3 --retry-all-errors -H "@$tmp/auth" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -o "$tmp/manifest.json" "$api/v2/$repo/ocx/manifests/$v" || die "cannot read the manifest of $v" 3
digest=sha256:$(sha256sum "$tmp/manifest.json" | cut -d' ' -f1)
layer=$(jq -r '.layers[0].digest // empty' "$tmp/manifest.json")
[ -n "$layer" ] || die "manifest of $v has no layer"
curl -fsSL --retry 3 --retry-all-errors -H "@$tmp/auth" -o "$tmp/layer.tar" "$api/v2/$repo/ocx/blobs/$layer" ||
    die "cannot download the feature layer" 3

want=$(cut -d' ' -f1 "$root/src/ocx/dist.json.sha256")
mkdir "$tmp/layer"
tar -xf "$tmp/layer.tar" -C "$tmp/layer" || die "cannot unpack the feature layer"
got=$(cut -d' ' -f1 "$tmp/layer/dist.json.sha256" 2>/dev/null) || got=
[ "$got" = "$want" ] || die "published dist.json.sha256 '$got' differs from the tree's '$want'"
# The whole file set and every byte must equal src/ocx. Measured with the pinned CLI (0.90.0): packaging
# adds and rewrites nothing, so no file is exempt. A version that exists with other content (publish.sh
# skips an existing version) fails here.
if ! diff -r "$tmp/layer" "$root/src/ocx" >"$tmp/diff" 2>&1; then
    head -n 10 "$tmp/diff" >&2
    die "the published $ref:$v differs from src/ocx; a published version is immutable, so the feature version must be bumped and released again"
fi

echo "verified $ref:$v ($digest), manifest sha256 $want"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Published"
        echo "- feature version: $v"
        echo "- ocx version: ${OCX_VERSION:-unknown}"
        echo "- manifest digest: \`$digest\`"
        echo "- package: https://github.com/orgs/${repo%%/*}/packages/container/package/${repo#*/}%2Focx"
        echo "- reference: \`$ref:$v\`"
    } >>"$GITHUB_STEP_SUMMARY"
fi
