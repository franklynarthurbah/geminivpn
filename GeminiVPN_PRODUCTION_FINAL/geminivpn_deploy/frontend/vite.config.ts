import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

export default defineConfig({
  base: '/',
  plugins: [react()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
  build: {
    // FIX 11a: Target modern evergreen browsers — enables smaller/faster output
    // ES2022 = async/await native, optional chaining, nullish coalescing, etc.
    // No polyfills needed → smaller bundle → faster parse → faster first paint
    target: 'es2022',

    // FIX 11b: Disable sourcemaps in production — eliminates extra .map files
    // (saves ~2-3x bundle size overhead from source map generation)
    sourcemap: false,

    // FIX 11c: Inline small assets directly into JS/CSS to save HTTP round-trips
    assetsInlineLimit: 4096,

    // Keep chunk warning threshold reasonable
    chunkSizeWarningLimit: 600,

    rollupOptions: {
      output: {
        // FIX 11d: Manual chunks — split vendor code so it's cached independently
        // Users re-downloading only changed chunks, not full bundle
        manualChunks: {
          'react-core':  ['react', 'react-dom'],
          'gsap':        ['gsap'],
          'radix-ui':    [
            '@radix-ui/react-dialog',
            '@radix-ui/react-accordion',
            '@radix-ui/react-select',
          ],
          'lucide':      ['lucide-react'],
          'sonner':      ['sonner'],
        },
        // Use content-hash in filenames for aggressive browser caching
        entryFileNames:  'assets/[name]-[hash].js',
        chunkFileNames:  'assets/[name]-[hash].js',
        assetFileNames:  'assets/[name]-[hash][extname]',
      },
    },

    // FIX 11e: Enable esbuild minification (faster than terser, equally good)
    minify: 'esbuild',
  },

  // FIX 11f: esbuild options — drop console.log in production
  esbuild: {
    drop: ['console', 'debugger'],
    legalComments: 'none',
  },

  server: {
    port: 5173,
    open: true,
    // Enable HTTP/2 in dev for realistic perf testing
    strictPort: true,
  },
})
