#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# install.sh: build-time entry point of the ocx Dev Container Feature. The devcontainer CLI runs it
# as root with the options as upper-cased env vars. It installs the ocx binary system-wide, then
# hands over to configure.sh. It writes nothing under any home directory.
#
# Download, checksum, safe-extract and manifest functions are ported from the official installer
# (ocx-sh/www-setup, src/install.sh, Apache-2.0), adapted to this feature's prefixes and options.
#
# Exit codes: 0 ok, 1 generic, 2 usage/env/missing tool, 3 network, 4 checksum, 5 extract,
# 7 platform (unsupported OS/arch/libc, or the installed binary does not run).
# Test-only: __OCXF_TESTING_SOURCE_ONLY=1 (do not run main), OCXF_RETRY_DELAY, OCXF_SRC_DIR.

# shellcheck disable=SC2310 # the predicates tested in conditions never exit; their status is the answer
# shellcheck disable=SC2034 # OCXF_* option variables are the interface read by the sourced configure.sh
set -eu

OCXF_SRC_DIR=${OCXF_SRC_DIR:-$(cd "$(dirname "$0")" && pwd)}
# shellcheck source=lib.sh
. "$OCXF_SRC_DIR/lib.sh"

OCXF_DIST_LIVE=https://setup.ocx.sh/dist.json
OCXF_STATE_DIR=/usr/local/share/ocx-feature
OCXF_MIN_GLIBC=2028
OCXF_ATTEMPTS=3
OCXF_TMP=
OCXF_STAGED=
OCXF_DL=
OCXF_CURL_TLS12=0
OCXF_WGET_BUSYBOX=0
OCXF_WGET_HTTPS_ONLY=0
OCXF_WGET_TLS12=0
OCXF_WGET_CACERT=0
OCXF_TLS_UNVALIDATED=0
OCXF_HASH_TOOL=

# --- options ----------------------------------------------------------------

# assert_no_cntrl <option name> <value>: a control byte (tab, CR, ESC, DEL, newline) would reach a TOML file
# or a generated script. tr, not a case bracket: literal control bytes in a pattern are fragile on dash and busybox.
assert_no_cntrl() {
    ocxf_plain=$(printf '%sx' "$2" | LC_ALL=C tr -d '[:cntrl:]')
    [ "$ocxf_plain" = "$(printf '%sx' "$2")" ] || err "option $1 must not contain control characters" 2
}

# Characters that must never reach a generated shell file or a config line.
assert_safe_path() {
    case "$2" in
        /*) ;;
        *) err "option $1 must be an absolute path (got: $2)" 2 ;;
    esac
    case "$2" in
        */../* | */..) err "option $1 must not contain '..' (got: $2)" 2 ;;
    esac
    case "$2" in
        *'"'* | *'$'* | *'`'* | *';'* | *'&'* | *'|'* | *'<'* | *'>'* | *'('* | *')'* | *'
'* | *\\*)
            err "option $1 contains characters unsafe for shell embedding (got: $2)" 2
            ;;
    esac
    assert_no_cntrl "$1" "$2"
}

# parse_bool <option name> <value>: print 1 or 0, or exit 2 on a spelling that is neither.
parse_bool() {
    case "$2" in
        1 | true | yes | TRUE | YES | True | Yes) printf '1\n' ;;
        0 | false | no | '' | FALSE | NO | False | No) printf '0\n' ;;
        *) err "option $1 must be true or false (got: $2)" 2 ;;
    esac
}

assert_https_option() {
    case "$2" in
        https://?*) ;;
        *) err "option $1 must be an https:// URL (got: $2)" 2 ;;
    esac
    case "$2" in
        *[[:space:]]* | *[[:cntrl:]]* | *'"'* | *"'"* | *'`'*)
            err "option $1 contains whitespace, quotes or control characters" 2
            ;;
    esac
}

parse_version() {
    ocxf_v=${VERSION:-pinned}
    ocxf_v=${ocxf_v#v}
    case "$ocxf_v" in
        pinned | latest) ;;
        '' | *[!0-9.]* | .* | *. | *..*) err "option version must be pinned, latest or X.Y.Z (got: ${VERSION:-})" 2 ;;
        *.*.*)
            ocxf_rest=${ocxf_v#*.}
            ocxf_rest=${ocxf_rest#*.}
            case "$ocxf_rest" in
                '' | *.*) err "option version must be pinned, latest or X.Y.Z (got: ${VERSION:-})" 2 ;;
            esac
            ;;
        *) err "option version must be pinned, latest or X.Y.Z (got: ${VERSION:-})" 2 ;;
    esac
    OCXF_VERSION_REQUEST=$ocxf_v
}

parse_consent_paths() {
    OCXF_CONSENT_PATHS=${CONSENTPATHS-/workspaces/*}
    [ -n "$OCXF_CONSENT_PATHS" ] || return 0
    ocxf_old_ifs=$IFS
    IFS=:
    # shellcheck disable=SC2086 # split on colons, the entries may hold a literal *
    set -f -- $OCXF_CONSENT_PATHS
    IFS=$ocxf_old_ifs
    set +f
    for ocxf_p in "$@"; do
        assert_safe_path consentPaths "$ocxf_p"
    done
}

# Every option env var is read here and only here; the manifest defaults are repeated on purpose
# (a unit test keeps them equal to devcontainer-feature.json).
parse_options() {
    parse_version

    OCXF_LIBC=${LIBC:-musl}
    case "$OCXF_LIBC" in
        musl | gnu | auto) ;;
        *) err "option libc must be musl, gnu or auto (got: $OCXF_LIBC)" 2 ;;
    esac

    OCXF_DIST_URL=${DISTURL:-}
    [ -z "$OCXF_DIST_URL" ] || assert_https_option distUrl "$OCXF_DIST_URL"
    OCXF_MIRROR_URL=${MIRRORURL:-}
    [ -z "$OCXF_MIRROR_URL" ] || assert_https_option mirrorUrl "$OCXF_MIRROR_URL"

    OCXF_CA_BUNDLE=${CABUNDLE:-}
    if [ -n "$OCXF_CA_BUNDLE" ]; then
        assert_safe_path caBundle "$OCXF_CA_BUNDLE"
        [ -f "$(rootpath "$OCXF_CA_BUNDLE")" ] && [ -r "$(rootpath "$OCXF_CA_BUNDLE")" ] ||
            err "option caBundle is not a readable file: $OCXF_CA_BUNDLE" 2
    fi

    OCXF_MANAGED_CONFIG=${MANAGEDCONFIG:-}
    case "$OCXF_MANAGED_CONFIG" in
        -* | *[!A-Za-z0-9._:/@-]*) err "option managedConfig must be an OCI reference (got: $OCXF_MANAGED_CONFIG)" 2 ;;
    esac

    OCXF_OCX_HOME=${OCXHOME:-}
    [ -z "$OCXF_OCX_HOME" ] || assert_safe_path ocxHome "$OCXF_OCX_HOME"
    OCXF_INSTALL_DIR=${INSTALLDIR:-/usr/local/bin}
    assert_safe_path installDir "$OCXF_INSTALL_DIR"

    OCXF_NO_UPDATE_CHECK=$(parse_bool noUpdateCheck "${NOUPDATECHECK-true}")
    OCXF_PULL=$(parse_bool pull "${PULL-true}")
    OCXF_SHELL_ACTIVATION=$(parse_bool shellActivation "${SHELLACTIVATION-true}")
    parse_consent_paths

    OCXF_PULL_GROUPS=${PULLGROUPS:-}
    case "$OCXF_PULL_GROUPS" in
        -* | *[!A-Za-z0-9_.,-]* | ,* | *, | *,,*) err "option pullGroups must be comma-separated group names (got: $OCXF_PULL_GROUPS)" 2 ;;
    esac
}

check_root() {
    [ "$(id -u)" = 0 ] || [ -n "${__OCXF_TESTING_ROOT:-}" ] ||
        err "must run as root (the devcontainer CLI does this at image build)" 2
}

# --- target -----------------------------------------------------------------

# Print the glibc version "MAJOR.MINOR" of this host, or nothing. getconf first, then the loader
# banner; no ldd needed.
glibc_version() {
    ocxf_gv=$(getconf GNU_LIBC_VERSION 2>/dev/null) || ocxf_gv=
    case "$ocxf_gv" in
        glibc\ *)
            printf '%s\n' "${ocxf_gv#glibc }"
            return 0
            ;;
    esac
    for ocxf_l in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 \
        /usr/lib/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 \
        /lib/ld-linux-aarch64.so.1 /lib64/ld-linux-aarch64.so.1 \
        /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /usr/lib/ld-linux-aarch64.so.1; do
        [ -x "$(rootpath "$ocxf_l")" ] || continue
        ocxf_gv=$("$(rootpath "$ocxf_l")" --version 2>&1 |
            sed -n '1s/.*release version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p') || ocxf_gv=
        if [ -n "$ocxf_gv" ]; then
            printf '%s\n' "$ocxf_gv"
            return 0
        fi
    done
    return 1
}

# glibc_ok: succeed when the host glibc is at least 2.28 (the floor of the gnu build).
glibc_ok() {
    ocxf_gv=$(glibc_version) || return 1
    ocxf_maj=${ocxf_gv%%.*}
    ocxf_min=${ocxf_gv#*.}
    ocxf_min=${ocxf_min%%[!0-9]*}
    case "$ocxf_maj$ocxf_min" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ $((ocxf_maj * 1000 + ocxf_min)) -ge "$OCXF_MIN_GLIBC" ]
}

detect_target() {
    [ "$(uname -s)" = Linux ] || err "unsupported OS $(uname -s): the feature installs on Linux only" 7
    case "$(uname -m)" in
        x86_64 | amd64) ocxf_arch=x86_64 ;;
        aarch64 | arm64) ocxf_arch=aarch64 ;;
        *) err "unsupported CPU architecture $(uname -m): ocx ships x86_64 and aarch64" 7 ;;
    esac
    case "$OCXF_LIBC" in
        musl) ocxf_libc=musl ;;
        gnu)
            glibc_ok || err "libc: gnu needs glibc 2.28 or newer, which this image does not have; use libc: musl or auto" 7
            ocxf_libc=gnu
            ;;
        *)
            if glibc_ok; then ocxf_libc=gnu; else ocxf_libc=musl; fi
            ;;
    esac
    OCXF_TARGET="$ocxf_arch-unknown-linux-$ocxf_libc"
}

# --- prerequisites ----------------------------------------------------------

ca_bundle_present() {
    [ -n "$OCXF_CA_BUNDLE" ] && return 0
    for ocxf_c in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
        /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        [ -s "$(rootpath "$ocxf_c")" ] && return 0
    done
    return 1
}

# gzip is a capability, not a name: busybox tar gunzips by itself, GNU tar needs a gzip binary.
gzip_capable() {
    has_cmd gzip && return 0
    has_cmd tar && has_cmd mktemp || return 1
    ocxf_gt=$(mktemp -d) || return 1
    : >"$ocxf_gt/f"
    if tar -czf "$ocxf_gt/a.tgz" -C "$ocxf_gt" f 2>/dev/null && [ -s "$ocxf_gt/a.tgz" ]; then
        rm -rf "$ocxf_gt"
        return 0
    fi
    rm -rf "$ocxf_gt"
    return 1
}

hash_tool_present() {
    has_cmd sha256sum || has_cmd shasum || has_cmd openssl
}

add_pkg() {
    case " $OCXF_PKGS " in
        *" $1 "*) ;;
        *) OCXF_PKGS="$OCXF_PKGS $1" ;;
    esac
}

# scan_prereqs: set OCXF_MISSING (human list) and OCXF_PKGS (package names) for what is absent.
scan_prereqs() {
    OCXF_MISSING=
    OCXF_PKGS=
    if ! has_cmd curl && ! has_cmd wget; then
        OCXF_MISSING="$OCXF_MISSING curl-or-wget"
        add_pkg curl
    fi
    if ! has_cmd tar; then
        OCXF_MISSING="$OCXF_MISSING tar"
        add_pkg tar
    fi
    if ! gzip_capable; then
        OCXF_MISSING="$OCXF_MISSING gzip"
        add_pkg gzip
    fi
    if ! hash_tool_present; then
        OCXF_MISSING="$OCXF_MISSING sha256-tool"
        add_pkg coreutils
    fi
    if ! has_cmd mktemp; then
        OCXF_MISSING="$OCXF_MISSING mktemp"
        add_pkg coreutils
    fi
    if ! ca_bundle_present; then
        OCXF_MISSING="$OCXF_MISSING ca-bundle"
        add_pkg ca-certificates
    fi
}

# pm_run <pkg>...: install through the first package manager found, retry once; the caller rescans
# to judge the result. Returns 1 only when there is no package manager.
pm_run() {
    if has_cmd apt-get; then
        DEBIAN_FRONTEND=noninteractive
        export DEBIAN_FRONTEND
        ocxf_lists=$(rootpath /var/lib/apt/lists)
        ocxf_ran_update=0
        if ! find "$ocxf_lists" -type f -name '*_*' 2>/dev/null | grep -q .; then
            apt-get update || warn "apt-get update failed"
            ocxf_ran_update=1
        fi
        if ! apt-get install -y --no-install-recommends "$@"; then
            warn "apt-get install failed, retrying once"
            apt-get update || warn "apt-get update failed"
            ocxf_ran_update=1
            apt-get install -y --no-install-recommends "$@" || warn "apt-get install failed again"
        fi
        [ "$ocxf_ran_update" = 0 ] || rm -rf "${ocxf_lists:?}"/*
    elif has_cmd apk; then
        pm_retry apk add --no-cache "$@"
    elif has_cmd dnf; then
        pm_retry dnf install -y "$@"
    elif has_cmd microdnf; then
        pm_retry microdnf install -y "$@"
    elif has_cmd yum; then
        pm_retry yum install -y "$@"
    elif has_cmd zypper; then
        pm_retry zypper --non-interactive install "$@"
    elif has_cmd pacman; then
        pm_retry pacman -Syu --noconfirm --needed "$@"
    else
        return 1
    fi
    return 0
}

pm_retry() {
    "$@" && return 0
    warn "$1 failed, retrying once"
    "$@" || warn "$1 failed again"
}

ensure_prereqs() {
    scan_prereqs
    [ -n "$OCXF_MISSING" ] || return 0
    say "installing missing prerequisites:$OCXF_MISSING"
    # shellcheck disable=SC2086 # OCXF_PKGS is a space-separated package list
    pm_run $OCXF_PKGS || err "missing:$OCXF_MISSING, and no supported package manager was found; install them in the base image$(ca_hint)" 2
    scan_prereqs
    [ -z "$OCXF_MISSING" ] || err "still missing after the install:$OCXF_MISSING; install them in the base image$(ca_hint)" 2
}

ca_hint() {
    case "$OCXF_MISSING" in
        *ca-bundle*) printf ', or set the caBundle option to a PEM file in the image' ;;
    esac
}

# --- downloads --------------------------------------------------------------

assert_https_url() {
    case "$1" in
        https://*) return 0 ;;
        *) err "refusing insecure (non-https) URL: $1" 3 ;;
    esac
}

detect_downloader() {
    if has_cmd curl; then OCXF_DL=curl; else OCXF_DL=wget; fi
}

# Send an optional TLS flag only when the tool's own --help lists it: BusyBox wget rejects
# --https-only and --secure-protocol, and curl before 7.34 rejects --tlsv1.2.
probe_downloader() {
    detect_downloader
    if [ "$OCXF_DL" = curl ]; then
        ocxf_help=$(curl --help all 2>&1) || true # only the text is read, not the status
        case "$ocxf_help" in
            *--tlsv1.2*) OCXF_CURL_TLS12=1 ;;
        esac
        return 0
    fi
    ocxf_help=$(wget --help 2>&1) || true # BusyBox exits 1 after printing its usage
    case "$ocxf_help" in *BusyBox*) OCXF_WGET_BUSYBOX=1 ;; esac
    case "$ocxf_help" in *--https-only*) OCXF_WGET_HTTPS_ONLY=1 ;; esac
    case "$ocxf_help" in *--secure-protocol*) OCXF_WGET_TLS12=1 ;; esac
    case "$ocxf_help" in *--ca-certificate*) OCXF_WGET_CACERT=1 ;; esac
    if [ "$OCXF_WGET_BUSYBOX" = 1 ]; then
        warn "BusyBox wget: no TLS floor and the server certificate may go unchecked; install curl for a verified download"
    fi
    if [ -n "$OCXF_CA_BUNDLE" ] && [ "$OCXF_WGET_CACERT" = 0 ]; then
        err "option caBundle is set but this wget cannot take a CA bundle; install curl or GNU wget" 2
    fi
}

# One argv per flag set, never an unquoted flag variable: a CA bundle path may contain spaces.
download_once() {
    ocxf_url=$1
    ocxf_dest=$2
    ocxf_ca=
    [ -z "$OCXF_CA_BUNDLE" ] || ocxf_ca=$(rootpath "$OCXF_CA_BUNDLE")
    if [ "$OCXF_DL" = curl ]; then
        if [ "$OCXF_CURL_TLS12" = 1 ] && [ -n "$ocxf_ca" ]; then
            curl --proto '=https' --tlsv1.2 --cacert "$ocxf_ca" -fsSL -o "$ocxf_dest" "$ocxf_url"
        elif [ "$OCXF_CURL_TLS12" = 1 ]; then
            curl --proto '=https' --tlsv1.2 -fsSL -o "$ocxf_dest" "$ocxf_url"
        elif [ -n "$ocxf_ca" ]; then
            curl --proto '=https' --cacert "$ocxf_ca" -fsSL -o "$ocxf_dest" "$ocxf_url"
        else
            curl --proto '=https' -fsSL -o "$ocxf_dest" "$ocxf_url"
        fi
        return
    fi
    set -- -q -O "$ocxf_dest"
    [ "$OCXF_WGET_HTTPS_ONLY" = 0 ] || set -- "$@" --https-only
    [ "$OCXF_WGET_TLS12" = 0 ] || set -- "$@" --secure-protocol=TLSv1_2
    [ -z "$ocxf_ca" ] || set -- "$@" --ca-certificate="$ocxf_ca"
    if [ "$OCXF_WGET_BUSYBOX" != 1 ]; then
        wget "$@" "$ocxf_url"
        return
    fi
    # BusyBox says on stderr when it skips certificate validation; that decides whether a
    # rolling manifest may be trusted.
    ocxf_st=0
    wget "$@" "$ocxf_url" 2>"$ocxf_dest.err" || ocxf_st=$?
    cat "$ocxf_dest.err" >&2
    if grep -q 'certificate validation not implemented' "$ocxf_dest.err"; then
        OCXF_TLS_UNVALIDATED=1
    fi
    rm -f "$ocxf_dest.err"
    return "$ocxf_st"
}

# download_to_file <url> <dest> <message>: retry any failure (a 5xx from one edge PoP is common);
# <message> is the exit-3 text once every attempt failed.
download_to_file() {
    assert_https_url "$1"
    ocxf_attempt=1
    ocxf_delay=${OCXF_RETRY_DELAY:-1}
    while :; do
        # shellcheck disable=SC2310 # the retry loop reads the status on purpose
        if download_once "$1" "$2"; then
            return 0
        fi
        [ "$ocxf_attempt" -lt "$OCXF_ATTEMPTS" ] || err "$3" 3
        say "download failed (attempt $ocxf_attempt/$OCXF_ATTEMPTS), retrying in ${ocxf_delay}s"
        [ "$ocxf_delay" = 0 ] || sleep "$ocxf_delay"
        ocxf_attempt=$((ocxf_attempt + 1))
        ocxf_delay=$((ocxf_delay * 2))
    done
}

# --- checksums --------------------------------------------------------------

probe_hash_tool() {
    if has_cmd sha256sum; then
        OCXF_HASH_TOOL=sha256sum
    elif has_cmd shasum; then
        OCXF_HASH_TOOL=shasum
    else
        OCXF_HASH_TOOL=openssl
    fi
}

file_sha256() {
    case "$OCXF_HASH_TOOL" in
        sha256sum) sha256sum "$1" | awk '{print $1}' ;;
        shasum) shasum -a 256 "$1" | awk '{print $1}' ;;
        *) openssl dgst -sha256 "$1" | awk '{print $NF}' ;;
    esac
}

# verify_checksum <file> <expected sha256>: mismatch, unreadable file or empty digest exit 4.
verify_checksum() {
    ocxf_exp=$(printf '%s' "$2" | tr 'A-F' 'a-f')
    ocxf_act=$(file_sha256 "$1" | tr 'A-F' 'a-f') || ocxf_act=
    if [ -z "$ocxf_act" ] || [ "$ocxf_exp" != "$ocxf_act" ]; then
        err "checksum mismatch for $(basename "$1")
  expected: $ocxf_exp
  got:      $ocxf_act" 4
    fi
}

# --- safe extraction --------------------------------------------------------

# Pass 1 rejects absolute and ".." members, pass 2 links that leave the tree, then extract.
safe_extract() {
    ocxf_bad=$(tar -tzf "$1" 2>/dev/null | grep -E '(^|/)\.\.(/|$)|^/' || true)
    [ -z "$ocxf_bad" ] || err "archive contains unsafe path: $ocxf_bad" 5
    ocxf_bad=$(tar -tvzf "$1" 2>/dev/null | sed 's/ link to / -> /' |
        awk -F ' -> ' '
            /->/ {
                target = ""
                for (i = 2; i <= NF; i++) target = target (i == 2 ? "" : " -> ") $i
                if (substr(target, 1, 1) == "/") { print target; next }
                n = split(target, parts, "/")
                depth = 0
                for (j = 1; j <= n; j++) {
                    if (parts[j] == "" || parts[j] == ".") continue
                    if (parts[j] == "..") {
                        depth--
                        if (depth < 0) { print target; next }
                    } else {
                        depth++
                    }
                }
            }
        ' || true)
    [ -z "$ocxf_bad" ] || err "archive contains escaping link target: $ocxf_bad" 5
    tar -xzf "$1" -C "$2" --no-same-owner --no-same-permissions ||
        err "failed to extract $(basename "$1")" 5
}

# --- manifest ---------------------------------------------------------------

# Echo the sha256 a manifest URL pins itself to (".../<64 hex>.json"), or nothing.
dist_pin_digest() {
    ocxf_base=${1%%\?*}
    ocxf_base=${ocxf_base%%#*}
    printf '%s' "${ocxf_base##*/}" | sed -n 's/^\([0-9a-f]\{64\}\)\.json$/\1/p'
}

# fetch_dist <url> <dest>: download; verify against the digest in the URL when it has one. A rolling
# manifest over a TLS-unvalidated wget is refused (its inline digests would vouch for a swapped archive).
fetch_dist() {
    ocxf_pin=$(dist_pin_digest "$1")
    download_to_file "$1" "$2" "failed to fetch the release manifest from $1
  Check the network, or use version: pinned for the manifest bundled with the feature."
    if [ -n "$ocxf_pin" ]; then
        verify_checksum "$2" "$ocxf_pin"
    elif [ "$OCXF_TLS_UNVALIDATED" = 1 ]; then
        err "this wget did not validate the TLS certificate, so the rolling manifest at $1 cannot be trusted
  Install curl, or point distUrl at a <sha256>.json pin." 4
    fi
}

# The vendored digest only detects corruption: whoever can alter the feature tarball can alter both files.
load_vendored_manifest() {
    [ -f "$OCXF_SRC_DIR/dist.json" ] && [ -f "$OCXF_SRC_DIR/dist.json.sha256" ] ||
        err "the bundled release manifest or its digest is missing from the feature" 4
    cp "$OCXF_SRC_DIR/dist.json" "$1"
    ocxf_want=$(awk '{print $1; exit}' "$OCXF_SRC_DIR/dist.json.sha256")
    verify_checksum "$1" "$ocxf_want"
}

# The reader below is raw text (first textual match, no JSON escapes). A manifest a JSON-aware checker
# could read differently (any backslash, a repeated key in one row) is refused before anything is trusted.
assert_plain_manifest() {
    ocxf_msg="release manifest is not in the expected plain form"
    ! grep -q '[\]' "$OCXF_MANIFEST" || err "$ocxf_msg" 4
    ocxf_dup=$(manifest_leaves | awk '
        {
            n = split("version channel tag target filename sha256 url", keys, " ")
            for (i = 1; i <= n; i++) {
                c = gsub("\"" keys[i] "\"[ \t]*:", "&")
                if (c > 1) { print keys[i]; exit }
            }
        }')
    [ -z "$ocxf_dup" ] || err "$ocxf_msg" 4
}

resolve_manifest() {
    OCXF_MANIFEST=$OCXF_TMP/dist.json
    if [ -n "$OCXF_DIST_URL" ]; then
        fetch_dist "$OCXF_DIST_URL" "$OCXF_MANIFEST"
    elif [ "$OCXF_VERSION_REQUEST" = latest ]; then
        fetch_dist "$OCXF_DIST_LIVE" "$OCXF_MANIFEST"
    else
        load_vendored_manifest "$OCXF_MANIFEST"
    fi
    assert_plain_manifest
    OCXF_DIST_DIGEST=$(file_sha256 "$OCXF_MANIFEST")
}

json_field() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Flat leaf objects, one per line (the manifest has no nested braces below the outer one).
manifest_leaves() {
    grep -o '{[^{}]*}' "$OCXF_MANIFEST" || true
}

newest_stable() {
    ocxf_leaf=$(manifest_leaves | grep '"channel"[[:space:]]*:[[:space:]]*"stable"' | head -1)
    json_field "$ocxf_leaf" version | sed 's/^v//'
}

resolve_release() {
    ocxf_newest=$(newest_stable)
    [ -n "$ocxf_newest" ] || err "the release manifest lists no stable release" 3
    case "$OCXF_VERSION_REQUEST" in
        pinned | latest) ocxf_want=$ocxf_newest ;;
        *) ocxf_want=$OCXF_VERSION_REQUEST ;;
    esac
    ocxf_row=$(manifest_leaves | grep "\"version\"[[:space:]]*:[[:space:]]*\"$ocxf_want\"" |
        grep "\"target\"[[:space:]]*:[[:space:]]*\"$OCXF_TARGET\"" | head -1)
    if [ -z "$ocxf_row" ] || [ "$(json_field "$ocxf_row" version)" != "$ocxf_want" ]; then
        err "no ocx $ocxf_want build for $OCXF_TARGET in the release manifest (newest available: $ocxf_newest); set version: latest or distUrl to a manifest that has it" 2
    fi
    OCXF_ROW_VERSION=$ocxf_want
    OCXF_ROW_TAG=$(json_field "$ocxf_row" tag)
    OCXF_ROW_FILE=$(json_field "$ocxf_row" filename)
    OCXF_ROW_SHA=$(json_field "$ocxf_row" sha256)
    OCXF_ROW_URL=$(json_field "$ocxf_row" url)
    case "$OCXF_ROW_SHA" in
        *[!0-9a-fA-F]* | '') err "release row for $ocxf_want has no valid sha256" 4 ;;
    esac
    [ "${#OCXF_ROW_SHA}" = 64 ] || err "release row for $ocxf_want has no valid sha256" 4
    case "$OCXF_ROW_TAG$OCXF_ROW_FILE" in
        '' | *[!A-Za-z0-9._-]*) err "release row for $ocxf_want has an unsafe tag or filename" 4 ;;
    esac
    case $OCXF_ROW_FILE in
        *.tar.gz) ;;
        *)
            # safe_extract only gunzips: stop before the download, not after it
            ocxf_oldest=$(manifest_leaves | grep "\"target\"[[:space:]]*:[[:space:]]*\"$OCXF_TARGET\"" |
                grep '"filename"[[:space:]]*:[[:space:]]*"[^"]*\.tar\.gz"' |
                sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
                sort -t. -k1,1n -k2,2n -k3,3n | head -1)
            [ -n "$ocxf_oldest" ] || err "ocx $ocxf_want ships as $OCXF_ROW_FILE; this feature installs .tar.gz releases only and the manifest has none for $OCXF_TARGET" 2
            err "ocx $ocxf_want ships as $OCXF_ROW_FILE; this feature installs .tar.gz releases only. The oldest $OCXF_TARGET .tar.gz build is $ocxf_oldest: set version to $ocxf_oldest or newer" 2
            ;;
    esac
    assert_https_url "$OCXF_ROW_URL"
    OCXF_ARCHIVE_URL=$OCXF_ROW_URL
    if [ -n "$OCXF_MIRROR_URL" ]; then
        ocxf_m=$OCXF_MIRROR_URL
        while [ "${ocxf_m%/}" != "$ocxf_m" ]; do ocxf_m=${ocxf_m%/}; done
        OCXF_ARCHIVE_URL=$ocxf_m/$OCXF_ROW_TAG/$OCXF_ROW_FILE
    fi
}

# --- install ----------------------------------------------------------------

cleanup() {
    [ -z "$OCXF_STAGED" ] || rm -f "$OCXF_STAGED"
    [ -z "$OCXF_TMP" ] || rm -rf "$OCXF_TMP"
}

make_tmp() {
    OCXF_TMP=$(mktemp -d) || err "cannot create a temporary directory" 2
    chmod 700 "$OCXF_TMP"
}

# The smoke test runs the staged binary where it will live (a noexec /tmp must not fail it).
smoke_test() {
    ocxf_out=$("$1" version 2>/dev/null | head -1) || ocxf_out=
    if [ "$ocxf_out" != "$OCXF_ROW_VERSION" ]; then
        err "the installed ocx does not run or reports '$ocxf_out' instead of $OCXF_ROW_VERSION; the $OCXF_TARGET build may not fit this image, try the libc option" 7
    fi
}

download_and_install() {
    ocxf_arc=$OCXF_TMP/$OCXF_ROW_FILE
    download_to_file "$OCXF_ARCHIVE_URL" "$ocxf_arc" "failed to download $OCXF_ARCHIVE_URL
  Check the network, or use the mirrorUrl option."
    verify_checksum "$ocxf_arc" "$OCXF_ROW_SHA"
    mkdir "$OCXF_TMP/x"
    safe_extract "$ocxf_arc" "$OCXF_TMP/x"
    ocxf_src=$OCXF_TMP/x/ocx-$OCXF_TARGET/ocx
    { [ -f "$ocxf_src" ] && [ ! -L "$ocxf_src" ]; } || err "archive does not contain ocx-$OCXF_TARGET/ocx" 5

    OCXF_BIN=$OCXF_INSTALL_DIR/ocx
    ocxf_dir=$(rootpath "$OCXF_INSTALL_DIR")
    mkdir -p "$ocxf_dir"
    OCXF_STAGED=$ocxf_dir/.ocx.$$
    cp "$ocxf_src" "$OCXF_STAGED"
    chmod 0755 "$OCXF_STAGED"
    smoke_test "$OCXF_STAGED"
    mv -f "$OCXF_STAGED" "$ocxf_dir/ocx"
    OCXF_STAGED=

    ocxf_state=$(rootpath "$OCXF_STATE_DIR")
    mkdir -p "$ocxf_state"
    printf '%s\n' "$OCXF_ROW_VERSION" >"$ocxf_state/ocx-version"
    printf '%s\n' "$OCXF_DIST_DIGEST" >"$ocxf_state/dist-digest"
    OCXF_VERSION=$OCXF_ROW_VERSION
    export OCXF_VERSION OCXF_BIN
}

main() {
    umask 022
    check_root
    parse_options
    detect_target
    ensure_prereqs
    probe_hash_tool
    probe_downloader
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    make_tmp
    resolve_manifest
    resolve_release
    download_and_install
    if [ -f "$OCXF_SRC_DIR/configure.sh" ]; then
        # shellcheck source=/dev/null # written by a sibling change, absent from this tree
        . "$OCXF_SRC_DIR/configure.sh"
        configure_main
    fi
    say "installed ocx $OCXF_VERSION ($OCXF_TARGET) at $OCXF_BIN"
}

[ "${__OCXF_TESTING_SOURCE_ONLY:-0}" = 1 ] || main "$@"
