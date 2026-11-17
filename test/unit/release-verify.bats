# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts/release" "$R/src/ocx" "$SANDBOX/layer"
    cp "$REPO_ROOT/scripts/release/verify.sh" "$R/scripts/release/"
    SHA=$(printf '%064d' 0 | tr 0 a)
    printf '%s  dist.json\n' "$SHA" >"$R/src/ocx/dist.json.sha256"
    # The published layer is a tar holding ./dist.json.sha256 (what devcontainer features publish pushes).
    cp "$R/src/ocx/dist.json.sha256" "$SANDBOX/layer/dist.json.sha256"
    tar -C "$SANDBOX/layer" -cf "$SANDBOX/layer.tar" ./dist.json.sha256
    printf '{"layers":[{"digest":"sha256:%s"}]}\n' "$(printf '%064d' 0 | tr 0 c)" >"$SANDBOX/manifest.json"
    export FEATURE_VERSION=1.0.1 OCX_VERSION=0.7.0 REPO=ocx-sh/devcontainer-features ACTOR=octo GH_TOKEN=tok
    export GITHUB_STEP_SUMMARY="$SANDBOX/summary"
    stub devcontainer
    # curl: token, manifest and blob requests by URL; -o names the output file.
    # shellcheck disable=SC2016 # stub body, expanded when the stub runs
    stub curl 'out=; prev=; for a; do [ "$prev" = -o ] && out=$a; prev=$a; done
case "$*" in
*token*) echo "{\"token\":\"t\"}" ;;
*manifests*) cp "'"$SANDBOX"'/manifest.json" "$out" ;;
*blobs*) cp "'"$SANDBOX"'/layer.tar" "$out" ;;
esac'
    VERIFY="$R/scripts/release/verify.sh"
}

@test "a matching published tarball verifies and writes the summary" {
    run_tool "$VERIFY"
    assert_success
    assert_output --partial "verified ghcr.io/ocx-sh/devcontainer-features/ocx:1.0.1"
    run cat "$GITHUB_STEP_SUMMARY"
    assert_output --partial "feature version: 1.0.1"
    assert_output --partial "ocx version: 0.7.0"
    assert_output --partial "manifest digest: \`sha256:"
}

@test "a published sidecar that differs from the tree fails" {
    printf '%s  dist.json\n' "$(printf '%064d' 0 | tr 0 d)" >"$SANDBOX/layer/dist.json.sha256"
    tar -C "$SANDBOX/layer" -cf "$SANDBOX/layer.tar" ./dist.json.sha256
    run_tool "$VERIFY"
    assert_failure 1
    assert_output --partial "differs from the tree's"
}

@test "a version that does not resolve fails before any registry call" {
    stub devcontainer 'exit 1'
    run_tool "$VERIFY"
    assert_failure 1
    assert_output --partial "does not resolve"
    refute_stub_called "curl"
}

@test "a registry network failure is exit 3" {
    stub curl 'exit 7'
    run_tool "$VERIFY"
    assert_failure 3
}

# tree_and_layer <file> <tree content> <layer content>: a file in src/ocx and in the published layer.
tree_and_layer() {
    printf '%s' "$2" >"$R/src/ocx/$1"
    printf '%s' "$3" >"$SANDBOX/layer/$1"
    tar -C "$SANDBOX/layer" -cf "$SANDBOX/layer.tar" .
}

@test "a published layer with the same sidecar but different content fails" {
    tree_and_layer install.sh 'echo safe' 'echo evil'
    run_tool "$VERIFY"
    assert_failure 1
    assert_output --partial "install.sh"
    assert_output --partial "must be bumped"
}

@test "a published layer with a file the tree lacks fails" {
    printf 'x' >"$SANDBOX/layer/extra.sh"
    tar -C "$SANDBOX/layer" -cf "$SANDBOX/layer.tar" .
    run_tool "$VERIFY"
    assert_failure 1
    assert_output --partial "extra.sh"
}

@test "identical content passes" {
    tree_and_layer install.sh 'echo same' 'echo same'
    run_tool "$VERIFY"
    assert_success
    assert_output --partial "verified"
}
