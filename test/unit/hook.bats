# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    WS="$SANDBOX/ws"
    mkdir -p "$WS/sub" "$SANDBOX/none"
    : >"$WS/ocx.toml"
    stub ocx
    as_uid 1000
    write_env
}

# as_uid <n>: pretend the hook runs as that uid (test-only knob of hook.sh).
as_uid() {
    __OCXF_TESTING_UID=$1
    export __OCXF_TESTING_UID
}

# write_env [KEY=value]...: the feature.env configure.sh would write, defaults overridable.
write_env() {
    mkroot /usr/local/share/ocx-feature
    {
        printf "OCXF_BIN='%s'\n" "$STUB_DIR/ocx"
        printf "OCXF_PULL='1'\nOCXF_PULL_GROUPS=''\nOCXF_MANAGED_CONFIG=''\nOCXF_OCX_HOME=''\nOCXF_CA_BUNDLE=''\nOCXF_CA_ENV='0'\n"
        for kv in "$@"; do printf "%s='%s'\n" "${kv%%=*}" "${kv#*=}"; done
    } >"$(env_file)"
}

env_file() { printf '%s' "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/feature.env"; }

# hook <phase> [dir]: run hook.sh in dir (default the workspace).
hook() {
    cd "${2:-$WS}" || return 1
    run_sh hook.sh "$1"
}

warnings() { printf '%s\n' "$output" | grep -c 'warning:' || true; }

@test "missing or unknown phase exits 2" {
    hook ''
    assert_failure 2
    hook bogus
    assert_failure 2
    assert_output --partial usage
}

@test "missing feature.env warns once and exits 0" {
    rm "$(env_file)"
    hook update-content
    assert_success
    [ "$(warnings)" = 1 ]
    refute_stub_called "ocx pull"
}

@test "missing binary warns once and exits 0" {
    write_env "OCXF_BIN=$SANDBOX/nope"
    hook update-content
    assert_success
    [ "$(warnings)" = 1 ]
}

@test "update-content pulls in the workspace" {
    hook update-content
    assert_success
    assert_output ""
    assert_stub_called "ocx pull"
}

@test "pull option off skips the pull" {
    write_env OCXF_PULL=0
    hook update-content
    assert_success
    refute_stub_called "ocx pull"
}

@test "groups are passed as --group=VALUE so a value never reads as a flag" {
    write_env OCXF_PULL_GROUPS=a,b
    hook update-content
    assert_stub_called "ocx pull --group=a,b"
}

@test "update-content never runs the managed config" {
    write_env OCXF_MANAGED_CONFIG=ocx.sh/c/d:u
    hook update-content
    refute_stub_called "ocx config setup --managed-config=ocx.sh/c/d:u"
}

@test "on-create applies the managed config with config setup" {
    write_env OCXF_MANAGED_CONFIG=ocx.sh/c/d:u
    hook on-create
    assert_success
    assert_output ""
    assert_stub_called "ocx config setup --managed-config=ocx.sh/c/d:u"
    refute_stub_called "ocx pull"
}

@test "on-create without a managed config does nothing" {
    hook on-create
    assert_success
    run cat "$STUB_LOG"
    assert_output ""
}

@test "on-create failure warns once with the fix and still exits 0" {
    write_env OCXF_MANAGED_CONFIG=ocx.sh/c/d:u
    stub ocx 'exit 75'
    hook on-create
    assert_success
    [ "$(warnings)" = 1 ]
    assert_output --partial 'config setup'
    assert_output --partial '75'
    assert_output --partial 'network'
}

@test "on-create exit 64 names the missing source" {
    write_env OCXF_MANAGED_CONFIG=ocx.sh/c/d:u
    stub ocx 'exit 64'
    hook on-create
    assert_success
    assert_output --partial 'source'
}

@test "pull exit codes: one warning, the code, the fix, exit 0" {
    for pair in 78:'ocx lock' 65:'ocx lock' 75:network 69:network 79:network 74:ownership 64:pullGroups 1:'see the ocx output'; do
        code=${pair%%:*}
        fix=${pair#*:}
        stub ocx "exit $code"
        hook update-content
        assert_success
        [ "$(warnings)" = 1 ]
        assert_output --partial "exit code $code"
        assert_output --partial "$fix"
        assert_output --partial 'pull'
    done
}

@test "no ocx.toml anywhere: ocx is not even run, nothing is printed" {
    stub ocx 'echo "error: no ocx.toml found" >&2; exit 64'
    hook update-content "$SANDBOX/none"
    assert_success
    assert_output ""
    refute_stub_called "ocx pull"
}

@test "exit 64 with OCX_PROJECT set but no ocx.toml above is silent" {
    stub ocx 'exit 64'
    OCX_PROJECT=/elsewhere hook update-content "$SANDBOX/none"
    assert_success
    assert_output ""
    assert_stub_called "ocx pull"
}

@test "exit 64 with ocx.toml in a parent directory warns" {
    stub ocx 'exit 64'
    hook update-content "$WS/sub"
    assert_success
    [ "$(warnings)" = 1 ]
}

@test "root on a workspace owned by someone else does not pull" {
    as_uid 0
    hook update-content
    assert_success
    [ "$(warnings)" = 1 ]
    assert_output --partial 'owned by another user'
    refute_stub_called "ocx pull"
}

@test "ownership falls back to ls when stat fails" {
    as_uid 0
    stub stat 'exit 1'
    hook update-content
    assert_success
    assert_output --partial 'owned by another user'
    refute_stub_called "ocx pull"
}

@test "root without any project does nothing" {
    as_uid 0
    hook update-content "$SANDBOX/none"
    assert_success
    assert_output ""
}

@test "non-root pulls even when the workspace is owned by another uid" {
    stub stat 'echo 0'
    hook update-content
    assert_stub_called "ocx pull"
}

@test "an unwritable workspace is fine" {
    chmod 555 "$WS"
    hook update-content
    chmod 755 "$WS"
    assert_success
    assert_stub_called "ocx pull"
}

@test "OCX_HOME and the CA variable reach ocx" {
    write_env OCXF_OCX_HOME="/h/o m" OCXF_CA_ENV=1 OCXF_CA_BUNDLE=/etc/ca.pem
    # shellcheck disable=SC2016 # stub body is expanded when the stub runs
    stub ocx 'printf "%s|%s\n" "$OCX_HOME" "$OCX_EXTRA_CA_CERTS" >"$SANDBOX/seen"'
    hook update-content
    assert_success
    run cat "$SANDBOX/seen"
    assert_output "/h/o m|/etc/ca.pem"
}

@test "CA variable is not exported when the config carries the bundle" {
    write_env OCXF_CA_BUNDLE=/etc/ca.pem
    # shellcheck disable=SC2016 # stub body is expanded when the stub runs
    stub ocx 'printf "[%s]\n" "${OCX_EXTRA_CA_CERTS-}" >"$SANDBOX/seen"'
    hook update-content
    run cat "$SANDBOX/seen"
    assert_output "[]"
}

@test "running twice gives the same result" {
    hook update-content
    hook update-content
    assert_success
    assert_output ""
}

# stat_stub_owner <uid> <path-glob>: stat reports uid for paths matching the glob, 0 for the rest.
stat_stub_owner() {
    stub stat "case \"\$*\" in $2) echo $1 ;; *) echo 0 ;; esac"
}

@test "S2 root with OCX_PROJECT naming a foreign directory does not pull, with no toml above cwd" {
    as_uid 0
    OCX_PROJECT=$WS hook update-content "$SANDBOX/none"
    assert_success
    [ "$(warnings)" = 1 ]
    assert_output --partial 'not pulling'
    refute_stub_called "ocx pull"
}

@test "S2 root with OCX_PROJECT naming a foreign project file does not pull" {
    as_uid 0
    OCX_PROJECT=$WS/ocx.toml hook update-content "$SANDBOX/none"
    assert_output --partial 'not pulling'
    refute_stub_called "ocx pull"
}

@test "S2 root skips a project whose ocx.lock or .ocx belongs to another user" {
    as_uid 0
    : >"$WS/ocx.lock"
    stat_stub_owner 1000 '*ocx.lock*'
    hook update-content
    assert_output --partial 'not pulling'
    refute_stub_called "ocx pull"
    rm "$WS/ocx.lock"
    mkdir "$WS/.ocx"
    stat_stub_owner 1000 '*/.ocx'
    OCX_PROJECT=$WS hook update-content "$SANDBOX/none"
    assert_output --partial 'not pulling'
    refute_stub_called "ocx pull"
}

@test "S2 root pulls when the project directory is root-owned and holds no foreign lock or store" {
    as_uid 0
    OCX_PROJECT=/ hook update-content "$SANDBOX/none"
    assert_stub_called "ocx pull"
}

@test "S10 exit 74 with ocxHome set names the directory, not file ownership" {
    write_env OCXF_OCX_HOME=/no/such/home
    stub ocx 'exit 74'
    hook update-content
    assert_success
    [ "$(warnings)" = 1 ]
    assert_output --partial 'ocxHome'
    assert_output --partial '/no/such/home'
    assert_output --partial 'writable'
    refute_output --partial 'ownership'
}
