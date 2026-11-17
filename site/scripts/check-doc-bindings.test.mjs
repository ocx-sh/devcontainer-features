// Offline: the binding checker goes red on each planted violation and stays green on the clean fixture.
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { check, examples, parseJsonc } from './check-doc-bindings.mjs';

const REF = 'ghcr.io/ocx-sh/devcontainer-features/ocx:1';
const JSONC = ['```jsonc', '{', '  // a comment', '  "image": "debian:stable-slim",', '  "features": { "' + REF + '": { "pull": false } }', '}', '```'].join('\n');
const CONSOLE = ['```console', 'ocx-feature: warning: ocx pull failed with exit code 78.', '  fix: run "ocx lock" in the project', '```'].join('\n');
const BASH = ['```bash', 'ocx version', 'ocx about', '```'].join('\n');
const NORUN = ['<!-- doc-norun: needs a proxy -->', '<!-- doc: proxy -->', '```jsonc', '{ "features": { "' + REF + '": {} } }', '```', '<!-- /doc-norun -->'].join('\n');

// A repository with three examples (jsonc, console, bash), one norun example and the tests behind them.
function repo({ pages = {}, bindings = {}, scenarios = {}, failures = {}, files = {} } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'docbind-'));
  const put = (p, text) => {
    mkdirSync(dirname(join(root, p)), { recursive: true });
    writeFileSync(join(root, p), text);
  };
  const base = {
    pages: { 'a.md': `<!-- doc: opt -->\n${JSONC}\n\n<!-- doc: warn -->\n${CONSOLE}\n\n<!-- doc: cmds -->\n${BASH}\n\n${NORUN}\n`, ...pages },
    bindings: {
      opt: { kind: 'scenario', test: 'pull-off' },
      warn: { kind: 'unit', test: 'hook.bats::no lock', expect: ['exit code 78.', 'fix: run "ocx lock" in the project'] },
      cmds: { kind: 'scenario', test: 'pull-off' },
      proxy: { kind: 'norun', reason: 'needs a proxy' },
      ...bindings,
    },
  };
  for (const [name, text] of Object.entries(base.pages)) put(`site/src/content/docs/${name}`, text);
  put('test/docs/bindings.json', JSON.stringify(base.bindings));
  put('test/ocx/scenarios.json', JSON.stringify({ 'pull-off': { image: 'debian:stable-slim', features: { ocx: { pull: false } } }, ...scenarios }));
  put('test/ocx/pull-off.sh', '#!/bin/sh\nocx version\nocx about\n');
  put('test/images/failures.json', JSON.stringify(failures));
  put('test/images.txt', '# images\ndebian debian:stable-slim\n');
  put('test/unit/hook.bats', '@test "no lock" {\n  assert_output --partial \'exit code 78.\'\n  assert_output --partial \'fix: run "ocx lock" in the project\'\n}\n');
  for (const [p, text] of Object.entries(files)) put(p, text);
  return root;
}

const has = (findings, re) => assert.ok(findings.some((f) => re.test(f)), `no finding matches ${re}:\n${findings.join('\n')}`);

test('the clean fixture has no findings', () => {
  assert.deepEqual(check(repo()), []);
});

test('a key on a page with no binding is reported', () => {
  const root = repo({ pages: { 'b.md': '<!-- doc: loose -->\n```bash\nocx version\n```\n' } });
  has(check(root), /'loose': no binding/);
});

test('a binding that names no page key is reported', () => {
  has(check(repo({ bindings: { ghost: { kind: 'norun', reason: 'x' } } })), /binding 'ghost' names a key no page carries/);
});

test('a bound scenario, failure, unit test or image alias that does not exist is reported', () => {
  has(check(repo({ bindings: { opt: { kind: 'scenario', test: 'no-such' } } })), /scenario 'no-such' is not in test\/ocx\/scenarios.json/);
  has(check(repo({ bindings: { warn: { kind: 'failure', test: 'fail-no-such' } } })), /failure 'fail-no-such' is not in/);
  has(check(repo({ bindings: { warn: { kind: 'unit', test: 'hook.bats::renamed', expect: ['x'] } } })), /has no test named "renamed"/);
  has(check(repo({ bindings: { opt: { kind: 'image', test: 'nope' } } })), /image alias 'nope' is not in test\/images.txt/);
});

test('a drifted fence is reported: options, image and an unchecked key', () => {
  const drift = (s) => ({ 'a.md': `<!-- doc: opt -->\n${s}\n` });
  const bindings = { warn: { kind: 'norun', reason: 'x' }, cmds: { kind: 'norun', reason: 'x' }, proxy: { kind: 'norun', reason: 'x' } };
  has(check(repo({ pages: drift(JSONC.replace('"pull": false', '"pull": true')), bindings })), /feature options differ/);
  has(check(repo({ pages: drift(JSONC.replace('debian:stable-slim', 'alpine:3')), bindings })), /image differs/);
  has(check(repo({ pages: drift(JSONC.replace('"image"', '"postCreateCommand": "x", "image"')), bindings })), /'postCreateCommand', which no test compares/);
});

test('an image difference stated with a reason passes, a stale reason does not', () => {
  const alpine = repo({ pages: { 'a.md': `<!-- doc: opt -->\n${JSONC.replace('debian:stable-slim', 'alpine:3')}\n` }, bindings: { opt: { kind: 'scenario', test: 'pull-off', imageReason: 'smaller' }, warn: { kind: 'norun', reason: 'x' }, cmds: { kind: 'norun', reason: 'x' }, proxy: { kind: 'norun', reason: 'x' } } });
  assert.ok(!check(alpine).some((f) => /image differs/.test(f)));
  has(check(repo({ bindings: { opt: { kind: 'scenario', test: 'pull-off', imageReason: 'stale' } } })), /imageReason is set but the images are equal/);
});

test('a console fragment the test does not assert, or the page does not show, is reported', () => {
  has(check(repo({ bindings: { warn: { kind: 'unit', test: 'hook.bats::no lock', expect: ['exit code 78.', 'fix: run "ocx lock" in the project', 'a new sentence'] } } })), /not in the fence: "a new sentence"/);
  const quiet = { 'test/unit/hook.bats': '@test "no lock" {\n  assert_output --partial \'exit code 78.\'\n}\n' };
  has(check(repo({ files: quiet })), /the test never asserts: "fix: run \\"ocx lock\\" in the project"/);
});

test('a console line that is neither asserted nor skipped is reported, a skip with a reason is not', () => {
  const extra = { 'a.md': `<!-- doc: warn -->\n${CONSOLE.replace('```console', '```console\nerror: ocx.lock not found')}\n` };
  const rest = { opt: { kind: 'norun', reason: 'x' }, cmds: { kind: 'norun', reason: 'x' }, proxy: { kind: 'norun', reason: 'x' } };
  const warn = { kind: 'unit', test: 'hook.bats::no lock', expect: ['exit code 78.', 'fix: run "ocx lock" in the project'] };
  has(check(repo({ pages: extra, bindings: { ...rest, warn } })), /neither asserted by an expect fragment nor skipped/);
  const skipped = check(repo({ pages: extra, bindings: { ...rest, warn: { ...warn, skip: [{ line: 'ocx.lock not found', reason: 'ocx text' }] } } }));
  assert.deepEqual(skipped.filter((f) => /'warn'/.test(f)), []);
});

test('a command the bound script does not run is reported', () => {
  has(check(repo({ files: { 'test/ocx/pull-off.sh': '#!/bin/sh\nocx version\n' } })), /command is not in the bound script: ocx about/);
});

test('a failure entry carries the page text: message and also lines must be in the fence', () => {
  const failures = { 'fail-x': { image: 'debian:stable-slim', options: {}, exit: 2, message: 'ocx pull failed with exit code 78.', also: ['  fix: run "ocx lock" in the project'] } };
  has(check(repo({ failures, bindings: { warn: { kind: 'failure', test: 'fail-x' } } })), /not in the fence: "ocx-feature: error: ocx pull failed/);
  const bad = { 'fail-x': { ...failures['fail-x'], also: ['  fix: something else'] } };
  has(check(repo({ failures: bad, bindings: { warn: { kind: 'failure', test: 'fail-x' } } })), /not in the fence: "  fix: something else"/);
});

test('a norun binding needs a reason and the page marker with the same reason', () => {
  has(check(repo({ bindings: { proxy: { kind: 'norun' } } })), /needs a reason/);
  has(check(repo({ bindings: { proxy: { kind: 'norun', reason: 'other reason' } } })), /reason differs/);
  const bare = { 'a.md': `<!-- doc: proxy -->\n\`\`\`jsonc\n{}\n\`\`\`\n` };
  has(check(repo({ pages: bare, bindings: { opt: { kind: 'norun', reason: 'x' }, warn: { kind: 'norun', reason: 'x' }, cmds: { kind: 'norun', reason: 'x' } } })), /inside <!-- doc-norun: reason -->/);
});

test('one key on two pages with different fences is reported', () => {
  const other = { 'b.md': `<!-- doc: opt -->\n${JSONC.replace('false', 'true')}\n` };
  has(check(repo({ pages: other })), /'opt' also sits on .* with a different fence/);
});

test('a marker below its fence binds that fence, a marker with no fence is reported', () => {
  assert.equal(examples('```bash\nocx version\n```\n<!-- doc: below -->\n').found[0].fence.body[0], 'ocx version');
  assert.equal(examples('text\n\n<!-- doc: none -->\n\nmore text\n').found[0].fence, undefined);
});

test('jsonc comments and trailing commas parse, strings with slashes survive', () => {
  assert.deepEqual(parseJsonc('{\n // c\n "a": "https://x.test", // t\n "b": [1,],\n}'), { a: 'https://x.test', b: [1] });
});
