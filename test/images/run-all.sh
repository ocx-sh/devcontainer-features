#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# run-all.sh: every image of test/images.txt through run-image.sh, JOBS at a time (default 3).
# Each image runs to completion and reports its own result; a failure never stops or hides the
# others. Ends with one table `alias | result | seconds` and exits 1 when any image failed.
# Re-run one image with `task test:image IMAGE=<alias>`.
# Exit: 0 all passed or skipped, 1 an image failed, 2 usage.
set -eu

OUT=target/reports/images
JOBS=${JOBS:-3}
case $JOBS in '' | *[!0-9]* | 0) echo "run-all: JOBS must be a positive integer (got: $JOBS)" >&2 && exit 2 ;; esac

# --one <alias>: run one image, record `<result> <seconds>` in $OUT/<alias>.result.
if [ "${1:-}" = --one ]; then
    a=$2
    t0=$(date +%s)
    rc=0
    sh test/images/run-image.sh "$a" >"$OUT/$a.console" 2>&1 || rc=$?
    secs=$(($(date +%s) - t0))
    if [ "$rc" -ne 0 ]; then
        res=FAIL
    elif grep -q ': skipped:' "$OUT/$a.console"; then
        res=skipped
    else
        res=pass
    fi
    echo "$res $secs" >"$OUT/$a.result"
    printf 'image %-22s %-8s %4ss\n' "$a" "$res" "$secs"
    exit 0
fi

mkdir -p "$OUT" target/reports/junit
aliases=$(awk '$1 !~ /^#/ && NF { print $1 }' test/images.txt)
rm -f "$OUT"/*.result
echo "images: $(echo "$aliases" | wc -l | tr -d ' ') in the list, $JOBS at a time"
# shellcheck disable=SC2016 # the script text is for the inner sh
echo "$aliases" | xargs -P "$JOBS" -I{} sh test/images/run-all.sh --one {}

echo
printf '%-22s | %-8s | %s\n' alias result seconds
printf '%-22s-+-%-8s-+-%s\n' ---------------------- -------- -------
failed=
for a in $aliases; do
    read -r res secs <"$OUT/$a.result" || {
        res=FAIL
        secs=0
    }
    printf '%-22s | %-8s | %s\n' "$a" "$res" "$secs"
    [ "$res" != FAIL ] || failed="$failed $a"
done
if [ -n "$failed" ]; then
    echo
    echo "failed:$failed"
    for a in $failed; do echo "  task test:image IMAGE=$a   (log: $OUT/$a.log)"; done
    exit 1
fi
