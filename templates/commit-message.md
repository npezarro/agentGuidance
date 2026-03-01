# Commit Message Guide

## Format

```
<type>: <what changed and why>

<optional body — more detail if needed>
```

## Types

| Type | When to Use |
|------|------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code restructuring with no behavior change |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `chore` | Build, config, dependency updates |
| `style` | Formatting, whitespace (no logic change) |

## Examples

```
feat: add email validation to signup form

fix: prevent duplicate orders when button is double-clicked

refactor: extract payment logic into PaymentService module

chore: update React from 18.2 to 18.3

docs: add deployment instructions to context.md
```

## Rules

- **Explain why, not just what.** The diff shows what changed; the message explains the intent.
- **Keep the first line under 72 characters.**
- **Use imperative mood.** "add feature" not "added feature" or "adds feature."
- **One logical change per commit.** Don't mix a bug fix with a refactor.
- **Don't split artificially.** A feature that touches 5 files is still one commit.
