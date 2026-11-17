# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

load helpers

setup() {
    ocxf_setup
    M="$OCXF_SRC_DIR/devcontainer-feature.json"
}

# jq <filter>: query the manifest, raw output.
q() {
    jq -r "$1" "$M"
}

@test "manifest is valid JSON" {
    run jq -e . "$M"
    assert_success
}

@test "manifest identity fields" {
    [ "$(q .id)" = ocx ]
    # Every release bumps the version, so only its form is fixed.
    [[ "$(q .version)" =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ ]]
    [ "$(q .documentationURL)" = "https://ocx.sh/integrations/devcontainer/" ]
    [ "$(q '.customizations.vscode.extensions[0]')" = "ocx-sh.ocx" ]
    [ "$(q '.installsAfter[0]')" = "ghcr.io/devcontainers/features/common-utils" ]
}

@test "hooks point at the installed hook script" {
    [ "$(q .onCreateCommand)" = "/usr/local/share/ocx-feature/hook.sh on-create" ]
    [ "$(q .updateContentCommand)" = "/usr/local/share/ocx-feature/hook.sh update-content" ]
}

@test "every option id is camelCase" {
    run jq -r '.options | keys[] | select(test("^[a-z][a-zA-Z0-9]*$") | not)' "$M"
    assert_success
    assert_output ""
}

@test "no option is named groups" {
    run jq -e '.options | has("groups")' "$M"
    assert_failure
}

@test "every option has type, default and description" {
    run jq -r '.options | to_entries[] | select(.value | (has("type") and has("default") and has("description")) | not) | .key' "$M"
    assert_success
    assert_output ""
}

@test "boolean options have boolean defaults" {
    run jq -r '.options | to_entries[] | select(.value.type == "boolean" and (.value.default | type) != "boolean") | .key' "$M"
    assert_output ""
}

@test "string options have string defaults" {
    run jq -r '.options | to_entries[] | select(.value.type == "string" and (.value.default | type) != "string") | .key' "$M"
    assert_output ""
}

@test "only string options carry enum or proposals" {
    run jq -r '.options | to_entries[] | select(.value.type != "string" and (.value | has("enum") or has("proposals"))) | .key' "$M"
    assert_output ""
}

@test "option types are string or boolean" {
    run jq -r '.options | to_entries[] | select(.value.type | IN("string", "boolean") | not) | .key' "$M"
    assert_output ""
}

@test "option defaults sit inside enum" {
    run jq -r '.options | to_entries[] | . as $o | select($o.value.enum and ($o.value.enum | index($o.value.default) | not)) | $o.key' "$M"
    assert_output ""
}

@test "env names are unique" {
    dups=$(manifest_option_env_names | sort | uniq -d)
    [ -z "$dups" ]
}

@test "no env name collides with a special shell variable" {
    for v in GROUPS UID EUID PPID PWD OLDPWD HOME PATH IFS RANDOM SECONDS LINENO HOSTNAME OPTIND OPTARG OPTERR SHELL USER SHLVL BASH ENV PS1 PS2 PS4 TMPDIR LANG; do
        names=$(manifest_option_env_names)
        run grep -x -F "$v" <<<"$names"
        assert_failure
    done
}

@test "manifest_option_env_names upper-cases camelCase" {
    run manifest_option_env_names
    assert_line "DISTURL"
    assert_line "PULLGROUPS"
    assert_line "VERSION"
}
