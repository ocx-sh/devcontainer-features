# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# scenario.sh: helpers shared by the scenario scripts (test/ocx/<scenario>.sh), POSIX sh. Source it
# after check.sh: `. "$(dirname "$0")/scenario.sh"` pulls in check.sh too.
# A scenario script runs inside the built container as the scenario's remoteUser (root when the
# scenario names none), with the whole test/ocx directory mounted as the workspace.
# shellcheck shell=sh disable=SC2034 # the variables are read by the sourcing scripts

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=check.sh
. "$here/check.sh"

state=/usr/local/share/ocx-feature
marker='Written by the ocx Dev Container Feature'
# The workspace folder: scenario projects live under it, where the default consentPaths grant consent.
workspace=$here
# The workspace is a bind mount of a host directory: files a root script leaves there cannot be
# removed by the host user afterwards, so every project this script made goes away when it exits.
trap 'rm -rf "$workspace"/*-"$$"-* "$workspace"/*-"$$"' EXIT
# Marker file name of a project this script made, so reruns inside one container stay independent.
proj_n=0

# new_project <name> [extra toml]: a project <workspace>/<name>-<pid> with jq in [tools] and any
# extra toml appended (a [group.x.tools] table), locked with the real registry. Sets $proj.
new_project() {
    proj_n=$((proj_n + 1))
    proj=$workspace/$1-$$-$proj_n
    mkdir -p "$proj" || return 1
    {
        printf '[tools]\njq = "ocx.sh/jqlang/jq:1.8"\n'
        [ -z "${2:-}" ] || printf '\n%s\n' "$2"
    } >"$proj/ocx.toml"
    (cd "$proj" && ocx lock >/dev/null 2>&1) || {
        printf 'ocx lock failed in %s\n' "$proj"
        return 1
    }
}

# binary_libc [file]: gnu when the ELF names a glibc loader (PT_INTERP, in the first page), else musl (static).
binary_libc() {
    if head -c 4096 "${1:-/usr/local/bin/ocx}" | grep -a -q '/ld-linux'; then echo gnu; else echo musl; fi
}

# is_libc <gnu|musl> [file]
is_libc() {
    __l=$(binary_libc "${2:-}")
    [ "$__l" = "$1" ] || {
        printf 'the ocx binary is a %s build, expected %s\n' "$__l" "$1"
        return 1
    }
}

# version_is <X.Y.Z>: ocx reports it and the feature recorded it.
version_is() {
    [ "$(ocx version)" = "$1" ] && [ "$(cat "$state/ocx-version")" = "$1" ] || {
        printf 'ocx version: %s, recorded: %s, expected %s\n' "$(ocx version 2>&1)" "$(cat "$state/ocx-version" 2>&1)" "$1"
        return 1
    }
}

# installed_ok: the default binary location holds a working ocx whose version matches the record.
installed_ok() {
    [ "$(ocx version)" = "$(cat "$state/ocx-version")" ]
}

# run_hook <phase> [dir]: the lifecycle hook the way the CLI starts it (cwd = project, sh -c).
run_hook() {
    (cd "${2:-$proj}" && sh -c "$state/hook.sh $1")
}

# owned_by <user> <path>...: every path exists and belongs to the user.
owned_by() {
    __u=$1
    shift
    for __p in "$@"; do
        __o=$(stat -c %U "$__p" 2>/dev/null) || {
            printf 'missing: %s\n' "$__p"
            return 1
        }
        [ "$__o" = "$__u" ] || {
            printf '%s is owned by %s, expected %s\n' "$__p" "$__o" "$__u"
            return 1
        }
    done
}

# no_feature_files_in_homes: the build wrote no feature-owned file under a home directory.
no_feature_files_in_homes() {
    for d in /root /home/*; do
        [ -d "$d" ] || continue
        found=$(grep -rIl "$marker" "$d" 2>/dev/null | head -n 5)
        [ -z "$found" ] || {
            printf 'feature-owned file in %s: %s\n' "$d" "$found"
            return 1
        }
    done
    return 0
}

# in_new_shell <shell flags> <command>: run a command in a NEW interactive shell, noise filtered.
# bash when present, else sh (login too, so /etc/profile.d runs where the shell reads it).
new_shell() {
    if command -v bash >/dev/null 2>&1; then
        bash -ic "$1" 2>&1 | grep -v -e 'cannot set terminal process group' -e 'no job control'
    else
        sh -lic "$1" 2>&1 | grep -v -e 'job control' -e "can't access tty"
    fi
}

# shell_finds <tool> <expected path fragment>: a new interactive shell run from $proj resolves the tool there.
shell_finds() {
    __out=$(cd "$proj" && new_shell "command -v $1") || true
    case $__out in
        *"$2"*) ;;
        *)
            printf 'command -v %s in a new shell printed: %s\n' "$1" "$__out"
            return 1
            ;;
    esac
}

# the checks every user case makes; $1 is the expected remote user, $2 its home
# user_case <user> <home>
user_case() {
    __want=$1
    __home=$2
    check "the build wrote no feature file under a home directory" no_feature_files_in_homes
    check "the test runs as $__want" test "$(id -un)" = "$__want"
    check "ocx runs as $__want" sh -c "ocx version >/dev/null && [ \"\$(id -un)\" = $__want ]"
    new_project "user-$__want" || true
    check "the project lock was written" test -s "$proj/ocx.lock"
    # the hook must recreate what the lock describes, so remove the links ocx lock did not make
    rm -rf "$proj/.ocx"
    check "hook.sh update-content exits 0 in the project" run_hook update-content
    check "the home .ocx, $proj/.ocx/toolchain and ocx.lock are owned by $__want" \
        owned_by "$__want" "$__home/.ocx" "$proj/.ocx/toolchain" "$proj/ocx.lock"
    check "a new shell resolves jq from the project toolchain" shell_finds jq "$proj/.ocx/toolchain"
}
