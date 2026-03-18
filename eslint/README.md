# Shared ESLint Config

Shared ESLint 9 flat config for use across all repos managed by agentGuidance.

## Rules Included

| Rule | Level | Notes |
|------|-------|-------|
| `no-unused-vars` | warn | TS override uses `@typescript-eslint/no-unused-vars` |
| `no-console` | warn | |
| `eqeqeq` | error | Always require `===` |
| `curly` | error | Always require braces |
| `prefer-const` | error | |
| `no-var` | error | |

TypeScript configs additionally enable:
- `@typescript-eslint/no-explicit-any` (warn)
- `@typescript-eslint/consistent-type-imports` (warn)

## Setup (JavaScript repos)

1. Ensure your repo has ESLint 9+ installed:

   ```bash
   npm install -D eslint
   ```

2. Create `eslint.config.js` in your repo root:

   ```js
   import baseConfig from '../agentGuidance/eslint/eslint.config.js';

   export default [
     ...baseConfig,
     // Add repo-specific overrides here
   ];
   ```

   If agentGuidance is not a sibling directory, adjust the import path or use a symlink.

## Setup (TypeScript repos)

1. Install dependencies:

   ```bash
   npm install -D eslint typescript-eslint @typescript-eslint/parser
   ```

2. Create `eslint.config.js`:

   ```js
   import baseConfig, { tsConfig } from '../agentGuidance/eslint/eslint.config.js';
   import tseslint from 'typescript-eslint';

   export default [
     ...baseConfig,
     ...tsConfig(tseslint),
     // Add repo-specific overrides here
   ];
   ```

## Global Ignores

The base config ignores `node_modules/`, `dist/`, `build/`, and `coverage/` by default.

## Future Work

- Propagation to all repos via `scripts/propagate-hooks.sh` or a dedicated script
- Optional npm package publishing for non-sibling repo setups
