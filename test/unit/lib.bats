# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

# Source lib.sh and run <code> under the interpreter under test.
lib() {
    run_snippet ". \"\$OCXF_SRC_DIR/lib.sh\"; $1"
}

@test "say prints to stderr with the prefix" {
    lib 'say hello world 2>&1 >/dev/null'
    assert_success
    assert_output "ocx-feature: hello world"
}

@test "say writes nothing to stdout" {
    lib 'say hi 2>/dev/null'
    assert_success
    assert_output ""
}

@test "warn prefixes warning" {
    lib 'warn careful 2>&1'
    assert_output "ocx-feature: warning: careful"
}

@test "err exits 1 by default" {
    lib 'err boom 2>&1'
    assert_failure 1
    assert_output "ocx-feature: error: boom"
}

@test "err exits with the given code" {
    lib 'err boom 7 2>/dev/null'
    assert_failure 7
}

@test "truthy01 maps the accepted spellings to 1" {
    for v in 1 true yes TRUE YES True Yes; do
        lib "truthy01 $v"
        assert_output "1"
    done
}

@test "truthy01 maps everything else to 0" {
    for v in 0 false no FALSE '' maybe 2 tRuE; do
        lib "truthy01 '$v'"
        assert_output "0"
    done
    lib 'truthy01'
    assert_output "0"
}

# The hostile values the quoter must round-trip through the interpreter under test.
# shellcheck disable=SC2016 # single quotes keep the hostile values literal
hostile() {
    case "$1" in
        1) printf '%s' 'plain' ;;
        2) printf '%s' 'with space' ;;
        3) printf '%s' "it's" ;;
        4) printf '%s' "'" ;;
        5) printf '%s' '$HOME `id` $(id)' ;;
        6) printf '%s' 'a;b&c|d' ;;
        7) printf '%s' '-n' ;;
        8) printf '%s' '--help' ;;
        9) printf '%s' '"double" \back\slash' ;;
        10) printf '%s' '*? [x] ~' ;;
        11) printf 'line1\nline2\n\n' ;;
        12) printf '%s' '' ;;
        13) printf '\ttab  trailing  ' ;;
    esac
}

@test "sh_quote round-trips hostile values" {
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
        hostile "$i" >"$SANDBOX/want"
        hostile "$i" >"$SANDBOX/val"
        lib "v=\$(cat '$SANDBOX/val'; printf x); v=\${v%x}
            q=\$(sh_quote \"\$v\")
            eval \"got=\$q\"
            [ \"\$got\" = \"\$v\" ] || { echo MISMATCH; exit 1; }
            printf '%s' \"\$got\" >'$SANDBOX/got'"
        assert_success
        cmp "$SANDBOX/want" "$SANDBOX/got"
    done
}

@test "sh_quote output is single-quoted" {
    lib "sh_quote \"it's\""
    assert_output "'it'\\''s'"
}

@test "sh_quote of an empty value is two quotes" {
    lib "sh_quote ''"
    assert_output "''"
}

@test "rootpath prefixes the testing root" {
    lib 'rootpath /etc/profile.d'
    assert_output "$__OCXF_TESTING_ROOT/etc/profile.d"
}

@test "rootpath is the identity without a testing root" {
    unset __OCXF_TESTING_ROOT
    lib 'rootpath /etc/profile.d'
    assert_output "/etc/profile.d"
}

@test "has_cmd reports presence by status only" {
    stub present
    lib 'has_cmd present'
    assert_success
    assert_output ""
    lib 'has_cmd definitely-not-a-command-xyz'
    assert_failure
}

@test "need_cmd passes for a present command" {
    stub present
    lib 'need_cmd present'
    assert_success
}

@test "need_cmd exits 2 for a missing command" {
    lib 'need_cmd definitely-not-a-command-xyz 2>&1'
    assert_failure 2
    assert_output "ocx-feature: error: definitely-not-a-command-xyz not found"
}

@test "need_cmd sees a command hidden by restrict_path" {
    stub curl
    restrict_path
    rm "$STUB_DIR/curl"
    lib 'need_cmd curl 2>&1'
    assert_failure 2
}

@test "sourcing twice is harmless" {
    # shellcheck disable=SC2016 # code for the interpreter under test
    lib '. "$OCXF_SRC_DIR/lib.sh"; say twice 2>&1'
    assert_success
    assert_output "ocx-feature: twice"
}

@test "stub logs calls and assert_stub_called matches" {
    stub tool
    run tool a 'b c'
    assert_success
    assert_stub_called "tool a b c"
    refute_stub_called "tool other"
}

@test "stub body decides the exit status" {
    stub failing 'exit 9'
    run failing
    assert_failure 9
}

@test "run_sh runs a script file under the interpreter" {
    # shellcheck disable=SC2016 # script text, expanded when it runs
    printf '#!/bin/sh\n. "$OCXF_SRC_DIR/lib.sh"\nsay "args=$*"\n' >"$SANDBOX/s.sh"
    run_sh "$SANDBOX/s.sh" one two
    assert_success
    assert_output "ocx-feature: args=one two"
}

@test "root helpers create paths inside the fake root" {
    mkroot /etc /usr/local/bin
    root_file /usr/local/share/x/y.txt "hello"
    [ -d "$__OCXF_TESTING_ROOT/etc" ]
    [ -d "$__OCXF_TESTING_ROOT/usr/local/bin" ]
    [ "$(cat "$__OCXF_TESTING_ROOT/usr/local/share/x/y.txt")" = hello ]
}
