import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // El dominio tiene que poder testearse sin red, sin base de datos y sin cluster (ADR-001).
    globals: false,
    coverage: {
      include: ['src/**/*.ts'],
      reporter: ['text', 'lcov'],
    },
  },
});
