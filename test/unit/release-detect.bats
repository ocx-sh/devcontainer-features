# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts/release" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/release/detect.sh" "$R/scripts/release/"
    A=$(printf '%064d' 0 | tr 0 a)
    B=$(printf '%064d' 0 | tr 0 b)
    printf '%s  dist.json\n' "$A" >"$R/src/ocx/dist.json.sha256"
    export GITHUB_OUTPUT="$SANDBOX/out" GITHUB_STEP_SUMMARY="$SANDBOX/summary"
    : >"$GITHUB_OUTPUT"
    unset PUBLISH_CURRENT PAYLOAD_VERSION PAYLOAD_SHA256 PAYLOAD_URL
    DETECT="$R/scripts/release/detect.sh"
}

# remote <digest>: curl stub that serves the upstream sidecar.
remote() {
    stub curl "printf '%s  dist.json\\n' $1"
}

@test "unchanged manifest ends the run on the fast path" {
    remote "$A"
    run_tool "$DETECT"
    assert_success
    run cat "$GITHUB_OUTPUT"
    assert_line "changed=false"
    assert_line "run=false"
    run cat "$GITHUB_STEP_SUMMARY"
    assert_output --partial "nothing to do"
}

@test "changed manifest asks for a release run" {
    remote "$B"
    run_tool "$DETECT"
    assert_success
    run cat "$GITHUB_OUTPUT"
    assert_line "changed=true"
    assert_line "run=true"
    assert_line "remote_sha=$B"
}

@test "publish_current runs even when unchanged" {
    remote "$A"
    PUBLISH_CURRENT=true run_tool "$DETECT"
    assert_success
    run cat "$GITHUB_OUTPUT"
    assert_line "changed=false"
    assert_line "run=true"
}

@test "a download failure is a failed run, not a pass" {
    stub curl 'exit 22'
    run_tool "$DETECT"
    assert_failure 3
    assert_output --partial "cannot download"
}

@test "the download retries inside curl" {
    remote "$A"
    run_tool "$DETECT"
    assert_stub_called "curl -fsS --retry 5 --retry-delay 3 --retry-all-errors --max-time 30 https://setup.ocx.sh/dist.json.sha256"
}

@test "a garbled sidecar is refused" {
    stub curl 'echo "<html>oops</html>"'
    run_tool "$DETECT"
    assert_failure 2
}

@test "a malformed payload sha256 is rejected before any download" {
    remote "$A"
    PAYLOAD_SHA256="not-hex; rm -rf /" run_tool "$DETECT"
    assert_failure 2
    assert_output --partial "payload sha256"
    run cat "$STUB_LOG"
    assert_output ""
}

@test "a short payload sha256 is rejected" {
    remote "$A"
    PAYLOAD_SHA256="abc123" run_tool "$DETECT"
    assert_failure 2
}

@test "a malformed payload version is rejected" {
    remote "$A"
    PAYLOAD_VERSION='1.2.3;id' run_tool "$DETECT"
    assert_failure 2
    assert_output --partial "payload version"
}

@test "a non-HTTPS payload url is rejected" {
    remote "$A"
    PAYLOAD_URL="http://evil.example/x" run_tool "$DETECT"
    assert_failure 2
}

@test "a well-formed payload is only logged, the sidecar decides" {
    remote "$A"
    PAYLOAD_VERSION=9.9.9 PAYLOAD_SHA256="$B" PAYLOAD_URL=https://setup.ocx.sh/dist.json run_tool "$DETECT"
    assert_success
    assert_output --partial "woken by dist-updated for ocx 9.9.9"
    run cat "$GITHUB_OUTPUT"
    assert_line "changed=false"
}
