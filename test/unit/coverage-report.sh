#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# coverage-report.sh <min-percent> <trace-log> <file>...: line coverage of the given shell files.
# Prints executed/executable per file and in total; exits 1 when any file or the total is below the minimum.
# Executable = not blank, not comment-only, not a bare closer (}, fi, done, esac, then, else, do, ;;),
# not a function header, not a case pattern alone, not a continuation or here-doc body line.
# shortcut: lines inside a multi-line quoted string count as executable; keep such strings on one line.
set -eu

min=$1
log=$2
shift 2
[ "$#" -gt 0 ] || {
    echo "coverage-report: no files in scope" >&2
    exit 2
}

# 1: traced "file:line" pairs from the log; 2: the files.
{
    sed -n 's/^+*cov:\(\/[^:]*\):\([0-9][0-9]*\):.*/T \1 \2/p' "$log"
    for f in "$@"; do
        printf 'F %s\n' "$f"
        cat "$f"
        printf 'E\n'
    done
} | awk -v min="$min" '
$1 == "T" && !infile { hit[$2 SUBSEP $3] = 1; next }
$0 ~ /^F / && !infile { infile = 1; name = substr($0, 3); n = 0; exe = 0; cov = 0; cont = 0; hd = ""; next }
$0 == "E" && infile {
    infile = 0
    pct = exe ? 100 * cov / exe : 100
    printf "%-28s %4d/%-4d %5.1f%%\n", name, cov, exe, pct
    tc += cov; te += exe
    if (cov * 100 < min * exe) bad = 1
    next
}
infile {
    n++
    line = $0
    sub(/^[ \t]+/, "", line)
    if (hd != "") { if (line == hd) hd = ""; next }
    if (cont) { cont = (line ~ /\\$/); next }
    cont = (line ~ /\\$/)
    if (match(line, /<<-?[ \t]*["\x27]?[A-Za-z_]+/)) {
        h = substr(line, RSTART, RLENGTH); sub(/<<-?[ \t]*["\x27]?/, "", h); hd = h
    }
    if (line == "" || line ~ /^#/) next
    if (line ~ /^(\}|\{|fi|done|esac|then|else|do|;;)([ \t;<>|&].*)?$/) next
    if (line ~ /^(\|\||&&|\|)/) next
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/) next
    if (line ~ /^[^()]*\)$/) next
    exe++
    if ((name SUBSEP n) in hit) cov++
}
END {
    pct = te ? 100 * tc / te : 100
    printf "%-28s %4d/%-4d %5.1f%%\n", "TOTAL", tc, te, pct
    if (tc * 100 < min * te) bad = 1
    if (bad) { printf "coverage below %s%%\n", min; exit 1 }
}'
