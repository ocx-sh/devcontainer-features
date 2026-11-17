#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# prepare.sh: build the release tree. With CHANGED=true it refreshes the vendored manifest, bumps the
# feature patch version, regenerates the README, checks the installer parity table and records the
# release in CHANGELOG.md; always it makes sure CHANGELOG.md has an entry for the feature version.
# The result is release-tree/tree.patch, a patch of src/ and CHANGELOG.md that the test and publish jobs apply to a clean checkout.
# Repo tooling: needs git, jq; runs under `pnpm exec` so the pinned devcontainer CLI is on PATH.
# env: CHANGED          "true" when the manifest digest differs (from detect.sh)
#      OUT_DIR          where tree.patch goes (default release-tree)
#      GITHUB_OUTPUT, GITHUB_STEP_SUMMARY   written when set
# Outputs: feature_version, ocx_version, old_ocx_version.
# Exit: 0 ok, 2 bad state; update-dist.sh exit 4 (digest mismatch) and 5 (guard violation) and
#       check-installer-parity.sh exit 1 (mismatch) pass through.
set -eu

die() {
    echo "prepare: $1" >&2
    exit 2
}

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
out=${OUT_DIR:-release-tree}
feature_json=src/ocx/devcontainer-feature.json
old_ocx=$(jq -r .latest.version src/ocx/dist.json)

if [ "${CHANGED:-false}" = true ]; then
    # GITHUB_OUTPUT is cleared so the helper scripts do not write their own keys into ours.
    GITHUB_OUTPUT='' sh scripts/update-dist.sh
    bump=$(GITHUB_OUTPUT='' sh scripts/bump-feature-version.sh patch)
    echo "feature version $bump"
    sh scripts/readme.sh
    GITHUB_OUTPUT='' sh scripts/check-installer-parity.sh
fi

feature=$(jq -r .version "$feature_json")
ocx=$(jq -r .latest.version src/ocx/dist.json)
case "$feature" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "feature version '$feature' is not x.y.z" ;; esac
[ -n "$ocx" ] && [ "$ocx" != null ] || die "vendored manifest has no latest version"

if ! grep -q "^## $feature - " CHANGELOG.md 2>/dev/null; then
    note="- ocx $ocx"
    [ "$old_ocx" = "$ocx" ] || note="- ocx $ocx (was $old_ocx)"
    entry="## $feature - $(date -u +%Y-%m-%d)

$note
"
    if [ -f CHANGELOG.md ] && grep -q '^## ' CHANGELOG.md; then
        awk -v entry="$entry" '!done && /^## / { print entry; done = 1 } { print }' CHANGELOG.md >CHANGELOG.md.new
    elif [ -f CHANGELOG.md ]; then
        {
            cat CHANGELOG.md
            echo
            echo "$entry"
        } >CHANGELOG.md.new
    else
        printf '# Changelog\n\n%s\n' "$entry" >CHANGELOG.md.new
    fi
    mv CHANGELOG.md.new CHANGELOG.md
fi

mkdir -p "$out"
git add -A -- src CHANGELOG.md
git diff --cached --binary HEAD >"$out/tree.patch"
# An unchanged tree still yields a non-empty artifact, so the upload never sees a zero-byte file only.
printf 'feature %s\nocx %s\nold_ocx %s\n' "$feature" "$ocx" "$old_ocx" >"$out/release.txt"
echo "release tree: feature $feature, ocx $ocx (was $old_ocx), patch $(wc -c <"$out/tree.patch") bytes"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "Prepared feature $feature with ocx $ocx (was $old_ocx)." >>"$GITHUB_STEP_SUMMARY"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "feature_version=$feature"
        echo "ocx_version=$ocx"
        echo "old_ocx_version=$old_ocx"
    } >>"$GITHUB_OUTPUT"
fi
