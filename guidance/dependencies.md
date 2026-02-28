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
