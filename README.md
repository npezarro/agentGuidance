# Agent Guidance

Centralized behavioral governance for autonomous Claude Code agents.

## Why This Exists

Running dozens of Claude Code sessions per week across 27+ repositories revealed a core problem: without centralized behavioral rules, agents drift in quality, forget conventions, make inconsistent decisions, and repeat mistakes that were already corrected in other sessions. A fix applied in one project never reaches the others. An instruction that works for a code review task produces poor results on a security audit.

This repo solves that by providing a single source of truth for agent behavioral defaults, steerability constraints, and operational safety rules that propagate to every session across every project.

## What It Does

- **Behavioral defaults** (`agent.md`): Defines how agents plan, execute, communicate, handle errors, and manage git workflows. These are the base personality and decision-making rules.
- **Steerability constraints** (`guidance/*.md`): Topic-specific rules for testing, debugging, code review, deployment, and security. Applied contextually based on the task at hand.
- **Per-project overrides** (each project's `CLAUDE.md`): Project-specific behavioral rules that extend or override the global defaults without editing the source of truth.
- **Behavioral profiles** (`profiles/`): 15 specialist personas (architect, critic, implementer, user advocate, security, QA, and others), each with distinct personality parameters, expertise boundaries, and deference rules. Each profile accumulates an experience log of behavioral observations across sessions.
- **Propagation**: A hook-based system ensures every new session in any repo fetches the latest behavioral rules at startup. Changes to `agent.md` apply everywhere on next session start.

## Design Decisions

**Layered architecture over monolithic config.** Global rules handle 80% of agent behavior. Sub-guidance handles domain-specific tasks. Project-level CLAUDE.md handles exceptions. This prevents bloated global rules while keeping per-project files minimal.

**Append-only experience logs.** Each behavioral profile accumulates observations over time rather than being rewritten. This preserves the learning history and makes it possible to trace why a rule exists.

**Propagation over copy-paste.** Early versions required manually copying rules to each repo. Now a session-start hook fetches the latest `agent.md` automatically, ensuring behavioral consistency without manual coordination.

## How It Works

```
CLAUDE.md (bootstrap) → fetches agent.md (core rules) → loads guidance/*.md (topic-specific)
```

1. **`CLAUDE.md`** is read by Claude Code at session start. It fetches the latest `agent.md` from this repo.
2. **`agent.md`** contains the full ruleset: planning, git workflow, code standards, security, deployment, and more.
3. **`guidance/`** contains detailed sub-guidance for specific topics (testing, debugging, code review, dependencies).
4. **`profiles/`** contains behavioral profile definitions and accumulated experience logs.
5. **`templates/`** contains reusable templates for common project artifacts.

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
├── agent.md                           # Core behavioral defaults
├── guidance/
│   ├── testing.md                     # When and how to write tests
│   ├── debugging.md                   # Systematic debugging workflow
│   ├── code-review.md                 # Self-review checklist before committing
│   ├── deployment.md                  # Deploy safety, staging, rollback
│   ├── operational-safety.md          # Resource awareness, guardrails
│   └── dependencies.md               # Package evaluation and management
├── profiles/
│   ├── _schema.md                     # Profile format specification
│   ├── architect/                     # Systems design persona
│   ├── critic/                        # Adversarial review persona
│   ├── implementer/                   # Execution-focused persona
│   ├── useradvocate/                  # User empathy persona
│   ├── security/                      # Security audit persona
│   └── ... (15 profiles total)
├── templates/
│   ├── context.md                     # Project context file template
│   ├── pr-body.md                     # Pull request body template
│   └── commit-message.md             # Commit message format guide
├── hooks/
│   └── fetch-rules.sh                 # SessionStart hook: fetch global rules
├── scripts/
│   └── propagate-hooks.sh             # Push hooks + CLAUDE.md to all repos
├── .claude/
│   ├── settings.json                  # Claude Code hooks configuration
│   └── scripts/
│       └── session-start.sh           # Automated session start script
├── LICENSE                            # MIT
└── README.md                          # This file
```

## Related Projects

- **[claude-bakeoff](https://github.com/npezarro/claude-bakeoff)**: A/B testing framework for comparing instruction environments. Used to validate changes to agentGuidance rules before deploying them.
- **[autonomousDev](https://github.com/npezarro/autonomousDev)**: Autonomous development agent governed by agentGuidance rules. Runs every 30 minutes across all repos.

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
