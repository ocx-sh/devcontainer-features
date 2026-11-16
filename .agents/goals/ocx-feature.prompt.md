Goal: complete every item in `.agents/goals/ocx-feature.md` in the repository
`ocx-sh/devcontainer-features`, each one checked off in that file with its
evidence. Run fully autonomously until the stop condition is reached.

## Read first

1. `.agents/goals/ocx-feature.md`: definition of done, autonomy grants, stop conditions.
2. `.agents/product-context.md`: the decisions already taken. Do not reopen them.
3. `.agents/research/*.md`: evidence, option tables and step lists. Trust a
   claim there only as far as its "Not verified / open" section allows.

## Rules

- Never ask the owner anything. Resolve a doubt from the research and the
  product context, pick the option that best serves the stated decisions, and
  record it under "Decisions taken" in the goal file with one line of reason.
- Act only inside the grants in the goal file's "Autonomy" section.
- An item is done only when its evidence is written next to it: a commit
  link, a run URL, or the command with its result. Verify by running. Never
  check an item on a subagent's claim alone; rerun the decisive command.
- Write the test first for every behaviour of `install.sh`. Reproduce a
  failure locally before pushing a fix. Docker is available locally; arm64 is
  not, so arm64 is proven in CI only. CI is the final gate.
- Orchestrate. Delegate implementation, review and research to subagents as
  the model routing in `CLAUDE.md` says, and run independent tracks in
  parallel. Give every subagent the goal file path and the exact item it owns.
- Tools come from `ocx` (`ocx add …`) or pnpm devDependencies; skills and
  rules come from grimoire (`grim add …`). Install nothing globally.
- Use the installed skills: `installer-script`, `shell-port` and
  `shell-diagnose` for `install.sh`; `docs-plan`, then writing, then
  `docs-review`, then `docs-instrument` for the documentation; the
  `ocx-theme-*` skills from `ghcr.io/ocx-sh/lore/ocx-theme:latest` for the
  site. Follow the `shell-quality`, `docs-quality` and `code-docs` rules.
- Conventional Commits, small commits. After the first commit and the `main`
  ruleset exist, land work through pull requests merged on green CI.
- Write friction with a skill or rule as a retro entry; never edit the skill.

## Order

1. First commit on `main` with the existing tool configuration and `.agents/`; push.
2. Adopt `ocx-sh/conventions`.
3. Feature, tests first: the bats unit suite, `install.sh`,
   `devcontainer-feature.json`, the vendored `dist.json`, hooks, the
   installer parity table.
4. `taskfile.yml` and `.taskrc.yml`: `lint`, `test:unit`, `test:image`,
   `test:images`, `test:scenarios`, `test`, `run`.
5. CI on amd64 and arm64, then the `main` ruleset.
6. Release workflow (hourly poll plus dispatch); prove it with one real run;
   publish; make the packages public; open the `www-setup` dispatch pull request.
7. Documentation: plan, site, use-case pages, review, gates, deploy.
8. Announcement pull requests on `ocx-sh/website` (hub category `build`) and
   `ocx-sh/ocx`; then the `devcontainers/devcontainers.github.io` pull request.
9. Hardening: an independent review of `install.sh` and the workflows
   (download integrity, trust boundaries, user handling, workflow
   permissions). Every finding gets a failing test first, then the fix.

## Known hazards

- `https://ocx.sh/` served an expired TLS certificate on 2026-11-16. Use
  `https://setup.ocx.sh/` for downloads and re-check before relying on `ocx.sh`.
- The docs site cannot build for production until the `nav.json` claim is
  merged in `ocx-sh/website` and a theme release is tagged. Both are the
  owner's. Open the pull request early, build and test the site against that
  branch, and leave the deploy as the only blocked step.
- The `conventions` deploy template pinned the deploy action at v0.3.0 while
  the theme is at 0.6.0; the action aborts on a Pagefind version mismatch.
- The standard `dev-container-features-test-lib` is bash. Test scripts must
  stay POSIX `sh` to run on images without bash.
- `GITHUB_TOKEN` commits do not trigger other workflows. The release workflow
  tests and publishes in the same run.
- `OCX_ANNOUNCE_TOKEN` may not include this repository in its scope. If the
  dispatch fails, the hourly poll carries releases; report the gap.

## Stop

Stop when every item is checked, or when each remaining item waits on the
owner or an upstream maintainer and everything else is finished. A failing
test, a red CI job or a tool error is not a reason to stop: diagnose and fix.

Final report: under ten lines, then an `## Actions` list of the owner-only
steps. Every pull request, issue and commit is a clickable link.
