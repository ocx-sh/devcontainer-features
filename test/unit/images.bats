# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# The base-image matrix plumbing: test/images.txt, the IMAGE enum of test:image, run-image.sh.
load helpers

setup() {
    ocxf_setup
    cd "$REPO_ROOT" || return 1
}

aliases() {
    awk '$1 !~ /^#/ && NF { print $1 }' test/images.txt
}

@test "the IMAGE enum of test:image lists exactly the aliases of test/images.txt, in order" {
    enum=$(sed -n 's/^ *enum: \[\(.*\)\]$/\1/p' taskfiles/images.taskfile.yml | tr -d ' ' | tr ',' '\n')
    [ -n "$enum" ]
    [ "$enum" = "$(aliases)" ]
}

@test "every alias is [a-z0-9-]+ and unique, every line has a reference and an optional known platform" {
    run aliases
    refute_output --regexp '[^a-z0-9
-]'
    [ "$(aliases | sort | uniq -d)" = "" ]
    bad=$(awk '$1 !~ /^#/ && NF && (NF < 2 || NF > 3 || (NF == 3 && $3 != "amd64" && $3 != "arm64"))' test/images.txt)
    [ -z "$bad" ]
}

@test "every locally built reference has a Dockerfile" {
    awk '$1 !~ /^#/ && $2 ~ /^ocx-test\// { print $2 }' test/images.txt | while read -r ref; do
        name=${ref#ocx-test/}
        [ -f "test/images/${name%%:*}/Dockerfile" ] || exit 1
    done
}

@test "run-image.sh without an alias or with an unknown one exits 2" {
    run_tool test/images/run-image.sh
    assert_failure 2
    run_tool test/images/run-image.sh nope
    assert_failure 2
    assert_output --partial "unknown image alias"
}

@test "run-image.sh skips an amd64-only image on arm64 with a visible line and exits 0" {
    __OCXF_TESTING_ARCH=aarch64 run_tool test/images/run-image.sh arch
    assert_success
    assert_output --partial "arch: skipped: not published for arm64"
}

@test "junit turns ok and not ok lines into test cases and a failing CLI run into a failure" {
    mkdir -p "$SANDBOX/out/junit"
    printf 'noise\nok - fine\nnot ok - broken <&>\n    # why\nok - after\n' >"$SANDBOX/log"
    : >"$SANDBOX/extra"
    run_snippet "__OCXF_RUN_IMAGE_SOURCE_ONLY=1 . test/images/run-image.sh; OUT=$SANDBOX/out; junit demo $SANDBOX/log 1 $SANDBOX/extra"
    assert_success
    xml=$SANDBOX/out/junit/image-demo.xml
    grep -q 'tests="4" failures="2"' "$xml"
    grep -q 'name="broken &lt;&amp;&gt;"' "$xml"
    grep -q 'why' "$xml"
    grep -q 'exit 1' "$xml"
}
