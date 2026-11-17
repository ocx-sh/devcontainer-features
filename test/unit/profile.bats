# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    export OCXF_VERSION=0.6.8 OCXF_BIN="$STUB_DIR/ocx" OCXF_INSTALL_DIR=/usr/local/bin
    export OCXF_CA_BUNDLE='' OCXF_MANAGED_CONFIG='' OCXF_OCX_HOME='' OCXF_NO_UPDATE_CHECK=0
    export OCXF_CONSENT_PATHS='' OCXF_PULL=1 OCXF_PULL_GROUPS='' OCXF_SHELL_ACTIVATION=1
    PROFILE="$__OCXF_TESTING_ROOT/etc/profile.d/ocx.sh"
    stub ocx 'echo "export OCXTEST_ENV=composed"'
}

gen() {
    run_sh "$REPO_ROOT/test/unit/configure-driver.sh"
    assert_success
}

# sh_c <code>: the interpreter under test, directly (no coverage wrapper: the profile is generated code).
sh_c() {
    # shellcheck disable=SC2086 # OCXF_TEST_SH is deliberately word-split
    run $OCXF_TEST_SH -c "$1"
}

# sh_i <code>: the same as an interactive shell.
sh_i() {
    # shellcheck disable=SC2086 # OCXF_TEST_SH is deliberately word-split
    run $OCXF_TEST_SH -i -c "$1" 2>&1
}

@test "header marker, no helper variable left, silent, under set -eu" {
    gen
    head -n 1 "$PROFILE" | grep -q 'id: ocx'
    sh_i "set -eu; . '$PROFILE'; echo \"[\${__ocx_sh-unset}]\""
    assert_success
    assert_output --partial '[unset]'
}

@test "non-interactive shell never calls ocx" {
    gen
    sh_c "set -eu; . '$PROFILE'"
    assert_success
    assert_output ""
    refute_stub_called "ocx --offline env --shell=sh"
    run cat "$STUB_LOG"
    assert_output ""
}

@test "interactive sh composes the project once with --shell=sh" {
    gen
    sh_i "unset BASH_VERSION ZSH_VERSION; . '$PROFILE'; echo \"v=\${OCXTEST_ENV-}\""
    assert_output --partial 'v=composed'
    assert_stub_called "ocx --offline env --shell=sh"
}

@test "interactive bash and zsh pick their shell" {
    gen
    sh_i "BASH_VERSION=5; . '$PROFILE'"
    assert_stub_called "ocx --offline env --shell=bash"
    sh_i "unset BASH_VERSION; ZSH_VERSION=5; . '$PROFILE'"
    assert_stub_called "ocx --offline env --shell=zsh"
}

@test "activation off: nothing runs even interactively" {
    OCXF_SHELL_ACTIVATION=0 gen
    sh_i ". '$PROFILE'"
    run cat "$STUB_LOG"
    assert_output ""
}

@test "ocx missing: silent, status 0, under set -eu" {
    rm "$STUB_DIR/ocx"
    gen
    sh_i "set -eu; . '$PROFILE'; echo ok"
    assert_success
    assert_output --partial ok
}

@test "ocx failing or printing nothing is harmless under set -e" {
    gen
    stub ocx 'echo boom >&2; exit 78'
    sh_i "set -eu; . '$PROFILE'; echo ok"
    assert_output --partial ok
    refute_output --partial boom
}

@test "sourcing twice in a row works" {
    gen
    sh_i "set -eu; . '$PROFILE'; . '$PROFILE'; echo ok"
    assert_output --partial ok
}

@test "a binary path with a space and a quote is quoted" {
    mkdir -p "$SANDBOX/b in'q"
    printf '#!/bin/sh\necho "export SPACED=yes"\n' >"$SANDBOX/b in'q/ocx"
    chmod +x "$SANDBOX/b in'q/ocx"
    OCXF_BIN="$SANDBOX/b in'q/ocx" gen
    sh_i ". '$PROFILE'; echo \"s=\${SPACED-}\""
    assert_output --partial 's=yes'
}

@test "OCX_HOME is exported when set, hostile value intact" {
    # shellcheck disable=SC2016 # hostile literal, must not expand
    OCXF_OCX_HOME='/h/a b$x' gen
    sh_c ". '$PROFILE'; printf %s \"\$OCX_HOME\"; env | grep -c '^OCX_HOME='"
    # shellcheck disable=SC2016 # literal expected output
    assert_output '/h/a b$x1'
}

@test "OCX_HOME is not touched when the option is empty" {
    gen
    sh_c "unset OCX_HOME; . '$PROFILE'; printf '[%s]' \"\${OCX_HOME-}\""
    assert_output '[]'
}

@test "CA variable is exported only as the fallback for a foreign config" {
    root_file /etc/ca.pem x
    root_file /etc/ocx/config.toml 'mine = 1
'
    OCXF_CA_BUNDLE=/etc/ca.pem gen
    sh_c ". '$PROFILE'; printf %s \"\$OCX_EXTRA_CA_CERTS\""
    assert_output '/etc/ca.pem'
}
