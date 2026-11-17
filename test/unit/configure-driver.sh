#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# configure-driver.sh: what install.sh does with configure.sh, under set -eu. Run it through run_sh
# so the bash leg traces it (a -c snippet has no BASH_SOURCE for the coverage PS4 under set -u).
set -eu
# shellcheck source=../../src/ocx/lib.sh
. "$OCXF_SRC_DIR/lib.sh"
# shellcheck source=../../src/ocx/configure.sh
. "$OCXF_SRC_DIR/configure.sh"
# shellcheck source=../../src/ocx/configure.sh
[ -z "${OCXF_TWICE:-}" ] || . "$OCXF_SRC_DIR/configure.sh"
configure_main
