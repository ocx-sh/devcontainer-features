# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

ASSETS="$REPO_ROOT/scripts/release/verify-assets.sh"
BASE_URL="https://github.com/ocx-sh/ocx/releases/download"
OLD="$OCXF_DIST_FIXTURE/dist.json"

setup() {
    ocxf_setup
    NEW="$SANDBOX/new.json"
    mkdir -p "$SANDBOX/assets"
    # gh stub: answers `gh api .../releases/tags/<tag> --jq '.assets[] | select(.name == "<file>") | .digest'`
    # from $SANDBOX/assets/<file>; no such file means the release has no such asset.
    # shellcheck disable=SC2016 # the stub body is expanded when the stub runs
    stub gh 'f=$(printf "%s" "$*" | sed -n '"'"'s/.*select(.name == "\([^"]*\)").*/\1/p'"'"')
[ -f "$SANDBOX/assets/$f" ] && cat "$SANDBOX/assets/$f"
exit 0'
    export SANDBOX
}

# release_0_6_9: NEW is the vendored manifest plus a 9.9.9 copy of every 9.9.8 row (sha256 aaaa...).
release_0_6_9() {
    jq '.latest.version = "9.9.9" | .releases = ([.releases[] | select(.version == "9.9.8") | .version = "9.9.9" | .tag = "v9.9.9" | .url = ("'"$BASE_URL"'/v9.9.9/" + .filename) | .sha256 = ("a" * 64)] + .releases)' "$OLD" >"$NEW"
    jq -r '.releases[] | select(.version == "9.9.9") | "echo sha256:" + .sha256 + " > '"$SANDBOX"'/assets/" + .filename' "$NEW" | sh
}

@test "matching digests pass and every new row is asked once" {
    release_0_6_9
    run_tool "$ASSETS" "$OLD" "$NEW"
    assert_success
    assert_stub_called 'gh api repos/ocx-sh/ocx/releases/tags/v9.9.9 --jq .assets[] | select(.name == "ocx-x86_64-unknown-linux-musl.tar.gz") | .digest'
    refute_stub_called 'gh api repos/ocx-sh/ocx/releases/tags/v9.9.8 --jq .assets[] | select(.name == "ocx-aarch64-apple-darwin.tar.gz") | .digest'
}

@test "a new row whose sha256 differs from the GitHub asset digest stops with exit 5" {
    release_0_6_9
    echo "sha256:$(printf 'b%.0s' $(seq 64))" >"$SANDBOX/assets/ocx-x86_64-apple-darwin.tar.gz"
    run_tool "$ASSETS" "$OLD" "$NEW"
    assert_failure 5
    assert_output --partial "9.9.9 x86_64-apple-darwin"
}

@test "a missing asset stops with exit 5" {
    release_0_6_9
    rm "$SANDBOX/assets/ocx-aarch64-unknown-linux-gnu.tar.gz"
    run_tool "$ASSETS" "$OLD" "$NEW"
    assert_failure 5
    assert_output --partial "9.9.9 aarch64-unknown-linux-gnu"
    assert_output --partial "no digest"
}

@test "an unchanged manifest still checks the four Linux rows of the pin" {
    jq -r '.releases[] | select(.version == "9.9.8") | "echo sha256:" + .sha256 + " > '"$SANDBOX"'/assets/" + .filename' "$OLD" | sh
    run_tool "$ASSETS" "$OLD" "$OLD"
    assert_success
    run grep -c 'unknown-linux' "$STUB_LOG"
    assert_output 4
    run grep -c . "$STUB_LOG"
    assert_output 4
}

@test "an unchanged manifest whose Linux asset digest differs stops with exit 5" {
    jq -r '.releases[] | select(.version == "9.9.8") | "echo sha256:" + .sha256 + " > '"$SANDBOX"'/assets/" + .filename' "$OLD" | sh
    echo "sha256:$(printf 'c%.0s' $(seq 64))" >"$SANDBOX/assets/ocx-x86_64-unknown-linux-musl.tar.gz"
    run_tool "$ASSETS" "$OLD" "$OLD"
    assert_failure 5
    assert_output --partial "9.9.8 x86_64-unknown-linux-musl"
}

@test "a missing gh exits 2" {
    restrict_path jq
    rm -f "$STUB_DIR/gh"
    run_tool "$ASSETS" "$OLD" "$OLD"
    assert_failure 2
}
