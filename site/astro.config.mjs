// The ocx Dev Container Feature section of ocx.sh: `/integrations/devcontainer/` (a claim in the theme's nav.json).
import { existsSync } from 'node:fs';
import starlight from '@astrojs/starlight';
import ocxTheme from '@ocx-sh/theme/starlight';
import { defineConfig } from 'astro/config';

const DOCS = new URL('./src/content/docs/', import.meta.url);
const exists = (slug) => ['.md', '.mdx'].some((ext) => existsSync(new URL(`${slug}${ext}`, DOCS)));

// Groups follow the page plan (.agents/discovery/writer-inventory.md section 4). A directory group lists whatever
// pages sit in its folder, so a new page needs no edit here; order inside a group is the page's `sidebar.order`,
// then its file name. The first-steps group lists its pages by slug, once they exist, in its own top-level group
// (DOC-DISC-21).
const sidebar = [
  { label: 'Get started', items: ['index', 'quickstart'].filter(exists).map((slug) => ({ slug })) },
  { label: 'Guides', items: [{ autogenerate: { directory: 'guides' } }] },
  { label: 'Integrate', items: [{ autogenerate: { directory: 'integrate' } }] },
  { label: 'Concepts', items: [{ autogenerate: { directory: 'concepts' } }] },
  { label: 'Troubleshooting', items: [{ autogenerate: { directory: 'troubleshooting' } }] },
  { label: 'Reference', items: [{ autogenerate: { directory: 'reference' } }, ...['changelog'].filter(exists).map((slug) => ({ slug }))] },
];

export default defineConfig({
  base: '/integrations/devcontainer/',
  // Starlight reads it before plugins run, so the theme checks it rather than sets it.
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  integrations: [
    starlight({
      title: 'ocx Dev Container Feature',
      description: 'Install ocx in a dev container and restore the project toolchain with one line in devcontainer.json.',
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/ocx-sh/devcontainer-features' }],
      plugins: [ocxTheme()],
      sidebar,
    }),
  ],
});
