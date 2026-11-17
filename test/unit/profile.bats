# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    export OCXF_VERSION=9.9.8 OCXF_BIN="$STUB_DIR/ocx" OCXF_INSTALL_DIR=/usr/local/bin
    export OCXF_CA_BUNDLE='' OCXF_MANAGED_CONFIG='' OCXF_OCX_HOME='' OCXF_NO_UPDATE_CHECK=0
    WS="$SANDBOX/ws"
    mkdir -p "$WS/sub"
    : >"$WS/ocx.toml"
    export OCXF_CONSENT_PATHS="$WS/*" OCXF_PULL=1 OCXF_PULL_GROUPS='' OCXF_SHELL_ACTIVATION=1
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

# sh_i <code>: the same as an interactive shell, started in $WS (a consented project) or $IN.
sh_i() {
    # shellcheck disable=SC2086 # OCXF_TEST_SH is deliberately word-split
    run $OCXF_TEST_SH -i -c "cd \"\${IN:-$WS}\" || exit 9; $1" 2>&1
}

@test "header marker, no helper variable left, silent, under set -eu" {
    gen
    head -n 1 "$PROFILE" | grep -q 'id: ocx'
    sh_i "set -eu; . '$PROFILE'; echo \"[\${__ocxf_sh-unset}]\""
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

# evil_stub: an ocx whose env output sets EVIL, to show activation never reached it.
evil_stub() { stub ocx 'echo "export EVIL=1"'; }

# project <dir>: a directory holding an ocx.toml.
project() {
    mkdir -p "$1"
    : >"$1/ocx.toml"
}

@test "S1 a project outside consentPaths is never activated and ocx is not called" {
    evil_stub
    project "$SANDBOX/other"
    gen
    IN="$SANDBOX/other" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
    run cat "$STUB_LOG"
    assert_output ""
}

@test "S1 a project inside consentPaths is activated, also from a nested directory" {
    evil_stub
    gen
    sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
    IN="$WS/sub" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
}

@test "S1 empty consentPaths never activates" {
    evil_stub
    OCXF_CONSENT_PATHS='' gen
    sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
    run cat "$STUB_LOG"
    assert_output ""
}

@test "S1 no ocx.toml anywhere: ocx is not called" {
    mkdir -p "$SANDBOX/none"
    OCXF_CONSENT_PATHS='/*' gen
    IN="$SANDBOX/none" sh_i ". '$PROFILE'; echo ok"
    assert_output --partial ok
    run cat "$STUB_LOG"
    assert_output ""
}

@test "S1 a consent pattern and a project path with a space" {
    evil_stub
    project "$SANDBOX/a b/ws/p q"
    OCXF_CONSENT_PATHS="$SANDBOX/a b/ws/*" gen
    IN="$SANDBOX/a b/ws/p q" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
}

@test "S1 a newline in the working directory neither breaks nor widens the match" {
    evil_stub
    nl='
'
    project "$WS/x${nl}y"
    project "$SANDBOX/ws2${nl}z"
    gen
    IN="$WS/x${nl}y" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
    IN="$SANDBOX/ws2${nl}z" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
}

@test "S1 pattern rules: dir/* covers the dir and below, a plain path only itself, a sibling prefix or other wildcard never" {
    evil_stub
    project "$SANDBOX/wsX"
    project "$WS/sub/deep"
    gen
    IN="$SANDBOX/wsX" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
    IN="$WS/sub/deep" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
    OCXF_CONSENT_PATHS="$WS" gen
    IN="$WS/sub/deep" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
    sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
    OCXF_CONSENT_PATHS="$SANDBOX/w*/*:$SANDBOX/*/ws" gen
    sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
}

@test "S1 OCX_PROJECT decides, a directory or a file" {
    evil_stub
    project "$SANDBOX/other"
    gen
    OCX_PROJECT="$SANDBOX/other" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=unset'
    IN="$SANDBOX/other" OCX_PROJECT="$WS" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
    IN="$SANDBOX/other" OCX_PROJECT="$WS/ocx.toml" sh_i ". '$PROFILE'; echo \"e=\${EVIL-unset}\""
    assert_output --partial 'e=1'
}

@test "S1 no helper variable is left behind, in either branch" {
    gen
    sh_i ". '$PROFILE'; set | grep -c '^__ocxf_' || true"
    assert_output --partial '0'
    IN="$SANDBOX" sh_i ". '$PROFILE'; set | grep -c '^__ocxf_' || true"
    assert_output --partial '0'
}

@test "S1 activation passes the pullGroups, so the restored groups are the ones on PATH" {
    OCXF_PULL_GROUPS=ci,lint gen
    sh_i ". '$PROFILE'"
    run grep -c -e '^ocx --offline env --group=ci,lint --shell=' "$STUB_LOG"
    assert_output 1
}
