# Agent Guidance

A centralized source of truth for AI agent (Claude) configuration and operational rules. This repo provides consistent behavior standards across sessions and projects.

## How It Works

```
CLAUDE.md (bootstrap) → fetches agent.md (core rules) → loads guidance/*.md (topic-specific)
```

1. **`CLAUDE.md`** is read by Claude Code at session start. It fetches the latest `agent.md` from this repo.
2. **`agent.md`** contains the full ruleset: planning, git workflow, code standards, security, deployment, and more.
3. **`guidance/`** contains detailed sub-guidance for specific topics (testing, debugging, code review, dependencies).
4. **`templates/`** contains reusable templates for common project artifacts.

## Quick Setup

### Option 1: Reference from another project

Add this to your project's `CLAUDE.md`:

```
On session start, fetch and apply the latest global rules:

    curl -s https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md

If the fetch fails, continue with local rules.
```

### Option 2: Copy into your project

```bash
# Copy the core guidance
curl -s https://raw.githubusercontent.com/npezarro/agentGuidance/main/agent.md > CLAUDE.md

# Optionally copy templates
mkdir -p templates
curl -s https://raw.githubusercontent.com/npezarro/agentGuidance/main/templates/context.md > templates/context.md
```

### Option 3: Use the hooks

Copy the `.claude/` directory into your project to get automated session-start behavior:

```bash
cp -r .claude/ /path/to/your/project/.claude/
```

## Repository Structure

```
agentGuidance/
├── CLAUDE.md                          # Bootstrap — entry point for Claude Code
├── agent.md                           # Core rules (the main guidance document)
├── guidance/
│   ├── testing.md                     # When and how to write tests
│   ├── debugging.md                   # Systematic debugging workflow
│   ├── code-review.md                 # Self-review checklist before committing
│   └── dependencies.md               # Package evaluation and management
├── templates/
│   ├── context.md                     # Project context file template
│   ├── pr-body.md                     # Pull request body template
│   └── commit-message.md             # Commit message format guide
├── .claude/
│   ├── settings.json                  # Claude Code hooks configuration
│   └── scripts/
│       └── session-start.sh           # Automated session start script
├── LICENSE                            # MIT
└── README.md                          # This file
```

## What's Covered

| File | Topics |
|------|--------|
| `agent.md` | Identity, commands, planning, batching, git workflow, context files, code standards, testing, debugging, dependencies, environment awareness, documentation freshness, security, code review, communication, multi-session continuity, deployment |
| `guidance/testing.md` | Test placement, structure, mocking, coverage, when to test |
| `guidance/debugging.md` | Reproduction, isolation, common patterns, git bisect |
| `guidance/code-review.md` | Pre-commit checklist, PR checklist, common issues |
| `guidance/dependencies.md` | Evaluation criteria, adding/updating/removing packages, security auditing |

## Customizing

The guidance is designed to be layered:

1. **Global rules** (`agent.md`) apply everywhere.
2. **Sub-guidance** (`guidance/*.md`) applies to specific activities.
3. **Project-level** `CLAUDE.md` can override or extend any rule for a specific repo.

To customize for your needs:
- Fork this repo
- Edit `agent.md` to change the default stack, commands, or standards
- Add project-specific guidance files under `guidance/`
- Update the bootstrap URL in `CLAUDE.md` to point to your fork

## License

MIT
