# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    CALLS="$SANDBOX/calls"
    : >"$CALLS"
    mkdir -p "$R/scripts/release" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/release/prepare.sh" "$R/scripts/release/"
    printf '{"latest":{"version":"9.9.8"}}\n' >"$R/src/ocx/dist.json"
    printf '{\n  "id": "ocx",\n  "version": "1.0.0",\n  "options": {}\n}\n' >"$R/src/ocx/devcontainer-feature.json"
    printf '# Changelog\n\nIntro.\n\n## 1.0.0 - 2026-11-17\n\n- ocx 9.9.8\n' >"$R/CHANGELOG.md"
    # Fakes for the scripts prepare.sh orchestrates: log the call, honour an exit code from the env.
    fake update-dist.sh FAKE_UPDATE_RC <<'EOT'
printf '{"latest":{"version":"0.7.0"}}\n' >"$(dirname "$0")/../src/ocx/dist.json"
EOT
    fake bump-feature-version.sh FAKE_BUMP_RC <<'EOT'
f=$(dirname "$0")/../src/ocx/devcontainer-feature.json
sed 's/"version": "1.0.0"/"version": "1.0.1"/' "$f" >"$f.new" && mv "$f.new" "$f"
echo "1.0.0 -> 1.0.1"
EOT
    mkdir -p "$R/scripts/release"
    # shellcheck disable=SC2016 # the generated script expands these when it runs
    {
        printf '#!/bin/sh\necho "verify-assets $(jq -r .latest.version "$1") $(jq -r .latest.version "$2")" >>"%s"\n' "$CALLS"
        printf 'exit "${FAKE_ASSETS_RC:-0}"\n'
    } >"$R/scripts/release/verify-assets.sh"
    fake readme.sh FAKE_README_RC </dev/null
    fake check-installer-parity.sh FAKE_PARITY_RC </dev/null
    stub git
    export GITHUB_OUTPUT="$SANDBOX/out" OUT_DIR="$SANDBOX/tree"
    : >"$GITHUB_OUTPUT"
    unset CHANGED GITHUB_STEP_SUMMARY
    PREP="$R/scripts/release/prepare.sh"
}

# fake <script> <rc var> < body: a stand-in under scripts/ that records its name in $CALLS.
fake() {
    {
        printf '#!/bin/sh\necho %s >>"%s"\n' "$1" "$CALLS"
        cat
        printf "exit \"\${%s:-0}\"\n" "$2"
    } >"$R/scripts/$1"
}

@test "changed path runs the steps in order and prepares a bumped tree" {
    CHANGED=true run_tool "$PREP"
    assert_success
    run cat "$CALLS"
    assert_output "update-dist.sh
verify-assets 9.9.8 0.7.0
bump-feature-version.sh
readme.sh
check-installer-parity.sh"
    run cat "$GITHUB_OUTPUT"
    assert_line "feature_version=1.0.1"
    assert_line "ocx_version=0.7.0"
    assert_line "old_ocx_version=9.9.8"
    run cat "$R/CHANGELOG.md"
    assert_output --partial "## 1.0.1 - "
    assert_output --partial "- ocx 0.7.0 (was 9.9.8)"
    # newest first, above the seeded entry
    run grep -n '^## ' "$R/CHANGELOG.md"
    assert_line --index 0 --partial "1.0.1"
    assert_line --index 1 --partial "1.0.0"
    assert_stub_called "git add -A -- src CHANGELOG.md site/src/content/docs"
    assert_stub_called "git diff --cached --binary HEAD"
    [ -f "$OUT_DIR/tree.patch" ]
    [ -s "$OUT_DIR/release.txt" ]
}

@test "unchanged tree runs no helper and keeps an existing changelog entry" {
    CHANGED=false run_tool "$PREP"
    assert_success
    run cat "$CALLS"
    assert_output ""
    run cat "$GITHUB_OUTPUT"
    assert_line "feature_version=1.0.0"
    assert_line "ocx_version=9.9.8"
    [ "$(grep -c '^## ' "$R/CHANGELOG.md")" -eq 1 ]
}

@test "a missing changelog entry is added for a feature-only release" {
    sed -i 's/^## 1.0.0/## 0.9.0/' "$R/CHANGELOG.md"
    run_tool "$PREP"
    assert_success
    run grep -c '^## 1.0.0 - ' "$R/CHANGELOG.md"
    assert_output 1
}

@test "a guard violation from update-dist stops the run with its exit code" {
    FAKE_UPDATE_RC=5 CHANGED=true run_tool "$PREP"
    assert_failure 5
    run cat "$CALLS"
    assert_output "update-dist.sh"
    [ ! -f "$OUT_DIR/tree.patch" ]
}

@test "a digest mismatch from update-dist stops the run with its exit code" {
    FAKE_UPDATE_RC=4 CHANGED=true run_tool "$PREP"
    assert_failure 4
}

@test "a parity mismatch fails the run after the other steps" {
    FAKE_PARITY_RC=1 CHANGED=true run_tool "$PREP"
    assert_failure 1
    [ ! -f "$OUT_DIR/tree.patch" ]
}

@test "the docs generator runs after the changelog entry when the site has one" {
    mkdir -p "$R/site/scripts"
    : >"$R/site/scripts/generate-docs.mjs"
    stub node
    CHANGED=true run_tool "$PREP"
    assert_success
    assert_stub_called "node scripts/generate-docs.mjs"
}

@test "no docs generator, no node call" {
    stub node
    CHANGED=true run_tool "$PREP"
    assert_success
    refute_stub_called "node scripts/generate-docs.mjs"
}

@test "a GitHub asset digest mismatch stops the run before the bump" {
    FAKE_ASSETS_RC=5 CHANGED=true run_tool "$PREP"
    assert_failure 5
    run cat "$CALLS"
    assert_output "update-dist.sh
verify-assets 9.9.8 0.7.0"
    [ ! -f "$OUT_DIR/tree.patch" ]
}
