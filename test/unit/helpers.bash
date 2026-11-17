# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Shared bats helpers for the feature's unit tests. Load with: load helpers
# Every test gets a sandbox, a fake filesystem root and a stubs dir first on PATH.

REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
OCXF_SRC_DIR="$REPO_ROOT/src/ocx"
export OCXF_SRC_DIR

bats_load_library "$REPO_ROOT/node_modules/bats-support/load.bash"
bats_load_library "$REPO_ROOT/node_modules/bats-assert/load.bash"

# POSIX tools the scripts may rely on; restrict_path links these (plus the shells) into the minimal PATH.
OCXF_MIN_TOOLS="sh awk basename cat chmod cp cut dirname env expr find grep head id ln ls mkdir mktemp mv od rm rmdir sed sort tail tee touch tr uname uniq wc xargs"

ocxf_setup() {
    SANDBOX="$BATS_TEST_TMPDIR/sandbox"
    STUB_DIR="$BATS_TEST_TMPDIR/stubs"
    STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
    __OCXF_TESTING_ROOT="$SANDBOX/root"
    mkdir -p "$SANDBOX" "$STUB_DIR" "$__OCXF_TESTING_ROOT"
    : >"$STUB_LOG"
    export SANDBOX STUB_DIR STUB_LOG __OCXF_TESTING_ROOT
    export PATH="$STUB_DIR:$PATH"
}

setup() {
    ocxf_setup
}

# mkroot <absolute path>...: create directories inside the fake root.
mkroot() {
    for _p in "$@"; do mkdir -p "$__OCXF_TESTING_ROOT$_p"; done
}

# root_file <absolute path> [content]: write a file inside the fake root, creating its directory.
root_file() {
    mkdir -p "$(dirname "$__OCXF_TESTING_ROOT$1")"
    printf '%s' "${2:-}" >"$__OCXF_TESTING_ROOT$1"
}

# stub <name> [script body]: executable stub, first on PATH; each call logs "name args..." to $STUB_LOG.
# The body is POSIX sh and may read "$@"; default body exits 0.
stub() {
    {
        printf '#!/bin/sh\n'
        # shellcheck disable=SC2016 # literal text for the generated stub, expanded when the stub runs
        printf 'printf '"'"'%%s\\n'"'"' "%s $*" >>"$STUB_LOG"\n' "$1"
        printf '%s\n' "${2:-exit 0}"
    } >"$STUB_DIR/$1"
    chmod +x "$STUB_DIR/$1"
}

assert_stub_called() {
    run grep -F -x -e "$1" "$STUB_LOG"
    assert_success
}

refute_stub_called() {
    run grep -F -x -e "$1" "$STUB_LOG"
    assert_failure
}

# restrict_path [tool...]: PATH = stubs + a dir holding only the minimal POSIX tools, the shells and the
# named extras, so "curl is missing" is testable. Call after stub; later stubs still win.
restrict_path() {
    _min="$BATS_TEST_TMPDIR/minbin"
    mkdir -p "$_min"
    for _t in $OCXF_MIN_TOOLS bash dash busybox jq $OCXF_TEST_SH_BIN "$@"; do
        _real=$(PATH="$OCXF_REAL_PATH" command -v "$_t") || continue
        ln -sf "$_real" "$_min/$_t"
    done
    PATH="$STUB_DIR:$_min"
    export PATH
}
OCXF_REAL_PATH=$PATH

# OCXF_TEST_SH: interpreter under test, default sh. "bash --posix" and "busybox sh" are two words.
OCXF_TEST_SH="${OCXF_TEST_SH:-sh}"
OCXF_TEST_SH_BIN="${OCXF_TEST_SH%% *}"

# run_sh <script> [args...]: run a feature script with the interpreter under test. With OCXF_COV_LOG
# set on the bash leg, xtrace lines go to that file (see coverage.sh).
run_sh() {
    _script="$1"
    shift
    case "$_script" in /*) ;; *) _script="$OCXF_SRC_DIR/$_script" ;; esac
    # shellcheck disable=SC2086 # OCXF_TEST_SH is deliberately word-split
    if [ -n "${OCXF_COV_LOG:-}" ]; then
        run sh "$REPO_ROOT/test/unit/coverage.sh" "$_script" "$@"
    else
        run $OCXF_TEST_SH "$_script" "$@"
    fi
}

# run_snippet <sh code>: run a code snippet under the interpreter under test; for sourcing lib.sh.
# The snippet sees $OCXF_SRC_DIR and the sandbox variables.
run_snippet() {
    # shellcheck disable=SC2086 # OCXF_TEST_SH is deliberately word-split
    if [ -n "${OCXF_COV_LOG:-}" ]; then
        run sh "$REPO_ROOT/test/unit/coverage.sh" -c "$1"
    else
        run $OCXF_TEST_SH -c "$1"
    fi
}

# manifest_option_env_names: print the env var install.sh receives for each option, one per line
# (upper-cased, non-word characters become "_", as the devcontainer CLI does).
manifest_option_env_names() {
    jq -r '.options | keys[]' "$OCXF_SRC_DIR/devcontainer-feature.json" |
        tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9_]/_/g'
}
