# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/check-installer-parity.sh" "$R/scripts/"
    cp "$OCXF_SRC_DIR/installer-parity.json" "$OCXF_SRC_DIR/devcontainer-feature.json" "$R/src/ocx/"
    CHK="$R/scripts/check-installer-parity.sh"
    TABLE="$R/src/ocx/installer-parity.json"
    MANIFEST="$R/src/ocx/devcontainer-feature.json"
    # An installer-like source built from the recorded variable list, with the noise the extractor must ignore.
    SRC="$SANDBOX/install.sh"
    {
        echo '# OCX_INSTALL_* knobs; OCX_INSTALL_ prefix; __OCX_TESTING_HATCH is internal'
        # shellcheck disable=SC2016 # literal installer text, not expanded
        echo 'x="${__OCX_TESTING_INSTALL_BINARY:-}"'
        while read -r n; do echo "v=\"\${$n:-}\""; done <"$REPO_ROOT/test/unit/fixtures/installer-vars.txt"
    } >"$SRC"
}

@test "the recorded variable list matches the table" {
    run_tool "$CHK" --from "$SRC"
    assert_success
}

@test "the real table has an entry per recorded variable" {
    jq -r '.variables[].name' "$OCXF_SRC_DIR/installer-parity.json" | sort >"$SANDBOX/t"
    sort "$REPO_ROOT/test/unit/fixtures/installer-vars.txt" | diff - "$SANDBOX/t"
}

@test "a variable added upstream fails and is named" {
    # shellcheck disable=SC2016 # literal installer text, not expanded
    echo 'x="${OCX_NEW_KNOB:-}"' >>"$SRC"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "OCX_NEW_KNOB"
}

@test "a variable removed upstream fails and is named" {
    grep -v OCX_INSTALL_FORCE "$SRC" >"$SANDBOX/s2"
    run_tool "$CHK" --from "$SANDBOX/s2"
    assert_failure 1
    assert_output --partial "OCX_INSTALL_FORCE"
}

@test "an exposed entry naming a missing option fails" {
    jq '(.variables[] | select(.name=="OCX_HOME") | .option) = "nope"' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "OCX_HOME"
}

@test "an exposed entry without an option fails" {
    jq 'del(.variables[] | select(.name=="OCX_HOME") | .option)' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "OCX_HOME"
}

@test "a manifest option missing from the table fails" {
    jq '.options.extra = {"type":"string","default":""}' "$MANIFEST" >"$SANDBOX/t" && mv "$SANDBOX/t" "$MANIFEST"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "extra"
}

@test "an unknown status fails" {
    jq '(.variables[0].status) = "maybe"' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "status"
}

@test "an empty note fails" {
    jq '(.variables[0].note) = ""' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "note"
}

@test "a note over 25 words fails" {
    jq '(.featureOnly[0].note) = ("word " * 26)' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "25 words"
}

@test "a featureOnly option that does not exist fails" {
    jq '.featureOnly += [{"option":"ghost","note":"Nothing."}]' "$TABLE" >"$SANDBOX/t" && mv "$SANDBOX/t" "$TABLE"
    run_tool "$CHK" --from "$SRC"
    assert_failure 1
    assert_output --partial "ghost"
}

@test "live fetch uses HTTPS curl to the raw installer and a failure exits 3" {
    stub curl 'exit 22'
    run_tool "$CHK"
    assert_failure 3
    grep -F 'https://raw.githubusercontent.com/ocx-sh/www-setup/main/src/install.sh' "$STUB_LOG"
}

@test "live fetch compares the downloaded source" {
    # shellcheck disable=SC2016 # the stub body is expanded when the stub runs
    stub curl 'while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift;; esac; shift; done
cp "$SRC_FILE" "$o"'
    SRC_FILE="$SRC" run_tool "$CHK"
    assert_success
}

@test "missing jq exits 2 and a missing --from file exits 2" {
    run_tool "$CHK" --from "$SANDBOX/nope"
    assert_failure 2
    restrict_path
    rm -f "$BATS_TEST_TMPDIR/minbin/jq"
    run_tool "$CHK" --from "$SRC"
    assert_failure 2
}
