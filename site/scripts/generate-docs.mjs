// Rewrites the generated regions of the reference pages from their sources, or with --check fails when a page is stale.
// A region sits between `<!-- generated:NAME:start -->` and `<!-- generated:NAME:end -->`; never edit it by hand.
// Usage: node scripts/generate-docs.mjs [--check] [--images FILE]   (run from site/)
// Exit: 0 ok, 1 a page is stale or an option has no heading (--check), 2 usage or a missing input.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DOCS = join(REPO, 'site/src/content/docs');

const cell = (s) => String(s).replace(/\|/g, '\\|').replace(/\s*\n\s*/g, ' ');
const code = (s) => `\`${s}\``;
const table = (head, rows) => [`| ${head.join(' | ')} |`, `|${head.map(() => '---').join('|')}|`, ...rows.map((r) => `| ${r.map(cell).join(' | ')} |`)].join('\n');

export function optionsRegion(feature) {
  const rows = Object.entries(feature.options).map(([name, o]) => {
    let allowed = o.type === 'boolean' ? '`true`, `false`' : 'Any string';
    if (o.enum) allowed = o.enum.map(code).join(', ');
    else if (o.proposals) allowed = `Any string; suggested ${o.proposals.map(code).join(', ')}`;
    const def = o.type === 'boolean' ? String(o.default) : o.default === '' ? '""' : o.default;
    return [`[${code(name)}](#opt-${name})`, o.type, code(def), allowed, o.description];
  });
  return table(['Option', 'Type', 'Default', 'Allowed values', 'Description'], rows);
}

export function parityRegions(parity) {
  const opt = (o) => (o ? `[${code(o)}](options.md#opt-${o})` : 'none');
  return {
    'parity-variables': table(
      ['Installer variable', 'Status', 'Feature option', 'Behaviour'],
      parity.variables.map((v) => [code(v.name), v.status, opt(v.option), v.note]),
    ),
    'parity-feature-only': table(
      ['Feature option', 'Difference from the installer'],
      parity.featureOnly.map((f) => [opt(f.option), f.note]),
    ),
  };
}

// images.txt: `<alias> <image reference> [platform]`, `#` comments and blank lines ignored.
export function imagesRegion(text) {
  const rows = text
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => {
      const [alias, ref, platform] = l.split(/\s+/);
      return [code(alias), code(ref), platform ? `${platform} only` : 'amd64 and arm64'];
    });
  return table(['Alias', 'Image', 'Architectures'], rows);
}

// The root changelog without its H1, so the page title stays the only top-level heading.
export function changelogRegion(md) {
  return md.replace(/^# .*\n/, '').trim();
}

export function replaceRegion(page, name, body) {
  const start = `<!-- generated:${name}:start -->`;
  const end = `<!-- generated:${name}:end -->`;
  const a = page.indexOf(start);
  const b = page.indexOf(end);
  if (a < 0 || b < a) throw new Error(`region ${name} is missing its start or end marker`);
  return `${page.slice(0, a + start.length)}\n\n${body}\n\n${page.slice(b)}`;
}

export function missingOptionAnchors(page, feature) {
  return Object.keys(feature.options).filter((n) => !page.includes(`{#opt-${n}}`));
}

function main(argv) {
  const check = argv.includes('--check');
  const i = argv.indexOf('--images');
  const imagesFile = i >= 0 ? argv[i + 1] : join(REPO, 'test/images.txt');
  const json = (p) => JSON.parse(readFileSync(join(REPO, p), 'utf8'));
  const feature = json('src/ocx/devcontainer-feature.json');
  const parity = json('src/ocx/installer-parity.json');
  const plan = [
    ['reference/options.md', { options: optionsRegion(feature) }],
    ['reference/installer-parity.md', parityRegions(parity)],
    ['changelog.md', { changelog: changelogRegion(readFileSync(join(REPO, 'CHANGELOG.md'), 'utf8')) }],
  ];
  // shortcut: test/images.txt lands on another branch; until then the committed region stays as it is.
  if (imagesFile && existsSync(imagesFile)) {
    plan.push(['reference/supported-images.md', { images: imagesRegion(readFileSync(imagesFile, 'utf8')) }]);
  }
  let stale = 0;
  for (const [file, regions] of plan) {
    const path = join(DOCS, file);
    const old = readFileSync(path, 'utf8');
    let page = old;
    for (const [name, body] of Object.entries(regions)) page = replaceRegion(page, name, body);
    if (page === old) continue;
    if (check) {
      console.error(`generate-docs: ${file} is stale; run: task site:docs:generate`);
      stale = 1;
    } else {
      writeFileSync(path, page);
      console.log(`generate-docs: wrote ${file}`);
    }
  }
  const options = readFileSync(join(DOCS, 'reference/options.md'), 'utf8');
  for (const n of missingOptionAnchors(options, feature)) {
    console.error(`generate-docs: reference/options.md has no heading {#opt-${n}}`);
    stale = 1;
  }
  return check || stale ? stale : 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    console.error(`generate-docs: ${e.message}`);
    process.exit(2);
  }
}
