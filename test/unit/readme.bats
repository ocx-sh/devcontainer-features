# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    R="$SANDBOX/repo"
    mkdir -p "$R/scripts" "$R/src/ocx"
    cp "$REPO_ROOT/scripts/readme.sh" "$R/scripts/"
    # The CLI stub writes README.md into <-p dir>/ocx, as generate-docs does.
    # shellcheck disable=SC2016 # stub body, expanded when the stub runs
    stub devcontainer 'while [ $# -gt 0 ]; do [ "$1" = -p ] && d=$2; shift; done
printf "generated\n" >"$d/ocx/README.md"'
    README="$R/scripts/readme.sh"
}

@test "regenerate writes src/ocx/README.md" {
    run_tool "$README"
    assert_success
    [ "$(cat "$R/src/ocx/README.md")" = generated ]
}

@test "check passes when the committed README is current" {
    printf 'generated\n' >"$R/src/ocx/README.md"
    run_tool "$README" --check
    assert_success
}

@test "check fails on a stale README and does not touch it" {
    printf 'old\n' >"$R/src/ocx/README.md"
    run_tool "$README" --check
    assert_failure 1
    assert_output --partial "stale"
    [ "$(cat "$R/src/ocx/README.md")" = old ]
}

@test "check fails when the README is missing" {
    run_tool "$README" --check
    assert_failure 1
}

@test "an unknown argument is a usage error" {
    run_tool "$README" --nope
    assert_failure 2
}
