# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# shellcheck disable=SC2119,SC2120 # inst forwards its arguments but most tests call it bare
# shellcheck disable=SC2016 # stub bodies and snippets are literal code for another shell
# shellcheck disable=SC2030,SC2031 # each bats test is its own subshell by design
load helpers

INSTALL="$REPO_ROOT/src/ocx/install.sh"
V=0.6.8
# The suite must pass on any host: unpinned tests see the real machine (busybox sh runs its own uname
# applet, so the uname stub cannot override it there), hence MUSL and GNU follow the host and the
# manifest carries both architectures.
case "$(uname -m)" in
    aarch64 | arm64) HOST_ARCH=aarch64 OTHER_ARCH=x86_64 ;;
    *) HOST_ARCH=x86_64 OTHER_ARCH=aarch64 ;;
esac
export HOST_ARCH
MUSL=$HOST_ARCH-unknown-linux-musl
GNU=$HOST_ARCH-unknown-linux-gnu
OTHER=$OTHER_ARCH-unknown-linux-musl
X86=x86_64-unknown-linux-musl
ARM=aarch64-unknown-linux-musl

# --- fixtures ----------------------------------------------------------------

# fake_archive <version> <triple> <reported version> <out>: a real .tar.gz holding a fake ocx.
fake_archive() {
    _d="$SANDBOX/fx/tree/$1-$2"
    mkdir -p "$_d/ocx-$2"
    printf '#!/bin/sh\nif [ "$1" = version ]; then echo %s; else exit 1; fi\n' "$3" >"$_d/ocx-$2/ocx"
    chmod +x "$_d/ocx-$2/ocx"
    tar -czf "$4" -C "$_d" "ocx-$2"
}

# serve <url> <file>: what the curl and wget stubs answer for a URL.
serve() {
    cp "$2" "$NETDIR/$(printf %s "$1" | tr '/:' '__')"
}

# mkdist: (re)build the vendored manifest and its digest in the sandbox source dir from fx/arc.
mkdist() {
    _rows=
    for _spec in $V:$MUSL $V:$GNU $V:$OTHER 0.6.7:$MUSL; do
        _v=${_spec%%:*}
        _t=${_spec#*:}
        _a="$SANDBOX/fx/arc/$_v-$_t.tgz"
        _url="https://example.test/rel/v$_v/ocx-$_t.tar.gz"
        serve "$_url" "$_a"
        _sha=$(sha256sum "$_a" | cut -d' ' -f1)
        _row="{\"version\":\"$_v\",\"channel\":\"stable\",\"tag\":\"v$_v\",\"target\":\"$_t\",\"filename\":\"ocx-$_t.tar.gz\",\"sha256\":\"$_sha\",\"url\":\"$_url\"}"
        _rows="${_rows:+$_rows,
    }$_row"
    done
    {
        printf '{\n  "schema": 1,\n  "latest": {"version":"%s","channel":"stable"},\n  "latest_next": null,\n  "releases": [\n    %s\n  ]\n}\n' "$V" "$_rows"
    } >"$SANDBOX/src/dist.json"
    _sum=$(sha256sum "$SANDBOX/src/dist.json" | cut -d' ' -f1)
    printf '%s  dist.json\n' "$_sum" >"$SANDBOX/src/dist.json.sha256"
}

# curl stub: serves files from $NETDIR by URL, exit 22 for anything else; --help lists --tlsv1.2.
make_curl() {
    cat >"$1" <<'EOF'
#!/bin/sh
printf 'curl %s\n' "$*" >>"$STUB_LOG"
if [ "$1" = --help ]; then echo "     --tlsv1.2"; exit 0; fi
for a; do url=$a; done
prev=
for a; do [ "$prev" = -o ] && dest=$a; prev=$a; done
f="$NETDIR/$(printf %s "$url" | tr '/:' '__')"
[ -f "$f" ] || exit 22
cp "$f" "$dest"
EOF
    chmod +x "$1"
}

# no_applets: busybox sh runs its built-in uname, sleep, wget, sha256sum and so on before any PATH
# stub, so tests that stub those names run on dash when the leg is busybox. Each such test is
# listed in $OCXF_DEMOTED_LOG so run-legs.sh can report how many did not run under busybox.
no_applets() {
    case "$OCXF_TEST_SH" in
        busybox*)
            [ -z "${OCXF_DEMOTED_LOG:-}" ] || printf '%s\n' "$BATS_TEST_NAME" >>"$OCXF_DEMOTED_LOG"
            OCXF_TEST_SH=dash
            # shellcheck disable=SC2034 # read by restrict_path in helpers.bash
            OCXF_TEST_SH_BIN=dash
            ;;
    esac
}

make_wget() {
    no_applets
    cat >"$STUB_DIR/wget" <<'EOF'
#!/bin/sh
printf 'wget %s\n' "$*" >>"$STUB_LOG"
if [ "$1" = --help ]; then printf '%s\n' "$WGET_HELP"; exit 0; fi
for a; do url=$a; done
prev=
for a; do [ "$prev" = -O ] && dest=$a; prev=$a; done
[ -z "${WGET_STDERR:-}" ] || echo "$WGET_STDERR" >&2
f="$NETDIR/$(printf %s "$url" | tr '/:' '__')"
[ -f "$f" ] || exit 4
cp "$f" "$dest"
EOF
    chmod +x "$STUB_DIR/wget"
}

setup() {
    ocxf_setup
    NETDIR="$SANDBOX/net"
    mkdir -p "$NETDIR" "$SANDBOX/fx/arc" "$SANDBOX/src" "$SANDBOX/home" "$SANDBOX/tmp"
    export NETDIR
    HOME="$SANDBOX/home"
    TMPDIR="$SANDBOX/tmp"
    OCXF_RETRY_DELAY=0
    OCXF_SRC_DIR="$SANDBOX/src"
    export HOME TMPDIR OCXF_RETRY_DELAY OCXF_SRC_DIR
    cp "$REPO_ROOT/src/ocx/lib.sh" "$REPO_ROOT/src/ocx/devcontainer-feature.json" "$SANDBOX/src/"
    for _spec in $V:$MUSL $V:$GNU $V:$OTHER 0.6.7:$MUSL; do
        fake_archive "${_spec%%:*}" "${_spec#*:}" "${_spec%%:*}" "$SANDBOX/fx/arc/${_spec%%:*}-${_spec#*:}.tgz"
    done
    mkdist
    make_curl "$STUB_DIR/curl"
    stub uname 'case "$1" in -m) echo "${FAKE_ARCH:-$HOST_ARCH}" ;; -s) echo "${FAKE_OS:-Linux}" ;; *) echo Linux ;; esac'
    stub getconf 'exit 1'
    root_file /etc/ssl/certs/ca-certificates.crt x
}

inst() {
    run_sh "$INSTALL" "$@"
}

# installed_version: what the fake ocx in the root reports.
installed_version() {
    "$__OCXF_TESTING_ROOT/usr/local/bin/ocx" version
}

assert_bad_option() {
    inst
    assert_failure 2
    assert_output --partial "$1"
}

# no_pm: stubs for every package manager that log and fail the test if ever called.
pm_stubs() {
    for _p in apt-get apk dnf microdnf yum zypper pacman; do stub "$_p" 'exit 0'; done
}

# --- success and install -----------------------------------------------------

@test "defaults: installs the newest stable ocx from the bundled manifest" {
    inst
    assert_success
    assert_output --partial "installed ocx $V ($MUSL) at /usr/local/bin/ocx"
    [ "$(installed_version)" = "$V" ]
    [ -x "$__OCXF_TESTING_ROOT/usr/local/bin/ocx" ]
    [ "$(stat -c %a "$__OCXF_TESTING_ROOT/usr/local/bin/ocx")" = 755 ]
}

@test "writes the version file and the manifest digest" {
    inst
    assert_success
    d="$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature"
    [ "$(cat "$d/ocx-version")" = "$V" ]
    [ "$(cat "$d/dist-digest")" = "$(sha256sum "$SANDBOX/src/dist.json" | cut -d' ' -f1)" ]
}

@test "no download is made for the bundled manifest, only for the archive" {
    inst
    assert_success
    run grep -c 'dist.json' "$STUB_LOG"
    assert_output 0
    run grep -c "ocx-$MUSL.tar.gz\$" "$STUB_LOG"
    assert_output 1
}

@test "second run is idempotent" {
    inst
    assert_success
    first=$(cat "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/ocx-version")
    inst
    assert_success
    [ "$(cat "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/ocx-version")" = "$first" ]
    [ "$(installed_version)" = "$V" ]
    run find "$__OCXF_TESTING_ROOT/usr/local/bin" -name '.ocx*'
    assert_output ""
}

@test "temp dir is removed after the run" {
    inst
    assert_success
    [ -z "$(ls -A "$TMPDIR")" ]
}

@test "installDir is honoured and created" {
    INSTALLDIR=/opt/tools/bin inst
    assert_success
    [ -x "$__OCXF_TESTING_ROOT/opt/tools/bin/ocx" ]
    assert_output --partial "at /opt/tools/bin/ocx"
}

@test "exact version present installs that version" {
    VERSION=0.6.7 inst
    assert_success
    [ "$(installed_version)" = 0.6.7 ]
    [ "$(cat "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/ocx-version")" = 0.6.7 ]
}

@test "a leading v on the version is accepted" {
    VERSION=v0.6.7 inst
    assert_success
    [ "$(installed_version)" = 0.6.7 ]
}

@test "exact version absent exits 2 naming the version, the newest and the helping options" {
    VERSION=9.9.9 inst
    assert_failure 2
    assert_output --partial "9.9.9"
    assert_output --partial "newest available: $V"
    assert_output --partial "version: latest"
    assert_output --partial "distUrl"
}

@test "pinned and latest differ only in the manifest source: latest fetches the live manifest" {
    cp "$SANDBOX/src/dist.json" "$SANDBOX/live.json"
    serve https://setup.ocx.sh/dist.json "$SANDBOX/live.json"
    VERSION=latest inst
    assert_success
    assert_stub_called "curl --proto =https --tlsv1.2 -fsSL -o $(grep -o "[^ ]*dist.json" "$STUB_LOG" | head -1) https://setup.ocx.sh/dist.json"
    [ "$(installed_version)" = "$V" ]
}

@test "latest: live manifest unreachable exits 3" {
    VERSION=latest inst
    assert_failure 3
    assert_output --partial "setup.ocx.sh"
}

@test "distUrl plain replaces the bundled manifest" {
    cp "$SANDBOX/src/dist.json" "$SANDBOX/custom.json"
    serve https://corp.test/dist.json "$SANDBOX/custom.json"
    # the bundled one is corrupted to prove it is not read
    printf 'junk' >"$SANDBOX/src/dist.json"
    DISTURL=https://corp.test/dist.json inst
    assert_success
    [ "$(cat "$__OCXF_TESTING_ROOT/usr/local/share/ocx-feature/dist-digest")" = "$(sha256sum "$SANDBOX/custom.json" | cut -d' ' -f1)" ]
}

@test "distUrl pinned by digest: match installs" {
    sum=$(sha256sum "$SANDBOX/src/dist.json" | cut -d' ' -f1)
    serve "https://corp.test/$sum.json" "$SANDBOX/src/dist.json"
    DISTURL="https://corp.test/$sum.json" inst
    assert_success
}

@test "distUrl pinned by digest: mismatch exits 4" {
    sum=$(printf 'a%.0s' $(seq 64))
    serve "https://corp.test/$sum.json" "$SANDBOX/src/dist.json"
    DISTURL="https://corp.test/$sum.json" inst
    assert_failure 4
    assert_output --partial "checksum mismatch"
}

@test "bundled manifest tampered exits 4 and installs nothing" {
    printf ' ' >>"$SANDBOX/src/dist.json"
    inst
    assert_failure 4
    [ ! -e "$__OCXF_TESTING_ROOT/usr/local/bin/ocx" ]
}

@test "bundled manifest digest file missing exits 4" {
    rm "$SANDBOX/src/dist.json.sha256"
    inst
    assert_failure 4
}

@test "mirror rewrites the archive URL to <mirror>/<tag>/<filename>" {
    serve "https://mirror.test/base/v$V/ocx-$MUSL.tar.gz" "$SANDBOX/fx/arc/$V-$MUSL.tgz"
    MIRRORURL=https://mirror.test/base// inst
    assert_success
    assert_stub_called "curl --proto =https --tlsv1.2 -fsSL -o $(grep -o "[^ ]*\.tar\.gz " "$STUB_LOG" | head -1)https://mirror.test/base/v$V/ocx-$MUSL.tar.gz"
}

@test "caBundle is passed to curl as --cacert" {
    root_file /etc/custom-ca.pem x
    CABUNDLE=/etc/custom-ca.pem inst
    assert_success
    grep -q -- "--cacert $__OCXF_TESTING_ROOT/etc/custom-ca.pem" "$STUB_LOG"
}

@test "download failure exits 3 after three attempts" {
    rm -f "$NETDIR"/*
    inst
    assert_failure 3
    run grep -c 'tar.gz$' "$STUB_LOG"
    assert_output 3
}

@test "download retry message appears" {
    rm -f "$NETDIR"/*
    inst
    assert_output --partial "download failed (attempt 1/3)"
}

@test "retry delay doubles and sleeps when set" {
    no_applets
    rm -f "$NETDIR"/*
    stub sleep 'exit 0'
    OCXF_RETRY_DELAY=2 inst
    assert_failure 3
    assert_stub_called "sleep 2"
    assert_stub_called "sleep 4"
}

@test "checksum mismatch exits 4 and tar is never called" {
    printf 'tampered' >"$NETDIR/$(printf %s "https://example.test/rel/v$V/ocx-$MUSL.tar.gz" | tr '/:' '__')"
    stub tar 'exit 0'
    inst
    assert_failure 4
    run grep -c '^tar' "$STUB_LOG"
    assert_output 0
}

@test "unsafe archive member (path traversal) exits 5" {
    cd "$SANDBOX/fx"
    mkdir -p evil && echo x >evil/f
    tar -czf arc/$V-$MUSL.tgz --transform 's,^evil/,../,' evil/f
    mkdist
    inst
    assert_failure 5
}

@test "unsafe archive member (absolute path) exits 5" {
    cd "$SANDBOX/fx"
    echo x >abs.txt
    tar -czf arc/$V-$MUSL.tgz -P --transform "s,^,/,;s,^/$SANDBOX/fx/,/," "$SANDBOX/fx/abs.txt" 2>/dev/null || tar -czf arc/$V-$MUSL.tgz --transform 's,^,/,' abs.txt
    mkdist
    inst
    assert_failure 5
}

@test "escaping symlink in the archive exits 5" {
    cd "$SANDBOX/fx"
    mkdir -p ln && ln -s ../../etc/passwd ln/link
    tar -czf arc/$V-$MUSL.tgz ln
    mkdist
    inst
    assert_failure 5
    assert_output --partial "escaping link"
}

@test "escaping hard link in the archive exits 5" {
    cd "$SANDBOX/fx"
    mkdir -p hl && echo x >hl/a && ln hl/a hl/b
    tar -czf arc/$V-$MUSL.tgz --transform 's,hl/a,/abs/a,' hl 2>/dev/null || true
    # a hard link whose target is absolute: tar prints "link to /abs/a"
    mkdist
    inst
    assert_failure 5
}

@test "corrupt archive that passes the checksum exits 5" {
    printf 'not a tarball' >"$SANDBOX/fx/arc/$V-$MUSL.tgz"
    mkdist
    inst
    assert_failure 5
}

@test "archive without ocx-<triple>/ocx exits 5" {
    cd "$SANDBOX/fx"
    mkdir -p other && echo x >other/file
    tar -czf arc/$V-$MUSL.tgz other
    mkdist
    inst
    assert_failure 5
    assert_output --partial "does not contain"
}

@test "smoke test failure exits 7 with a libc hint and leaves no binary" {
    fake_archive $V $MUSL 9.9.9 "$SANDBOX/fx/arc/$V-$MUSL.tgz"
    mkdist
    inst
    assert_failure 7
    assert_output --partial "libc"
    [ ! -e "$__OCXF_TESTING_ROOT/usr/local/bin/ocx" ]
    [ -z "$(ls -A "$__OCXF_TESTING_ROOT/usr/local/bin" 2>/dev/null)" ]
}

@test "the smoke test runs 'ocx version'" {
    inst
    assert_success
    # the fake ocx answers only 'version', so a different command would have failed the install
    run "$__OCXF_TESTING_ROOT/usr/local/bin/ocx" --version
    assert_failure
}

# --- hand-over ---------------------------------------------------------------

@test "configure.sh is sourced and configure_main sees the OCXF variables" {
    cat >"$SANDBOX/src/configure.sh" <<'EOF'
configure_main() {
    printf 'SEEN %s|%s|%s|%s|%s|%s\n' "$OCXF_VERSION" "$OCXF_BIN" "$OCXF_TARGET" "$OCXF_NO_UPDATE_CHECK" "$OCXF_CONSENT_PATHS" "$OCXF_INSTALL_DIR" >&2
}
EOF
    inst
    assert_success
    assert_output --partial "SEEN $V|/usr/local/bin/ocx|$MUSL|1|/workspaces/*|/usr/local/bin"
}

@test "a failing configure_main fails the build" {
    printf 'configure_main() { exit 6; }\n' >"$SANDBOX/src/configure.sh"
    inst
    assert_failure 6
}

@test "no configure.sh is fine" {
    inst
    assert_success
}

# --- root and user rules -----------------------------------------------------

@test "not root without the test root exits 2" {
    stub id 'echo 1000'
    export __OCXF_TESTING_ROOT=''
    inst
    assert_failure 2
    assert_output --partial "must run as root"
}

@test "_REMOTE_USER variants never matter and nothing is written under HOME" {
    mkdir -p "$HOME/keep" "$__OCXF_TESTING_ROOT/home/ghost"
    echo x >"$HOME/keep/f"
    find "$HOME" "$__OCXF_TESTING_ROOT/home" | sort >"$SANDBOX/before"
    for u in "" 1000 root ghostuser; do
        _REMOTE_USER=$u _REMOTE_USER_HOME=/home/$u _CONTAINER_USER=$u _CONTAINER_USER_HOME=/home/$u inst
        assert_success
    done
    _REMOTE_USER=ghostuser _REMOTE_USER_HOME='' inst
    assert_success
    find "$HOME" "$__OCXF_TESTING_ROOT/home" | sort >"$SANDBOX/after"
    run diff "$SANDBOX/before" "$SANDBOX/after"
    assert_success
}

@test "the script never mentions the remote-user variables" {
    run grep -c '_REMOTE_USER\|_CONTAINER_USER' "$INSTALL"
    assert_output 0
}

# --- option parsing ----------------------------------------------------------

@test "invalid version exits 2 naming the option" {
    for v in 1.2 1.2.3.4 1..2 .1.2 1.2. abc 1.2.x ''"'"; do
        VERSION=$v assert_bad_option "option version"
    done
}

@test "invalid libc exits 2 naming the option" {
    LIBC=bsd assert_bad_option "option libc"
}

@test "http or malformed mirror and dist URLs exit 2" {
    for v in http://m.test ftp://m.test https:// "https://m .test" 'https://m.test/"x' "https://m.test/'x" 'https://m.test/`x'; do
        MIRRORURL=$v assert_bad_option "option mirrorUrl"
        DISTURL=$v assert_bad_option "option distUrl"
    done
    MIRRORURL="$(printf 'https://m.test/\001')" assert_bad_option "option mirrorUrl"
}

@test "caBundle must be an absolute readable file" {
    CABUNDLE=relative.pem assert_bad_option "option caBundle"
    CABUNDLE=/nope.pem assert_bad_option "option caBundle"
    mkroot /etc/dir
    CABUNDLE=/etc/dir assert_bad_option "option caBundle"
}

@test "managedConfig accepts OCI references and rejects other characters" {
    MANAGEDCONFIG='ghcr.io/org/cfg:1.0@sha256:abc' inst
    assert_success
    for v in 'a b' 'a;b' 'a$b' 'a"b'; do
        MANAGEDCONFIG=$v assert_bad_option "option managedConfig"
    done
}

@test "ocxHome and installDir reject unsafe values" {
    for v in rel /a/../b /a/.. '/a"b' '/a$b' '/a`b' '/a;b' '/a&b' '/a|b' '/a<b' '/a>b' '/a(b' '/a)b' '/a\b' "/a
b"; do
        OCXHOME=$v assert_bad_option "option ocxHome"
        INSTALLDIR=$v assert_bad_option "option installDir"
    done
}

@test "ocxHome absolute is accepted" {
    OCXHOME=/opt/ocx-home inst
    assert_success
}

@test "boolean options accept true-ish and false-ish spellings" {
    for v in true TRUE yes 1; do
        NOUPDATECHECK=$v PULL=$v SHELLACTIVATION=$v inst
        assert_success
    done
    for v in false FALSE no 0 ''; do
        NOUPDATECHECK=$v PULL=$v SHELLACTIVATION=$v inst
        assert_success
    done
}

@test "boolean options reject other values and name the option" {
    NOUPDATECHECK=maybe assert_bad_option "option noUpdateCheck"
    PULL=2 assert_bad_option "option pull"
    SHELLACTIVATION=on assert_bad_option "option shellActivation"
}

@test "boolean values map to 1 and 0" {
    export NOUPDATECHECK=false PULL=true SHELLACTIVATION=no
    run_snippet "__OCXF_TESTING_SOURCE_ONLY=1; . $INSTALL; parse_options; echo \$OCXF_NO_UPDATE_CHECK\$OCXF_PULL\$OCXF_SHELL_ACTIVATION"
    assert_output 010
}

@test "consentPaths: empty, multiple, star and invalid entries" {
    CONSENTPATHS='' inst
    assert_success
    CONSENTPATHS='/workspaces/*:/srv/a' inst
    assert_success
    for v in 'rel' '/a:rel' '/a::/b' '/a/../b' '/a;b' '/a$b'; do
        CONSENTPATHS=$v assert_bad_option "option consentPaths"
    done
}

@test "pullGroups: valid lists and invalid forms" {
    PULLGROUPS=dev,ci-1.x_y inst
    assert_success
    for v in 'a b' ',a' 'a,' 'a,,b' 'a;b' 'a/b'; do
        PULLGROUPS=$v assert_bad_option "option pullGroups"
    done
}

@test "S6 a managedConfig or pullGroups value starting with a dash exits 2" {
    MANAGEDCONFIG=-x.sh/a/b:1 assert_bad_option "option managedConfig"
    MANAGEDCONFIG=--managed-config assert_bad_option "option managedConfig"
    PULLGROUPS=-h assert_bad_option "option pullGroups"
    PULLGROUPS=--all assert_bad_option "option pullGroups"
}

@test "S4 control characters in a string option exit 2 naming the option" {
    esc=$(printf '\033') tab=$(printf '\t') cr=$(printf '\r') del=$(printf '\177') nl='
'
    root_file "/etc/ca${esc}.pem" x
    CABUNDLE="/etc/ca${esc}.pem" assert_bad_option "option caBundle"
    CONSENTPATHS="/srv/a${tab}b" assert_bad_option "option consentPaths"
    for c in "$esc" "$tab" "$cr" "$del" "$nl"; do
        OCXHOME="/h${c}x" assert_bad_option "option ocxHome"
        INSTALLDIR="/i${c}x" assert_bad_option "option installDir"
        CABUNDLE="/c${c}x" assert_bad_option "option caBundle"
        CONSENTPATHS="/p${c}x" assert_bad_option "option consentPaths"
        DISTURL="https://d.test/${c}x" assert_bad_option "option distUrl"
        MIRRORURL="https://m.test/${c}x" assert_bad_option "option mirrorUrl"
        MANAGEDCONFIG="a${c}b" assert_bad_option "option managedConfig"
        PULLGROUPS="a${c}b" assert_bad_option "option pullGroups"
        LIBC="musl${c}" assert_bad_option "option libc"
        VERSION="1.2.3${c}" assert_bad_option "option version"
    done
}

# --- manifest / script parity ------------------------------------------------

@test "every manifest option is read by the script and no other option is" {
    manifest_option_env_names | sort >"$SANDBOX/manifest.names"
    grep -oE '\$\{[A-Z]+:?-' "$INSTALL" | tr -d '${:-' | sort -u >"$SANDBOX/script.names"
    run diff "$SANDBOX/manifest.names" "$SANDBOX/script.names"
    assert_success
}

@test "script defaults equal the manifest defaults" {
    run_snippet '__OCXF_TESTING_SOURCE_ONLY=1; . '"$INSTALL"'; parse_options
printf "VERSION=%s\nLIBC=%s\nDISTURL=%s\nMIRRORURL=%s\nCABUNDLE=%s\nMANAGEDCONFIG=%s\nOCXHOME=%s\nINSTALLDIR=%s\nNOUPDATECHECK=%s\nCONSENTPATHS=%s\nPULL=%s\nPULLGROUPS=%s\nSHELLACTIVATION=%s\n" \
 "$OCXF_VERSION_REQUEST" "$OCXF_LIBC" "$OCXF_DIST_URL" "$OCXF_MIRROR_URL" "$OCXF_CA_BUNDLE" "$OCXF_MANAGED_CONFIG" "$OCXF_OCX_HOME" "$OCXF_INSTALL_DIR" "$OCXF_NO_UPDATE_CHECK" "$OCXF_CONSENT_PATHS" "$OCXF_PULL" "$OCXF_PULL_GROUPS" "$OCXF_SHELL_ACTIVATION"'
    assert_success
    printf '%s\n' "$output" | sort >"$SANDBOX/script.defaults"
    jq -r '.options | to_entries[] | "\(.key|ascii_upcase)=\(.value.default | if . == true then "1" elif . == false then "0" else tostring end)"' \
        "$REPO_ROOT/src/ocx/devcontainer-feature.json" | sort >"$SANDBOX/manifest.defaults"
    run diff "$SANDBOX/manifest.defaults" "$SANDBOX/script.defaults"
    assert_success
}

# --- target ------------------------------------------------------------------

@test "aarch64 and arm64 select the aarch64 archive" {
    no_applets
    for m in aarch64 arm64; do
        FAKE_ARCH=$m inst
        assert_success
        assert_output --partial "($ARM)"
    done
}

@test "x86_64 and amd64 select the x86_64 archive" {
    no_applets
    FAKE_ARCH=amd64 inst
    assert_success
    assert_output --partial "($X86)"
}

@test "unsupported architecture exits 7" {
    no_applets
    FAKE_ARCH=riscv64 inst
    assert_failure 7
    assert_output --partial "riscv64"
}

@test "non-Linux OS exits 7" {
    no_applets
    FAKE_OS=Darwin inst
    assert_failure 7
    assert_output --partial "Darwin"
}

@test "libc gnu with glibc 2.28 selects gnu" {
    stub getconf 'echo "glibc 2.28"'
    LIBC=gnu inst
    assert_success
    assert_output --partial "($GNU)"
}

@test "libc gnu with glibc 2.27 exits 7" {
    stub getconf 'echo "glibc 2.27"'
    LIBC=gnu inst
    assert_failure 7
    assert_output --partial "glibc 2.28"
}

@test "libc gnu with no glibc exits 7" {
    LIBC=gnu inst
    assert_failure 7
}

@test "libc auto picks gnu on glibc 2.41 and musl on 2.27 and when nothing is detected" {
    stub getconf 'echo "glibc 2.41"'
    LIBC=auto inst
    assert_output --partial "($GNU)"
    stub getconf 'echo "glibc 2.27"'
    LIBC=auto inst
    assert_output --partial "($MUSL)"
    stub getconf 'exit 1'
    LIBC=auto inst
    assert_output --partial "($MUSL)"
}

@test "glibc 3.0 and a garbage banner" {
    stub getconf 'echo "glibc 3.0"'
    LIBC=auto inst
    assert_output --partial "($GNU)"
    stub getconf 'echo "glibc x.y"'
    LIBC=auto inst
    assert_output --partial "($MUSL)"
}

@test "libc auto falls back to the loader banner when getconf has no answer" {
    root_file /lib64/ld-linux-x86-64.so.2 '#!/bin/sh
echo "ld.so (GNU libc) release version 2.36."'
    chmod +x "$__OCXF_TESTING_ROOT/lib64/ld-linux-x86-64.so.2"
    LIBC=auto inst
    assert_output --partial "($GNU)"
}

@test "a loader that prints no version counts as no glibc" {
    root_file /lib/ld-linux-aarch64.so.1 '#!/bin/sh
echo "usage"'
    chmod +x "$__OCXF_TESTING_ROOT/lib/ld-linux-aarch64.so.1"
    LIBC=auto inst
    assert_output --partial "($MUSL)"
}

# --- prerequisites -----------------------------------------------------------

@test "a complete image triggers no package manager call" {
    pm_stubs
    inst
    assert_success
    run grep -E '^(apt-get|apk|dnf|microdnf|yum|zypper|pacman)' "$STUB_LOG"
    assert_failure
}

# prep_missing: PATH without curl, wget, a CA bundle; the pm stub installs them.
prep_pm() {
    no_applets
    make_curl "$STUB_DIR/curl.later"
    rm -rf "$__OCXF_TESTING_ROOT/etc/ssl"
    rm -f "$STUB_DIR/curl"
    restrict_path sha256sum tar gzip
    _installer='cp "$STUB_DIR/curl.later" "$STUB_DIR/curl"; mkdir -p "$__OCXF_TESTING_ROOT/etc/ssl/certs"; echo x > "$__OCXF_TESTING_ROOT/etc/ssl/certs/ca-certificates.crt"'
}

@test "apt-get: update when lists are empty, install without recommends, lists removed" {
    prep_pm
    mkroot /var/lib/apt/lists/partial
    stub apt-get "[ \"\$1\" = install ] && { $_installer; }; [ \"\$1\" = update ] && echo x >\"\$__OCXF_TESTING_ROOT/var/lib/apt/lists/deb_x\"; exit 0"
    inst
    assert_success
    assert_stub_called "apt-get update"
    assert_stub_called "apt-get install -y --no-install-recommends curl ca-certificates"
    [ -z "$(ls -A "$__OCXF_TESTING_ROOT/var/lib/apt/lists")" ]
}

@test "apt-get: no update and lists untouched when the lists exist" {
    prep_pm
    root_file /var/lib/apt/lists/deb.debian.org_dists_InRelease x
    stub apt-get "[ \"\$1\" = install ] && { $_installer; }; exit 0"
    inst
    assert_success
    refute_stub_called "apt-get update"
    [ -f "$__OCXF_TESTING_ROOT/var/lib/apt/lists/deb.debian.org_dists_InRelease" ]
}

@test "apt-get: a failed install is retried once after an update" {
    prep_pm
    root_file /var/lib/apt/lists/a_b x
    stub apt-get "if [ \"\$1\" = install ]; then if [ -e \"\$SANDBOX/tried\" ]; then $_installer; exit 0; fi; : >\"\$SANDBOX/tried\"; exit 100; fi; exit 0"
    inst
    assert_success
    assert_stub_called "apt-get update"
    run grep -c '^apt-get install' "$STUB_LOG"
    assert_output 2
}

@test "apt-get: still failing after the retry exits 2 naming what is missing" {
    prep_pm
    root_file /var/lib/apt/lists/a_b x
    stub apt-get '[ "$1" = install ] && exit 100; exit 0'
    inst
    assert_failure 2
    assert_output --partial "curl-or-wget"
    assert_output --partial "ca-bundle"
    assert_output --partial "caBundle option"
}

@test "other package managers get their exact install call" {
    for spec in "apk|add --no-cache curl ca-certificates" \
        "dnf|install -y curl ca-certificates" \
        "microdnf|install -y curl ca-certificates" \
        "yum|install -y curl ca-certificates" \
        "zypper|--non-interactive install curl ca-certificates" \
        "pacman|-Syu --noconfirm --needed curl ca-certificates"; do
        pm=${spec%%|*}
        : >"$STUB_LOG"
        prep_pm
        stub "$pm" "$_installer; exit 0"
        inst
        assert_success
        assert_stub_called "$pm ${spec#*|}"
        rm -f "$STUB_DIR/$pm" "$STUB_DIR/curl"
    done
}

@test "a package manager failing twice is retried exactly once and then exits 2" {
    prep_pm
    stub apk 'exit 1'
    inst
    assert_failure 2
    run grep -c '^apk' "$STUB_LOG"
    assert_output 2
}

@test "no package manager and a missing tool exits 2 naming it" {
    prep_pm
    inst
    assert_failure 2
    assert_output --partial "curl-or-wget"
    assert_output --partial "no supported package manager"
}

@test "no package manager and no CA bundle names the CA bundle and the caBundle option" {
    prep_pm
    inst
    assert_failure 2
    assert_output --partial "ca-bundle"
    assert_output --partial "caBundle option"
}

@test "missing tar and gzip are installed by name" {
    no_applets
    make_curl "$STUB_DIR/curl"
    restrict_path sha256sum
    stub apk 'exit 0'
    inst
    assert_failure 2
    assert_stub_called "apk add --no-cache tar gzip"
}

@test "missing sha256 tool and mktemp are installed as coreutils" {
    no_applets
    restrict_path tar gzip
    rm -f "$BATS_TEST_TMPDIR/minbin/mktemp"
    stub apk 'exit 0'
    inst
    assert_failure 2
    assert_stub_called "apk add --no-cache coreutils"
}

@test "gzip is a capability: tar that gunzips by itself is enough" {
    restrict_path sha256sum
    stub tar 'if [ "$1" = -czf ]; then echo x >"$2"; exit 0; fi; exec /bin/false'
    pm_stubs
    inst
    run grep -E '^(apt-get|apk)' "$STUB_LOG"
    assert_failure
}

@test "an empty CA bundle path set via caBundle needs no ca-certificates package" {
    rm -rf "$__OCXF_TESTING_ROOT/etc/ssl"
    root_file /etc/mine.pem x
    pm_stubs
    CABUNDLE=/etc/mine.pem inst
    assert_success
    run grep -E '^apt-get' "$STUB_LOG"
    assert_failure
}

@test "each CA bundle location counts" {
    pm_stubs
    for p in /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        rm -rf "${__OCXF_TESTING_ROOT:?}/etc"
        root_file "$p" x
        inst
        assert_success
    done
    run grep -E '^apt-get' "$STUB_LOG"
    assert_failure
}

# --- downloaders and hash tools ----------------------------------------------

@test "wget (GNU) is used when curl is absent and gets its flags" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='  --https-only
  --secure-protocol=PR
  --ca-certificate=FILE'
    restrict_path sha256sum tar gzip
    root_file /etc/mine.pem x
    CABUNDLE=/etc/mine.pem inst
    assert_success
    grep -q -- "-q -O .* --https-only --secure-protocol=TLSv1_2 --ca-certificate=$__OCXF_TESTING_ROOT/etc/mine.pem https://" "$STUB_LOG"
}

@test "wget (GNU) without a CA option and without optional flags" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='usage'
    restrict_path sha256sum tar gzip
    inst
    assert_success
    grep -q -- "wget -q -O [^ ]* https://" "$STUB_LOG"
}

@test "busybox wget warns, and a bundled manifest still installs" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='BusyBox v1.37 multi-call binary.'
    restrict_path sha256sum tar gzip
    inst
    assert_success
    assert_output --partial "BusyBox wget"
}

@test "busybox wget with a CA bundle option it cannot take exits 2" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='BusyBox v1.37 multi-call binary.'
    restrict_path sha256sum tar gzip
    root_file /etc/mine.pem x
    CABUNDLE=/etc/mine.pem inst
    assert_failure 2
    assert_output --partial "caBundle"
}

@test "busybox wget that skips TLS validation refuses a rolling manifest with exit 4" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='BusyBox v1.37 multi-call binary.' WGET_STDERR='wget: note: TLS certificate validation not implemented'
    restrict_path sha256sum tar gzip
    cp "$SANDBOX/src/dist.json" "$SANDBOX/live.json"
    serve https://setup.ocx.sh/dist.json "$SANDBOX/live.json"
    VERSION=latest inst
    assert_failure 4
    assert_output --partial "did not validate the TLS certificate"
}

@test "busybox wget unvalidated TLS is fine for a digest-pinned manifest" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='BusyBox v1.37 multi-call binary.' WGET_STDERR='wget: note: TLS certificate validation not implemented'
    restrict_path sha256sum tar gzip
    sum=$(sha256sum "$SANDBOX/src/dist.json" | cut -d' ' -f1)
    serve "https://corp.test/$sum.json" "$SANDBOX/src/dist.json"
    DISTURL="https://corp.test/$sum.json" inst
    assert_success
}

@test "wget download failure exits 3" {
    rm -f "$STUB_DIR/curl"
    make_wget
    export WGET_HELP='usage'
    restrict_path sha256sum tar gzip
    rm -f "$NETDIR"/*
    inst
    assert_failure 3
}

@test "curl without --tlsv1.2 support and with a CA bundle" {
    stub curl 'case "$1" in --help) echo old; exit 0;; esac; for a; do url=$a; done; prev=; for a; do [ "$prev" = -o ] && dest=$a; prev=$a; done; cp "$NETDIR/$(printf %s "$url" | tr "/:" "__")" "$dest"'
    root_file /etc/mine.pem x
    CABUNDLE=/etc/mine.pem inst
    assert_success
    grep -q -- "curl --proto =https --cacert $__OCXF_TESTING_ROOT/etc/mine.pem -fsSL" "$STUB_LOG"
    : >"$STUB_LOG"
    inst
    assert_success
    grep -q -- "curl --proto =https -fsSL" "$STUB_LOG"
}

@test "curl with --tlsv1.2 and no CA bundle option" {
    inst
    assert_success
    grep -q -- "curl --proto =https --tlsv1.2 -fsSL" "$STUB_LOG"
}

@test "shasum -a 256 works as the sha256 tool" {
    no_applets
    real=$(PATH=$OCXF_REAL_PATH command -v sha256sum)
    stub shasum "[ \"\$1\" = -a ] && shift 2; exec $real \"\$@\""
    restrict_path tar gzip
    inst
    assert_success
    grep -q '^shasum -a 256' "$STUB_LOG"
}

@test "openssl dgst -sha256 works as the sha256 tool" {
    no_applets
    real=$(PATH=$OCXF_REAL_PATH command -v sha256sum)
    stub openssl "shift 2; h=\$($real \"\$1\" | cut -d' ' -f1); echo \"SHA2-256(\$1)= \$h\""
    restrict_path tar gzip
    inst
    assert_success
    grep -q '^openssl dgst -sha256' "$STUB_LOG"
}

@test "sha256sum is preferred over shasum" {
    stub shasum 'exit 1'
    inst
    assert_success
    run grep -c '^shasum' "$STUB_LOG"
    assert_output 0
}
