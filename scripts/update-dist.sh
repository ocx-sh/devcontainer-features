#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# update-dist.sh: refresh the vendored ocx release manifest (src/ocx/dist.json and its .sha256 sidecar)
# from https://setup.ocx.sh, behind guards that refuse anything but a clean, additive upstream change.
# Repo tooling, not part of the feature: needs curl (unless --from), sha256sum and jq.
#
# Usage: update-dist.sh [--check] [--force] [--from <dir>]
#   --check       never write; exit 10 when an update is available
#   --force       skip the guards (never the digest check)
#   --from <dir>  read dist.json and dist.json.sha256 from <dir> instead of fetching
# env: OCXF_DIST_BASE  base URL of the two files (HTTPS only, default https://setup.ocx.sh)
#      GITHUB_OUTPUT   when set, appends changed, old_version, new_version, pin_changed, digest
#
# Exit: 0 ok (unchanged, or updated), 2 usage or missing tool, 3 network, 4 digest mismatch,
#       5 guard violation (each printed), 10 update available (--check only).
#
# Guards (the first four mirror ocx-sh/find_ocx scripts/update_dist.py): additions-only with the whole
# row compared, release-host url allowlist with single-segment tag and filename, no duplicate
# (version,target), latest on the stable channel, no downgrade, new pin covers every target the old
# pin covers. Added here: schema 1, 64 lowercase hex sha256, the four Linux targets the feature installs.
set -eu

BASE_DEFAULT=https://setup.ocx.sh
URL_PREFIX=https://github.com/ocx-sh/ocx/releases/download/
LINUX_TARGETS="x86_64-unknown-linux-musl x86_64-unknown-linux-gnu aarch64-unknown-linux-musl aarch64-unknown-linux-gnu"

die() {
    echo "update-dist: $1" >&2
    exit "${2:-2}"
}

root=$(cd "$(dirname "$0")/.." && pwd)
vend="$root/src/ocx"
check=0
force=0
from=
while [ $# -gt 0 ]; do
    case "$1" in
        --check) check=1 ;;
        --force) force=1 ;;
        --from)
            [ $# -ge 2 ] || die "--from needs a directory"
            from=$2
            shift
            ;;
        *) die "usage: update-dist.sh [--check] [--force] [--from <dir>]" ;;
    esac
    shift
done

for t in sha256sum jq; do
    command -v "$t" >/dev/null 2>&1 || die "$t not found"
done
[ -n "$from" ] || command -v curl >/dev/null 2>&1 || die "curl not found"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "$from" ]; then
    [ -f "$from/dist.json" ] && [ -f "$from/dist.json.sha256" ] || die "$from lacks dist.json or dist.json.sha256"
    cp "$from/dist.json" "$from/dist.json.sha256" "$tmp/"
else
    base=${OCXF_DIST_BASE:-$BASE_DEFAULT}
    case "$base" in
        https://*) ;;
        *) die "OCXF_DIST_BASE must be an HTTPS URL, got $base" ;;
    esac
    for f in dist.json dist.json.sha256; do
        curl -fsSL --proto '=https' --proto-redir '=https' --max-time 60 -o "$tmp/$f" "${base%/}/$f" ||
            die "could not fetch ${base%/}/$f" 3
    done
fi

new_digest=$(sha256sum "$tmp/dist.json" | cut -d' ' -f1)
side=$(cut -d' ' -f1 "$tmp/dist.json.sha256" | head -n 1)
[ "$new_digest" = "$side" ] || die "digest mismatch: manifest is $new_digest, sidecar says $side" 4

new="$tmp/dist.json"
old="$vend/dist.json"
old_digest=$(sha256sum "$old" | cut -d' ' -f1)
old_version=$(jq -r '.latest.version' "$old")
new_version=$(jq -r '.latest.version' "$new" 2>/dev/null) || die "upstream manifest is not valid JSON" 5

if [ "$force" -eq 0 ]; then
    # Every violation is one line; jq prints them all, then the count decides.
    # shellcheck disable=SC2016 # jq program, not shell
    jq -r --slurpfile old "$old" --arg prefix "$URL_PREFIX" --arg linux "$LINUX_TARGETS" '
        def ver: split(".") | map(tonumber);
        def key: "\(.version) \(.target)";
        def seg: test("^[A-Za-z0-9._+-]+$") and . != "." and . != "..";
        def okurl: type == "string" and startswith($prefix) and (.[($prefix | length):] | split("/") | length == 2 and all(.[]; seg));
        . as $n | $old[0] as $o |
        ( if .schema != 1 then "schema is \(.schema), expected 1" else empty end ),
        ( if (.latest.channel // "") != "stable" then "latest is on channel \(.latest.channel // "missing"), not stable" else empty end ),
        ( if (.latest.version // "" | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) then "latest.version \(.latest.version) is not x.y.z"
          elif ($o.latest.version | ver) > (.latest.version | ver) then "downgrade: newest stable \(.latest.version) is lower than vendored \($o.latest.version)" else empty end ),
        ( .releases | group_by(key)[] | select(length > 1) | "duplicate row \(.[0] | key)" ),
        ( .releases[] | select(.sha256 | (type == "string" and test("^[0-9a-f]{64}$")) | not) | "\(key): sha256 is not 64 lowercase hex" ),
        ( .releases[] | select(.url | okurl | not) | "\(key): url \(.url) is not a release asset under \($prefix)" ),
        ( .releases[] | select(.tag | (type == "string" and seg) | not) | "\(key): tag \(.tag) is not a single path segment" ),
        ( .releases[] | select(.filename | (type == "string" and seg and test("\\.(zip|tar\\.gz|tar\\.xz)$")) | not) | "\(key): filename \(.filename) is not a single segment with a known archive extension" ),
        ( $o.releases[] as $r | ($n.releases | map(select(key == ($r | key))) | first) as $m
          | if $m == null then "\($r | key): vendored row removed upstream"
            elif $m != $r then "\($r | key): vendored row changed upstream" else empty end ),
        ( ($linux | split(" ")[]) as $t | select([$n.releases[] | select(.version == $n.latest.version and .target == $t)] | length == 0)
          | "\($n.latest.version) \($t): required Linux target missing" ),
        ( ($o.releases | map(select(.version == $o.latest.version) | .target)[]) as $t
          | select([$n.releases[] | select(.version == $n.latest.version and .target == $t)] | length == 0)
          | "\($n.latest.version) \($t): target covered by the vendored pin \($o.latest.version) is missing" )
    ' "$new" >"$tmp/violations" 2>"$tmp/jqerr" || {
        sed 's/^/update-dist: /' "$tmp/jqerr" >&2
        die "guard run failed on the upstream manifest" 5
    }
    if [ -s "$tmp/violations" ]; then
        sed 's/^/guard violation: /' "$tmp/violations" >&2
        exit 5
    fi
fi

changed=false
[ "$new_digest" = "$old_digest" ] || changed=true
pin_changed=false
[ "$new_version" = "$old_version" ] || pin_changed=true

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "changed=$changed"
        echo "old_version=$old_version"
        echo "new_version=$new_version"
        echo "pin_changed=$pin_changed"
        echo "digest=$new_digest"
    } >>"$GITHUB_OUTPUT"
fi

if [ "$changed" = false ]; then
    echo "unchanged $old_version"
    exit 0
fi
if [ "$check" -eq 1 ]; then
    echo "update available $old_version -> $new_version (digest $new_digest)"
    exit 10
fi
cp "$tmp/dist.json" "$old.new"
cp "$tmp/dist.json.sha256" "$vend/dist.json.sha256.new"
mv "$old.new" "$old"
mv "$vend/dist.json.sha256.new" "$vend/dist.json.sha256"
echo "updated $old_version -> $new_version"
