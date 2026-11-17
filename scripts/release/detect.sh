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
#      REPO, ACTOR, GH_TOKEN   when REPO is set and the run would otherwise do nothing, recover a
#                        feature version whose tag exists but that the registry does not have (needs git, jq)
# Outputs: changed (digest differs), run (changed, PUBLISH_CURRENT, or recover), recover, published (registry has the feature version), remote_sha.
# Exit: 0 ok (changed or not), 2 malformed payload or sidecar, 3 network or an unexpected registry answer.
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

# Recovery: a release that pushed its commit and tag but failed to publish leaves the manifest unchanged
# forever. When the tag v<feature version> exists on the remote (the workflow tags before it publishes)
# and the registry has no such version, run again and publish it. No tag means never published at all,
# the state before the first release, which only an explicit publish_current starts.
recover=false
published=false
if [ "$run" = false ] && [ -n "${REPO:-}" ]; then
    fv=$(jq -r '.version // empty' "$root/src/ocx/devcontainer-feature.json") || fv=
    case "$fv" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "feature version '$fv' is not x.y.z" ;; esac
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # Authenticated, so a private package answers 404 for a missing version like a public one; anonymous cannot tell them apart.
    printf 'user = "%s:%s"\n' "${ACTOR:?}" "${GH_TOKEN:?}" |
        curl -fsS --retry 3 --retry-all-errors --max-time 30 -K - "https://ghcr.io/token?service=ghcr.io&scope=repository:$REPO/ocx:pull" >"$tmp/token.json" ||
        die "cannot get a registry token" 3
    printf 'Authorization: Bearer %s\n' "$(jq -r .token "$tmp/token.json")" >"$tmp/auth"
    code=$(curl -sS --retry 3 --retry-all-errors --max-time 30 -I -o /dev/null -w '%{http_code}' -H "@$tmp/auth" \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json' \
        "https://ghcr.io/v2/$REPO/ocx/manifests/$fv") || die "cannot ask the registry for $fv" 3
    case "$code" in
        200) published=true ;;
        404)
            rc=0
            (cd "$root" && git ls-remote --exit-code --tags origin "refs/tags/v$fv" >/dev/null 2>&1) || rc=$?
            case "$rc" in 0) recover=true run=true ;; 2) ;; *) die "cannot list the remote tags" 3 ;; esac
            ;;
        *) die "registry answered $code for ocx:$fv" 3 ;;
    esac
fi

if [ "$run" = true ]; then
    msg="release run needed: manifest changed=$changed, recover=$recover, publish_current=${PUBLISH_CURRENT:-false} (vendored ${local_sha%"${local_sha#????????????}"}, upstream ${remote%"${remote#????????????}"})"
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
        echo "recover=$recover"
        echo "published=$published"
        echo "remote_sha=$remote"
    } >>"$GITHUB_OUTPUT"
fi
