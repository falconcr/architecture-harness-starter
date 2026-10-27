// Lint minimo: el objetivo del repo es mostrar gates deterministas, no imponer un estilo.
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'node_modules', '*.config.js', '.dependency-cruiser.js'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      'no-console': 'off',
      '@typescript-eslint/consistent-type-imports': 'error',
    },
  },
);
