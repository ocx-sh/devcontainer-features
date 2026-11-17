# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts/release" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/release/publish.sh" "$R/scripts/release/"
    # verify.sh is tested on its own; here it only records that it ran.
    printf '#!/bin/sh\necho verify >>"%s"\n' "$STUB_LOG" >"$R/scripts/release/verify.sh"
    export FEATURE_VERSION=1.0.1 OCX_VERSION=0.7.0 DEFAULT_BRANCH=main REPO=ocx-sh/devcontainer-features
    export ACTOR=octo GH_TOKEN=tok123 GITHUB_STEP_SUMMARY="$SANDBOX/summary"
    unset DRY_RUN
    # git: a dirty tree (diff --cached --quiet fails), no remote tag (ls-remote fails).
    stub git 'case "$*" in *"diff --cached --quiet"*) exit 1 ;; *ls-remote*) exit 2 ;; esac'
    stub docker
    stub base64 'cat'
    stub devcontainer 'case "$*" in *"info manifest"*) exit 1 ;; esac'
    PUB="$R/scripts/release/publish.sh"
}

@test "publishes in order: commit, push, tag, login, publish, verify" {
    run_tool "$PUB"
    assert_success
    run grep -n -e '^git' -e '^docker' -e '^devcontainer' -e '^verify' "$STUB_LOG"
    assert_line --index 0 --partial "git add -A -- src CHANGELOG.md site/src/content/docs"
    assert_line --index 1 --partial "git diff --cached --quiet"
    assert_line --index 2 --partial "commit -q -m chore(release): ocx 0.7.0, feature 1.0.1"
    assert_line --index 3 --partial "push origin HEAD:refs/heads/main"
    assert_line --index 4 --partial "ls-remote --exit-code --tags origin refs/tags/v1.0.1"
    assert_line --index 5 --partial "git tag v1.0.1"
    assert_line --index 6 --partial "push origin refs/tags/v1.0.1"
    assert_line --index 7 --partial "docker login ghcr.io -u octo --password-stdin"
    assert_line --index 8 --partial "devcontainer features info manifest ghcr.io/ocx-sh/devcontainer-features/ocx:1.0.1"
    assert_line --index 9 --partial "devcontainer features publish --registry ghcr.io --namespace ocx-sh/devcontainer-features ./src"
    assert_line --index 10 --partial "verify"
}

@test "the commit author is the actions bot" {
    run_tool "$PUB"
    run grep "commit" "$STUB_LOG"
    assert_output --partial "user.name=github-actions[bot]"
    assert_output --partial "41898282+github-actions[bot]@users.noreply.github.com"
}

@test "the token is not in the log as a bare argument and no push is forced" {
    run_tool "$PUB"
    run grep -e '--force' -e ' -f ' -e '+HEAD' "$STUB_LOG"
    assert_failure
}

@test "a dry run commits, pushes, tags and publishes nothing" {
    DRY_RUN=true run_tool "$PUB"
    assert_success
    assert_output --partial "dry run"
    run grep -e '^git' -e '^docker' -e 'features publish' -e '^verify' "$STUB_LOG"
    assert_failure
    run grep 'features package' "$STUB_LOG"
    assert_success
    run cat "$GITHUB_STEP_SUMMARY"
    assert_output --partial "Dry run"
}

@test "a rejected push stops before the tag and the publish" {
    stub git 'case "$*" in *"diff --cached --quiet"*) exit 1 ;; *" push "*) exit 1 ;; esac'
    run_tool "$PUB"
    assert_failure 1
    assert_output --partial "rejected; nothing was published"
    run grep -e 'git tag' -e '^docker' -e 'features publish' "$STUB_LOG"
    assert_failure
}

@test "an already published version is a no-op for the registry" {
    stub devcontainer 'exit 0'
    run_tool "$PUB"
    assert_success
    assert_output --partial "already published"
    refute_stub_called "devcontainer features publish --registry ghcr.io --namespace ocx-sh/devcontainer-features ./src"
    assert_stub_called "verify"
}

@test "an existing tag is kept, an unchanged tree makes no commit" {
    stub git 'case "$*" in *"diff --cached --quiet"*) exit 0 ;; esac'
    run_tool "$PUB"
    assert_success
    assert_output --partial "tag v1.0.1 exists"
    run grep -e 'commit' -e 'git tag' "$STUB_LOG"
    assert_failure
}

@test "a failing publish fails the run before verify" {
    stub devcontainer 'exit 1'
    run_tool "$PUB"
    assert_failure 1
    refute_stub_called "verify"
}

@test "a malformed feature version is refused" {
    FEATURE_VERSION='1.0.1; id' run_tool "$PUB"
    assert_failure 2
    run cat "$STUB_LOG"
    assert_output ""
}
