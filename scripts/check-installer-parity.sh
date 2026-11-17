#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# check-installer-parity.sh: keep src/ocx/installer-parity.json in step with the official ocx installer.
# Usage: check-installer-parity.sh [--from <file>]
#   --from <file>  read the installer source from a local file instead of GitHub raw (HTTPS)
# Variables are every OCX_* name in the source, as a whole word; __OCX_* test hatches and the bare
# OCX_INSTALL_ prefix do not count. Also validates the table against devcontainer-feature.json:
# statuses in the enum, exposed entries name an existing option, every option is covered, notes
# are non-empty and at most 25 words.
# Repo tooling: needs jq (and curl without --from).
# Exit: 0 table matches, 1 mismatch (each printed), 2 usage or missing tool, 3 network.
set -eu

URL=https://raw.githubusercontent.com/ocx-sh/www-setup/main/src/install.sh

die() {
    echo "check-installer-parity: $1" >&2
    exit "${2:-2}"
}

root=$(cd "$(dirname "$0")/.." && pwd)
table="$root/src/ocx/installer-parity.json"
manifest="$root/src/ocx/devcontainer-feature.json"
from=
while [ $# -gt 0 ]; do
    case "$1" in
        --from)
            [ $# -ge 2 ] || die "--from needs a file"
            from=$2
            shift
            ;;
        *) die "usage: check-installer-parity.sh [--from <file>]" ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || die "jq not found"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "$from" ]; then
    [ -f "$from" ] || die "$from is not a file"
    src=$from
else
    command -v curl >/dev/null 2>&1 || die "curl not found"
    src="$tmp/install.sh"
    curl -fsSL --proto '=https' --proto-redir '=https' --max-time 60 -o "$src" "$URL" || die "could not fetch $URL" 3
fi

grep -oE '(^|[^A-Za-z0-9_])OCX_[A-Z0-9_]+' "$src" | sed 's/^[^O]*//' | grep -v '_$' | sort -u >"$tmp/upstream" || true
jq -r '.variables[].name' "$table" | sort -u >"$tmp/table"

rc=0
comm -23 "$tmp/upstream" "$tmp/table" | sed 's/^/missing from the table: /' >"$tmp/out"
comm -13 "$tmp/upstream" "$tmp/table" | sed 's/^/gone upstream: /' >>"$tmp/out"

# shellcheck disable=SC2016 # jq program, not shell
jq -r --slurpfile m "$manifest" '
    ($m[0].options | keys) as $opts
    | def words: split(" ") | map(select(. != "")) | length;
    ( .variables[] | . as $v
      | ( if (["exposed", "fixed", "not-exposed"] | index($v.status)) == null then "\($v.name): status \($v.status) is not exposed, fixed or not-exposed"
          elif $v.status == "exposed" and (($v.option // "") as $o | ($opts | index($o)) == null) then "\($v.name): exposed but option \($v.option // "missing") is not in devcontainer-feature.json"
          else empty end),
        ( if ($v.note // "") == "" then "\($v.name): note is empty" elif ($v.note | words) > 25 then "\($v.name): note is over 25 words" else empty end ) ),
    ( .featureOnly[] | . as $f
      | ( if ($opts | index($f.option)) == null then "featureOnly \($f.option): not an option in devcontainer-feature.json" else empty end),
        ( if ($f.note // "") == "" then "featureOnly \($f.option): note is empty" elif ($f.note | words) > 25 then "featureOnly \($f.option): note is over 25 words" else empty end ) ),
    ( ([.variables[] | select(.status == "exposed") | .option] + [.featureOnly[].option]) as $covered
      | $opts[] | select(. as $o | $covered | index($o) | not) | "option \(.) is neither exposed by a variable nor in featureOnly" )
' "$table" >>"$tmp/out" || die "could not read $table" 1

if [ -s "$tmp/out" ]; then
    cat "$tmp/out" >&2
    rc=1
fi
[ "$rc" -eq 0 ] && echo "parity ok: $(wc -l <"$tmp/upstream" | tr -d ' ') installer variables match"
exit "$rc"
