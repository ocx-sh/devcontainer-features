#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# run-legs.sh: run the unit suite once per interpreter, then gate coverage (runs inside the test image).
# env: OCXF_FILE (bats path, default test/unit), OCXF_LEGS (newline list, default all three),
#      OCXF_MIN_COV (percent, default 90). A filtered run still prints coverage but never gates it.
set -eu

cd "$(dirname "$0")/../.."
repo=$PWD
file=${OCXF_FILE:-test/unit}
legs=${OCXF_LEGS:-'dash
busybox sh
bash --posix'}
min=${OCXF_MIN_COV:-90}
# The coverage scope: one glob, every feature script. New scripts are picked up automatically.
scope="$repo/src/ocx/*.sh"

out="$repo/target/reports/junit"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$out"
: >"$tmp/cov.log"
rc=0
cov_ran=0

old_ifs=$IFS
IFS='
'
for leg in $legs; do
    IFS=$old_ifs
    name=${leg%% *}
    rm -rf "$tmp/rep"
    mkdir "$tmp/rep"
    cov=
    if [ "$name" = bash ]; then
        cov="$tmp/cov.log"
        cov_ran=1
    fi
    bats_rc=0
    : >"$tmp/demoted"
    OCXF_DEMOTED_LOG=$tmp/demoted OCXF_TEST_SH=$leg OCXF_COV_LOG=$cov node_modules/bats/bin/bats --formatter tap \
        --report-formatter junit --output "$tmp/rep" "$file" >"$tmp/tap" 2>&1 || bats_rc=$?
    [ -f "$tmp/rep/report.xml" ] && cp "$tmp/rep/report.xml" "$out/unit-$name.xml"
    total=$(sed -n 's/^1\.\.//p' "$tmp/tap")
    fails=$(grep -c '^not ok' "$tmp/tap" || true)
    printf '%s: %s tests, %s failures\n' "$name" "${total:-0}" "$fails"
    # busybox applets beat PATH stubs, so install.bats runs those tests on dash (no_applets); say so.
    demoted=$(sort -u "$tmp/demoted" | wc -l)
    [ "$demoted" -eq 0 ] || printf '%s: %s tests ran on dash instead (stubbed names busybox applets override)\n' "$name" "$demoted"
    if [ "$bats_rc" -ne 0 ]; then
        grep -v '^ok' "$tmp/tap" >&2 || true
        rc=1
    fi
    IFS='
'
done
IFS=$old_ifs

if [ "$cov_ran" -eq 1 ]; then
    gate=$min
    [ "$file" = test/unit ] || gate=0
    # shellcheck disable=SC2086 # the scope glob expands here
    set -- $scope
    sh test/unit/coverage-report.sh "$gate" "$tmp/cov.log" "$@" || rc=1
fi
exit "$rc"
