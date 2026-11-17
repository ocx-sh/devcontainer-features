#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# coverage.sh <script> [args...] | -c <code>: run under bash --posix with xtrace lines appended to
# $OCXF_COV_LOG, as "+cov:<file>:<line>:". run_sh and run_snippet call it on the bash leg only.
# PS4 is set inside the shell because Debian's bash ignores an imported PS4; the script is sourced so
# it runs in the traced shell with its own path as $0. Scripts started as separate processes are not traced.
exec 9>>"${OCXF_COV_LOG:?}"
# shellcheck disable=SC2016 # the string is code for the traced shell
trace='PS4="+cov:\${BASH_SOURCE}:\${LINENO}:"; BASH_XTRACEFD=9; set -x'
if [ "$1" = "-c" ]; then
    exec bash --posix -c "$trace; $2"
fi
exec bash --posix -c "$trace; . \"\$0\"" "$@"
