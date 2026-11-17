# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/bump-feature-version.sh" "$R/scripts/"
    cp "$OCXF_SRC_DIR/devcontainer-feature.json" "$R/src/ocx/"
    BUMP="$R/scripts/bump-feature-version.sh"
    JSON="$R/src/ocx/devcontainer-feature.json"
}

# set_version <v>: rewrite the top-level version in the sandbox copy.
set_version() {
    sed "0,/^  \"version\": \".*\",/s//  \"version\": \"$1\",/" "$OCXF_SRC_DIR/devcontainer-feature.json" >"$JSON"
}

@test "default bump is patch" {
    set_version 1.2.3
    run_tool "$BUMP"
    assert_success
    assert_output "1.2.3 -> 1.2.4"
    [ "$(jq -r .version "$JSON")" = 1.2.4 ]
}

@test "minor resets patch" {
    set_version 1.2.3
    run_tool "$BUMP" minor
    assert_output "1.2.3 -> 1.3.0"
}

@test "major resets minor and patch" {
    set_version 1.2.3
    run_tool "$BUMP" major
    assert_output "1.2.3 -> 2.0.0"
}

@test "the diff is exactly one line" {
    set_version 1.2.3
    cp "$JSON" "$SANDBOX/before.json"
    run_tool "$BUMP" minor
    assert_success
    run diff "$SANDBOX/before.json" "$JSON"
    [ "$(printf '%s\n' "$output" | grep -c '^[<>]')" -eq 2 ]
    # the rest of the file, including option defaults named version, is untouched
    [ "$(jq -c '.options' "$SANDBOX/before.json")" = "$(jq -c '.options' "$JSON")" ]
}

@test "GITHUB_OUTPUT gets old_version and new_version" {
    set_version 1.2.3
    export GITHUB_OUTPUT="$SANDBOX/out"
    : >"$GITHUB_OUTPUT"
    run_tool "$BUMP" major
    assert_success
    grep -Fx 'old_version=1.2.3' "$GITHUB_OUTPUT"
    grep -Fx 'new_version=2.0.0' "$GITHUB_OUTPUT"
}

@test "a malformed current version exits 2 and changes nothing" {
    set_version 1.2
    cp "$JSON" "$SANDBOX/before.json"
    run_tool "$BUMP"
    assert_failure 2
    cmp "$SANDBOX/before.json" "$JSON"
}

@test "a pre-release suffixed version is malformed" {
    set_version 1.2.3-rc.1
    run_tool "$BUMP"
    assert_failure 2
}

@test "an unknown level exits 2" {
    set_version 1.2.3
    run_tool "$BUMP" huge
    assert_failure 2
}
