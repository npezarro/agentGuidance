# Propagation Agent — Experience Log

---
## 2026-04-16 | Initial Profile Creation
**Task:** Established propagation agent profile to handle consistent multi-destination learning routing
**What worked:** Defined clear scope — routing only, not learning discovery or content authoring
**What didn't:** N/A — initial setup
**Learned:** The propagation function was previously implicit in every agent's responsibilities, leading to inconsistent execution. Making it an explicit role with a dedicated script (propagate-learning.sh) gives it a single owner.

---
## 2026-05-11 | job-pipeline repo split reference updates
**Task:** Update all documentation references across 4 repos after job pipeline was split into its own standalone repo
**What worked:** Read every file before editing; distinguished active reference files (rules, accounts) from historical logs (closeouts, completed-work) and only updated the former. Grepped broadly to find all references, then made a judgment call on which to update.
**What didn't:** N/A -- straightforward routing task
**Learned:** When a repo is split/moved, historical closeout logs and completed-work entries should not be updated (they describe the state at that time). Only update active reference documents (rules, accounts, wiki sources, context.md). The agentGuidance agent.md had no job-pipeline-specific paths, so no changes needed there.
