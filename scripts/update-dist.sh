#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# update-dist.sh: refresh the vendored ocx release manifest (src/ocx/dist.json and its .sha256 sidecar)
# from https://setup.ocx.sh, behind guards that refuse anything but a clean, additive upstream change.
# Repo tooling, not part of the feature: needs curl (unless --from), sha256sum and jq.
#
# Usage: update-dist.sh [--check] [--force] [--from <dir>]
#   --check       never write; exit 10 when an update is available
#   --force       skip the policy guards (additions-only, no downgrade, coverage); never the digest check
#                 and never the format guards below
#   --from <dir>  read dist.json and dist.json.sha256 from <dir> instead of fetching
# env: OCXF_DIST_BASE  base URL of the two files (HTTPS only, default https://setup.ocx.sh)
#      GITHUB_OUTPUT   when set, appends changed, old_version, new_version, pin_changed, digest
#
# Exit: 0 ok (unchanged, or updated), 2 usage or missing tool, 3 network, 4 digest mismatch,
#       5 guard violation (each printed), 10 update available (--check only).
#
# Format guards, always run, before any jq policy guard: no backslash byte, no duplicate key, and the file
# must be byte-identical to dist-canonical.jq's rendering of its own content (the layout setup.ocx.sh
# publishes). That closes every parser differential between these jq guards and the installer's
# grep/sed: escapes, duplicate keys, reordered or extra fields, multi-line rows, rows before "latest".
# If upstream legitimately adds a field or changes the layout, the run stops (exit 5) and the release
# issue says so; that fail-closed stop is intended, update dist-canonical.jq in the same change.
#
# Policy guards (the first four mirror ocx-sh/find_ocx scripts/update_dist.py): additions-only with the whole
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

# Format guards: never skipped, not even by --force. src/ocx/install.sh reads this file with grep and sed
# (first textual match wins, no escape decoding) while the guards below read it with jq (escapes decoded,
# last duplicate key wins). The file is accepted only when both read the same thing.
# shellcheck disable=SC1003 # a literal backslash for grep
if grep -q '\\' "$new"; then
    die "guard violation: the manifest contains a backslash; escape sequences are refused (the installer does not decode them)" 5
fi
jq -e . "$new" >/dev/null 2>&1 || die "upstream manifest is not valid JSON" 5
dup=$(jq -c --stream -n '[inputs | select(length == 2) | .[0] | map(tostring) | join("/")] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$new") ||
    die "upstream manifest is not valid JSON" 5
[ "$dup" = '""' ] || die "guard violation: duplicate key in an object: $dup" 5
jq -j -f "$root/scripts/dist-canonical.jq" "$new" >"$tmp/canon" 2>/dev/null || die "guard violation: the manifest does not have the expected shape" 5
if ! cmp -s "$new" "$tmp/canon"; then
    line=$(awk 'NR == FNR { a[FNR] = $0; next } a[FNR] != $0 { print FNR ": " substr(a[FNR], 1, 200); exit }' "$new" "$tmp/canon")
    die "guard violation: the manifest is not byte-identical to its canonical rendering; first differing line ${line:-(line count or final newline)}" 5
fi
new_version=$(jq -r '.latest.version' "$new")

# Every violation is one line; jq prints them all, then the count decides. --force sets $force and only
# silences the policy block at the end; the integrity block always runs.
# \A and \z, not ^ and $: jq's ^ and $ also match before a trailing newline, which the installer rejects.
# Linux rows of the newest version must be .tar.gz (older rows may be .tar.xz); every url is the release
# url of its own tag and filename.
# shellcheck disable=SC2016 # jq program, not shell
jq -r --slurpfile old "$old" --arg prefix "$URL_PREFIX" --arg linux "$LINUX_TARGETS" --argjson force "$force" '
    def ver: split(".") | map(tonumber);
    def key: "\(.version) \(.target)";
    def seg: test("\\A[A-Za-z0-9._+-]+\\z") and . != "." and . != "..";
    def okurl: type == "string" and startswith($prefix) and (.[($prefix | length):] | split("/") | length == 2 and all(.[]; seg));
    . as $n | $old[0] as $o |
    ( if .schema != 1 then "schema is \(.schema), expected 1" else empty end ),
    ( if (.latest.channel // "") != "stable" then "latest is on channel \(.latest.channel // "missing"), not stable" else empty end ),
    ( if (.latest.version // "" | test("\\A[0-9]+\\.[0-9]+\\.[0-9]+\\z") | not) then "latest.version \(.latest.version) is not x.y.z"
      elif ([.releases[] | select(.channel == "stable")] | first | .version) != .latest.version then "first stable row is \([.releases[] | select(.channel == "stable")] | first | .version), the installer would pin it, but latest.version is \(.latest.version)" else empty end ),
    ( .releases | group_by(key)[] | select(length > 1) | "duplicate row \(.[0] | key)" ),
    ( .releases[] | select(.sha256 | (type == "string" and test("\\A[0-9a-f]{64}\\z")) | not) | "\(key): sha256 is not 64 lowercase hex" ),
    ( .releases[] | select(.url | okurl | not) | "\(key): url \(.url) is not a release asset under \($prefix)" ),
    ( .releases[] | select(.tag | (type == "string" and seg) | not) | "\(key): tag \(.tag) is not a single path segment" ),
    ( .releases[] | select(.filename | (type == "string" and seg and test("\\.(zip|tar\\.gz|tar\\.xz)\\z")) | not) | "\(key): filename \(.filename) is not a single segment with a known archive extension" ),
    ( .releases[] | select(.url != $prefix + .tag + "/" + .filename) | "\(key): url \(.url) does not match tag \(.tag) and filename \(.filename)" ),
    ( .releases[] | select(.version == $n.latest.version and (.target | test("-unknown-linux-")) and (.filename | endswith(".tar.gz") | not)) | "\(key): linux archive \(.filename) is not .tar.gz" ),
    ( ($linux | split(" ")[]) as $t | select([$n.releases[] | select(.version == $n.latest.version and .target == $t)] | length == 0)
      | "\($n.latest.version) \($t): required Linux target missing" ),
    ( if $force == 1 then empty else
        ( if (.latest.version | test("\\A[0-9]+\\.[0-9]+\\.[0-9]+\\z")) and ($o.latest.version | ver) > (.latest.version | ver) then "downgrade: newest stable \(.latest.version) is lower than vendored \($o.latest.version)" else empty end ),
        ( $o.releases[] as $r | ($n.releases | map(select(key == ($r | key))) | first) as $m
          | if $m == null then "\($r | key): vendored row removed upstream"
            elif $m != $r then "\($r | key): vendored row changed upstream" else empty end ),
        ( ($o.releases | map(select(.version == $o.latest.version) | .target)[]) as $t
          | select([$n.releases[] | select(.version == $n.latest.version and .target == $t)] | length == 0)
          | "\($n.latest.version) \($t): target covered by the vendored pin \($o.latest.version) is missing" )
      end )
' "$new" >"$tmp/violations" 2>"$tmp/jqerr" || {
    sed 's/^/update-dist: /' "$tmp/jqerr" >&2
    die "guard run failed on the upstream manifest" 5
}
if [ -s "$tmp/violations" ]; then
    sed 's/^/guard violation: /' "$tmp/violations" >&2
    exit 5
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
