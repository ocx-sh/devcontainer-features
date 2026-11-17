#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# configure.sh: the build-time configuration half of the ocx Dev Container Feature. Source it after
# lib.sh, then call configure_main. Definitions only: no side effects, no shell options; install.sh
# owns set -eu. Reads the validated OCXF_* variables, writes only under /etc and
# /usr/local/share/ocx-feature (all through rootpath), never under a home directory.

OCXF_MARK='# Written by the ocx Dev Container Feature (id: ocx). Edits are overwritten on rebuild.'
OCXF_RC_BEGIN='# >>> ocx devcontainer feature >>>'
# Split in two: coverage-report.sh mistakes the closing marker text for a here-doc opener.
OCXF_RC_END='# <<<'" ocx devcontainer feature <<<"
OCXF_CA_CAP=32768 # ocx refuses an extra_ca_certs file above this many bytes (ocx 0.6.8)

# ocxf_toml_str <value>: a TOML basic string, backslash, quote and newline escaped.
ocxf_toml_str() {
    printf '"%s"\n' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; $!s/$/\\n/' | tr -d '\n')"
}

# ocxf_consent_array: the OCXF_CONSENT_PATHS list as a TOML array body, empty entries dropped.
ocxf_consent_array() {
    __ocxf_rest="${OCXF_CONSENT_PATHS:-}:"
    __ocxf_out=
    while [ -n "$__ocxf_rest" ]; do
        __ocxf_p=${__ocxf_rest%%:*}
        __ocxf_rest=${__ocxf_rest#*:}
        [ -n "$__ocxf_p" ] || continue
        __ocxf_out="${__ocxf_out:+$__ocxf_out, }$(ocxf_toml_str "$__ocxf_p")"
    done
    printf '%s\n' "$__ocxf_out"
    unset __ocxf_rest __ocxf_out __ocxf_p
}

# ocxf_ca_usable: 0 when OCXF_CA_BUNDLE names a readable file within the size cap ocx accepts.
ocxf_ca_usable() {
    __ocxf_f=$(rootpath "$OCXF_CA_BUNDLE")
    if [ ! -r "$__ocxf_f" ]; then
        warn "CA bundle $OCXF_CA_BUNDLE is not readable; ocx is not told about it"
        return 1
    fi
    __ocxf_n=$(wc -c <"$__ocxf_f" | tr -d ' ')
    if [ "$__ocxf_n" -gt "$OCXF_CA_CAP" ]; then
        warn "CA bundle $OCXF_CA_BUNDLE is $__ocxf_n bytes, above the $OCXF_CA_CAP ocx accepts; ocx is not told about it"
        return 1
    fi
    return 0
}

# ocxf_write_config: /etc/ocx/config.toml. Sets OCXF_CA_ENV (1: the CA must be exported) for the later steps.
ocxf_write_config() {
    OCXF_CA_ENV=0
    __ocxf_conf=$(rootpath /etc/ocx/config.toml)
    __ocxf_ca=0
    if [ -n "${OCXF_CA_BUNDLE:-}" ] && ocxf_ca_usable; then __ocxf_ca=1; fi
    __ocxf_paths=$(ocxf_consent_array)

    if [ -e "$__ocxf_conf" ] && [ "$(head -n 1 "$__ocxf_conf")" != "$OCXF_MARK" ]; then
        # Foreign file: never touched. The CA bundle has an env fallback, the rest does not.
        __ocxf_lost=
        [ "${OCXF_NO_UPDATE_CHECK:-0}" = 1 ] && __ocxf_lost="$__ocxf_lost, update check"
        [ -n "$__ocxf_paths" ] && __ocxf_lost="$__ocxf_lost, consent paths"
        [ -n "${OCXF_MANAGED_CONFIG:-}" ] && __ocxf_lost="$__ocxf_lost, managed config"
        if [ "$__ocxf_ca" = 1 ]; then
            __ocxf_lost="$__ocxf_lost, CA bundle (exported as OCX_EXTRA_CA_CERTS instead)"
            OCXF_CA_ENV=1
        fi
        if [ -n "$__ocxf_lost" ]; then
            warn "/etc/ocx/config.toml exists and is not managed by this feature, so it was left alone; not applied:${__ocxf_lost#,}"
        fi
        unset __ocxf_conf __ocxf_ca __ocxf_paths __ocxf_lost
        return 0
    fi

    mkdir -p "$(dirname "$__ocxf_conf")"
    {
        printf '%s\n' "$OCXF_MARK"
        if [ "$__ocxf_ca" = 1 ]; then
            printf '\nextra_ca_certs = %s\n' "$(ocxf_toml_str "$OCXF_CA_BUNDLE")"
        fi
        if [ "${OCXF_NO_UPDATE_CHECK:-0}" = 1 ]; then
            printf '\n[update]\nself = "manual"\ntoolchain = "manual"\n'
        fi
        if [ -n "$__ocxf_paths" ]; then
            printf '\n[shell.consent]\npaths = [%s]\n' "$__ocxf_paths"
        fi
        if [ -n "${OCXF_MANAGED_CONFIG:-}" ]; then
            printf '\n[managed]\nsource = %s\nrequired = false\n' "$(ocxf_toml_str "$OCXF_MANAGED_CONFIG")"
        fi
    } >"$__ocxf_conf"
    chmod 644 "$__ocxf_conf"
    unset __ocxf_conf __ocxf_ca __ocxf_paths
}

# ocxf_consent_arms: the OCXF_CONSENT_PATHS list as case arms, each literal quoted. ocx 0.6.8 grants a
# plain path to itself and "dir/*" to dir and everything below; any other "*" grants nothing, so it is dropped.
ocxf_consent_arms() {
    __ocxf_rest="${OCXF_CONSENT_PATHS:-}:"
    __ocxf_out=
    while [ -n "$__ocxf_rest" ]; do
        __ocxf_p=${__ocxf_rest%%:*}
        __ocxf_rest=${__ocxf_rest#*:}
        __ocxf_glob=0
        case $__ocxf_p in
            */\*) __ocxf_glob=1 __ocxf_p=${__ocxf_p%/\*} ;;
        esac
        case $__ocxf_p in
            *'*'*) continue ;;
        esac
        while [ "${__ocxf_p%/}" != "$__ocxf_p" ]; do __ocxf_p=${__ocxf_p%/}; done
        if [ "$__ocxf_glob" = 1 ]; then
            __ocxf_arm="$(sh_quote "$__ocxf_p")/*" # an empty base must not match the empty "no project" answer
            [ -z "$__ocxf_p" ] || __ocxf_arm="$(sh_quote "$__ocxf_p") | $__ocxf_arm"
        elif [ -n "$__ocxf_p" ]; then
            __ocxf_arm=$(sh_quote "$__ocxf_p")
        else
            continue
        fi
        __ocxf_out="${__ocxf_out:+$__ocxf_out | }$__ocxf_arm"
    done
    printf '%s\n' "$__ocxf_out"
    unset __ocxf_rest __ocxf_out __ocxf_p __ocxf_glob __ocxf_arm
}

# ocxf_write_profile: /etc/profile.d/ocx.sh, sourced by login shells and the rc blocks. The activation
# snippet runs ocx only when the nearest project lies under a consentPaths entry: ocx env itself
# applies any project's [env] table without asking.
ocxf_write_profile() {
    __ocxf_pf=$(rootpath /etc/profile.d/ocx.sh)
    mkdir -p "$(dirname "$__ocxf_pf")"
    __ocxf_arms=$(ocxf_consent_arms)
    __ocxf_groups=
    [ -z "${OCXF_PULL_GROUPS:-}" ] || __ocxf_groups=" --group=$(sh_quote "$OCXF_PULL_GROUPS")"
    {
        printf '%s\n' "$OCXF_MARK"
        [ -z "${OCXF_OCX_HOME:-}" ] || printf 'export OCX_HOME=%s\n' "$(sh_quote "$OCXF_OCX_HOME")"
        [ "$OCXF_CA_ENV" != 1 ] || printf 'export OCX_EXTRA_CA_CERTS=%s\n' "$(sh_quote "$OCXF_CA_BUNDLE")"
        if [ "${OCXF_SHELL_ACTIVATION:-0}" = 1 ] && [ -n "$__ocxf_arms" ]; then
            printf 'case $- in\n*i*)\n'
            printf '    if [ -x %s ]; then\n' "$(sh_quote "$OCXF_BIN")"
            # shellcheck disable=SC2016 # literal text of the generated profile, expanded when it is sourced
            printf '%s\n' \
                '        __ocxf_d=${OCX_PROJECT-}' \
                '        if [ -n "$__ocxf_d" ]; then' \
                '            [ -d "$__ocxf_d" ] || case $__ocxf_d in' \
                '            */*) __ocxf_d=${__ocxf_d%/*}; [ -n "$__ocxf_d" ] || __ocxf_d=/ ;;' \
                '            *) __ocxf_d=. ;;' \
                '            esac' \
                '        else' \
                '            __ocxf_d=$(pwd -P 2>/dev/null && printf x) || __ocxf_d=x' \
                '            __ocxf_d=${__ocxf_d%x}; __ocxf_d=${__ocxf_d%?}' \
                '            while [ -n "$__ocxf_d" ] && [ ! -f "$__ocxf_d/ocx.toml" ]; do' \
                '                if [ "$__ocxf_d" = / ]; then __ocxf_d=; else __ocxf_d=${__ocxf_d%/*}; [ -n "$__ocxf_d" ] || __ocxf_d=/; fi' \
                '            done' \
                '        fi'
            # shellcheck disable=SC2016 # literal text of the generated profile, expanded when it is sourced
            printf '%s\n' \
                '        if [ -n "$__ocxf_d" ]; then' \
                '            __ocxf_d=$(cd -- "$__ocxf_d" 2>/dev/null && pwd -P && printf x) || __ocxf_d=x' \
                '            __ocxf_d=${__ocxf_d%x}; __ocxf_d=${__ocxf_d%?}' \
                '        fi' \
                '        case $__ocxf_d in'
            printf '        %s)\n' "$__ocxf_arms"
            # shellcheck disable=SC2016 # literal text of the generated profile, expanded when it is sourced
            printf '%s\n' \
                '            if [ -n "${BASH_VERSION-}" ]; then __ocxf_sh=bash' \
                '            elif [ -n "${ZSH_VERSION-}" ]; then __ocxf_sh=zsh' \
                '            else __ocxf_sh=sh; fi'
            # shellcheck disable=SC2016 # literal text of the generated profile, expanded when it is sourced
            printf '            eval "$(%s --offline env%s --shell="$__ocxf_sh" 2>/dev/null)" || :\n' "$(sh_quote "$OCXF_BIN")" "$__ocxf_groups"
            printf '            ;;\n        esac\n        unset __ocxf_d __ocxf_sh\n    fi\n    ;;\nesac\n'
        fi
    } >"$__ocxf_pf"
    chmod 644 "$__ocxf_pf"
    unset __ocxf_pf __ocxf_arms __ocxf_groups
}

# ocxf_resolve <path>: follow symlinks so the edit lands in the target and the link survives.
ocxf_resolve() {
    __ocxf_t=$1
    __ocxf_i=0
    while [ -L "$__ocxf_t" ] && [ "$__ocxf_i" -lt 20 ]; do
        __ocxf_l=$(readlink "$__ocxf_t") || break
        case $__ocxf_l in
            /*) __ocxf_t=$__ocxf_l ;;
            *) __ocxf_t=$(dirname "$__ocxf_t")/$__ocxf_l ;;
        esac
        __ocxf_i=$((__ocxf_i + 1))
    done
    printf '%s\n' "$__ocxf_t"
    unset __ocxf_t __ocxf_i __ocxf_l
}

# ocxf_wire_rc <abs path>: put (or replace in place) the marked block in an existing rc file.
# shortcut: a CRLF file keeps its CRLF lines but our block is written with LF; markers match either.
ocxf_wire_rc() {
    __ocxf_rc=$(ocxf_resolve "$(rootpath "$1")")
    [ -f "$__ocxf_rc" ] || return 0
    if [ ! -w "$__ocxf_rc" ]; then
        warn "$1 is not writable; the ocx profile is not wired into it"
        return 0
    fi
    __ocxf_tmp=$(mktemp)
    OCXF_BLOCK="$OCXF_RC_BEGIN
[ -r /etc/profile.d/ocx.sh ] && . /etc/profile.d/ocx.sh
$OCXF_RC_END
" OCXF_S="$OCXF_RC_BEGIN" OCXF_E="$OCXF_RC_END" awk '
{ a[NR] = $0; l = $0; sub(/\r$/, "", l); if (l == ENVIRON["OCXF_S"]) last = NR
  else if (l == ENVIRON["OCXF_E"] && last && !s) { s = last; e = NR } }
END {
    if (s) { for (i = 1; i < s; i++) print a[i]; printf "%s", ENVIRON["OCXF_BLOCK"]; for (i = e + 1; i <= NR; i++) print a[i] }
    else { for (i = 1; i <= NR; i++) print a[i]; printf "%s", ENVIRON["OCXF_BLOCK"] }
}' "$__ocxf_rc" >"$__ocxf_tmp"
    cat "$__ocxf_tmp" >"$__ocxf_rc"
    rm -f "$__ocxf_tmp"
    unset __ocxf_rc __ocxf_tmp
}

# ocxf_write_runtime: the files the lifecycle hooks use at container run time.
ocxf_write_runtime() {
    __ocxf_dir=$(rootpath /usr/local/share/ocx-feature)
    [ -f "$OCXF_SRC_DIR/hook.sh" ] || err "hook.sh not found in $OCXF_SRC_DIR" 1
    mkdir -p "$__ocxf_dir"
    cp "$OCXF_SRC_DIR/hook.sh" "$__ocxf_dir/hook.sh"
    chmod 755 "$__ocxf_dir/hook.sh"
    {
        printf 'OCXF_BIN=%s\n' "$(sh_quote "${OCXF_BIN:-}")"
        printf 'OCXF_VERSION=%s\n' "$(sh_quote "${OCXF_VERSION:-}")"
        printf 'OCXF_PULL=%s\n' "$(sh_quote "${OCXF_PULL:-0}")"
        printf 'OCXF_PULL_GROUPS=%s\n' "$(sh_quote "${OCXF_PULL_GROUPS:-}")"
        printf 'OCXF_MANAGED_CONFIG=%s\n' "$(sh_quote "${OCXF_MANAGED_CONFIG:-}")"
        printf 'OCXF_OCX_HOME=%s\n' "$(sh_quote "${OCXF_OCX_HOME:-}")"
        printf 'OCXF_CA_BUNDLE=%s\n' "$(sh_quote "${OCXF_CA_BUNDLE:-}")"
        printf 'OCXF_CA_ENV=%s\n' "$(sh_quote "$OCXF_CA_ENV")"
    } >"$__ocxf_dir/feature.env"
    chmod 644 "$__ocxf_dir/feature.env"
    unset __ocxf_dir
}

configure_main() {
    ocxf_write_config
    ocxf_write_profile
    for __ocxf_f in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc /etc/zsh/zshrc /etc/zshrc; do
        ocxf_wire_rc "$__ocxf_f"
    done
    unset __ocxf_f
    ocxf_write_runtime
}
