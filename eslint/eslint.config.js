/**
 * Shared ESLint flat config (ESLint 9+)
 *
 * Usage in consuming repos:
 *   import baseConfig from '../agentGuidance/eslint/eslint.config.js';
 *   export default [...baseConfig];
 *
 * See README.md in this directory for full setup instructions.
 */

const baseRules = {
  "no-unused-vars": "warn",
  "no-console": "warn",
  eqeqeq: ["error", "always"],
  curly: ["error", "all"],
  "prefer-const": "error",
  "no-var": "error",
};

const baseConfig = [
  // Global ignores
  {
    ignores: ["**/node_modules/**", "**/dist/**", "**/build/**", "**/coverage/**"],
  },

  // Base config for all JS/JSX files
  {
    files: ["**/*.{js,jsx,mjs,cjs}"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
    },
    rules: {
      ...baseRules,
    },
  },

  // TypeScript overrides (requires @typescript-eslint/eslint-plugin and typescript-eslint)
  // Consumers using TypeScript should install:
  //   npm install -D typescript-eslint @typescript-eslint/parser
  // Then spread tsConfig into their config array.
];

/**
 * TypeScript config block. Import separately if your repo uses TypeScript.
 *
 *   import { tsConfig } from '../agentGuidance/eslint/eslint.config.js';
 *   import tseslint from 'typescript-eslint';
 *   export default [...baseConfig, ...tsConfig(tseslint)];
 */
export function tsConfig(tseslint) {
  return [
    {
      files: ["**/*.{ts,tsx,mts,cts}"],
      languageOptions: {
        parser: tseslint.parser,
      },
      plugins: {
        "@typescript-eslint": tseslint.plugin,
      },
      rules: {
        ...baseRules,
        // Swap no-unused-vars for the TS-aware version
        "no-unused-vars": "off",
        "@typescript-eslint/no-unused-vars": "warn",
        "@typescript-eslint/no-explicit-any": "warn",
        "@typescript-eslint/consistent-type-imports": "warn",
      },
    },
  ];
}

export default baseConfig;
