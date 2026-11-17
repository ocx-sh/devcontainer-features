# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

MARK='# Written by the ocx Dev Container Feature (id: ocx). Edits are overwritten on rebuild.'

setup() {
    ocxf_setup
    export OCXF_VERSION=9.9.8 OCXF_BIN=/usr/local/bin/ocx OCXF_INSTALL_DIR=/usr/local/bin
    export OCXF_CA_BUNDLE='' OCXF_MANAGED_CONFIG='' OCXF_OCX_HOME='' OCXF_NO_UPDATE_CHECK=0
    export OCXF_CONSENT_PATHS='' OCXF_PULL=1 OCXF_PULL_GROUPS='' OCXF_SHELL_ACTIVATION=1
    mkroot /etc
}

# configure_main under the interpreter under test, set -eu like install.sh.
cfg() {
    run_sh "$REPO_ROOT/test/unit/configure-driver.sh"
}

R() { printf '%s%s' "$__OCXF_TESTING_ROOT" "$1"; }

tree_sum() {
    (cd "$__OCXF_TESTING_ROOT" && find . \( -type f -o -type l \) | sort | while read -r f; do
        # shellcheck disable=SC2012 # ls -ld prints the mode of one known path
        printf '%s %s %s\n' "$(cksum <"$f")" "$f" "$(ls -ld "$f" | cut -c1-10)"
    done)
}

@test "default run writes config, profile, hook and env, exit 0" {
    cfg
    assert_success
    [ -f "$(R /etc/ocx/config.toml)" ]
    [ -f "$(R /etc/profile.d/ocx.sh)" ]
    [ -x "$(R /usr/local/share/ocx-feature/hook.sh)" ]
    [ -f "$(R /usr/local/share/ocx-feature/feature.env)" ]
}

@test "config with no options is just the marker" {
    cfg
    assert_success
    run cat "$(R /etc/ocx/config.toml)"
    assert_output "$MARK"
}

@test "no update check writes manual for both keys" {
    OCXF_NO_UPDATE_CHECK=1 cfg
    run cat "$(R /etc/ocx/config.toml)"
    assert_output "$MARK

[update]
self = \"manual\"
toolchain = \"manual\""
}

@test "consent paths become a TOML array, empty entries dropped" {
    OCXF_CONSENT_PATHS='/workspaces/*::/a b/"q"\z:' cfg
    assert_success
    run cat "$(R /etc/ocx/config.toml)"
    assert_output "$MARK

[shell.consent]
paths = [\"/workspaces/*\", \"/a b/\\\"q\\\"\\\\z\"]"
}

@test "managed config source is written with required = false" {
    OCXF_MANAGED_CONFIG='ocx.sh/corp/cfg:user' cfg
    run cat "$(R /etc/ocx/config.toml)"
    assert_output "$MARK

[managed]
source = \"ocx.sh/corp/cfg:user\"
required = false"
}

@test "CA bundle goes into the config as a top-level key before the tables" {
    root_file /etc/ssl/ca.pem 'pem'
    OCXF_CA_BUNDLE=/etc/ssl/ca.pem OCXF_NO_UPDATE_CHECK=1 cfg
    assert_success
    run sed -n '3p' "$(R /etc/ocx/config.toml)"
    assert_output 'extra_ca_certs = "/etc/ssl/ca.pem"'
    run grep -n '^\[update\]' "$(R /etc/ocx/config.toml)"
    assert_output --partial '5:[update]'
    # config carries the CA: nothing to export from profile or hook env
    run grep -c 'OCX_EXTRA_CA_CERTS' "$(R /etc/profile.d/ocx.sh)"
    assert_output 0
    run grep -F "OCXF_CA_ENV='0'" "$(R /usr/local/share/ocx-feature/feature.env)"
    assert_success
}

@test "CA bundle over 32 KiB or missing is not written and warns" {
    mkroot /etc/ssl
    head -c 40000 /dev/zero | tr '\0' 'a' >"$(R /etc/ssl/big.pem)"
    OCXF_CA_BUNDLE=/etc/ssl/big.pem cfg
    assert_success
    assert_output --partial 'warning'
    assert_output --partial '32768'
    run grep -c extra_ca_certs "$(R /etc/ocx/config.toml)"
    assert_output 0
    OCXF_CA_BUNDLE=/etc/ssl/none.pem cfg
    assert_output --partial 'warning'
    run grep -c extra_ca_certs "$(R /etc/ocx/config.toml)"
    assert_output 0
}

@test "foreign config is untouched, one warning names the unapplied settings, CA falls back to env" {
    root_file /etc/ocx/config.toml 'mine = 1
'
    root_file /etc/ssl/ca.pem 'pem'
    OCXF_NO_UPDATE_CHECK=1 OCXF_CONSENT_PATHS="/w/*" OCXF_MANAGED_CONFIG=a/b:c OCXF_CA_BUNDLE=/etc/ssl/ca.pem cfg
    assert_success
    run cat "$(R /etc/ocx/config.toml)"
    assert_output 'mine = 1'
    OCXF_NO_UPDATE_CHECK=1 OCXF_CONSENT_PATHS="/w/*" OCXF_MANAGED_CONFIG=a/b:c OCXF_CA_BUNDLE=/etc/ssl/ca.pem cfg
    [ "$(printf '%s\n' "$output" | grep -c warning)" = 1 ]
    assert_output --partial 'update check'
    assert_output --partial 'consent paths'
    assert_output --partial 'managed config'
    assert_output --partial 'CA bundle'
    run grep -F 'OCX_EXTRA_CA_CERTS' "$(R /etc/profile.d/ocx.sh)"
    assert_success
    run grep -F "OCXF_CA_ENV='1'" "$(R /usr/local/share/ocx-feature/feature.env)"
    assert_success
}

@test "foreign config with nothing to apply stays silent" {
    root_file /etc/ocx/config.toml 'mine = 1
'
    cfg
    assert_success
    assert_output ""
}

@test "config carrying the marker is rewritten" {
    root_file /etc/ocx/config.toml "$MARK
[update]
self = \"auto\"
"
    OCXF_NO_UPDATE_CHECK=1 cfg
    assert_success
    assert_output ""
    run grep -c auto "$(R /etc/ocx/config.toml)"
    assert_output 0
}

@test "second run changes nothing, byte for byte" {
    printf 'a\nb' >"$(R /etc/bash.bashrc)"
    OCXF_NO_UPDATE_CHECK=1 OCXF_CONSENT_PATHS="/w/*" OCXF_MANAGED_CONFIG=a/b:c OCXF_OCX_HOME=/opt/h cfg
    assert_success
    one=$(tree_sum)
    OCXF_NO_UPDATE_CHECK=1 OCXF_CONSENT_PATHS="/w/*" OCXF_MANAGED_CONFIG=a/b:c OCXF_OCX_HOME=/opt/h cfg
    assert_success
    [ "$one" = "$(tree_sum)" ]
}

@test "sourcing configure.sh twice is harmless" {
    OCXF_TWICE=1 cfg
    assert_success
}

# rc wiring

BEGIN='# >>> ocx devcontainer feature >>>'
END='# <<< ocx devcontainer feature <<<'
LINE='[ -r /etc/profile.d/ocx.sh ] && . /etc/profile.d/ocx.sh'

@test "each existing rc file gets the block, missing ones are not created" {
    for f in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc; do
        root_file "$f" "# rc
"
        cfg
        assert_success
        run cat "$(R "$f")"
        assert_output "# rc
$BEGIN
$LINE
$END"
        rm -rf "$__OCXF_TESTING_ROOT"
        mkdir -p "$__OCXF_TESTING_ROOT/etc"
    done
    cfg
    [ ! -e "$(R /etc/bash.bashrc)" ] && [ ! -e "$(R /etc/zsh/zshrc)" ] && [ ! -e "$(R /etc/bashrc)" ]
}

@test "wiring is written even with shell activation off" {
    root_file /etc/bash.bashrc ''
    OCXF_SHELL_ACTIVATION=0 cfg
    run grep -c -F "$LINE" "$(R /etc/bash.bashrc)"
    assert_output 1
}

@test "file without trailing newline gets one before the block" {
    printf 'no newline' >"$(R /etc/bash.bashrc)"
    cfg
    run cat "$(R /etc/bash.bashrc)"
    assert_output "no newline
$BEGIN
$LINE
$END"
}

@test "existing block is replaced in place, surroundings kept" {
    # shellcheck disable=SC2016 # literal hostile text, must not expand
    printf 'top \\ $x `y`\n%s\nold\n%s\nbottom' "$BEGIN" "$END" >"$(R /etc/bash.bashrc)"
    cfg
    run cat "$(R /etc/bash.bashrc)"
    assert_output "top \\ \$x \`y\`
$BEGIN
$LINE
$END
bottom"
    cfg
    run grep -c -F "$BEGIN" "$(R /etc/bash.bashrc)"
    assert_output 1
}

@test "CRLF file: block not duplicated" {
    printf 'a\r\n%s\r\nold\r\n%s\r\nz\r\n' "$BEGIN" "$END" >"$(R /etc/bash.bashrc)"
    cfg
    cfg
    run grep -c -F "$BEGIN" "$(R /etc/bash.bashrc)"
    assert_output 1
    run grep -c -F 'old' "$(R /etc/bash.bashrc)"
    assert_output 0
}

@test "unterminated block is left alone and a fresh block is appended" {
    printf 'a\n%s\nb\n' "$BEGIN" >"$(R /etc/bash.bashrc)"
    cfg
    run cat "$(R /etc/bash.bashrc)"
    assert_output "a
$BEGIN
b
$BEGIN
$LINE
$END"
}

@test "symlinked rc: the link stays, the target is edited, mode kept" {
    mkroot /etc/real
    printf 'x\n' >"$(R /etc/real/bashrc)"
    chmod 640 "$(R /etc/real/bashrc)"
    ln -s real/bashrc "$(R /etc/bash.bashrc)"
    cfg
    [ -L "$(R /etc/bash.bashrc)" ]
    run grep -c -F "$LINE" "$(R /etc/real/bashrc)"
    assert_output 1
    run ls -l "$(R /etc/real/bashrc)"
    assert_output --regexp '^-rw-r-----'
}

@test "dangling rc symlink is skipped" {
    ln -s nowhere "$(R /etc/bash.bashrc)"
    cfg
    assert_success
    [ ! -e "$(R /etc/nowhere)" ]
}

# run-time files

@test "hook.sh is copied executable, feature.env is 0644" {
    cfg
    run ls -l "$(R /usr/local/share/ocx-feature/hook.sh)" "$(R /usr/local/share/ocx-feature/feature.env)"
    assert_line --regexp '^-rwxr-xr-x.*hook.sh'
    assert_line --regexp '^-rw-r--r--.*feature.env'
}

@test "missing hook.sh in the source dir is an error" {
    mkdir -p "$SANDBOX/empty"
    cp "$OCXF_SRC_DIR/configure.sh" "$OCXF_SRC_DIR/lib.sh" "$SANDBOX/empty/"
    OCXF_SRC_DIR="$SANDBOX/empty" cfg
    assert_failure
    assert_output --partial 'hook.sh'
}

@test "feature.env round-trips hostile values" {
    hostile="a b 'q' \"d\" \$HOME \`id\` ; & | \\ x
line2"
    export OCXF_OCX_HOME="/h/$hostile" OCXF_MANAGED_CONFIG="m$hostile" OCXF_PULL_GROUPS="g$hostile"
    export OCXF_BIN="/b/$hostile"
    cfg
    assert_success
    # shellcheck disable=SC2016 # the snippet expands in the shell under test
    run_snippet '. "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/feature.env"
printf "%s" "$OCXF_BIN|$OCXF_OCX_HOME|$OCXF_MANAGED_CONFIG|$OCXF_PULL_GROUPS|$OCXF_VERSION|$OCXF_PULL"'
    assert_success
    assert_output "/b/$hostile|/h/$hostile|m$hostile|g$hostile|9.9.8|1"
}

@test "feature.env holds only KEY='value' lines for the listed keys" {
    cfg
    run grep -v -E "^OCXF_(BIN|VERSION|PULL|PULL_GROUPS|MANAGED_CONFIG|OCX_HOME|CA_BUNDLE|CA_ENV)='" "$(R /usr/local/share/ocx-feature/feature.env)"
    assert_failure
}

@test "nothing is written below any home directory" {
    mkroot /home/dev /root
    export HOME="$__OCXF_TESTING_ROOT/home/dev"
    cfg
    run find "$(R /home)" "$(R /root)" -type f
    assert_output ""
}
