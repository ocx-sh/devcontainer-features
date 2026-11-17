#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# Option caBundle on an image whose system certificate store is empty (test/images/small-ca): the
# build could only download ocx through the given bundle, and ocx gets it as extra_ca_certs.
# shellcheck disable=SC2329 # check calls the functions by name
. "$(dirname "$0")/scenario.sh"

store_is_empty() {
    [ -z "$(find /etc/ssl/certs -type f -size +0 2>/dev/null | head -n 1)" ] && [ ! -s /etc/ssl/certs/ca-certificates.crt ]
}
check "the image has no system certificate bundle (the build used the given one)" store_is_empty
small_bundle() {
    [ "$(wc -c </etc/ocx-test/ca.pem)" -le 32768 ]
}
check "the given bundle is under the 32 KiB ocx cap" small_bundle
check "ocx runs" installed_ok
check "/etc/ocx/config.toml sets extra_ca_certs to the bundle" grep -q '^extra_ca_certs = "/etc/ocx-test/ca.pem"$' /etc/ocx/config.toml

finish
