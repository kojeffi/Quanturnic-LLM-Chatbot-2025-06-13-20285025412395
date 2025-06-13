import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { fileURLToPath, URL } from 'node:url';
import environment from 'vite-plugin-environment';

export default defineConfig({
  base: '/',
  plugins: [
    react({
      // Only include babel config if you're using Emotion
      // babel: {
      //   plugins: ['@emotion/babel-plugin']
      // }
    }),
    environment('all', { prefix: 'CANISTER_' }),
    environment('all', { prefix: 'DFX_' })
  ],
  envDir: '../',
  define: {
    'process.env': {},
    global: 'globalThis',
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'production')
  },
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      '@dfinity/principal',
      '@dfinity/agent'
    ],
    esbuildOptions: {
      define: {
        global: 'globalThis'
      },
      loader: {
        '.js': 'jsx'
      },
      plugins: [
        {
          name: 'fix-node-globals-polyfill',
          setup(build) {
            build.onResolve({ filter: /_virtual-process-env/ }, () => {
              return { path: '/_virtual-process-env', namespace: 'file' };
            });
          }
        }
      ]
    }
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    assetsInlineLimit: 0,
    sourcemap: process.env.NODE_ENV !== 'production',
    rollupOptions: {
      input: fileURLToPath(new URL('./index.html', import.meta.url)),
      output: {
        entryFileNames: 'assets/[name].[hash].js',
        chunkFileNames: 'assets/[name].[hash].js',
        assetFileNames: 'assets/[name].[hash].[ext]',
        manualChunks: (id) => {
          if (id.includes('node_modules')) {
            if (id.includes('@dfinity')) return 'dfinity';
            if (id.includes('framer-motion')) return 'framer-motion';
            return 'vendor';
          }
        }
      }
    },
    commonjsOptions: {
      transformMixedEsModules: true,
      include: [/node_modules/, /src\/declarations/]
    }
  },
  resolve: {
    alias: [
      {
        find: 'declarations',
        replacement: fileURLToPath(new URL('../src/declarations', import.meta.url))
      },
      {
        find: '@',
        replacement: fileURLToPath(new URL('./src', import.meta.url))
      },
      {
        find: 'stream',
        replacement: 'stream-browserify'
      },
      {
        find: 'buffer',
        replacement: 'buffer/'
      }
    ]
  },
  server: {
    port: 3000,
    strictPort: true,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Content-Security-Policy": "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: https:",
      "X-Content-Type-Options": "nosniff"
    },
    proxy: {
      '/api': {
        target: 'http://localhost:4943',
        changeOrigin: true,
        secure: false
      }
    }
  }
});