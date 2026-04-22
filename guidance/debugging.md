# Debugging Guidance

A systematic approach to diagnosing and fixing issues.

## The Debugging Workflow

```
0. Gather Context → 1. Reproduce → 2. Read the Error → 3. Isolate → 4. Hypothesize → 5. Verify → 6. Fix → 7. Confirm
```

### 0. Gather Existing Knowledge First

Before touching code or forming hypotheses, check whether this problem (or a closely related one) has been solved before:

- **Memory**: Read relevant feedback/project memory files — corrections from past sessions are your highest-signal source
- **CLAUDE.md**: The repo's CLAUDE.md documents architecture decisions and known gotchas
- **Guidance**: Check `agentGuidance/guidance/` for domain-specific rules (auth-basepath.md, deployment.md, etc.)
- **Wiki**: Scan knowledgeBase wiki index for cross-repo patterns
- **privateContext**: Check for credentials, registered URIs, or infrastructure details that constrain the solution
- **Git history**: `git log --oneline --grep="<keyword>"` to find prior fixes

This is not optional background reading — it's the most efficient debugging step. **The previous session's fix is often already documented in memory.** Skipping this to "save time" causes multi-hour debugging loops.

### Approach Switching (15-minute rule)

If you've been trying variations of the same approach for 15+ minutes without progress:
1. Stop iterating on the current approach
2. Re-read memory/guidance for the domain (Step 0 again)
3. Spawn a debugger agent for a fresh perspective
4. Try a **fundamentally different** approach

Repeating the same category of fix with different values is not debugging — it's brute force.

### 1. Reproduce the Issue

Before touching code, confirm you can trigger the problem:
- Run the exact command or action that causes the error.
- Note the exact error message, stack trace, and context.
- If you can't reproduce it, you can't confidently fix it.

### 2. Read the Error Fully

- Read the **entire** stack trace, not just the first line.
- Look for the **first** error in a chain — cascading failures often hide the root cause.
- Check if the error message directly tells you what's wrong (it often does).

### 3. Isolate the Problem

- **Binary search:** Comment out half the suspect code. Does the error persist?
- **Minimal reproduction:** Can you trigger it with a 5-line script?
- **Check boundaries:** Is the issue in your code, a dependency, or the environment?

### 4. Check the Obvious First

Before diving deep, rule out:

```bash
# Am I on the right branch?
git branch --show-current

# Is the latest code deployed/running?
git log --oneline -3

# Are env vars loaded?
echo $NODE_ENV
cat .env | head -5  # (don't log secrets)

# Are deps up to date?
npm ls <suspect-package>
npm install

# Is the right version running?
node -v
npm -v

# Any port conflicts?
ss -tlnp | grep <port>

# Disk space?
df -h

# Permissions?
ls -la <file>
```

### 5. Targeted Debugging

Add **focused** logging — not scattered `console.log("here")`:

```javascript
// Bad
console.log("here");
console.log("here2");

// Good
console.log('[DEBUG] processOrder input:', { orderId, items: items.length });
console.log('[DEBUG] processOrder result:', { status, total });
```

### 6. Use Git to Find What Changed

```bash
# What changed recently?
git log --oneline -20

# What's different from the working version?
git diff HEAD~3

# Find the exact commit that broke it
git bisect start
git bisect bad          # current commit is broken
git bisect good <hash>  # this commit was working
# Git will binary-search through commits
```

### 7. Common Patterns

| Symptom | Likely Cause |
|---------|-------------|
| `MODULE_NOT_FOUND` | Missing dependency, wrong path, missing build step |
| `EACCES` / permission denied | File ownership issue (`sudo chown`) |
| `EADDRINUSE` | Port already in use — kill the other process or use a different port |
| `TypeError: x is not a function` | Wrong import, wrong version, or `x` is undefined |
| `undefined` where you expect data | Async issue, wrong property name, missing await |
| Works locally, fails in CI | Different Node version, missing env vars, different OS |
| Works on first load, breaks on refresh | Client-side state not synced with server, stale cache |

### 8. After Fixing

- Remove all debug logging before committing.
- Write a regression test if possible.
- Document the root cause in the commit message.
- Update `context.md` if the fix reveals something about the environment.
