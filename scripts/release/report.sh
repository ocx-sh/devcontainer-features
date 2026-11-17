#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# report.sh: keep one "release-blocked" issue in step with the release run. A failed job opens the
# issue, or comments on the open one; a published release closes it. Nothing else changes.
# Repo tooling: needs gh, jq, curl.
# env: NEEDS_JSON   the workflow's `toJSON(needs)` (job results)
#      REPO, RUN_URL, GH_TOKEN
#      OCX_VERSION  optional; when empty the upstream manifest is asked, else "unknown"
#      OCXF_DIST_BASE  base URL for that lookup (default https://setup.ocx.sh)
# Exit: 0 ok, 2 bad input.
set -eu

LABEL=release-blocked
needs=${NEEDS_JSON:?}
repo=${REPO:?}
url=${RUN_URL:?}

failed=$(printf '%s' "$needs" | jq -r 'to_entries[] | select(.value.result == "failure") | .key') || exit 2
published=$(printf '%s' "$needs" | jq -r '.publish.result // ""') || exit 2
open=$(gh issue list --repo "$repo" --label "$LABEL" --state open --json number --jq '.[0].number // empty')

if [ -n "$failed" ]; then
    ocx=${OCX_VERSION:-}
    if [ -z "$ocx" ]; then
        ocx=$(curl -fsS --max-time 20 "${OCXF_DIST_BASE:-https://setup.ocx.sh}/dist.json" | jq -r '.latest.version // empty' 2>/dev/null) || ocx=
        [ -n "$ocx" ] || ocx=unknown
    fi
    names=$(printf '%s' "$failed" | tr '\n' ' ')
    body="The release run failed in: $names

Run: $url

Nothing is published while this issue is open. Fix the cause and the next hourly run retries on its own. If the run already pushed the release commit, finish it with: \`gh workflow run release.yml -f publish_current=true\`."
    if [ -n "$open" ]; then
        gh issue comment "$open" --repo "$repo" --body "Failed again ($names): $url"
    else
        gh label create "$LABEL" --repo "$repo" --color B60205 --description "the unattended release is stuck" 2>/dev/null || true
        gh issue create --repo "$repo" --label "$LABEL" --title "Release blocked: ocx $ocx" --body "$body"
    fi
elif [ "$published" = success ] && [ -n "$open" ]; then
    gh issue close "$open" --repo "$repo" --comment "Released: $url"
fi
