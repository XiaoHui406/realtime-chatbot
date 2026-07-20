import { defineConfig, UserConfig } from 'vite';
import path from 'path';

const sdkPath = path.resolve(__dirname, 'CubismSdkForWeb-5-r.5');

export default defineConfig((): UserConfig => {
  return {
    root: './',
    base: '/',
    resolve: {
      extensions: ['.ts', '.js'],
      alias: {
        '@framework': path.resolve(sdkPath, 'Framework/src'),
      },
    },
    build: {
      target: 'baseline-widely-available',
      assetsDir: 'assets',
      outDir: './dist',
      sourcemap: false,
      modulePreload: false,
      rollupOptions: {
        output: {
          entryFileNames: 'assets/[name].js',
          chunkFileNames: 'assets/[name].js',
          assetFileNames: 'assets/[name].[ext]',
        },
      },
    },
  };
});
