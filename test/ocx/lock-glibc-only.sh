#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# A package that ships glibc builds only (node) cannot be locked on a musl image: ocx lock exits 78 and
# names the missing platform (troubleshooting/restore-warnings).
# shellcheck disable=SC2329,SC2016 # check calls the functions by name; the backticks are text of ocx's message, not command substitution
. "$(dirname "$0")/scenario.sh"

proj=$workspace/glibc-only-$$
mkdir -p "$proj"
printf '[tools]\nnode = "ocx.sh/nodejs/node:22"\n' >"$proj/ocx.toml"
case $(uname -m) in
    aarch64 | arm64) arch=arm64 ;;
    *) arch=amd64 ;;
esac
rc=0
(cd "$proj" && ocx lock >"$proj/out" 2>&1) || rc=$?

check "ocx lock exits 78" test "$rc" = 78
check "ocx lock names the missing musl leaf of node" grep -F -q "error: no 'linux/$arch+libc.musl' leaf for binding 'node' at the locked version; run " "$proj/out"
check "ocx lock points at ocx update" grep -F -q '`ocx update` to re-resolve if it has since been added' "$proj/out"

finish
