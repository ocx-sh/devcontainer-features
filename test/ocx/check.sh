# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# check.sh: a tiny assertion helper for the feature's test scripts, POSIX sh (no bash, no test lib),
# so it runs on every base image. Source it, call check any number of times, end with finish:
#
#   . ./check.sh   (or . "$(dirname "$0")/check.sh")
#   check "ocx is on PATH" command -v ocx
#   finish
#
# check <label> <command...>  run the command; print "ok - label" or "not ok - label" plus its output.
#                             Use `check label sh -c '...'` or a function for compound conditions.
# finish                      print a summary line, exit 1 when any check failed, else 0.
# The "ok - " / "not ok - " lines are what task test:image turns into JUnit test cases.
# Do not `set -e` in the sourcing script: check records failures and keeps going.

CHECK_TOTAL=0
CHECK_FAILED=0

check() {
    __check_label=$1
    shift
    CHECK_TOTAL=$((CHECK_TOTAL + 1))
    if __check_out=$("$@" 2>&1); then
        printf 'ok - %s\n' "$__check_label"
    else
        CHECK_FAILED=$((CHECK_FAILED + 1))
        printf 'not ok - %s\n' "$__check_label"
        if [ -n "$__check_out" ]; then printf '%s\n' "$__check_out" | sed 's/^/    # /'; fi
    fi
    unset __check_label __check_out
}

finish() {
    printf '# %s checks, %s failed\n' "$CHECK_TOTAL" "$CHECK_FAILED"
    [ "$CHECK_FAILED" -eq 0 ] || exit 1
    exit 0
}
