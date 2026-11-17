# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts/release"
    cp "$REPO_ROOT/scripts/release/report.sh" "$R/scripts/release/"
    export REPO=ocx-sh/devcontainer-features RUN_URL=https://github.com/ocx-sh/devcontainer-features/actions/runs/7 GH_TOKEN=tok
    export OCX_VERSION=0.7.0
    FAIL='{"detect":{"result":"success"},"prepare":{"result":"success"},"test":{"result":"failure"},"publish":{"result":"skipped"}}'
    GREEN='{"detect":{"result":"success"},"prepare":{"result":"success"},"test":{"result":"success"},"publish":{"result":"success"}}'
    REPORT="$R/scripts/release/report.sh"
}

# open_issue <n|"">: gh stub; "gh issue list" answers with the open issue number.
open_issue() {
    stub gh "case \"\$*\" in *'issue list'*) echo '$1' ;; esac"
}

@test "a failed run with no open issue creates the label and one issue" {
    open_issue ""
    NEEDS_JSON="$FAIL" run_tool "$REPORT"
    assert_success
    run grep -c 'issue create' "$STUB_LOG"
    assert_output 1
    assert_stub_called "gh label create release-blocked --repo ocx-sh/devcontainer-features --color B60205 --description the unattended release is stuck"
    run grep 'issue create' "$STUB_LOG"
    assert_output --partial "--title Release blocked: ocx 0.7.0"
    assert_output --partial "--label release-blocked"
    run cat "$STUB_LOG"
    assert_output --partial "failed in: test"
    assert_output --partial "Run: $RUN_URL"
}

@test "a failed run with an open issue comments instead of opening another" {
    open_issue 12
    NEEDS_JSON="$FAIL" run_tool "$REPORT"
    assert_success
    run grep 'issue create' "$STUB_LOG"
    assert_failure
    run grep 'issue comment 12' "$STUB_LOG"
    assert_success
}

@test "a published release closes the open issue with the run link" {
    open_issue 12
    NEEDS_JSON="$GREEN" run_tool "$REPORT"
    assert_success
    run grep 'issue close 12' "$STUB_LOG"
    assert_output --partial "--comment Released: $RUN_URL"
}

@test "a green run with no open issue does nothing" {
    open_issue ""
    NEEDS_JSON="$GREEN" run_tool "$REPORT"
    assert_success
    run grep -e 'issue close' -e 'issue create' -e 'issue comment' "$STUB_LOG"
    assert_failure
}

@test "a cancelled run neither reports nor closes" {
    open_issue 12
    NEEDS_JSON='{"detect":{"result":"success"},"publish":{"result":"cancelled"}}' run_tool "$REPORT"
    assert_success
    run grep -e 'issue close' -e 'issue create' -e 'issue comment' "$STUB_LOG"
    assert_failure
}

@test "without a known ocx version the title asks upstream, else says unknown" {
    open_issue ""
    stub curl 'echo "{\"latest\":{\"version\":\"0.8.0\"}}"'
    OCX_VERSION='' NEEDS_JSON="$FAIL" run_tool "$REPORT"
    run grep 'issue create' "$STUB_LOG"
    assert_output --partial "Release blocked: ocx 0.8.0"
    : >"$STUB_LOG"
    stub curl 'exit 22'
    OCX_VERSION='' NEEDS_JSON="$FAIL" run_tool "$REPORT"
    run grep 'issue create' "$STUB_LOG"
    assert_output --partial "Release blocked: ocx unknown"
}
