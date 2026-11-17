// Binds every documentation example to the test that backs it (DOC-EX-01, DOC-EX-02, DOC-EX-06).
// A page marks an example with `<!-- doc: <slug> -->` above its code fence (below it on the landing page).
// test/docs/bindings.json holds exactly one binding per slug, and this script fails when
//   - a slug on a page has no binding, or a binding names a slug no page carries;
//   - the bound test does not exist (scenario, failure entry, bats test, image alias);
//   - the same slug sits on two pages with different fences, or a marker has no fence;
//   - a `norun` binding has no reason, or the page's fence is not inside a `doc-norun` pair with that reason;
//   - the fence and the test have drifted apart:
//       jsonc    feature options, and image, users and environment where the page states them, equal the scenario's
//       console  every line holds an `expect` fragment, and each fragment is in the fence and in the test
//       bash     every command line is in the bound script
// Binding: { kind: scenario|failure|unit|image|norun, test, expect[], normalize[[regex, to]], imageReason,
//            unchecked{key: reason}, reason }. `normalize` rewrites volatile text on both sides before any comparison.
// Usage: node scripts/check-doc-bindings.mjs [--root REPO]   (run from anywhere; default root is this repository)
// Exit: 0 clean, 1 findings, 2 usage or a missing input.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const FEATURE_REF = /^ghcr\.io\/ocx-sh\/devcontainer-features\/ocx(:[^/]+)?$/;
const COMPARED = ['image', 'containerUser', 'remoteUser', 'containerEnv', 'features'];
const KINDS = ['scenario', 'failure', 'unit', 'image', 'norun'];
const MARKER = /^<!--\s*doc:\s*([a-z0-9-]+)\s*-->\s*$/;
const FENCE = /^(`{3,}|~{3,})\s*([^\s`]*)/;
const NORUN_OPEN = /^<!--\s*doc-norun\s*:\s*(.*?)\s*-->\s*$/;
const NORUN_CLOSE = /^<!--\s*\/doc-norun\s*-->\s*$/;

const walk = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name);
    return e.isDirectory() ? walk(p) : /\.mdx?$/.test(e.name) ? [p] : [];
  });

// examples(text): every marker with its fence { slug, line, lang, body, fenceLine } and the norun regions [{from, to, reason}].
export function examples(text) {
  const lines = text.split('\n');
  const fences = [];
  const markers = [];
  const norun = [];
  let open = null;
  let region = null;
  lines.forEach((l, i) => {
    if (open) {
      if (l.startsWith(open.marker) && l.slice(open.marker.length).trim() === '') {
        open.end = i + 1;
        fences.push(open);
        open = null;
      } else open.body.push(l);
      return;
    }
    const f = FENCE.exec(l);
    if (f) return void (open = { marker: f[1], lang: f[2], body: [], start: i + 1 });
    const m = MARKER.exec(l);
    if (m) markers.push({ slug: m[1], line: i + 1 });
    const o = NORUN_OPEN.exec(l);
    if (o) region = { from: i + 1, reason: o[1].replace(/^:\s*/, '') };
    if (NORUN_CLOSE.test(l) && region) norun.push({ ...region, to: i + 1 }), (region = null);
  });
  const blank = (n) => !lines[n - 1]?.trim();
  const found = markers.map((m) => {
    let n = m.line + 1;
    while (n <= lines.length && blank(n)) n++;
    let fence = fences.find((f) => f.start === n);
    if (!fence) {
      n = m.line - 1;
      while (n > 0 && blank(n)) n--;
      fence = fences.find((f) => f.end === n);
    }
    return { ...m, fence };
  });
  return { found, norun };
}

// jsonc: strip whole-line and trailing comments that sit outside strings, then parse.
export function parseJsonc(src) {
  const out = src
    .split('\n')
    .map((l) => l.replace(/^\s*\/\/.*$/, '').replace(/("(?:[^"\\]|\\.)*")|\/\/.*$/g, (m, s) => s ?? ''))
    .join('\n')
    .replace(/,(\s*[}\]])/g, '$1');
  return JSON.parse(out);
}

const stable = (v) => JSON.stringify(v, (_, x) => (x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1))) : x));

export function check(repo) {
  const findings = [];
  const add = (file, line, msg) => findings.push(`${relative(repo, file) || file}:${line}: DOC-EX-02: ${msg}`);
  const read = (p) => readFileSync(join(repo, p), 'utf8');
  const docs = join(repo, 'site/src/content/docs');
  const bindingsFile = join(repo, 'test/docs/bindings.json');
  const bindings = JSON.parse(read('test/docs/bindings.json'));
  const scenarios = JSON.parse(read('test/ocx/scenarios.json'));
  const failures = JSON.parse(read('test/images/failures.json'));
  const images = Object.fromEntries(
    read('test/images.txt')
      .split('\n')
      .filter((l) => l.trim() && !l.startsWith('#'))
      .map((l) => l.trim().split(/\s+/))
      .map(([alias, ref]) => [alias, ref]),
  );

  const seen = new Map();
  for (const file of walk(docs).sort()) {
    const { found, norun } = examples(readFileSync(file, 'utf8'));
    for (const ex of found) {
      if (!ex.fence) {
        add(file, ex.line, `doc key '${ex.slug}' has no code fence next to it`);
        continue;
      }
      const body = ex.fence.body.join('\n');
      const prior = seen.get(ex.slug);
      if (prior && prior.body !== body) add(file, ex.line, `doc key '${ex.slug}' also sits on ${relative(repo, prior.file)}:${prior.line} with a different fence`);
      else if (prior) add(file, ex.line, `doc key '${ex.slug}' appears twice (also ${relative(repo, prior.file)}:${prior.line})`);
      else seen.set(ex.slug, { file, line: ex.line, body, lang: ex.fence.lang, fenceLine: ex.fence.start, norun: norun.find((r) => r.from < ex.fence.start && ex.fence.end < r.to) });
    }
  }

  for (const slug of Object.keys(bindings)) if (!seen.has(slug)) add(bindingsFile, 1, `binding '${slug}' names a key no page carries`);

  for (const [slug, ex] of seen) {
    const b = bindings[slug];
    const here = (msg) => add(ex.file, ex.line, `'${slug}': ${msg}`);
    if (!b) {
      here(`no binding in test/docs/bindings.json; add one that names the test backing this example`);
      continue;
    }
    if (!KINDS.includes(b.kind)) {
      here(`binding kind '${b.kind}' is not one of ${KINDS.join(', ')}`);
      continue;
    }
    if (b.kind === 'norun') {
      if (!b.reason?.trim()) here('a norun binding needs a reason');
      else if (!ex.norun) here(`a norun example sits inside <!-- doc-norun: reason --> and <!-- /doc-norun --> on its page`);
      else if (ex.norun.reason !== b.reason) here(`the page's doc-norun reason differs from the binding's ("${ex.norun.reason}" vs "${b.reason}")`);
      continue;
    }
    if (ex.norun) here('the fence sits in a doc-norun region but its binding is not norun');

    const norm = (b.normalize ?? []).map(([re, to]) => [new RegExp(re, 'g'), to]);
    const canon = (s) => norm.reduce((t, [re, to]) => t.replace(re, to), s);

    // the test: its source text, and for a scenario its configuration
    let source = '';
    let conf = null;
    let derived = [];
    if (b.kind === 'scenario' || b.kind === 'image') {
      let script;
      if (b.kind === 'scenario') {
        conf = scenarios[b.test];
        script = `test/ocx/${b.test}.sh`;
        if (!conf) here(`scenario '${b.test}' is not in test/ocx/scenarios.json`);
      } else {
        const ref = images[b.test];
        script = 'test/ocx/test.sh';
        if (!ref) here(`image alias '${b.test}' is not in test/images.txt`);
        else conf = { image: ref, features: { ocx: {} } };
      }
      if (!existsSync(join(repo, script))) here(`${script} does not exist`);
      else source = read(script);
      if (!conf) continue;
    } else if (b.kind === 'failure') {
      const f = failures[b.test];
      if (!f) {
        here(`failure '${b.test}' is not in test/images/failures.json`);
        continue;
      }
      derived = [`ocx-feature: error: ${f.message}`, ...(f.also ?? [])];
      source = derived.join('\n');
    } else {
      const [file, name] = String(b.test).split('::');
      const p = `test/unit/${file}`;
      if (!name || !existsSync(join(repo, p))) {
        here(`unit test '${b.test}' must read <file>.bats::<test name> and the file must exist under test/unit`);
        continue;
      }
      const lines = read(p).split('\n');
      const at = lines.findIndex((l) => l.startsWith(`@test "${name}" {`));
      if (at < 0) {
        here(`${p} has no test named "${name}"`);
        continue;
      }
      let end = at + 1;
      while (end < lines.length && lines[end] !== '}') end++;
      source = lines.slice(at, end + 1).join('\n');
    }

    const fenceText = canon(ex.body);
    const testText = canon(source);
    const lang = ex.lang;

    if (lang === 'jsonc' || lang === 'json') {
      if (!conf) {
        here('a json example needs a scenario or image test that carries the options');
        continue;
      }
      let page;
      try {
        page = parseJsonc(ex.body);
      } catch (e) {
        here(`the fence is not valid JSON with comments: ${e.message}`);
        continue;
      }
      const refs = Object.keys(page.features ?? {});
      if (refs.length !== 1 || !FEATURE_REF.test(refs[0])) {
        here('the fence must name exactly one feature, ghcr.io/ocx-sh/devcontainer-features/ocx:<tag>');
        continue;
      }
      const want = canon(stable(page.features[refs[0]]));
      const got = canon(stable(conf.features?.ocx ?? {}));
      if (want !== got) here(`feature options differ: page ${want}, test ${got}`);
      if (b.kind === 'image' && want !== '{}') here('an image test runs the default options, but the page sets options');
      for (const key of ['containerUser', 'remoteUser', 'containerEnv']) {
        if (key in page && canon(stable(page[key])) !== canon(stable(conf[key]))) here(`${key} differs: page ${stable(page[key])}, test ${stable(conf[key])}`);
      }
      if ('image' in page) {
        const same = canon(page.image) === canon(conf.image ?? '');
        if (!same && !b.imageReason) here(`image differs: page ${page.image}, test ${conf.image}; run the page's image or state imageReason`);
        if (same && b.imageReason) here('imageReason is set but the images are equal; remove it');
      } else if (b.imageReason) here('imageReason is set but the page states no image; remove it');
      const extra = Object.keys(page).filter((k) => !COMPARED.includes(k));
      for (const k of extra) if (!b.unchecked?.[k]) here(`the fence has '${k}', which no test compares; name it in "unchecked" with a reason`);
      for (const k of Object.keys(b.unchecked ?? {})) if (!extra.includes(k)) here(`unchecked '${k}' is not in the fence; remove it`);
    } else if (lang === 'console') {
      const expect = [...derived, ...(b.expect ?? [])].filter((s) => s.trim());
      const fragments = [...new Set(expect.map(canon))];
      if (!fragments.length) here('a console example needs "expect" fragments the test asserts');
      for (const frag of fragments) {
        if (!fenceText.includes(frag)) here(`expected text is not in the fence: ${JSON.stringify(frag)}`);
        if (!testText.includes(frag)) here(`the test never asserts: ${JSON.stringify(frag)}`);
      }
      const skips = b.skip ?? [];
      for (const s of skips) if (!s.reason?.trim() || !s.line) here(`a skip needs "line" and "reason": ${JSON.stringify(s)}`);
      fenceText.split('\n').forEach((line, i) => {
        if (!line.trim()) return;
        const covered = fragments.some((f) => line.includes(f)) || skips.some((s) => s.line && canon(line).includes(canon(s.line)) && s.reason?.trim());
        if (!covered) add(ex.file, ex.fenceLine + 1 + i, `'${slug}': this line is neither asserted by an expect fragment nor skipped with a reason: ${line.trim()}`);
      });
    } else if (lang === 'bash' || lang === 'sh') {
      if (b.kind === 'failure' || b.kind === 'unit') here('a command example is bound to a scenario or image script that runs the same commands');
      ex.body.split('\n').filter((l) => l.trim() && !l.trim().startsWith('#')).forEach((cmd) => {
        if (!testText.includes(canon(cmd.trim()))) here(`the command is not in the bound script: ${cmd.trim()}`);
      });
    } else here(`no content binding exists for a '${lang}' fence`);
  }
  return findings;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const i = args.indexOf('--root');
  const repo = resolve(i >= 0 ? args[i + 1] : join(dirname(fileURLToPath(import.meta.url)), '../..'));
  if (!existsSync(join(repo, 'test/docs/bindings.json'))) {
    console.error(`check-doc-bindings: ${repo}/test/docs/bindings.json is missing`);
    process.exit(2);
  }
  const findings = check(repo);
  for (const f of findings) console.log(f);
  console.log(`check-doc-bindings: ${findings.length} finding${findings.length === 1 ? '' : 's'}`);
  process.exit(findings.length ? 1 : 0);
}
