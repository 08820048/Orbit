import { defineConfig } from 'astro/config';

// Static output, deployed to Cloudflare Pages (see docs/WEBSITE.md).
export default defineConfig({
  site: 'https://orbit-mac.pages.dev',
  trailingSlash: 'ignore',
  build: { format: 'directory' },
});
