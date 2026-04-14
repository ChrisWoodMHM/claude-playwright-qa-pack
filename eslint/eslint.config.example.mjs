// ESLint flat config for Playwright + TypeScript projects.
// Drop this in your repo as `eslint.config.mjs` (ESLint 9+ flat config).
//
// Install peer deps:
//   npm install -D eslint typescript-eslint eslint-plugin-playwright
//
// The `@typescript-eslint/no-floating-promises` rule requires type-aware parsing,
// enabled below via `projectService: true`. This rule mechanically catches missing
// `await` on Playwright calls — the #1 cause of E2E flakiness.

import tseslint from 'typescript-eslint';
import playwright from 'eslint-plugin-playwright';

export default [
  {
    ignores: ['test-results/**', 'playwright-report/**', 'node_modules/**', 'dist/**', 'build/**'],
  },

  // TypeScript defaults applied to all .ts files
  ...tseslint.configs.recommended.map((config) => ({
    ...config,
    files: ['**/*.ts'],
  })),

  // Playwright rules applied to spec files
  {
    ...playwright.configs['flat/recommended'],
    files: ['**/*.spec.ts', '**/*.spec.js'],
  },

  // Project-wide TS rules with type-aware parsing
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      '@typescript-eslint/no-require-imports': 'off',

      // Catches missing `await` on Playwright async APIs. Requires the type-aware
      // parser enabled above. This rule alone prevents the majority of flaky-test
      // incidents — do not disable it.
      '@typescript-eslint/no-floating-promises': 'error',
    },
  },

  // Playwright-specific rules on spec files
  {
    files: ['**/*.spec.ts', '**/*.spec.js'],
    rules: {
      'playwright/missing-playwright-await': 'error',
      'playwright/no-focused-test': 'error',
      'playwright/no-page-pause': 'error',
      'playwright/valid-expect': 'error',

      'playwright/no-wait-for-timeout': 'warn',
      'playwright/no-element-handle': 'warn',
      'playwright/no-eval': 'warn',
      'playwright/prefer-web-first-assertions': 'warn',
      'playwright/prefer-strict-equal': 'warn',
      'playwright/prefer-to-have-count': 'warn',
      'playwright/prefer-to-have-length': 'warn',
      'playwright/prefer-to-contain': 'warn',
      'playwright/valid-title': 'warn',

      // Allow conditional skip guards, disallow committed unconditional skips
      'playwright/no-skipped-test': ['warn', { allowConditional: true }],

      // Turn these off if your codebase uses them as intentional patterns
      'playwright/no-conditional-in-test': 'off',
      'playwright/no-conditional-expect': 'off',
    },
  },
];
