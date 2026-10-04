import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// Built into the backend's public folder: the API serves the back-office at
// /admin, same origin as /api, so there is no CORS and no second server.
export default defineConfig({
  base: '/admin/',
  plugins: [react()],
  build: {
    outDir: '../backend/public/admin',
    emptyOutDir: true,
  },
  server: {
    port: 5180,
    proxy: { '/api': process.env.ADMIN_API ?? 'http://localhost:3099' },
  },
});
