#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# lib.sh: shared helpers of the ocx Dev Container Feature scripts. Source it, never run it.
# POSIX sh; callers own their shell options. Exit codes of every feature script:
#   0 ok, 1 generic, 2 usage/env/missing tool, 3 network, 4 checksum, 5 extract, 7 platform.
# __OCXF_TESTING_ROOT is test-only (never documented): every script reaches the
# filesystem through rootpath so tests never touch the real /etc or /usr.

[ -n "${__OCXF_LIB_LOADED:-}" ] && return 0
__OCXF_LIB_LOADED=1

say() {
    printf 'ocx-feature: %s\n' "$*" >&2
}

warn() {
    printf 'ocx-feature: warning: %s\n' "$*" >&2
}

# err <msg> [code]: print and exit; code defaults to 1.
err() {
    printf 'ocx-feature: error: %s\n' "$1" >&2
    exit "${2:-1}"
}

truthy01() {
    case "${1:-}" in
        1 | true | yes | TRUE | YES | True | Yes) printf '1\n' ;;
        *) printf '0\n' ;;
    esac
}

# The one quoter: output is safe to re-read with eval or a generated script.
# The trailing x keeps $(...) from stripping trailing newlines of the value.
sh_quote() {
    __ocxf_q=$(printf '%sx' "$1" | sed "s/'/'\\\\''/g")
    __ocxf_q=${__ocxf_q%x}
    printf "'%s'\n" "$__ocxf_q"
    unset __ocxf_q
}

rootpath() {
    printf '%s%s\n' "${__OCXF_TESTING_ROOT:-}" "$1"
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

need_cmd() {
    has_cmd "$1" || err "$1 not found" 2
}
