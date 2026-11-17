#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# detect.sh: the hourly fast path of the release workflow. Compares the digest sidecar published at
# setup.ocx.sh with the vendored one and says whether a release run has work to do.
# Repo tooling: needs curl.
# env: PUBLISH_CURRENT   "true" to run even when the manifest is unchanged
#      PAYLOAD_VERSION, PAYLOAD_SHA256, PAYLOAD_URL
#                        the repository_dispatch client_payload; untrusted, only format-checked
#                        and logged, never used for the decision (the sidecar is always re-fetched)
#      OCXF_DIST_BASE    base URL of the sidecar (HTTPS only, default https://setup.ocx.sh)
#      GITHUB_OUTPUT, GITHUB_STEP_SUMMARY   written when set
# Outputs: changed (digest differs), run (changed, or PUBLISH_CURRENT), remote_sha.
# Exit: 0 ok (changed or not), 2 malformed payload or sidecar, 3 network.
set -eu

die() {
    echo "detect: $1" >&2
    exit "${2:-2}"
}

root=$(cd "$(dirname "$0")/../.." && pwd)
base=${OCXF_DIST_BASE:-https://setup.ocx.sh}
case "$base" in https://*) ;; *) die "OCXF_DIST_BASE must be an HTTPS URL" ;; esac

# The payload is only a wake-up: reject anything malformed, trust nothing in it.
if [ -n "${PAYLOAD_VERSION:-}" ]; then
    case "$PAYLOAD_VERSION" in
        *[!0-9A-Za-z.+-]* | .* | '') die "payload version is malformed" ;;
    esac
    case "$PAYLOAD_VERSION" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "payload version is not x.y.z" ;; esac
fi
if [ -n "${PAYLOAD_SHA256:-}" ]; then
    case "$PAYLOAD_SHA256" in
        *[!0-9a-f]*) die "payload sha256 is not lowercase hex" ;;
    esac
    [ "${#PAYLOAD_SHA256}" -eq 64 ] || die "payload sha256 is not 64 characters"
fi
if [ -n "${PAYLOAD_URL:-}" ]; then
    case "$PAYLOAD_URL" in
        *[!A-Za-z0-9:/._~%?=\&+@-]*) die "payload url has unexpected characters" ;;
        https://*) ;;
        *) die "payload url is not HTTPS" ;;
    esac
fi

body=$(curl -fsS --retry 5 --retry-delay 3 --retry-all-errors --max-time 30 "$base/dist.json.sha256") ||
    die "cannot download $base/dist.json.sha256" 3
remote=${body%%[[:space:]]*}
case "$remote" in *[!0-9a-f]* | '') die "sidecar digest is not lowercase hex" ;; esac
[ "${#remote}" -eq 64 ] || die "sidecar digest is not 64 characters"

local_body=$(cat "$root/src/ocx/dist.json.sha256")
local_sha=${local_body%%[[:space:]]*}

changed=false
[ "$remote" = "$local_sha" ] || changed=true
run=$changed
[ "${PUBLISH_CURRENT:-false}" != true ] || run=true

if [ "$run" = true ]; then
    msg="release run needed: manifest changed=$changed, publish_current=${PUBLISH_CURRENT:-false} (vendored ${local_sha%"${local_sha#????????????}"}, upstream ${remote%"${remote#????????????}"})"
else
    msg="nothing to do: vendored manifest matches setup.ocx.sh (${local_sha%"${local_sha#????????????}"})"
fi
echo "$msg"
if [ -n "${PAYLOAD_VERSION:-}" ]; then echo "woken by dist-updated for ocx $PAYLOAD_VERSION"; fi
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "$msg" >>"$GITHUB_STEP_SUMMARY"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "changed=$changed"
        echo "run=$run"
        echo "remote_sha=$remote"
    } >>"$GITHUB_OUTPUT"
fi
