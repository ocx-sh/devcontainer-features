// Offline: the page generators turn their sources into tables and refuse a page that is stale.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { changelogRegion, imagesRegion, missingOptionAnchors, optionsRegion, parityRegions, replaceRegion } from './generate-docs.mjs';

const feature = {
  options: {
    libc: { type: 'string', default: 'musl', enum: ['musl', 'gnu'], description: 'Flavour | of the binary.' },
    pull: { type: 'boolean', default: true, description: 'Restore.' },
    path: { type: 'string', default: '', proposals: ['a'], description: 'Path.' },
  },
};

test('options table lists type, default and allowed values in file order', () => {
  const rows = optionsRegion(feature).split('\n');
  assert.equal(rows.length, 5);
  assert.match(rows[2], /^\| \[`libc`\]\(#opt-libc\) \| string \| `musl` \| `musl`, `gnu` \| Flavour \\\| of the binary\. \|$/);
  assert.match(rows[3], /\| boolean \| `true` \| `true`, `false` \|/);
  assert.match(rows[4], /\| `""` \| Any string; suggested `a` \|/);
});

test('parity tables link an option and say none otherwise', () => {
  const r = parityRegions({ variables: [{ name: 'OCX_X', status: 'fixed', note: 'n' }, { name: 'OCX_Y', status: 'exposed', option: 'libc', note: 'm' }], featureOnly: [{ option: 'pull', note: 'p' }] });
  assert.match(r['parity-variables'], /`OCX_X` \| fixed \| none \| n/);
  assert.match(r["parity-variables"], /\[`libc`\]\(options\.md#opt-libc\)/);
  assert.match(r['parity-feature-only'], /\[`pull`\]/);
});

test('images region reads alias, reference and an optional platform, skipping comments', () => {
  const t = imagesRegion('# c\n\ndebian debian:stable-slim\narch archlinux amd64\n').split('\n');
  assert.equal(t.length, 4);
  assert.match(t[2], /`debian` \| `debian:stable-slim` \| amd64 and arm64/);
  assert.match(t[3], /amd64 only/);
});

test('changelog region drops the H1', () => {
  assert.equal(changelogRegion('# Changelog\n\nIntro.\n\n## 1.0.0\n'), 'Intro.\n\n## 1.0.0');
});

test('replaceRegion swaps the body, is idempotent and rejects a missing marker', () => {
  const page = 'a\n<!-- generated:x:start -->\nold\n<!-- generated:x:end -->\nb\n';
  const once = replaceRegion(page, 'x', 'NEW');
  assert.equal(once, 'a\n<!-- generated:x:start -->\n\nNEW\n\n<!-- generated:x:end -->\nb\n');
  assert.equal(replaceRegion(once, 'x', 'NEW'), once);
  assert.throws(() => replaceRegion('no markers', 'x', 'NEW'), /region x/);
});

test('an option without a heading anchor is reported', () => {
  assert.deepEqual(missingOptionAnchors('## libc {#opt-libc}\n', feature), ['pull', 'path']);
});
