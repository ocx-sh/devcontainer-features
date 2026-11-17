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
    cp "$REPO_ROOT/scripts/update-dist.sh" "$REPO_ROOT/scripts/dist-canonical.jq" "$R/scripts/"
    cp "$OCXF_SRC_DIR/dist.json" "$OCXF_SRC_DIR/dist.json.sha256" "$R/src/ocx/"
    cp "$OCXF_SRC_DIR/dist.json" "$OCXF_SRC_DIR/dist.json.sha256" "$UP/"
    UPD="$R/scripts/update-dist.sh"
}

# seal: write the sidecar matching $UP/dist.json.
seal() { (cd "$UP" && sha256sum dist.json >dist.json.sha256); }

# publish <jq filter>: write the filtered vendored manifest as the upstream one, in the canonical layout,
# with a matching sidecar.
publish() {
    jq "$1" "$OCXF_SRC_DIR/dist.json" | jq -j -f "$REPO_ROOT/scripts/dist-canonical.jq" >"$UP/dist.json"
    seal
}

# hostile <sed expr>: upstream is the vendored manifest text edited by sed, sidecar matching.
hostile() {
    sed "$1" "$OCXF_SRC_DIR/dist.json" >"$UP/dist.json"
    seal
}

MUSL_URL="$BASE_URL/v0.6.8/ocx-x86_64-unknown-linux-musl.tar.gz"

# jq filter adding stable version $1 with every target the vendored newest version has.
newver() {
    printf '.latest.version="%s" | .releases = ([.releases[] | select(.version=="0.6.8") | .version="%s" | .tag="v%s" | .url=("%s/v%s/" + .filename) | .sha256=("a"+("0"*63))] + .releases)' "$1" "$1" "$1" "$BASE_URL" "$1"
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
    : >"$SANDBOX/out"
    GITHUB_OUTPUT="$SANDBOX/out" run_tool "$UPD" --from "$UP"
    assert_success
    assert_output "updated 0.6.8 -> 0.6.8"
    grep -Fx 'pin_changed=false' "$SANDBOX/out"
    grep -Fx 'changed=true' "$SANDBOX/out"
}

@test "GITHUB_OUTPUT carries changed, versions, pin_changed and digest" {
    publish "$(newver 0.6.9)"
    : >"$SANDBOX/out"
    GITHUB_OUTPUT="$SANDBOX/out" run_tool "$UPD" --from "$UP"
    assert_success
    grep -Fx 'changed=true' "$SANDBOX/out"
    grep -Fx 'old_version=0.6.8' "$SANDBOX/out"
    grep -Fx 'new_version=0.6.9' "$SANDBOX/out"
    grep -Fx 'pin_changed=true' "$SANDBOX/out"
    grep -Fx "digest=$(cut -d' ' -f1 "$UP/dist.json.sha256")" "$SANDBOX/out"
}

@test "GITHUB_OUTPUT on unchanged says changed=false" {
    : >"$SANDBOX/out"
    GITHUB_OUTPUT="$SANDBOX/out" run_tool "$UPD" --from "$UP"
    assert_success
    grep -Fx 'changed=false' "$SANDBOX/out"
    grep -Fx 'new_version=0.6.8' "$SANDBOX/out"
    grep -Fx 'pin_changed=false' "$SANDBOX/out"
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

@test "--force bypasses the policy guards and writes" {
    publish '.releases |= map(select(.target != "aarch64-apple-darwin"))'
    run_tool "$UPD" --force --from "$UP"
    assert_success
    assert_output "updated 0.6.8 -> 0.6.8"
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
    # shellcheck disable=SC2016 # the stub body is expanded when the stub runs
    stub curl 'while [ $# -gt 0 ]; do case "$1" in -o) o=$2; shift;; esac; shift; done
case "$o" in *.sha256) cp "$UPSTREAM/dist.json.sha256" "$o";; *) cp "$UPSTREAM/dist.json" "$o";; esac'
    UPSTREAM="$UP" OCXF_DIST_BASE="https://example.test" run_tool "$UPD"
    assert_success
    assert_output "unchanged 0.6.8"
    grep -F 'https://example.test/dist.json.sha256' "$STUB_LOG"
}

# hostile_refused <sed expr> <expected text> [update-dist options]: exit 5 and nothing written.
hostile_refused() {
    hostile "$1"
    before=$(sums)
    run_tool "$UPD" ${3:+"$3"} --from "$UP"
    assert_failure 5
    assert_output --partial "$2"
    [ "$(sums)" = "$before" ]
}

@test "guard: an escaped duplicate url key is refused" {
    hostile_refused 's|"url":"'"$MUSL_URL"'"|"url":"https://evil.example/o.tar.gz","ur\\u006c":"'"$MUSL_URL"'"|' "backslash"
}

@test "guard: an escaped duplicate sha256 key is refused" {
    hostile_refused 's|"sha256":"96ddbd85[0-9a-f]*"|"sha256":"'"$(printf '0%.0s' $(seq 64))"'","sh\\u0061256":"96ddbd85be99542fcc3f73023103b8c0fcabe8d041a4f7e8abac697eba57d40f"|' "backslash"
}

@test "guard: a duplicate key without escapes is refused" {
    hostile_refused 's|"url":"'"$MUSL_URL"'"|"url":"https://evil.example/o.tar.gz","url":"'"$MUSL_URL"'"|' "duplicate key"
}

@test "guard: a reordered row is refused" {
    hostile_refused 's|\("sha256":"[0-9a-f]*"\),\("url":"[^"]*"\)}|\2,\1}|' "canonical"
}

@test "guard: rows before latest are refused" {
    hostile_refused '3d;s|^  \]$|  ],\n  "latest": {"version":"0.6.8","channel":"stable"}|' "canonical"
}

@test "--force does not skip the format guards" {
    hostile_refused 's|\("sha256":"[0-9a-f]*"\),\("url":"[^"]*"\)}|\2,\1}|' "canonical" --force
}

@test "guard: two parsers agree" {
    for f in "$OCXF_SRC_DIR/dist.json" "$SANDBOX/fixture.json"; do
        [ -f "$f" ] || jq -j -f "$REPO_ROOT/scripts/dist-canonical.jq" <(jq "$(newver 0.6.9)" "$OCXF_SRC_DIR/dist.json") >"$f"
        # the installer's own resolver, row by row, against jq
        # .tar.xz rows are refused by resolve_release before any download, so only .tar.gz rows resolve
        jq -r '.releases[] | select(.filename | endswith(".tar.gz")) | [.version, .target, .url, .sha256] | @tsv' "$f" >"$SANDBOX/jq.tsv"
        run sh -c '
            export __OCXF_TESTING_SOURCE_ONLY=1
            OCXF_SRC_DIR=$1; . "$1/install.sh"
            OCXF_MANIFEST=$2; OCXF_MIRROR_URL=
            err() { echo "ERR $1"; exit 1; }
            while IFS="	" read -r v t u s; do
                OCXF_TARGET=$t; OCXF_VERSION_REQUEST=$v
                ( resolve_release; printf "%s\t%s\t%s\t%s\n" "$OCXF_ROW_VERSION" "$t" "$OCXF_ROW_URL" "$OCXF_ROW_SHA" )
            done <"$3"' sh "$OCXF_SRC_DIR" "$f" "$SANDBOX/jq.tsv"
        assert_success
        [ "$output" = "$(cat "$SANDBOX/jq.tsv")" ]
    done
}

@test "guard: sha256 with a trailing newline" {
    guard nl "$(newver 0.6.9) | (.releases[0].sha256) += \"\\n\"" "backslash"
}

@test "guard: version with a trailing newline" {
    guard vnl "$(newver 0.6.9) | .latest.version += \"\\n\"" "backslash"
}

@test "guard: linux row that is not tar.gz" {
    guard xz "$(newver 0.6.9) | (.releases[] | select(.version == \"0.6.9\" and .target == \"x86_64-unknown-linux-musl\")) |= (.filename = \"ocx.tar.xz\" | .url = \"$BASE_URL/v0.6.9/ocx.tar.xz\")" "x86_64-unknown-linux-musl"
}

@test "guard: url that does not match tag and filename" {
    guard urlm "$(newver 0.6.9) | (.releases[0].url) = \"$BASE_URL/v0.6.9/other.tar.gz\"" "does not match"
}

@test "guard: a newest stable row that is not the latest version" {
    guard first '.releases = ([.releases[0] | .version = "0.5.0" | .tag = "v0.5.0" | .url = ("'"$BASE_URL"'/v0.5.0/" + .filename)] + .releases)' "first stable row"
}
