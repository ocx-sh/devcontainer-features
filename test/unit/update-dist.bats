# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

UPD="$REPO_ROOT/scripts/update-dist.sh"
BASE_URL="https://github.com/ocx-sh/ocx/releases/download"

# A throwaway repo copy: scripts/ and src/ocx/{dist.json,dist.json.sha256}; $UP is the upstream dir.
mkrepo() {
    R="$SANDBOX/repo"
    UP="$SANDBOX/up"
    mkdir -p "$R/scripts" "$R/src/ocx" "$UP"
    cp "$REPO_ROOT/scripts/update-dist.sh" "$R/scripts/"
    cp "$OCXF_SRC_DIR/dist.json" "$OCXF_SRC_DIR/dist.json.sha256" "$R/src/ocx/"
    cp "$OCXF_SRC_DIR/dist.json" "$OCXF_SRC_DIR/dist.json.sha256" "$UP/"
    UPD="$R/scripts/update-dist.sh"
}

# publish <jq filter>: write the filtered vendored manifest as the upstream one, with a matching sidecar.
publish() {
    jq "$1" "$OCXF_SRC_DIR/dist.json" >"$UP/dist.json"
    (cd "$UP" && sha256sum dist.json >dist.json.sha256)
}

# jq filter adding stable version $1 with every target the vendored newest version has.
newver() {
    printf '.latest.version="%s" | .releases = ([.releases[] | select(.version=="0.6.8") | .version="%s" | .tag="v%s" | .url=("%s/v%s/" + .filename) | .sha256=("%064d"|sub("0";"a"))] + .releases)' "$1" "$1" "$1" "$BASE_URL" "$1"
}

sums() { (cd "$R/src/ocx" && sha256sum dist.json dist.json.sha256); }

setup() {
    ocxf_setup
    mkrepo
}

@test "unchanged upstream prints unchanged and touches nothing" {
    before=$(sums)
    run_tool "$UPD" --from "$UP"
    assert_success
    assert_output "unchanged 0.6.8"
    [ "$(sums)" = "$before" ]
}

@test "new newest version is written byte-identically" {
    publish "$(newver 0.6.9)"
    run_tool "$UPD" --from "$UP"
    assert_success
    assert_output "updated 0.6.8 -> 0.6.9"
    cmp "$UP/dist.json" "$R/src/ocx/dist.json"
    cmp "$UP/dist.json.sha256" "$R/src/ocx/dist.json.sha256"
}

@test "only-older rows added updates without moving the pin" {
    publish '.releases += [(.releases[0] | .version="0.0.1" | .tag="v0.0.1" | .url=("'"$BASE_URL"'/v0.0.1/" + .filename))]'
    export GITHUB_OUTPUT="$SANDBOX/out"
    : >"$GITHUB_OUTPUT"
    run_tool "$UPD" --from "$UP"
    assert_success
    assert_output "updated 0.6.8 -> 0.6.8"
    grep -Fx 'pin_changed=false' "$GITHUB_OUTPUT"
    grep -Fx 'changed=true' "$GITHUB_OUTPUT"
}

@test "GITHUB_OUTPUT carries changed, versions, pin_changed and digest" {
    publish "$(newver 0.6.9)"
    export GITHUB_OUTPUT="$SANDBOX/out"
    : >"$GITHUB_OUTPUT"
    run_tool "$UPD" --from "$UP"
    assert_success
    grep -Fx 'changed=true' "$GITHUB_OUTPUT"
    grep -Fx 'old_version=0.6.8' "$GITHUB_OUTPUT"
    grep -Fx 'new_version=0.6.9' "$GITHUB_OUTPUT"
    grep -Fx 'pin_changed=true' "$GITHUB_OUTPUT"
    grep -Fx "digest=$(cut -d' ' -f1 "$UP/dist.json.sha256")" "$GITHUB_OUTPUT"
}

@test "GITHUB_OUTPUT on unchanged says changed=false" {
    export GITHUB_OUTPUT="$SANDBOX/out"
    : >"$GITHUB_OUTPUT"
    run_tool "$UPD" --from "$UP"
    assert_success
    grep -Fx 'changed=false' "$GITHUB_OUTPUT"
    grep -Fx 'new_version=0.6.8' "$GITHUB_OUTPUT"
    grep -Fx 'pin_changed=false' "$GITHUB_OUTPUT"
}

@test "--check exits 10 on an update and writes nothing" {
    publish "$(newver 0.6.9)"
    before=$(sums)
    run_tool "$UPD" --check --from "$UP"
    assert_failure 10
    assert_output --partial "0.6.8 -> 0.6.9"
    [ "$(sums)" = "$before" ]
}

@test "--check exits 0 when unchanged" {
    run_tool "$UPD" --check --from "$UP"
    assert_success
    assert_output "unchanged 0.6.8"
}

@test "digest mismatch exits 4 and writes nothing" {
    publish "$(newver 0.6.9)"
    printf '%064d  dist.json\n' 1 >"$UP/dist.json.sha256"
    before=$(sums)
    run_tool "$UPD" --from "$UP"
    assert_failure 4
    [ "$(sums)" = "$before" ]
}

# guard <name> <jq filter> <expected text>: the filter corrupts upstream, expect exit 5 naming the row.
guard() {
    publish "$2"
    before=$(sums)
    run_tool "$UPD" --from "$UP"
    assert_failure 5
    assert_output --partial "$3"
    [ "$(sums)" = "$before" ]
}

@test "guard: a vendored row with a changed sha256" {
    guard sha '(.releases[] | select(.target=="x86_64-unknown-linux-musl" and .version=="0.6.8") | .sha256) = ("b" * 64)' "0.6.8 x86_64-unknown-linux-musl"
}

@test "guard: a vendored row with a changed url" {
    guard url '(.releases[] | select(.target=="x86_64-unknown-linux-musl") | .url) += "x"' "0.6.8 x86_64-unknown-linux-musl"
}

@test "guard: a vendored row removed" {
    guard drop 'del(.releases[] | select(.target=="aarch64-apple-darwin"))' "0.6.8 aarch64-apple-darwin"
}

@test "guard: a url off the release host" {
    guard host "$(newver 0.6.9) | (.releases[0].url) = \"https://evil.example/ocx-sh/ocx/releases/download/v0.6.9/x.tar.gz\"" "0.6.9"
}

@test "guard: a url that is not https" {
    guard http "$(newver 0.6.9) | (.releases[0].url) |= sub(\"^https\"; \"http\")" "0.6.9"
}

@test "guard: a url with a dot segment" {
    guard dots "$(newver 0.6.9) | (.releases[0].url) = \"$BASE_URL/v0.6.9/../../x.tar.gz\"" "0.6.9"
}

@test "guard: a malformed sha256" {
    guard hex "$(newver 0.6.9) | (.releases[0].sha256) = \"ABC\"" "0.6.9"
}

@test "guard: an upper-case sha256" {
    guard upper "$(newver 0.6.9) | (.releases[0].sha256) |= ascii_upcase | (.releases[0].sha256) |= sub(\"^A\"; \"A\")" "0.6.9"
}

@test "guard: schema other than 1" {
    guard schema '.schema = 2' "schema"
}

@test "guard: a downgrade of the newest stable version" {
    guard down '.latest.version = "0.0.1"' "0.0.1"
}

@test "guard: latest is not on the stable channel" {
    guard chan "$(newver 0.7.0-rc.1) | .latest.channel = \"rc\"" "stable"
}

@test "guard: a required Linux target missing for the newest version" {
    guard tgt "$(newver 0.6.9) | del(.releases[] | select(.version==\"0.6.9\" and .target==\"aarch64-unknown-linux-gnu\"))" "aarch64-unknown-linux-gnu"
}

@test "guard: a duplicate (version,target) row" {
    guard dup '.releases += [.releases[0]]' "duplicate"
}

@test "guard: new version drops a target the old pin covers" {
    guard cover "$(newver 0.6.9) | del(.releases[] | select(.version==\"0.6.9\" and .target==\"aarch64-apple-darwin\"))" "aarch64-apple-darwin"
}

@test "guard: a filename that is not a single path segment" {
    guard seg "$(newver 0.6.9) | (.releases[0].filename) = \"../x.tar.gz\"" "0.6.9"
}

@test "--force bypasses the guards and writes" {
    publish '.latest.version = "0.0.1" | .releases |= map(select(.target != "aarch64-apple-darwin"))'
    run_tool "$UPD" --force --from "$UP"
    assert_success
    assert_output "updated 0.6.8 -> 0.0.1"
    cmp "$UP/dist.json" "$R/src/ocx/dist.json"
}

@test "--force still refuses a digest mismatch" {
    publish "$(newver 0.6.9)"
    printf '%064d  dist.json\n' 1 >"$UP/dist.json.sha256"
    run_tool "$UPD" --force --from "$UP"
    assert_failure 4
}

@test "missing jq exits 2" {
    restrict_path sha256sum
    rm -f "$BATS_TEST_TMPDIR/minbin/jq"
    run_tool "$UPD" --from "$UP"
    assert_failure 2
    assert_output --partial "jq"
}

@test "missing curl exits 2 when fetching" {
    restrict_path sha256sum jq
    run_tool "$UPD"
    assert_failure 2
    assert_output --partial "curl"
}

@test "a non-HTTPS base is refused" {
    stub curl
    OCXF_DIST_BASE="http://setup.ocx.sh" run_tool "$UPD"
    assert_failure 2
    assert_output --partial "HTTPS"
    refute_stub_called "curl"
}

@test "unknown option and a missing --from argument exit 2" {
    run_tool "$UPD" --bogus
    assert_failure 2
    run_tool "$UPD" --from
    assert_failure 2
}

@test "--from a dir without the files exits 2" {
    run_tool "$UPD" --from "$SANDBOX/nope"
    assert_failure 2
}

@test "fetch goes through curl to the base and a failure exits 3" {
    stub curl 'exit 22'
    OCXF_DIST_BASE="https://example.test" run_tool "$UPD"
    assert_failure 3
}

@test "fetch downloads manifest and sidecar from the base" {
    stub curl 'while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift;; esac; shift; done
case "$o" in *.sha256) cp "$UPSTREAM/dist.json.sha256" "$o";; *) cp "$UPSTREAM/dist.json" "$o";; esac'
    UPSTREAM="$UP" OCXF_DIST_BASE="https://example.test" run_tool "$UPD"
    assert_success
    assert_output "unchanged 0.6.8"
    grep -F 'https://example.test/dist.json.sha256' "$STUB_LOG"
}
