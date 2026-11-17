#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# hook.sh <on-create|update-content>: lifecycle hook of the ocx Dev Container Feature. Runs as the
# remote user with the workspace as cwd, where lib.sh is not on any path, so it is self-contained.
# Exit: 0 always (a hook must never fail container creation), 2 unknown or missing phase.
set -eu

say() {
    printf 'ocx-feature: %s\n' "$*" >&2
}

warn() {
    printf 'ocx-feature: warning: %s\n' "$*" >&2
}

# nearest_toml: print the directory of the nearest ocx.toml from cwd upward, or nothing.
nearest_toml() {
    __d=$PWD
    while :; do
        if [ -f "$__d/ocx.toml" ]; then
            printf '%s\n' "$__d"
            return 0
        fi
        [ "$__d" != / ] || return 0
        __d=$(dirname "$__d")
    done
}

owner_uid() {
    if stat -c %u "$1" 2>/dev/null; then return 0; fi
    # shellcheck disable=SC2012 # ls -nd reads one directory's owner; find -printf is GNU-only
    ls -nd "$1" | awk '{ print $3 }'
}

# run_checked <what> <fix-for-78/65 hint ...>: run "$@" after the description, warn once on failure.
# Exit codes: ocx 64 = no project or bad argument, 65/78 = lock stale/missing, 69/75/79 = network or not found.
run_checked() {
    __what=$1
    shift
    __rc=0
    "$@" || __rc=$?
    [ "$__rc" -ne 0 ] || return 0
    if [ "$__rc" -eq 64 ] && [ "$__what" = pull ]; then
        __t=$(nearest_toml)
        [ -n "$__t" ] || return 0
    fi
    __fix='see the ocx output above'
    case $__rc in
        78 | 65) __fix='run "ocx lock" in the project and commit ocx.lock' ;;
        75 | 69 | 79) __fix='check the network, mirror and proxy settings, then rerun the container command' ;;
        74)
            if [ -n "${OCXF_OCX_HOME:-}" ]; then
                __fix="the ocxHome directory $OCXF_OCX_HOME must exist and be writable by the user who opens the container; the feature does not create it"
            else
                __fix='check file ownership of ocx.toml, ocx.lock and .ocx in the workspace'
            fi
            ;;
        64)
            if [ "$__what" = pull ]; then __fix='probably an unknown group in the pullGroups option'; else __fix='no managed config source was given'; fi
            ;;
    esac
    warn "ocx $__what failed with exit code $__rc.
  attempted: $*
  fix: $__fix"
}

do_on_create() {
    [ -n "${OCXF_MANAGED_CONFIG:-}" ] || return 0
    run_checked 'config setup' "$OCXF_BIN" config setup --managed-config "$OCXF_MANAGED_CONFIG"
}

# project_dir: the directory of the project ocx will use: OCX_PROJECT (a directory or a file) when set,
# else the nearest ocx.toml. Printed even when it does not exist.
project_dir() {
    if [ -z "${OCX_PROJECT:-}" ]; then
        nearest_toml
    elif [ -d "$OCX_PROJECT" ]; then
        printf '%s\n' "$OCX_PROJECT"
    else
        dirname -- "$OCX_PROJECT"
    fi
}

# foreign_owned <dir>: succeed when the project, its lock, its store or an OCX_PROJECT file belongs to a non-root user.
foreign_owned() {
    for __p in "$1" "$1/ocx.lock" "$1/.ocx" "${OCX_PROJECT:-}"; do
        { [ -n "$__p" ] && [ -e "$__p" ]; } || continue
        __o=$(owner_uid "$__p")
        [ "$__o" = 0 ] || return 0
    done
    return 1
}

do_update_content() {
    [ "${OCXF_PULL:-0}" = 1 ] || return 0
    __proj=$(project_dir)
    __uid=${__OCXF_TESTING_UID:-$(id -u)}
    # No project anywhere above: ocx would only print its own "no ocx.toml" error, so stay silent.
    [ -n "$__proj" ] || return 0
    # Root must not take over a foreign checkout: ocx would write ocx.lock and the toolchain links there.
    # shellcheck disable=SC2310 # the predicate's status is the answer, set -e is not wanted inside it
    if [ "$__uid" = 0 ] && foreign_owned "$__proj"; then
        warn "not pulling: $__proj is owned by another user and this hook runs as root, which would take over ocx.lock and the toolchain links; run ocx pull as that user"
        return 0
    fi
    if [ -n "${OCXF_PULL_GROUPS:-}" ]; then
        run_checked pull "$OCXF_BIN" pull -g "$OCXF_PULL_GROUPS"
    else
        run_checked pull "$OCXF_BIN" pull
    fi
}

main() {
    phase=${1:-}
    case $phase in
        on-create | update-content) ;;
        *)
            say "usage: hook.sh <on-create|update-content>"
            exit 2
            ;;
    esac
    env_file="${__OCXF_TESTING_ROOT:-}/usr/local/share/ocx-feature/feature.env"
    if [ ! -r "$env_file" ]; then
        warn "$env_file is missing; skipping $phase"
        exit 0
    fi
    # Written only by configure.sh at build time, root-owned, values quoted with sh_quote.
    # shellcheck disable=SC1090 # path is computed at run time
    . "$env_file"
    if [ ! -x "${OCXF_BIN:-}" ]; then
        warn "ocx binary ${OCXF_BIN:-} not found; skipping $phase"
        exit 0
    fi
    [ -z "${OCXF_OCX_HOME:-}" ] || export OCX_HOME="$OCXF_OCX_HOME"
    [ "${OCXF_CA_ENV:-0}" != 1 ] || export OCX_EXTRA_CA_CERTS="$OCXF_CA_BUNDLE"
    case $phase in
        on-create) do_on_create ;;
        update-content) do_update_content ;;
    esac
    exit 0
}

main "$@"
