import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { resolve } from 'path';

/**
 * Vite config for the API management dashboard.
 *
 * - `build.outDir` points at a `dist` folder inside this client dir; the
 *   server serves it statically from `/admin` (see src/index.ts).
 * - The dev server proxies `/api` to the game server (default :3001) so the
 *   dashboard talks to a live backend during development.
 * - `base: './'` keeps the built index.html portable regardless of mount path.
 *
 * Run dev:   `npm run admin:dev`  (from packages/server)
 * Run build: `npm run admin:build`
 */
export default defineConfig({
  plugins: [vue()],
  base: './',
  root: resolve(__dirname),
  resolve: {
    alias: {
      '@admin': resolve(__dirname),
    },
  },
  build: {
    outDir: resolve(__dirname, 'dist'),
    emptyOutDir: true,
    target: 'es2020',
    sourcemap: false,
  },
  server: {
    port: 3010,
    proxy: {
      '/api': {
        target: 'http://localhost:3001',
        changeOrigin: true,
      },
    },
  },
});
