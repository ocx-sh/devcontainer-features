#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# lint.sh: ShellCheck at every severity plus shfmt over every shell file this repo owns.
# Files are discovered through git (tracked or new, not ignored), never listed by hand.
# Exit: 0 clean, 1 finding, 2 missing tool or no files found.
set -eu

cd "$(dirname "$0")/.."
for t in git shellcheck shfmt xargs grep; do
    command -v "$t" >/dev/null 2>&1 || {
        echo "lint: $t not found" >&2
        exit 2
    }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
list() {
    # shellcheck disable=SC2016 # the loop body is for the inner sh, which expands it
    git ls-files -z --cached --others --exclude-standard -- "$@" | xargs -0 -r sh -c 'for f; do [ -f "$f" ] && printf "%s\n" "$f"; done' sh
}
list ':(glob)src/**/*.sh' ':(glob)scripts/**/*.sh' ':(glob)test/**/*.sh' >"$tmp/sh"
list ':(glob)test/**/*.bash' >"$tmp/bash"
list ':(glob)test/**/*.bats' >"$tmp/bats"
cat "$tmp/sh" "$tmp/bash" "$tmp/bats" >"$tmp/all"
if [ ! -s "$tmp/all" ]; then
    echo "lint: no shell files found" >&2
    exit 2
fi
echo "lint: files"
sed 's/^/  /' "$tmp/all"

rc=0
sc() {
    shell=$1
    list=$2
    [ -s "$list" ] || return 0
    tr '\n' '\0' <"$list" | xargs -0 shellcheck --severity=style --shell="$shell" || rc=1
}
sc sh "$tmp/sh"
sc bash "$tmp/bash"
sc bats "$tmp/bats"

tr '\n' '\0' <"$tmp/all" | xargs -0 shfmt -d || rc=1

# A suppression needs its reason after a second # on the same line.
tr '\n' '\0' <"$tmp/all" | xargs -0 grep -nE 'shellcheck[[:space:]]+disable=' |
    grep -vE 'disable=[A-Za-z0-9,]+[[:space:]]+#[[:space:]]*[^[:space:]]' >"$tmp/noreason" || true
if [ -s "$tmp/noreason" ]; then
    echo "lint: shellcheck disable without a reason on the same line:" >&2
    cat "$tmp/noreason" >&2
    rc=1
fi
exit "$rc"
