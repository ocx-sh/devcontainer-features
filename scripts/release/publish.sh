#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The OCX Authors

# publish.sh: land and publish a tested release tree. Commit it to the default branch, tag it, push
# the feature to ghcr.io with the pinned devcontainer CLI, then verify the registry (verify.sh).
# Order matters: a rejected push (main moved) stops the run before anything is published, and nothing
# is ever force-pushed. Not atomic: once the commit and tag are pushed, a failed publish leaves a tagged but
# unpublished version. detect.sh finds that state (tag on the remote, no such version in the registry) and the
# next run publishes it; re-running here keeps the tag and skips a version that is already published.
# Run it in a checkout with the release tree applied, under `pnpm exec` (devcontainer on PATH).
# Repo tooling: needs git, docker, devcontainer, base64.
# env: FEATURE_VERSION, OCX_VERSION   x.y.z of the feature and of the pinned ocx
#      DEFAULT_BRANCH, REPO           default branch name and owner/repo (the registry namespace)
#      GH_TOKEN, ACTOR                job token and user for the git push and the ghcr.io login
#      EXPECT_SHA                     when set, the default branch head this run was prepared from; a moved head stops the run
#      DRY_RUN                        "true" validates and packages, but commits, pushes, tags and publishes nothing
#      GITHUB_STEP_SUMMARY            written when set
# Exit: 0 ok, 1 push or publish failed, 2 bad input; verify.sh failures pass through.
set -eu

die() {
    echo "publish: $1" >&2
    exit "${2:-2}"
}

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
v=${FEATURE_VERSION:?}
case "$v" in *[!0-9.]* | .* | *. | *..*) die "FEATURE_VERSION '$v' is not x.y.z" ;; esac
case "$v" in [0-9]*.[0-9]*.[0-9]*) ;; *) die "FEATURE_VERSION '$v' is not x.y.z" ;; esac
: "${OCX_VERSION:?}" "${DEFAULT_BRANCH:?}" "${REPO:?}"
ref=ghcr.io/$REPO/ocx
tag=v$v

summary() {
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"
}

if [ "${DRY_RUN:-false}" = true ]; then
    pkg=$(mktemp -d)
    trap 'rm -rf "$pkg"' EXIT
    devcontainer features package ./src -f -o "$pkg"
    echo "dry run: packaged $ref:$v, nothing committed, pushed, tagged or published"
    summary "Dry run: feature $v with ocx $OCX_VERSION packaged; nothing committed, pushed, tagged or published."
    exit 0
fi

# A job-scoped Basic header: the token never lands in .git/config or in the remote URL.
hdr="http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN:?}" | base64 | tr -d '\n')"

# A queued run can start from a stale base. Stop cleanly before committing rather than fail the push later.
if [ -n "${EXPECT_SHA:-}" ]; then
    head=$(git -c "$hdr" ls-remote origin "refs/heads/$DEFAULT_BRANCH" | cut -f1) || die "cannot read the head of $DEFAULT_BRANCH" 1
    [ "$head" = "$EXPECT_SHA" ] || die "$DEFAULT_BRANCH moved to ${head:-?} since this run started from $EXPECT_SHA; nothing was published, the next run starts from the new head" 1
fi

git add -A -- src CHANGELOG.md site/src/content/docs
if ! git diff --cached --quiet; then
    git -c user.name=github-actions[bot] -c user.email=41898282+github-actions[bot]@users.noreply.github.com \
        commit -q -m "chore(release): ocx $OCX_VERSION, feature $v"
fi
# Never force: if main moved since the run started this fails, and nothing is published.
git -c "$hdr" push origin "HEAD:refs/heads/$DEFAULT_BRANCH" || die "push to $DEFAULT_BRANCH rejected; nothing was published" 1

if git -c "$hdr" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    echo "tag $tag exists, keeping it"
else
    git tag "$tag"
    git -c "$hdr" push origin "refs/tags/$tag" || die "pushing tag $tag failed" 1
fi

printf '%s' "$GH_TOKEN" | docker login ghcr.io -u "${ACTOR:?}" --password-stdin >/dev/null

if devcontainer features info manifest "$ref:$v" >/dev/null 2>&1; then
    echo "$ref:$v is already published, skipping the publish"
else
    devcontainer features publish --registry ghcr.io --namespace "$REPO" ./src || die "devcontainer features publish failed" 1
fi

sh "$root/scripts/release/verify.sh"
