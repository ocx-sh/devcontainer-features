#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# report.sh: keep one "release-blocked" issue in step with the release run. A failed job opens the
# issue, or comments on the open one (at most once a day); a published release closes it, and so does a
# run that finds nothing to do while the current feature version is published, so a stale or false
# issue heals. A detect failure on a scheduled run is only reported when the previous completed run also
# failed in detect (a network blip is not an incident). Nothing else changes.
# Repo tooling: needs gh, jq, curl.
# env: NEEDS_JSON   the workflow's `toJSON(needs)` (job results and detect outputs)
#      REPO, RUN_URL, GH_TOKEN
#      EVENT_NAME   github.event_name; "schedule" enables the persistent-detect-failure rule
#      OCX_VERSION  optional; when empty the upstream manifest is asked, else "unknown";
#                   only x.y.z is ever accepted into the title
#      OCXF_DIST_BASE  base URL for that lookup (default https://setup.ocx.sh)
# Exit: 0 ok, 2 bad input.
set -eu

LABEL=release-blocked
needs=${NEEDS_JSON:?}
repo=${REPO:?}
url=${RUN_URL:?}

failed=$(printf '%s' "$needs" | jq -r 'to_entries[] | select(.value.result == "failure") | .key') || exit 2
published=$(printf '%s' "$needs" | jq -r '.publish.result // ""') || exit 2
idle=$(printf '%s' "$needs" | jq -r 'if .detect.outputs.run == "false" and .detect.outputs.published == "true" then "yes" else "" end') || exit 2
open=$(gh issue list --repo "$repo" --label "$LABEL" --state open --json number --jq '.[0].number // empty')

if [ -n "$failed" ]; then
    if [ "$failed" = detect ] && [ "${EVENT_NAME:-}" = schedule ]; then
        prev=$(gh run list --repo "$repo" --workflow release.yml --status completed --limit 1 --json databaseId --jq '.[0].databaseId // empty') || prev=
        prev_detect=
        [ -z "$prev" ] || prev_detect=$(gh run view "$prev" --repo "$repo" --json jobs --jq '.jobs[] | select(.name == "detect") | .conclusion') || prev_detect=
        if [ "$prev_detect" != failure ]; then
            echo "report: first detect failure on a scheduled run, not reporting yet"
            exit 0
        fi
    fi
    ocx=${OCX_VERSION:-}
    if [ -z "$ocx" ]; then
        ocx=$(curl -fsS --max-time 20 "${OCXF_DIST_BASE:-https://setup.ocx.sh}/dist.json" | jq -r '.latest.version // empty' 2>/dev/null) || ocx=
    fi
    # Upstream text reaches a public issue title: only a plain x.y.z gets through.
    case "$ocx" in
        '' | *[!0-9.]* | .* | *. | *..* | *.*.*.*) ocx=unknown ;;
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) ocx=unknown ;;
    esac
    names=$(printf '%s' "$failed" | tr '\n' ' ')
    body="The release run failed in: $names

Run: $url

The feature version is published only by a run that completes. Recovery is automatic for a transient failure and for a release whose commit and tag were pushed but whose publish failed: the next hourly run publishes a tagged but unpublished version, and this issue closes itself when a run finds the current version published. A failure of a guard or a test needs a fix on the default branch first. To publish the version already in devcontainer-feature.json by hand: \`gh workflow run release.yml -f publish_current=true\`."
    if [ -n "$open" ]; then
        last=$(gh issue view "$open" --repo "$repo" --json comments,createdAt --jq '(.comments[-1].createdAt // .createdAt)[0:10]') || last=
        if [ "$last" = "$(date -u +%Y-%m-%d)" ]; then
            echo "report: issue $open already has an update from today, not commenting again"
        else
            gh issue comment "$open" --repo "$repo" --body "Failed again ($names): $url"
        fi
    else
        gh label create "$LABEL" --repo "$repo" --color B60205 --description "the unattended release is stuck" 2>/dev/null || true
        gh issue create --repo "$repo" --label "$LABEL" --title "Release blocked: ocx $ocx" --body "$body"
    fi
elif [ "$published" = success ] && [ -n "$open" ]; then
    gh issue close "$open" --repo "$repo" --comment "Released: $url"
elif [ -n "$idle" ] && [ -n "$open" ]; then
    gh issue close "$open" --repo "$repo" --comment "Healed: nothing to release and the current feature version is published: $url"
fi
