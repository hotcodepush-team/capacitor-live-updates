export default {
  input: 'dist/esm/index.js',
  output: [
    {
      file: 'dist/plugin.js',
      format: 'iife',
      name: 'capacitorHotCodePush',
      globals: { '@capacitor/core': 'capacitorExports' },
      sourcemap: true,
    },
    {
      file: 'dist/plugin.cjs.js',
      format: 'cjs',
      sourcemap: true,
    },
  ],
  external: ['@capacitor/core'],
};
