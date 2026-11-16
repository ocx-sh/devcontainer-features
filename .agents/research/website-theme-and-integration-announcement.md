# ocx website theme adoption and integration announcement: procedure for devcontainer-features

Date: 2026-11-16. Read-only research; no feature code or docs pages written.

## Commits inspected

| Repo | Ref | Source |
|---|---|---|
| ocx-sh/website | `a9dd6af515bb6244063c8ddab0ce5508b6d7e5a2` (tag `v0.6.0`, `@ocx-sh/theme` 0.6.0) | local checkout `/home/mherwig/dev/ocx-sh/website` |
| ocx-sh/ocx | `36ce3ca6` | local checkout `/home/mherwig/dev/ocx-sh/ocx` (`website/` is its docs site) |
| ocx-sh/find_ocx | `f99a38c` | shallow clone, scratch |
| ocx-sh/rules_ocx | `e311b99` | shallow clone, scratch |
| ocx-sh/ocx-sdk-python | `48f9af3` | shallow clone, scratch (extra sibling with a site) |
| ocx-sh/setup-ocx | `eaeb678` | shallow clone, scratch |
| ocx-sh/vscode-ocx | `aadb2d5` | shallow clone, scratch |
| ocx-sh/ocx-mirror | `79499f0` | shallow clone, scratch |
| ocx-sh/conventions | `fe887c6` (`v0.3.5`) | clone, scratch |
| ocx-sh/marketing (private) | `374b18a` | clone, scratch |
| ocx-sh/devcontainer-features (this repo) | none: branch `main` has no commits; the GitHub repo exists, public, empty (`gh api repos/ocx-sh/devcontainer-features`) | local |

Paths below are relative to the repo named in the same cell or heading. `W:` = website, `O:` = ocx, `F:` = find_ocx, `R:` = rules_ocx, `C:` = conventions, `T:` = this repo.

## Headline findings

1. Only three repos run a themed Starlight site on ocx.sh: `find_ocx` (`/integrations/cmake/`), `rules_ocx` (`/integrations/bazel/`), `ocx-sdk-python` (`/integrations/python/`), plus `ocx` (`/docs/`) and `website` (root). `setup-ocx`, `vscode-ocx` have README-only docs; `ocx-mirror` has MkDocs Material on GitHub Pages (`ocx-mirror/mkdocs.yml:5`). The usable recipe therefore comes from find_ocx and rules_ocx.
2. A new site needs a PR to `ocx-sh/website` that claims a path in `nav.json` AND a new theme release before the new repo can build (the theme throws `base "…" is not a claim path` otherwise). The claim PR is also the "announce" PR for the hub card (same file). Precedent: [ae6a885](https://github.com/ocx-sh/website/commit/ae6a885) `feat(nav): claim /integrations/cmake/ for ocx-sh/find_ocx`.
3. `conventions` does NOT scaffold the Starlight site. It scaffolds the deploy workflow, the `ocx-theme` grim bundle, the `docs` tool group (node, pnpm), Renovate and CI task wiring. The Astro project is hand-built (`site/`), copied from find_ocx or rules_ocx.
4. The `ocx-theme` bundle (six skills) is not in this repo's `grimoire.toml` (`T:grimoire.toml`: only shell-essentials, docs-essentials, code-docs-essentials). It is on ghcr at `0.6.0`/`latest` (`ghcr.io/v2/ocx-sh/lore/ocx-theme/tags/list`, fetched 2026-11-16).
5. Proposed docs URL: `https://ocx.sh/integrations/devcontainer/` (claim `/integrations/devcontainer/`, hub `integrations`, category `editors`). The slug is an owner decision (see Open).

## 1. Theme adoption recipe

### 1.1 Claim first

- `base` must be a `nav.json` claim `{ path, repo, search }` or the build throws (`W:skills/ocx-theme-setup/SKILL.md:26-38`, error table at `:103-107`).
- Grammar: hub children are `/integrations/<slug>/`, slug `[a-z0-9]+(-[a-z0-9]+)*`, at most 32 chars; `repo` matches `ocx-sh/<name>` (`W:skills/ocx-theme-setup/references/nav-registry.md:27-37`).
- Adding a section (`nav-registry.md:97-103`): (1) PR on `ocx-sh/website` adding the claim and an `entries` item, (2) after the theme release, install it in the new repo and set `base`, (3) ask the owner to onboard the Bunny zone.
- Claim shape to add to `W:packages/theme/src/nav.json` `claims` (current claims at `nav.json` claims array, e.g. `{ "path": "/integrations/cmake/", "repo": "ocx-sh/find_ocx", "search": true }`): `{ "path": "/integrations/devcontainer/", "repo": "ocx-sh/devcontainer-features", "search": true }`. `search: true` makes the site build a Pagefind bundle every other section merges; the deploy action then requires `dist/pagefind/pagefind-entry.json` (`ocx-theme-deploy/SKILL.md:121-123`).
- The claim commit pattern ([ae6a885](https://github.com/ocx-sh/website/commit/ae6a885)) touched: `packages/theme/src/nav.json`, `packages/theme/test/hub-grid.test.ts`, `packages/theme/test/registry.test.ts`, `infra/bunny/__snapshots__/{match-golden.txt,plan-dev.json,plan-prod.json}`, `infra/bunny/rules.test.ts` (hard-coded rule counts, then 13/12 -> 14/13), and `infra/bunny/legacy.json` (a GitHub Pages redirect). A new repo has no Pages site to redirect, and `legacy.json` now has an empty `entries` list, so `rules.mjs:222-233` generates one `ocx:repo-<name>` OriginStorage rule per claiming repo instead. Expect the snapshots and rule-count assertions to change; run `task check` and `task bunny:test` in website.
- Bunny edge-rule ceiling: 50 per pull zone, plan ceiling 40, prod at 19 and dev at 18 rules (`W:infra/bunny/README.md:56`). One new claim adds one rule.

### 1.2 Packages and versions (what siblings run today)

| Package | Version | Source |
|---|---|---|
| `@ocx-sh/theme` | `0.6.0` (npm latest, modified 2026-11-16; `npm view`). Siblings: `ocx` 0.6.0 (`O:website/package.json`), find_ocx and rules_ocx 0.5.0 | `F:site/package.json`, `R:site/package.json` |
| `@astrojs/starlight` | peer `>=0.42.0 <0.43`; ocx 0.42.6, find_ocx 0.42.4. The upper bound is deliberate: a Starlight minor arrives only through a theme release | `W:packages/theme/package.json` peers, `ocx-theme-setup/SKILL.md:76-78` |
| `astro` | peer `^7`; ocx 7.4.12, find_ocx 7.3.5 | same |
| `@astrojs/markdown-satteri` | `0.4.3`, only find_ocx, for `headingAttributes` (`## Title {#id}`) in `.md` | `F:site/astro.config.mjs` |
| dev: `@lhci/cli` 0.15.1, `lighthouse` 12.6.1 (ocx 13.6.0), `playwright-core` ^1.63 (ocx ^1.65.1) | Lighthouse gate | `F:site/package.json`, `O:website/package.json` |

Pin exact versions (siblings have no `^`). A git-SHA pin of the theme (`github:ocx-sh/website#<sha>&path:/packages/theme`) is only for unreleased fixes and needs `allowBuilds` entries (`ocx-theme-setup/SKILL.md:46-74`); 0.6.0 is on npm, so use npm.

### 1.3 Required layout (find_ocx shape; same in rules_ocx and ocx-sdk-python)

```
site/                      # own pnpm project, not a workspace root
  package.json             # scripts: dev, build, check, test, lighthouse
  pnpm-workspace.yaml      # allowBuilds: {esbuild: true, sharp: true}; minimumReleaseAgeExclude: ['@ocx-sh/theme@<ver>']
  pnpm-lock.yaml           # committed; CI uses pnpm install --frozen-lockfile
  astro.config.mjs
  tsconfig.json
  lighthouse.budgets.mjs   # copied; BASE constant = claim path
  scripts/lighthouse.mjs   # trimmed copy of W:scripts/lighthouse.mjs (+ lighthouse.test.mjs)
  src/content.config.ts    # docs collection: docsLoader() + docsSchema()
  src/content/docs/**      # pages (hand-authored here, or generated by a port script)
  src/public/ or public/   # favicon only if overriding; theme serves /favicon.svg
```

Sources: `F:site/*` listing, `R:site/*` listing, `F:site/src/content.config.ts`, `F:site/pnpm-workspace.yaml`, `R:site/pnpm-workspace.yaml`. find_ocx and rules_ocx pages are generated into `src/content/docs` by `scripts/port-docs.mjs` from older sources (Sphinx `.rst`, Stardoc) (`F:site/astro.config.mjs:1-2`). That is not needed for a new repo: `O:website/` and `W:site/` author pages directly under `src/content/docs/`. Recommendation: author directly, skip the port script, skip `casts/` unless a real recorded terminal session is wanted (the `Terminal` component needs a cast under `public/`, `ocx-theme-quality/SKILL.md:71-75`).

### 1.4 Astro and Starlight config (minimum)

From `F:site/astro.config.mjs` and `ocx-theme-setup/SKILL.md:82-107`:

```js
import starlight from '@astrojs/starlight';
import ocxTheme from '@ocx-sh/theme/starlight';
import { defineConfig } from 'astro/config';
export default defineConfig({
  base: '/integrations/devcontainer/',   // the claim
  trailingSlash: 'always',               // required, plugin throws otherwise
  devToolbar: { enabled: false },
  integrations: [starlight({
    title: 'ocx Dev Container Feature',
    description: '…',
    social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/ocx-sh/devcontainer-features' }],
    plugins: [ocxTheme()],
    sidebar: [ /* explicit groups, see 1.6 */ ],
  })],
});
```

- Never set `site`; the plugin sets `https://ocx.sh` and rejects any other value (`ocx-theme-setup/SKILL.md:100-107`).
- Leave `markdown.processor` unset (Sätteri default). Any other processor disables the GitHub alerts, `{#id}` headings, `.md` links and includes, and the plugin warns (`:200-203`). find_ocx only adds `satteri({ features: { headingAttributes: true } })` for `.md` pages (`F:site/astro.config.mjs`), which docs-quality's `{#kebab-id}` rule (DOC-NAV-07) needs on plain `.md`; in `.mdx` use `\{#id\}` or `{#id}` (`ocx-theme-setup/SKILL.md:226-230`).
- Use an explicit `sidebar`; the autogenerated one lists the 404 page (`R:site/astro.config.mjs` comment). find_ocx drives it from `site/sidebar.mjs` and fails the build when an entry has no page (`F:site/astro.config.mjs`).
- Plugin options: `breadcrumbs`, `math`, `glossary`, `foldOutline` (`ocx-theme-setup/SKILL.md:111-120`). Only `ocx` uses `glossary` (`O:website/astro.config.mjs`, `frequency: 'all'`); a small feature site needs none. `expressiveCode: { shiki: { langAlias } }` is needed if fences use docs-quality tier suffixes such as `bash-run` (`F:site/fence-langs.mjs`).
- The plugin injects `tokens.css`, `base.css`, `starlight.css`, fourteen component overrides, IBM Plex fonts (400/600 only, no custom font), Pagefind merge, a favicon route, and a sitemap; `frag/` is a reserved directory (`ocx-theme-setup/SKILL.md:177-250`). Overriding `Search` drops header menu, mobile drawer, sidebar collapsibles and toaster (`:212-217`). Do not override.

### 1.5 Content collections and frontmatter

- Collection is stock Starlight: `docsLoader()` + `docsSchema()` (`F:site/src/content.config.ts`). Frontmatter: `title`, `description` only.
- `doc_type` / `doc_tier` are NOT frontmatter. docs-quality forbids YAML front matter for them (DOC-TYPE-28) and forbids placing the comment above front matter (DOC-TYPE-29). Required form inside the first 12 lines, after the closing `---` (`T:.claude/rules/docs-quality.md` "Declare the page"):
  - `.md`: `<!-- doc_type: how-to -->` then `<!-- doc_tier: everyday -->` (`F:site/pages/index.md:1-6`, `F:site/pages/guides/pin-and-freeze.md:5-6`).
  - `.mdx`: `{/* doc_type: how-to */}` and `{/* doc_tier: integration */}` (`O:website/src/content/docs/integration/devcontainers-and-editors.mdx:5-6`). An HTML comment in MDX is a hard build error (DOC-TYPE-30).
  - `doc_type` enum: tutorial, how-to, reference, explanation, troubleshooting, runbook, landing, readme, changelog. `doc_tier` enum: first-steps, everyday, integration; required only on tutorial, how-to, landing (DOC-DISC-13).
- An undeclared page is skipped by every check, so the gate stays green (docs-quality.md "Declare the page").
- Theme markdown widgets need no import in `.md`/`.mdx`: GitHub alerts (`> [!NOTE]`), `:::note[Title]` asides, `<details>`, `## Title {#id}`, `[x](./other.md#frag)` (`W:skills/ocx-theme-components/SKILL.md:139-159`). `Collapsible`, `Tabs`, other components need `.mdx`.
- Links: root-relative links must stay inside a claim, else `ocx-site check` fails (`ocx-theme-setup/SKILL.md:261-263`). Cross-links to the main docs are `/docs/...`.

### 1.6 Navigation and sidebar conventions

- Sibling sidebar order (find_ocx `site/sidebar.mjs`): Get started (Overview, Tutorial), Everyday (guides), Integrate, Concepts, Troubleshooting, Reference. rules_ocx: Overview, Tutorial, Guides, Concepts, Reference with collapsed sub-groups (`R:site/astro.config.mjs`).
- docs-quality: nest at most three levels, collapse the third (DOC-NAV-02); put the first-steps entry in a different top-level group from the everyday hub (DOC-DISC-21, checked by `nav_depth.py`); every cross-linked heading carries an explicit `{#kebab-id}` (DOC-NAV-07).
- Header, search box, breadcrumb, footer and the ecosystem menu come from the theme and `nav.json`; the shared header is swapped live from `/_shell/` (theme 0.3.0+) so nav edits in website reach built sites without a rebuild (`nav-registry.md:64-95`). Markup/CSS changes need a theme bump.

### 1.7 Shared components relevant to this feature

All imported by path, `@ocx-sh/theme/components/<File>.astro` (`ocx-theme-components/SKILL.md:12-20`, catalog `:59-132`):

| Need | Component |
|---|---|
| Install command | `InstallCommand.astro` (installer one-liner per shell as synced tabs), `InstallBar.astro`, `ui/CommandBar.astro`, `CopyButton.astro` |
| Alternative panels (devcontainer.json / VS Code UI / CLI) | `Tabs.astro` + `TabItem.astro` (Starlight-compatible) |
| Callouts | Starlight `Aside` (restyled), or markdown `> [!NOTE]` / `:::caution[...]` |
| Steps, cards | Starlight `Steps`, `Card`, `CardGrid`, `LinkCard` from `@astrojs/starlight/components`, restyled |
| Terminal transcripts | `ShellSession.astro` (fenced `$` command + output), `Terminal.astro` (recorded cast) |
| Hub cards of integrations | `HubGrid.astro` (`<HubGrid hub="integrations" />`), used on the website root only |
| Icons | `ui/Icon.astro` from the registry. Hard rule: an agent never draws or edits icon paths (`W:AGENTS.md`, `ocx-theme-icons/SKILL.md`) |

Rules every component follows: first paint is final, nothing loads before interaction, accessible names required, one `variant="primary"` per view (`ocx-theme-components/SKILL.md:27-53`). Tokens only, never raw colour values (`W:AGENTS.md`; skill `ocx-theme-theming`). No custom stylesheet is needed for a docs-only site.

### 1.8 pnpm and Node

- Both come from ocx, not corepack. Baseline `ocx.toml` group `docs`: `node = "ocx.sh/nodejs/node:24.21.0"`, `pnpm = "ocx.sh/pnpm/pnpm:11.22.0"` (`C:src/ocx.toml.jinja`, rendered when `site` is set); find_ocx pins `node:24`, `pnpm:11` (`F:ocx.toml`).
- `packageManager` in `package.json` is allowed only when equal to the ocx pnpm pin (`C:docs/contract.md:74`, checklist "pnpm via ocx, no corepack; `packageManager` equals the ocx pin", `C:skills/ocx-baseline/references/adoption-checklist.md`).
- This repo's `ocx.toml` has `node = "...:26"`, no pnpm, no lychee, floating tags (`T:ocx.toml`). Astro 7 engines `node >=22.12.0` and the theme `>=22` (`W:node_modules/astro/package.json:199`, `W:packages/theme/package.json:113`); every sibling runs 24. Align on 24.x exact pins when adopting conventions (pin-exact step, 6.2).
- Run everything as `ocx exec -- task <name>` or `ocx exec -- pnpm ...` (`W:AGENTS.md` "Commands").
- `pnpm-workspace.yaml` needs `allowBuilds: { esbuild: true, sharp: true }` and `minimumReleaseAgeExclude: ['@ocx-sh/theme@<version>']` because a fresh theme release is younger than pnpm's release-age cooldown (`F:site/pnpm-workspace.yaml`, `O:website/pnpm-workspace.yaml`).

### 1.9 Local commands, tests, gates

find_ocx task names (`F:taskfile.yml:69-107`), to copy under `site:`:

| Task | Does |
|---|---|
| `site:install` | `ocx exec -- pnpm install --frozen-lockfile` (dir `site`) |
| `site:build` | `pnpm run build` (`astro build`; find_ocx prefixes its port script) |
| `site:check` | build + `pnpm run test` + `pnpm run check`. find_ocx `check` = `check-anchors.mjs && check-fences.mjs && docs-gate.mjs && ocx-site check --dist dist` (`F:site/package.json`) |
| `site:lighthouse` | `playwright-core install chromium`, then `pnpm run lighthouse` |
| `site:dev` | live site at `http://localhost:<port>/integrations/<slug>/` |

Gates (`W:skills/ocx-theme-quality/SKILL.md:18-31`): `ocx-site check --dist dist` (root-relative links vs claims, dist layout vs claim, Pagefind version), Lighthouse 100 in all four categories (mobile, best of 3 runs), budgets, images-blocked no-shift check, lazy-hydration check, axe, `lychee` over `dist`.

Budgets for a content page (`ocx-theme-quality/SKILL.md:37-47`): HTML 14,200 B gzip per page, script before input 11 KiB, total transfer 126 KiB in the skill table but find_ocx's `lighthouse.budgets.mjs` uses 147 KB (`F:site/lighthouse.budgets.mjs`), DOM 800 elements, fonts 42,000 B. A budget may only be ratcheted down; the skill and the consumer file disagree on the total-transfer number (Open).

Lighthouse recipe: copy a trimmed `scripts/lighthouse.mjs` and `lighthouse.budgets.mjs` from website into `site/`; serve with `astro preview` under the claimed `base`; leave `frag/` and `404.html` out of page discovery (`ocx-theme-quality/SKILL.md:93-117`). Prerequisites in CI: `pnpm --dir site exec playwright-core install-deps chromium` (`F:.github/workflows/site.yml`).

docs-quality gate in the site build: find_ocx's `site/scripts/docs-gate.mjs` runs `doc_declaration`, `prose`, `page_type`, `landing_check`, `doc_examples` (on built pages), `markdownlint-cli2` with `site/.markdownlint.jsonc`, `links_raw` (source), then `--self-test` of every check; ratchet counts in `site/docs-baseline.json` (all zero) (`F:site/scripts/docs-gate.mjs:1-60`, `F:site/docs-baseline.json`). It reads the checks from `../.claude/rules/docs-quality/checks` (`:12`), which exists in this repo. The script is find_ocx-specific (port-docs expansion); for authored `.md/.mdx` pages, point it at `site/src/content/docs` and drop the `generated` set. Not run here.

Version pin and Renovate (see also 6.3): find_ocx's repo `renovate.json` groups `@ocx-sh/theme` with `ocx-sh/website/.github/actions/deploy` as group `ocx-theme` because "the action aborts when its Pagefind differs from the theme's" (`F:renovate.json`). The conventions preset does the same (`C:renovate/default.json` last packageRule "D-07: shared deploy action moves with the site theme"). `W:HANDOVER.md` and the setup skill still say Dependabot; the fleet moved to Renovate and conventions removes `dependabot.yml` (`C:MANIFEST.toml` line 7 `paths = [".github/dependabot.yml", ...]`). A theme bump that raises the Starlight range must land in the same PR.

## 2. Deploy

### 2.1 The action: `ocx-sh/website/.github/actions/deploy`

`W:.github/actions/deploy/action.yml` (node24, `index.mjs`). Inputs: `dist` (required), `storage-key` (required; empty fails before any request), `path` (default: the repo's only claim, or its shortest), `storage-host` (default `storage.bunnycdn.com`), `dry-run`, `preview`, `force-prune`, `force-upload`. Outputs: `url`, `uploaded`, `deleted`. Semantics: validate `dist` and claim; upload non-HTML and hashed `_astro/` + Pagefind chunks first; then Pagefind entry files and HTML; then prune stale HTML only (cap: more than half of at least 10 listed pages aborts without deleting); never purge; skip files whose Bunny checksum and length match (`ocx-theme-deploy/SKILL.md:101-150`). Failure table: `ocx-theme-deploy/references/failure-modes.md`.

Consumer workflow rules (`ocx-theme-deploy/SKILL.md:41-99`): triggers only `push: main`, daily `schedule`, `workflow_dispatch`; no `tags:`, no `pull_request`; `permissions: {}` at top; `environment: { name: ocx.sh }`; `concurrency: { group: ocx-sh-deploy, cancel-in-progress: false }`; pin every `uses:` to a 40-hex SHA with `# vX.Y.Z`; never `BUNNY_API_KEY`, never a purge in CI. The action versions with the theme: one `vX.Y.Z` tag. The v0.6.0 SHA is `a9dd6af515bb6244063c8ddab0ce5508b6d7e5a2`.

Two workflow forms exist; use the conventions one for a repo that adopts the baseline:

- find_ocx `deploy.yml`: separate build and deploy jobs, artifact hand-off, daily cron `17 4 * * *`, `ocx-sh/setup-ocx@25fa771… # v1.4.0`, deploy action `@ac3359ef… # v0.5.0` (`F:.github/workflows/deploy.yml`).
- conventions `deploy-site.yml` (template-owned, rendered when `site.deploy` is true): single job, `ocx-sh/conventions/.github/actions/setup@<hash>` with `groups: default,docs`, runs `task ci:docs`, then the deploy action with `dist: <site.dist>`, `path: <site.path with trailing slash>`, `storage-key: ${{ secrets.BUNNY_STORAGE_KEY }}`; triggers `push: main` on `site.dir/**`, `ocx.toml`, `ocx.lock`, extra `site.paths`, plus `workflow_dispatch`; no schedule (`C:src/.github/workflows/deploy-site.yml.jinja`). It pins the action at `v0.3.0` (`e86b8301…`), three theme releases behind 0.6.0, and the template says "move only via copier update" (`C:renovate/default.json` disables Renovate on it). Because the action aborts on a Pagefind mismatch with the theme, a site on theme 0.6.0 needs a conventions release that bumps the pin first (Open).

### 2.2 Infra per new site

| Item | Value for this repo | Who creates it | Source |
|---|---|---|---|
| Claim in released theme | `/integrations/devcontainer/` -> `ocx-sh/devcontainer-features` | website PR + release tag (agent writes PR; owner merges and tags) | 1.1, `W:RELEASING.md` |
| Storage zone | `sh-ocx-devcontainer-features` (`zoneName`: `ocx-sh/rules_ocx` -> `sh-ocx-rules-ocx`, `nav-registry.md:46`). HTTP-API zone, not S3 | owner-local `task bunny:onboard -- ocx-sh/devcontainer-features` in website, with `BUNNY_API_KEY` in website `.env` | `W:infra/bunny/README.md:23-33`, `onboard.mjs:1-3` |
| Zone 404 page | `/bunnycdn_errors/404.html`, set by onboard | same command | `onboard.mjs` `NOT_FOUND_PATH` |
| GitHub environment `ocx.sh` on this repo, deployment branches limited to `main` | does not exist yet (`gh api repos/ocx-sh/devcontainer-features/environments` returned none; find_ocx has `github-pages` and `ocx.sh`) | owner. `bunny:onboard` exits 1 without the environment or its branch policy | `W:infra/bunny/README.md:12-16`, `onboard.mjs` |
| Secret `BUNNY_STORAGE_KEY` in that environment | one zone's password | `bunny:onboard` pipes it to `gh secret set` over stdin | `ocx-theme-deploy/SKILL.md:26-39` |
| Edge rule routing the path to the zone | one `ocx:repo-devcontainer-features` OriginStorage rule, generated from the claim | owner runs `task bunny:apply -- --zone dev`, then prod, after the claim is in a merged website | `W:infra/bunny/rules.mjs:222-233`, README "Apply edge rules" |
| Pull zones | `sh-ocx` (prod, `ocx.sh`, `next.ocx.sh`) and `sh-ocx-dev` (`sh-ocx-dev.b-cdn.net`) already exist; no new pull zone per site | none | `W:HANDOVER.md` "Topology" |
| DNS / subdomain | none. One domain, path-mounted: no per-site subdomain | none | `W:HANDOVER.md` "One domain, path-mounted" |
| Previews | the website `previews` workflow builds only the sites listed in `W:scripts/previews/sites.mjs` (ocx, rules_ocx, python-sdk, catalog), zone `sh-ocx-preview-<slug>`, URL `https://sh-ocx-preview-<slug>.b-cdn.net/`, secret `BUNNY_PREVIEW_KEY_<SLUG>` in website env `previews`. A consumer's `deploy.yml` never sets `preview`. A new site would be a website PR adding an entry to `SITES` plus owner `bunny:onboard -- --preview <site>`, `bunny:zone:apply`, `bunny:apply` | owner for zones and secret | `ocx-theme-deploy/SKILL.md:152-170`, `W:infra/bunny/README.md:257-284` |
| PR checks | find_ocx `site.yml` runs build, `site:check` and Lighthouse on PRs, no deploy | agent | `F:.github/workflows/site.yml` |

`bunny:onboard` and the other write tasks refuse under `CI` and read the key only from the owner's gitignored `.env` (`W:infra/bunny/README.md:7-12`). The website agent runs them under the owner's grant of 2026-10-04 (`W:AGENTS.md`); that grant is website-scoped, so treat them as owner-only from this repo.

Resulting URL: `https://ocx.sh/integrations/devcontainer/`, and the dev-zone check URL `https://sh-ocx-dev.b-cdn.net/integrations/devcontainer/` (the dev host answered 200 for the cmake path on 2026-11-16; `ocx.sh` itself did not answer from this sandbox, so prod reachability was not confirmed).

Apex status: `ocx.sh` HTML still reaches Bunny through an nginx hop; the DNS cutover (OG-C) is planned for the end of 2026 (`W:HANDOVER.md` "Apex cutover"). find_ocx's README already links `https://ocx.sh/integrations/cmake/...` (`F:README.md:17,43`), so linking the ocx.sh URL before go-live is the precedent; its working state is not verified here.

### 2.3 Owner-only steps in the deploy path

1. Merge the website claim PR and cut a theme release tag (signed tag, `W:RELEASING.md`).
2. Create GitHub environment `ocx.sh` on `ocx-sh/devcontainer-features`, branch policy `main`.
3. Run `task bunny:onboard -- ocx-sh/devcontainer-features` (needs `BUNNY_API_KEY`); then `bunny:apply` for dev and prod; `bunny:verify`.
4. Required checks and repo settings on the new repo (branch protection, "Allow GitHub Actions to create and approve pull requests" for the feature publish workflow per `T:.agents/research/devcontainer-feature-spec-and-distribution.md:77`).

## 3. Skills and rules

### 3.1 Website repo `skills/` (published to `ghcr.io/ocx-sh/lore/<name>`, bundle `ocx-theme`)

`W:publish.toml` lists six skills and one bundle; they version with the npm package: each `vX.Y.Z` tag runs `grim publish --version vX.Y.Z` (`publish.toml:4-9`, `W:RELEASING.md`). Bundle definition `W:bundles/ocx-theme.toml`. Install into another repo: add to `grimoire.toml`

```toml
[bundles]
ocx-theme = "ghcr.io/ocx-sh/lore/ocx-theme:latest"
```

or `grim add ghcr.io/ocx-sh/lore/ocx-theme:latest` (`ocx-theme-setup/SKILL.md:24`); conventions renders exactly that line when `theme_bundle` is true (`C:src/grimoire.toml.jinja`). Commit `grimoire.lock` and the generated client files; never edit installed copies (`W:AGENTS.md` "Agent config").

| Skill | Purpose and trigger | Run on a new integration repo? |
|---|---|---|
| `ocx-theme-setup` | Add the Starlight plugin to an Astro site: claim path, install, `astro.config.mjs`, plugin options, overrides, fonts, glossary, Shell layout, `ocx-site check`. Trigger: installing or upgrading the theme, a build error `is not a claim path`, `trailingSlash must be 'always'`, `site … is not https://ocx.sh`, a new repo needing a path | Yes, first |
| `ocx-theme-deploy` | The reusable Bunny deploy action: workflow template, inputs, `BUNNY_STORAGE_KEY`, upload order, prune cap, previews, failure modes. Trigger: editing the deploy workflow, a deploy 401, a missing `index.html` | Yes, after setup |
| `ocx-theme-components` | Component catalog: import paths, props, a11y contracts, lazy loading, Markdown widgets | Yes, while writing pages |
| `ocx-theme-quality` | Lighthouse 100x4, budgets, no-flicker, lazy hydration, axe, `ocx-site check`, consumer Lighthouse recipe | Yes, when wiring `site:lighthouse` and CI |
| `ocx-theme-theming` | `--ocx-*` tokens, accent rule, dark parity, focus, `@layer ocx`. Trigger: writing CSS | Only if the site gets custom CSS (none planned) |
| `ocx-theme-icons` | Icon registry, `NAME_MAP`, hard rule: agents never draw SVG paths | Only if a page needs an icon |

Source: `W:skills/*/SKILL.md` frontmatter and bodies. No separate "integration announce" or "site scaffold" skill exists: `W:HANDOVER.md` "Guideline + lore skills" states "No separate `ocx-site-integration` skill exists"; setup and deploy cover a repo joining the site. The announce step (hub card) is not covered by any skill (4.1).

The conventions repo adds the `ocx-baseline` skill (adopt, modernize, audit) and the `ocx-baseline` rule, published as `ghcr.io/ocx-sh/conventions/ocx-baseline[-rule]` (`C:publish.toml`, `C:skills/ocx-baseline/SKILL.md`). It is a skill in the conventions repo and not in `grimoire.toml` of the siblings read.

### 3.2 Docs skills in this repo (from bundle `docs-essentials`, locked in `T:grimoire.lock`)

Order for new docs: `docs-plan` -> write pages (rules load automatically) -> `docs-review` per page or branch -> `docs-instrument` for the CI gate. docs-instrument's retrofit is first when pages already exist, because eight check families read the declaration (`T:.claude/skills/docs-instrument/SKILL.md:16-18`).

| Skill | Purpose | When | Output and location |
|---|---|---|---|
| `docs-plan` | Discovery and IA: product shape, surface enumeration, friction logs, ranked tasks in three tiers, one user need per task (`As a X, I need to Y, so that Z`), typed page inventory, coverage table, delete list, seeded declarations. Writes no prose; stops when the artifact exists | Before writing or restructuring docs; for a new repo with no pages the inventory is empty and the value is the task list, tiers and IA plan | One YAML artifact. Default `docs/discovery/use-cases.yaml` with friction logs in `docs/discovery/friction-logs/`; override once in docs config; `.agents/discovery/` when it must stay off the published surface (`T:.claude/skills/docs-plan/references/discovery-artifact.md:13-27`). The `.agents/docs-plan/` and `.agents/docs-baseline/` paths named in the request do not appear in the skills; the shipped default is `docs/discovery/`. In this repo `docs/` would be outside the Astro tree, so choose `.agents/discovery/` (checks exclude `.agents`) |
| `docs-review` | Grade pages against docs-quality on demand: runs `doc_declaration`, `prose`, `page_type`, `landing_check` per page (add `doc_examples`, `nav_depth`, `links_raw` for a tree); reports `path:line: DOC-XXX-nn: message`; never fixes unless asked | After writing a page or before a PR; default target is the branch diff | Findings in the reply only; undeclared pages listed first (`T:.claude/skills/docs-review/SKILL.md`) |
| `docs-instrument` | Wires the checks into CI cheapest first: published-file list, declaration retrofit, two runner targets `docs:check` (error, changed files) and `docs:audit` (warning, whole tree), markdownlint, link checking (strict build or `lychee --include-fragments dist/`), tested-example harness, reader signals, Lighthouse ratchet | After pages exist and a runner exists; stop condition: every check self-tests and has been seen red once, baseline counts recorded | `docs/.meta/observability.md` (signal manifest), a baseline file one line per check, runner targets. Starlight rows: `astro.config.*`, build dir `dist/`, `lychee --include-fragments dist/` (`T:.claude/skills/docs-instrument/references/wiring-by-generator.md:30,44,64,98,131`) |

Skills code-docs-cleanup, installer-script, shell-diagnose, shell-integration, shell-port are in the repo but are not docs-site skills.

### 3.3 docs-quality hard requirements for a usage page

From `T:.claude/rules/docs-quality.md` non-negotiables (IDs resolve to `rules/docs-quality/*.md`):

- Declaration comment with `doc_type` (+ `doc_tier` for tutorial, how-to, landing), inside the first 12 lines, never frontmatter, `{/* */}` in MDX (rows 1-3).
- Never a page declaring one type with another type's content; no branches on a tutorial (row 5, DOC-DISC-17).
- How-to: state the goal before the first `##` (DOC-TYPE-22), close with a "See also / Next steps" heading (DOC-TYPE-25), a hard prerequisite before step 1 (DOC-TYPE-23, reading heuristic). Reference: description only, no first person (DOC-TYPE-04), one entry shape (description, syntax block, parameter table; DOC-TYPE-17), split at about 15 items (DOC-TYPE-19). Troubleshooting entries titled `Error:`/`Warning:` with cause "This issue occurs when", last on the page, own page at five or more (DOC-TYPE-08, -09). Explanation opens with what it explains (DOC-TYPE-26).
- Landing: one-sentence lead (DOC-TYPE-10), a runnable command or link menu before word 150 (DOC-TYPE-11), at most two button CTAs (DOC-TYPE-12), no placeholder text and no adoption claim without a source link (rule row 7).
- First-steps page: under about 100 words before its first command (DOC-DISC-16), ends at one observable result (DOC-DISC-15), every step produces a visible result (DOC-DISC-18); tutorial only for two or more interacting concepts (DOC-DISC-19). Product shape: declare one of cli, library, hosted-service, framework (DOC-DISC-23); for a wrapper of a CLI, a per-entry parity table with a closed support-tier enum (DOC-DISC-24, `page_type.py`); state a first example's precondition (binary, key, server) before the call (DOC-DISC-25).
- Prose: sentences at most 25 words (DOC-PLAIN-02), real headings, one H1, no skipped levels (DOC-PLAIN-13), no chatbot artifacts (DOC-PLAIN-08), no authorship claims (DOC-PLAIN-09), AI assistance stated in the PR body (DOC-PLAIN-22), counts on stripped prose (DOC-PLAIN-04).
- Examples: every runnable example backed by a test in the required gate, bound by a declared key (DOC-EX-01, -02); every fence tagged with a language (DOC-EX-05); tier suffix one hyphen-joined token like `bash-norun` (DOC-EX-20); a no-run snippet in a paired marker with a reason (DOC-EX-06); recordings from a real run, kept out of the gate (DOC-EX-11, -12); player no autoplay (DOC-EX-15).
- Navigation: explicit `{#kebab-id}` on every cross-linked heading (DOC-NAV-07), sidebar at most three levels (DOC-NAV-02), build fails on a dead internal link or anchor checked on built output (DOC-OBS-01); a raw-markdown link pass needs a source root and exclusions (DOC-OBS-02).
- Rollout: error on changed files from the first commit, warning whole tree until the backfill lands, then red (docs-quality.md "The gate").
- README (DOC-TYPE-32 to -36): plain-language description first, install path, link to the docs site, license, who it is for. Changelog (DOC-TYPE-37 to -41): Keep a Changelog headings, migration path on breaking entries.

For this feature specifically, the doc-example rule matters: a `devcontainer.json` snippet that claims to work needs a test. The feature repo's own `devcontainer features test` scenarios (`T:.agents/research/devcontainer-feature-spec-and-distribution.md:106-125`) are the natural binding target through a declared `# doc: <slug>` key (DOC-EX-02); `jsonc`/`json` fences without a runner must be wrapped in a no-run marker with a reason.

## 4. Announce a new integration: touchpoints

| # | Place | Repo | File and anchor | What changes | Separate PR? |
|---|---|---|---|---|---|
| A | Path claim and ecosystem hub card | website | `packages/theme/src/nav.json` `claims` and `entries` | Claim `/integrations/devcontainer/`; add an entry. This feeds the header mega-menu, the `/integrations/` hub (`W:site/src/content/docs/integrations/index.mdx` renders `<HubGrid hub="integrations" />`) and breadcrumbs. Precedent: cmake entry went from `"planned": true` to `"href"` in [ae6a885](https://github.com/ocx-sh/website/commit/ae6a885) | Yes, plus theme release |
| B | Tests and Bunny snapshots that the claim changes | website | `infra/bunny/__snapshots__/*`, `infra/bunny/rules.test.ts`, `packages/theme/test/{hub-grid,registry}.test.ts` | Update hard-coded counts and snapshots (precedent diff in A) | Same PR as A |
| C | Roadmap row | ocx | `website/src/content/docs/roadmap.md:62` `\| DevContainer features \| Planned \| — \|` | Change status to Shipped (status words used: Shipped, In progress, Planned) and link to the feature docs, e.g. `[Dev Container Feature](/integrations/devcontainer/)`, like row 61 `GitHub Actions \| In progress \| [ocx-sh/setup-ocx](…)` | Yes |
| D | Manual devcontainer recipe | ocx | `website/src/content/docs/integration/devcontainers-and-editors.mdx`, section `## Use OCX in a dev container \{#devcontainer\}` (lines ~72-95: "OCX has no dev container feature", Dockerfile `COPY --from=ghcr.io/ocx-sh/ocx:0.9.2-alpine`, `postCreateCommand`) | Replace with the feature reference and a pointer to the site; keep the manual recipe only as a fallback for unsupported bases. Keep the anchor `{#devcontainer}`: it is linked from `index.mdx:39,55`, `getting-started/first-project.mdx:141,165`. The page is `how-to` / `integration` and the pre-existing sentence "OCX has no dev container feature" becomes false | Yes |
| E | Integrate hub page | ocx | `website/src/content/docs/integration/index.md`, bullet at line 20 ("Dev containers and editors shares the toolchain…") and "Other integrations" paragraph (line ~36, "Project documentation lives on separate sites: rules_ocx (Bazel), ocx-sdk (Python) and CMake") with link definitions `[p-integrations-bazel]: /integrations/bazel/` | Add the devcontainer site link and a link definition `[p-integrations-devcontainer]: /integrations/devcontainer/` | Yes |
| F | Sidebar | ocx | `website/astro.config.mjs:125` `page('Dev containers and editors', '/integration/devcontainers-and-editors/')` | No change if the page stays; the separate-site integrations (bazel, python, cmake) have no sidebar entry beyond `integration/bazel/` and `integration/python/` pages which describe what ocx asks of the integration | Only if a page is added |
| G | Landing tab (optional) | website | `site/src/fragments/landing-integrations.mdx` (Tabs: Bazel, CMake, Python, GitHub, with deferred fragments in `site/src/pages/frag/landing-tab/[tab].astro`) | Optional extra tab; the height of the tallest panel is pinned in `site/src/components/landing-content.ts:63`. Owner design decision | Yes, optional |
| H | Feature README and repo | devcontainer-features | root `README.md`, generated `src/ocx/README.md` | README links the docs site, as find_ocx does (`F:README.md:43` "Guides, concepts… are at https://ocx.sh/integrations/cmake/") (DOC-TYPE-34) | This repo |
| I | containers.dev index | `devcontainers/devcontainers.github.io` | `_data/collection-index.yml` on `gh-pages` | One entry per collection (`T:.agents/research/devcontainer-feature-spec-and-distribution.md:86-98`) | External PR; separate from ocx announcement |
| J | Marketing ledger (private) | marketing | `knowledge/integrations.md` (maturity ledger: "the guard against overselling… check it before any integration appears in public content") and `repos.md` repo table | Add a row; the ledger rows have state and "Safe to market?" | Optional, owner |
| K | Changelogs | ocx, website | `O:CHANGELOG.md`, `W:CHANGELOG.md` | Generated by git-cliff from commits; no hand edit, no news or blog page exists on the root site (`W:site/src/content/docs/` has only `index`, `404`, `apps`, `integrations`, `team`) | None |

Entry shapes to copy (all in `W:packages/theme/src/nav.json` `entries`):

```json
{ "id": "cmake", "hub": "integrations", "category": "build", "label": "CMake",
  "meta": "find_ocx", "desc": "find_package() for ocx-managed tools.", "href": "/integrations/cmake/" }
{ "id": "vscode", "hub": "integrations", "category": "editors", "label": "VS Code",
  "meta": "vscode-ocx", "desc": "Pinned tools on the editor PATH, with lockfile hints.", "planned": true }
```

Proposed new entry, hub `integrations`, category `editors` (categories: build, ci, sdks, editors; `nav.json` hubs):

```json
{ "id": "devcontainer", "hub": "integrations", "category": "editors", "label": "Dev Containers",
  "meta": "devcontainer-features", "desc": "ocx in every dev container, as a Feature.", "href": "/integrations/devcontainer/" }
```

Notes:
- The `vscode` entry is still `planned: true` with no href although `vscode-ocx` ships (v0.1.3 per `marketing/repos.md`; `O:...devcontainers-and-editors.mdx:15` documents it). `vscode-ocx` has no docs site or claim. Not our change, but the two sit in the same category; mention to the owner.
- `github-actions` links directly to the GitHub repo (`"href": "https://github.com/ocx-sh/setup-ocx"`), so a README-only integration can still be a live card without a site claim. That is the fallback if the site is not ready.
- The header and hub update reaches already-built sites at runtime within about a minute of the website deploy via `/_shell/` (`nav-registry.md:14-16`); the theme release is still needed for the claim to validate in the new repo.
- Other repos list no integrations: `setup-ocx/README.md`, `vscode-ocx/README.md`, `ocx-mirror/README.md`, `ocx/README.md` contain no integration index (grep found only `roadmap.md:61`, `devcontainers-and-editors.mdx`, `index.mdx`, `first-project.mdx`, `integration/index.md`).
- Order: A+B (website PR, theme release) -> new repo site deploys -> C, D, E (ocx PR; links resolve once the site is live) -> I.

## 5. What sibling usage docs contain, and the proposed inventory

### 5.1 Sibling page structures

| Site | Pages (all under `site/` or `docs/`) | Source |
|---|---|---|
| find_ocx (`/integrations/cmake/`) | Overview (`landing`, first-steps), Tutorial (`tutorial`, first-steps, ends "What you built" and "Next steps"); Everyday guides: add-a-tool, pin-and-freeze, pin-digests, find-package, use-system-ocx, update-vendored, migrate-04; Integrate: ci, mirror, mirror-packages, cross-build, policy-and-config; Concepts: how-it-works, entry-points, reproducible-first, lazy-vs-eager, env-and-config; Troubleshooting: configure-errors (`Error: …` entries with `{#ids}`), module-conflicts, exit-codes; Reference: commands, variables, Findocx.cmake | `F:site/sidebar.mjs`, `F:site/pages/**`, headings of `tutorial.md`, `guides/mirror.md`, `troubleshooting/configure-errors.md` |
| rules_ocx (`/integrations/bazel/`) | Overview, Tutorial, Guides (pin-toolchain, ci-reproducible, offline-mirror, cross-platform, remote-cache), Concepts (how-it-works, trust-and-config), Reference (environment, rules and macros, module extension) | `R:site/astro.config.mjs` sidebar, `R:docs/**` |
| ocx-sdk-python (`/integrations/python/`) | index, guide/quickstart, run-pinned-tools, bootstrap, vendoring, hermetic-ci, reproducible-ci, cross-platform, pytest-fixture, async, authoring, troubleshooting, concepts/, reference (api, command-map, compatibility-checklist, environment) | `ocx-sdk-python/docs/**` |
| ocx main docs, integration section | Per-integration how-to pages (`doc_type: how-to`, `doc_tier: integration`): github-actions (persist env, project example, pull in CI, cap parallel pulls, carry PATH), docker (tags, copy binary, bake toolchain, frozen resolution, private registries), devcontainers-and-editors, proxy-and-ca, registry-auth-recipes, unattended-ci, plus an `integration/index.md` landing | `O:website/src/content/docs/integration/*`, headings listed with `grep "^#"` |
| setup-ocx (README only) | Usage (minimal workflow), Inputs table (default column), Outputs table, Examples, Managed config, Caching, Permissions, Development | `setup-ocx/README.md:15-161` |
| vscode-ocx (README only) | What it does, Commands, Using OCX with tasks (run a binary, chain tasks, key binding), Settings, `ocx.toml` validation, Environment variables, Requirements | `vscode-ocx/README.md` |

Common bar across find_ocx, rules_ocx, python: one first-steps entry (overview + a tutorial that ends at a visible result), everyday how-tos keyed to a task, an `integration` tier for mirror/offline/proxy/CI, concepts that explain the pin-and-lock model, a troubleshooting page of `Error:` entries with exact messages, a reference page for every knob (options, variables, exit codes), and an explicit "Build behind a mirror / offline" guide. Versioning/pinning has its own page (find_ocx `pin-and-freeze`, `pin-digests`; rules_ocx `pin-toolchain`). Every page ends with "Next steps". Zero gate findings (`F:site/docs-baseline.json`).

### 5.2 Proposed page inventory for the feature site (11 lines)

1. Overview (`landing`, first-steps): what the Feature installs, one `devcontainer.json` snippet, who it is for, link menu.
2. Tutorial: first dev container with pinned tools (`tutorial`, first-steps): add Feature, reopen, `ocx pull`, run a tool, one visible result.
3. Choose a version and pin it (`how-to`, everyday): `pinned` vs `latest` vs `X.Y.Z`, feature tag `:1`, `:1.2`, how updates arrive.
4. Use the project toolchain in the container (`how-to`, everyday): `ocx.toml` / `ocx.lock`, groups, `syncOnCreate`, consent paths, shell hook.
5. Use it with VS Code and Codespaces (`how-to`, everyday): extension `ocx-sh.ocx`, picker, Codespaces prebuilds.
6. Work on any base image (`how-to`, everyday): Debian, Ubuntu, Alpine, other distros, non-root remote user, support matrix equals the CI scenario matrix.
7. Build behind a proxy or mirror, and offline (`how-to`, integration): `mirrorUrl`, `distUrl`, `caBundle`, `managedConfig`, air-gapped image bake.
8. Reproduce the container in CI (`how-to`, integration): `devcontainer features test`, `devcontainers/ci`, locked builds.
9. How the install works and what is verified (`explanation`): baked `dist.json` snapshot, sha256, no `ocx self setup`, idempotence, per-user state.
10. Troubleshooting (`troubleshooting`): `Error:` entries for checksum, unsupported libc or arch, missing downloader, permission on `OCX_HOME`.
11. Reference (`reference`): option table (id, type, default, maps to), environment variables, files installed, exit codes; changelog link.

Option names come from `T:.agents/research/ocx-bootstrap-contract.md:203-233`; they are proposals there, not final. Page 11 should be derived from `devcontainer-feature.json` by a test (DOC-TYPE-18). `devcontainer features generate-docs` writes `src/ocx/README.md`; keep hand-written content in `NOTES.md` (`T:.agents/research/devcontainer-feature-spec-and-distribution.md:80`); the Starlight pages are separate from that generated README.

## 6. Conventions repo: adopt first

`ocx-sh/conventions` v0.3.5 (`C:README.md`): copier template + Renovate preset + composite setup action + drift checker + `ocx-baseline` skill.

- Template does scaffold, for `profile: full` with a `site` answer: `deploy-site.yml` (template-owned), the `docs` tool group with node and pnpm exact pins, `ci:docs` wiring in `verify-basic.yml` (job `docs`: setup `default,docs` -> `task ci:docs`), and the `ocx-theme` bundle line in `grimoire.toml` (`theme_bundle` defaults to `site is not none`) (`C:copier.yml` questions `site`, `theme_bundle`; `C:MANIFEST.toml:102-105`; `C:src/ocx.toml.jinja`; `C:src/grimoire.toml.jinja`; `C:docs/contract.md:99`).
- Template does NOT scaffold: the Astro project, `astro.config.mjs`, `lighthouse.budgets.mjs`, any pages, or the real `ci:docs` body (seeded stub: `echo "no site lighthouse gate yet - wire site:lighthouse here"`, `C:src/taskfile.yml.jinja:44-47`). The repo owns `taskfile.yml`, `ocx.toml`, `grimoire.toml`, `AGENTS.md`, `.gitleaks.toml`, `.github/renovate-local.json` after the first copy (seeded-once, `C:MANIFEST.toml`).
- Site answers for a new repo: `site: { dir: site, dist: site/dist, deploy: true, path: /integrations/devcontainer, paths: [...] }` (rules_ocx uses `path: /integrations/bazel/` and `paths: ["docs/**"]`, `R:.copier-answers.yml`; fleet entries `C:fleet.toml`). A non-empty `path` renders with a trailing slash.
- Baseline contract tasks the root `taskfile.yml` must define: `verify`, `ci:lint`, `ci:test`, `ci:build`, `ci:docs`, `ci:deep` (`C:docs/contract.md:70-72`); lowercase `taskfile.yml`; ocx exact pins and committed `ocx.lock`; Renovate, never Dependabot; grim clients claude, codex, opencode; AGENTS.md canonical, CLAUDE.md a pointer; template-owned files carry the banner `ocx-baseline: template-owned file` and a hand edit fails `task baseline:check`.
- Renovate: `renovate.json` extends `github>ocx-sh/conventions//renovate/default#<hash>` and `local>ocx-sh/<repo>//.github/renovate-local` (`R:renovate.json`); the preset groups the theme and deploy action as "ocx site theme" (`C:renovate/default.json`). find_ocx, which has no `.copier-answers.yml`, uses a hand-written grouping instead (`F:renovate.json`).
- Drift checker: `drift/check.py` plus `fleet.toml` tracks every adopted repo (`C:README.md`, `C:skills/ocx-baseline/SKILL.md` audit step). This repo has no `fleet.toml` entry (grep for devcontainer in conventions found no repo entry), so adopting means a conventions PR adding `[repos.devcontainer-features]` with `iteration`, `adopted`, answers.
- Adopt procedure (skill `ocx-baseline`, `C:skills/ocx-baseline/SKILL.md:15-24`): clean branch; `bash $CONV/scripts/adopt.sh <dest> <fleet-key>` (renders template, renames `Taskfile.yml`, removes Dependabot, rewrites `_src_path`) or for a new repo `uvx --from copier==9.18.2 copier copy gh:ocx-sh/conventions <dir>` (`C:README.md`); `python3 $CONV/scripts/pin-exact.py <dest>/ocx.toml`; work the checklist (`C:skills/ocx-baseline/references/adoption-checklist.md`); done when `task setup`, `task verify`, `task baseline:check` pass.
- Order: conventions BEFORE theme adoption. Reasons: it fixes `ocx.toml` pins (node 24, pnpm) and the `docs` group the site needs, installs `ocx-theme` bundle, renders `deploy-site.yml` and Renovate. Then the website claim PR can run in parallel, and the Astro `site/` is added on top of the baseline. The conventions deploy template pins action v0.3.0 (Open).
- This repo is a feature repo, not Bazel or CMake: `languages` would be `shell` (the existing `shell-essentials` bundle) and `typescript` for `site/` scripts (`typescript-essentials` bundle, as website). The profile is `full`; `mirror` is for upstream mirror repos (`C:README.md` "Profiles").
- The target repo has no commits yet; baseline files and the research directory are untracked (`git status`). The first commit must exist before `adopt.sh` ("needs a clean tree", `C:README.md`).

## Step list for this repo

| # | Tag | Step |
|---|---|---|
| 1 | owner-only | Decide the claim slug (`devcontainer` vs `devcontainers`), the hub category (`editors`), and whether the docs site is wanted now or the card should initially link the repo like `github-actions`. |
| 2 | agent | Make the first commit on `main` (clean tree for adopt). Keep `.agents/research/` committed or ignored as the owner prefers. |
| 3 | agent | Adopt conventions: add `[repos.devcontainer-features]` to `C:fleet.toml` (PR to `ocx-sh/conventions`), run `scripts/adopt.sh` or `copier copy` with `profile: full`, `languages: [shell, typescript]`, `site: {dir: site, dist: site/dist, deploy: true, path: /integrations/devcontainer, paths: [...]}`, `theme_bundle: true`; then `scripts/pin-exact.py`; fix `ocx.toml` (node 24.x, pnpm 11.x, lychee); `task setup`, `task verify`, `task baseline:check`. |
| 4 | agent | Open the website claim PR (nav.json claim + entry, tests, Bunny snapshots) on `ocx-sh/website`; run `task check`, `task bunny:test` there. Feeds touchpoints A and B. |
| 5 | owner-only | Merge the website PR, bump `packages/theme/package.json`, run the full Lighthouse gate, push the signed tag (`W:RELEASING.md`). |
| 6 | agent | `grim add ghcr.io/ocx-sh/lore/ocx-theme:latest` (or conventions renders it); commit `grimoire.lock` and client files. Run `ocx-theme-setup`, then `ocx-theme-components`/`ocx-theme-quality` as needed. |
| 7 | agent | Run `docs-plan` (artifact in `.agents/discovery/`), friction log delegated to a repo-blind subagent where possible; seed declarations. |
| 8 | agent | Scaffold `site/` from find_ocx (package.json, pnpm-workspace.yaml, astro.config.mjs with the claim as `base`, content.config.ts, `lighthouse.budgets.mjs`, `scripts/lighthouse.mjs`, `.markdownlint.jsonc`); install with `pnpm install` through ocx so `pnpm-lock.yaml` is committed; set `minimumReleaseAgeExclude`. |
| 9 | agent | Write the pages from the 5.2 inventory under `site/src/content/docs/`; each with declaration comments, `{#kebab-id}` anchors, tagged fences; run `docs-review` on the branch diff. |
| 10 | agent | Wire `ci:docs` to `task site:check` + `site:lighthouse`; add a repo-owned `docs-gate` adapted from find_ocx; run `docs-instrument` (declaration retrofit commit, `docs:check`/`docs:audit`, baseline file, self-tests, plant-and-revert proof). |
| 11 | agent | Open the ocx PR: roadmap row, `devcontainers-and-editors.mdx` section, `integration/index.md` (touchpoints C, D, E). Hold until step 14 is live. |
| 12 | owner-only | Create the GitHub environment `ocx.sh` on this repo (branch policy `main`). |
| 13 | owner-only | In website run `task bunny:onboard -- ocx-sh/devcontainer-features`, then `task bunny:apply -- --zone dev` and prod, `task bunny:verify -- --zone dev`. |
| 14 | agent | Dispatch `deploy-site` (this repo, `workflow_dispatch` on main) once the zone and secret exist; watch it; verify `https://sh-ocx-dev.b-cdn.net/integrations/devcontainer/` and `https://ocx.sh/integrations/devcontainer/`. Re-run failed jobs once for infrastructure flakes. |
| 15 | owner-only | Merge PRs: conventions fleet entry, website claim, ocx announcement, this repo's feature and site PRs; set GHCR packages public; run the feature's first publish. |
| 16 | agent (after owner) | Optional: containers.dev index PR, marketing ledger row, landing tab. |

## Not verified / open

- `ocx.sh` did not answer from this sandbox (`curl` exit code 000 for `/`, `/integrations/`, `/integrations/cmake/`); live prod behaviour, the apex cutover state and the published URLs were not checked. Dev host `sh-ocx-dev.b-cdn.net` answered 200 for `/integrations/cmake/`. `T:.agents/research/ocx-bootstrap-contract.md` (last "Not verified" bullet) reports an expired TLS certificate on `ocx.sh` on 2026-11-16; not re-checked.
- No build was run: neither the website nor any sibling site was built, linted, or Lighthouse-tested here. The `docs-gate.mjs` adaptation for authored pages is a proposal, not tested. `ocx-site check` was not run.
- The `conventions` deploy template pins the website action at `v0.3.0` (`e86b8301…`), but theme 0.6.0 is current and the action aborts on a Pagefind mismatch with the theme (`W:HANDOVER.md` deploy section; `F:renovate.json` description). Whether a conventions release bumps that pin before adoption was not checked (latest tag `v0.3.5`). Renovate is disabled on `deploy-site.yml`, so only a conventions update moves it.
- Total-transfer budget conflict: skill table says 126 KiB, `F:site/lighthouse.budgets.mjs` says 147 KB (website's own budgets file `tests/budgets.mjs` was not opened).
- Slug choice and category (`devcontainer` vs `devcontainers`; `editors` vs `build`) are not decided anywhere in the sources.
- Whether `ocx-theme-deploy` requires a legacy redirect: `legacy.json` is empty and `repoRules` creates the rule from the claim (`rules.mjs:222-233`), so none should be needed; not run (`task bunny:plan` not executed).
- Whether the preview deploy can build a site of authored pages with a config of its own: `scripts/previews/sites.mjs` builds from a sparse-checked-out docs dir of markdown with the example Starlight config, which suits ported docs but not a `site/` with its own `astro.config.mjs`. Preview support for a new site is unverified; PR previews for the new repo are likely unavailable.
- The `.agents/docs-plan/` and `.agents/docs-baseline/` locations named in the request are not what the skills document; documented defaults are `docs/discovery/use-cases.yaml` (docs-plan) and a one-line-per-check baseline file "beside the runner" (docs-instrument, `references/rollout.md:82-83`). find_ocx uses `site/docs-baseline.json`.
- `docs-plan` could not be assessed for an empty-docs repo (inventory is empty); the friction-log subagent delegation relies on harness support.
- `ocx-mirror` has a docs site (MkDocs, GitHub Pages) but no theme claim; `setup-ocx`, `vscode-ocx` have no site. Whether they plan claims (`nav.json` has `vscode` and `mirror` entries marked `planned`) was not checked.
- Marketing repo is private; its ledger rows were read, not changed; it counts as an optional touchpoint only.
- `ocx` PR #739 and website PR #30 (Renovate local rules) are open and may touch neighbouring files; not diffed.
- Whether pnpm `minimumReleaseAge` behaviour needs `minimumReleaseAgeExclude` on a new site: both siblings carry it for the theme version; the cooldown default was not read.
