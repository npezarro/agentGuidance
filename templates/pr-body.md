# Pull Request Template

> Use this structure when creating PRs with `gh pr create`.

## Summary
<!-- 1-3 bullet points describing what this PR does and why -->
-

## Changes
<!-- List the key files/areas changed -->
-

## Testing
<!-- How was this tested? -->
- [ ] Build passes (`npm run build`)
- [ ] Tests pass (`npm test`)
- [ ] Manual testing: <!-- describe what was verified -->

## Notes
<!-- Anything the reviewer should know: trade-offs, follow-up work, deployment steps -->

---

**Usage with `gh`:**
```bash
gh pr create --title "Short descriptive title" --body "$(cat <<'EOF'
## Summary
- Added X to improve Y

## Changes
- `src/module.js` — new validation logic
- `tests/module.test.js` — regression test

## Testing
- [x] Build passes
- [x] Tests pass
- [x] Manually verified with edge case inputs
EOF
)"
```
