# Dependency Management Guidance

Rules for evaluating, adding, updating, and removing packages.

## Before Adding a Dependency

Ask these questions in order:

### 1. Do I Really Need This?
- Can the standard library do it? (`fs`, `path`, `crypto`, `URL`, `fetch`)
- Can an existing dependency in `package.json` do it?
- Is it a small utility I can write in <20 lines?
- If yes to any of the above, don't add the dependency.

### 2. Is It Worth the Cost?
Every dependency is a liability: supply chain risk, bundle size, maintenance burden, breaking changes.

Evaluate:
```bash
# Check package size
npx bundlephobia <package-name>

# Check publish frequency and maintenance
npm info <package-name>

# Check for known vulnerabilities
npm audit

# Check download stats (popularity ≈ community support)
npm info <package-name> | grep downloads
```

### 3. Evaluation Criteria

| Factor | Green | Red Flag |
|--------|-------|----------|
| Last publish | Within 12 months | >2 years ago |
| Open issues | Reasonable ratio | Hundreds with no response |
| License | MIT, Apache-2.0, ISC, BSD | GPL (viral), SSPL, no license |
| Dependencies | Few or none | Deep dependency tree |
| Bundle size | <50KB gzipped | >500KB for a utility |
| TypeScript | Has types or `@types/` | No types available |

## Adding a Dependency

```bash
# Production dependency
npm install <package> --save-exact

# Development dependency (test tools, linters, build tools)
npm install <package> --save-dev --save-exact

# NEVER install globally for project-specific tools
# Use npx instead: npx <tool> <args>
```

**After installing:**
1. Run `npm run build` — confirm no conflicts.
2. Run `npm test` — confirm no regressions.
3. Commit `package.json` AND `package-lock.json` together.

## Updating Dependencies

```bash
# Check what's outdated
npm outdated

# Update a specific package
npm install <package>@latest --save-exact

# Update all (be cautious — test thoroughly)
npm update
```

**After updating:**
1. Read the changelog for breaking changes.
2. Run the full test suite.
3. Test affected features manually if needed.

## Removing Dependencies

```bash
# Remove and verify
npm uninstall <package>

# Check nothing is broken
npm run build && npm test

# Search for leftover imports
grep -r "<package>" src/
```

## Lockfile Rules

- **Always commit lockfiles** (`package-lock.json` or `yarn.lock`).
- **Never delete and regenerate** lockfiles unless there's a specific, documented reason.
- **Don't mix package managers.** One repo = one package manager.
- If the repo uses `yarn`, use `yarn`. If it uses `npm`, use `npm`.

## Security

```bash
# Check for vulnerabilities
npm audit

# Fix automatically where possible
npm audit fix

# For breaking fixes, review individually
npm audit fix --dry-run
```

- Run `npm audit` periodically, not just when adding packages.
- Don't ignore high/critical vulnerabilities — escalate or fix them.
- If a dependency has an unpatched vulnerability and no fix is coming, find an alternative.

### Transitive Vulnerability Fixes with npm Overrides

When `npm audit` reports vulnerabilities in transitive dependencies (deps of your deps), `npm audit fix` often can't help because the direct dependency hasn't published a fix yet. Use `npm overrides` to force a safe version:

```json
{
  "overrides": {
    "vulnerable-package": "^2.1.0"
  }
}
```

For deeply nested transitive deps, scope the override to the parent:

```json
{
  "overrides": {
    "parent-package": {
      "vulnerable-package": "^2.1.0"
    }
  }
}
```

**After adding overrides:**
1. Delete `node_modules` and `package-lock.json`, then `npm install` to regenerate cleanly.
2. Run `npm audit` to confirm the vulnerability is resolved.
3. Run `npm test` and `npm run build` to verify no breakage from the version bump.
4. Commit both `package.json` and `package-lock.json`.

## Dependabot Major Version PRs — Do Not Merge Autonomously

Dependabot's `groups` config bundles minor+patch updates but opens individual PRs for major bumps. **Do not merge major-version Dependabot PRs autonomously, even if CI passes.**

CI passing (`npm ci + npm test + npm run build`) does not guarantee the app behaves correctly with a new major version. Major bumps frequently have runtime behavior changes that tests don't catch:
- **Tailwind v4**: drops `tailwind.config.js` in favor of CSS-based config; existing class names may break silently
- **TypeScript 6**: tighter inference; stricter type narrowing catches things 5.x allowed at runtime
- **ESLint 10**: drops legacy `.eslintrc` config format; rules and plugins may behave differently
- **Vitest 4**: changed browser mode APIs; parallel test defaults changed
- **marked v18**: breaking AST/parser changes for custom renderers

**Pattern:** Dependabot major PRs are opened individually (not grouped). When reviewing the PR queue, flag these to the user rather than merging silently. The review process: read the release notes/migration guide, check for config format changes, run a local smoke test of the actual app (not just `npm test`). Source: runeval/youtubeSpeedSetAndRemember/promptlibrary Dependabot PRs (2026-06-28/29).

**When to use:** When `npm audit fix` can't resolve the issue and the vulnerable package has a patched version available but the intermediate dependency hasn't updated yet. This pattern has been applied across 10+ repos (uuid, axios, @hono/node-server, esbuild, http-proxy-agent).
