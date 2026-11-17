# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

# The release bumps src/ocx/dist.json and then runs this suite on that tree, so no test may hard-code the
# ocx version the vendored manifest pins. Test data uses the frozen fixture in test/unit/fixtures/dist (9.9.x).

@test "no unit test hard-codes the ocx version the vendored manifest pins" {
    pin=$(jq -r .latest.version "$OCXF_SRC_DIR/dist.json")
    [ -n "$pin" ]
    run grep -rnF --exclude-dir=fixtures -e "$pin" "$BATS_TEST_DIRNAME"
    [ -z "$output" ] || {
        printf 'test/unit hard-codes the vendored pin %s; use the fixture (OCXF_DIST_FIXTURE) or derive it with jq:\n%s\n' "$pin" "$output" >&2
        return 1
    }
}

@test "the vendored manifest matches its sidecar" {
    (cd "$OCXF_SRC_DIR" && sha256sum -c dist.json.sha256)
}

@test "the frozen fixture is canonical and matches its sidecar" {
    run jq -j -f "$REPO_ROOT/scripts/dist-canonical.jq" "$OCXF_DIST_FIXTURE/dist.json"
    [ "$output" = "$(cat "$OCXF_DIST_FIXTURE/dist.json")" ]
    (cd "$OCXF_DIST_FIXTURE" && sha256sum -c dist.json.sha256)
}
