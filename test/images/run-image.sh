#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# run-image.sh <alias>: the base-image test for one line of test/images.txt. One wrapper over
# `devcontainer features test` (the feature's test/ocx/test.sh, default options, as root); it adds
# the pieces the CLI does not: the image list, a log, JUnit XML, the dist.json version comparison,
# the busybox negative check, and cleanup of everything the run created.
# Run from the repo root inside `ocx exec -g default --` (the task does), so pnpm and node resolve.
#
# Writes target/reports/images/<alias>.log and target/reports/junit/image-<alias>.xml.
# Other test runs (scenarios) reuse run_cli / cleanup_run by sourcing this file with
# __OCXF_RUN_IMAGE_SOURCE_ONLY=1.
# Exit: 0 passed or skipped (image not published for this architecture), 1 a check failed, 2 usage.
# shellcheck disable=SC2310 # run_cli is tried in a condition on purpose; its status is the answer
set -eu

DC=${OCXF_DEVCONTAINER:-pnpm exec devcontainer}
OUT=target/reports

# host_arch: amd64 or arm64 (__OCXF_TESTING_ARCH overrides uname -m in the unit test).
host_arch() {
    __m=${__OCXF_TESTING_ARCH:-$(uname -m)}
    case $__m in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) echo "$__m" ;;
    esac
}

# image_line <alias>: the "<alias> <ref> [platform]" line, or nothing.
image_line() {
    awk -v a="$1" '$1 !~ /^#/ && $1 == a { print; exit }' test/images.txt
}

# run_cli <log> <image ref>: the devcontainer CLI test of the feature on one base image.
# The CLI names its working directory after Date.now(), so two runs started in the same millisecond
# collide (EEXIST). Starts are spaced by a lock held for the first second of each run. The CLI's own
# end-of-run cleanup removes EVERY container labelled devcontainer.is_test_run, including a sibling
# run's, so it is turned off here; cleanup_run removes only this run's containers.
run_cli() {
    mkdir -p "$OUT/images"
    __lock=$OUT/images/.start.lock
    until mkdir "$__lock" 2>/dev/null; do sleep 0.3; done
    # shellcheck disable=SC2086 # DC is a command line of several words on purpose
    $DC features test -p . -f ocx --skip-scenarios --skip-duplicated --preserve-test-containers -i "$2" >"$1" 2>&1 &
    __pid=$!
    sleep 1.2
    rmdir "$__lock"
    wait "$__pid"
}

# cleanup_run <log>...: remove what the CLI runs named in the logs left behind. Every run works in
# /tmp/devcontainercli/container-features-test/<epoch> and names its images vsc-<epoch>-*, so parallel
# runs never touch each other's.
cleanup_run() {
    for __log in "$@"; do
        [ -f "$__log" ] || continue
        grep -o 'container-features-test/[0-9][0-9]*' "$__log" | sort -u | sed 's|.*/||' | while read -r __e; do
            docker ps -aq --filter "label=devcontainer.local_folder=/tmp/devcontainercli/container-features-test/$__e" | xargs -r docker rm -f >/dev/null 2>&1 || :
            docker image ls -q --filter "reference=vsc-$__e-*" | sort -u | xargs -r docker rmi -f >/dev/null 2>&1 || :
            rm -rf "/tmp/devcontainercli/container-features-test/$__e"
        done
    done
    unset __log
}

# junit <alias> <log> <rc> <extra cases file>: JUnit XML from the ok / not ok lines of the log.
# Always one more case for the CLI run itself, so a build failure (no check lines) is red.
junit() {
    awk -v suite="image-$1" -v rc="$3" '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); gsub(/[^\t\n\r -~]/, "?", s); return s }
    function flush() { if (name != "") { n++; cases = cases sprintf("<testcase classname=\"%s\" name=\"%s\"", suite, esc(name)); if (bad) { f++; cases = cases sprintf("><failure message=\"not ok\">%s</failure></testcase>\n", esc(detail)) } else cases = cases "/>\n" } name = ""; bad = 0; detail = "" }
    /^ok - /      { flush(); name = substr($0, 6) }
    /^not ok - /  { flush(); name = substr($0, 10); bad = 1 }
    /^    # /     { if (bad) detail = detail substr($0, 7) "\n" }
    { tail[NR % 40] = $0 }
    END {
        flush()
        n++
        cases = cases sprintf("<testcase classname=\"%s\" name=\"devcontainer features test exits 0\"", suite)
        if (rc != 0) { f++; for (i = NR - 39; i <= NR; i++) if (i > 0) t = t tail[i % 40] "\n"; cases = cases sprintf("><failure message=\"exit %s\">%s</failure></testcase>\n", rc, esc(t)) } else cases = cases "/>\n"
        printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite name=\"%s\" tests=\"%d\" failures=\"%d\">\n%s", suite, n, f + 0, cases
    }' "$2" >"$OUT/junit/image-$1.xml.tmp"
    if [ -s "$4" ]; then
        # extra cases (the busybox negative check) go in before the closing tag
        sed '$d' "$OUT/junit/image-$1.xml.tmp" >"$OUT/junit/image-$1.xml"
        cat "$4" >>"$OUT/junit/image-$1.xml"
        echo '</testsuite>' >>"$OUT/junit/image-$1.xml"
        rm -f "$OUT/junit/image-$1.xml.tmp"
    else
        echo '</testsuite>' >>"$OUT/junit/image-$1.xml.tmp"
        mv "$OUT/junit/image-$1.xml.tmp" "$OUT/junit/image-$1.xml"
    fi
}

# newest_stable: the version of "latest" in the vendored release manifest.
newest_stable() {
    sed -n '/"latest": *{/,/}/s/.*"version": *"\([^"]*\)".*/\1/p' src/ocx/dist.json | head -n 1
}

[ -z "${__OCXF_RUN_IMAGE_SOURCE_ONLY:-}" ] || return 0

[ $# -eq 1 ] || {
    echo "usage: run-image.sh <alias>" >&2
    exit 2
}
alias=$1
line=$(image_line "$alias")
[ -n "$line" ] || {
    echo "run-image: unknown image alias '$alias' (see test/images.txt)" >&2
    exit 2
}
# shellcheck disable=SC2086 # the line is three whitespace-separated fields
set -- $line
ref=$2
only=${3:-}
arch=$(host_arch)
if [ -n "$only" ] && [ "$only" != "$arch" ]; then
    echo "image $alias: skipped: not published for $arch ($ref is $only only)"
    exit 0
fi

mkdir -p "$OUT/junit" "$OUT/images"
log=$OUT/images/$alias.log
neglog=$OUT/images/$alias-negative.log
extra=$OUT/images/$alias.extra.xml
: >"$extra"
rm -f "$neglog"
built=
trap 'cleanup_run "$log" "$neglog"; [ -z "$built" ] || docker rmi -f "$built" >/dev/null 2>&1 || :' EXIT

case $ref in
    ocx-test/*)
        dir=test/images/$(basename "${ref%%:*}")
        echo "image $alias: building $ref from $dir/Dockerfile"
        docker build -q -t "$ref" "$dir" >/dev/null
        built=$ref
        ;;
esac

echo "image $alias: devcontainer features test on $ref"
rc=0
run_cli "$log" "$ref" || rc=$?

# The version the container reports must be the newest stable version of the vendored manifest.
expected=$(newest_stable)
got=$(sed -n 's/^# ocx-version=//p' "$log" | tail -n 1)
if [ "$rc" -eq 0 ] && [ "$got" != "$expected" ]; then
    printf 'not ok - installed ocx %s is the newest stable of src/ocx/dist.json (%s)\n' "${got:-none}" "$expected" >>"$log"
    rc=1
elif [ "$rc" -eq 0 ]; then
    printf 'ok - installed ocx %s is the newest stable of src/ocx/dist.json\n' "$got" >>"$log"
fi

# busybox: the same feature on the BARE image must fail and say why.
if [ "$alias" = busybox ]; then
    bare=$(sed -n 's/^FROM \(busybox:[^ ]*\).*/\1/p' test/images/busybox-ca/Dockerfile)
    echo "image $alias: bare $bare must fail naming the CA bundle and caBundle"
    nrc=0
    run_cli "$neglog" "$bare" || nrc=$?
    if [ "$nrc" -ne 0 ] && grep -q 'ca-bundle' "$neglog" && grep -q 'caBundle' "$neglog"; then
        printf 'ok - bare %s fails and the message names the CA bundle and caBundle\n' "$bare" >>"$log"
    else
        printf 'not ok - bare %s fails and the message names the CA bundle and caBundle (exit %s)\n' "$bare" "$nrc" >>"$log"
        rc=1
    fi
    {
        printf '# bare image run, last 15 lines:\n'
        tail -n 15 "$neglog" | sed 's/^/    # /'
    } >>"$log"
fi

junit "$alias" "$log" "$rc" "$extra"
rm -f "$extra"
grep -E '^(not )?ok - |^# ' "$log" || :
if [ "$rc" -ne 0 ]; then
    echo "image $alias: FAILED (log: $log)"
    grep -A8 '^not ok - ' "$log" | head -n 60 || :
    grep -q '^not ok - ' "$log" || tail -n 40 "$log"
    exit 1
fi
echo "image $alias: passed"
