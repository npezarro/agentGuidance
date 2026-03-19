# Recurring Tasks

Shared infrastructure for running non-dev Claude tasks on a schedule. Extracted from the common patterns in `daily-tldr.sh`, `autonomousDev/run.sh`, and `daily-job-pipeline.sh`.

## Structure

```
recurring-tasks/
  runner.sh              # Shared task runner (locking, logging, Discord, Claude CLI)
  generate-crontab.sh    # Reads task configs, generates crontab entries
  .env.example           # Discord webhook and settings
  tasks/                 # Task configs (bash-sourceable key=value)
    job-search.conf
    application-materials.conf
    company-ranking.conf
  prompts/               # Prompt templates (markdown with {{VAR}} placeholders)
    job-search.md
    application-materials.md
    company-ranking.md
  logs/                  # Run logs (gitignored)
  output/                # Run metadata JSON (gitignored)
```

## Usage

Run a task manually:
```bash
./runner.sh job-search
./runner.sh application-materials --dry-run
```

List available tasks:
```bash
./runner.sh
```

Generate crontab entries:
```bash
./generate-crontab.sh           # print to stdout
./generate-crontab.sh --install # append to crontab
```

## Adding a new task

1. Create `tasks/<name>.conf` with schedule, timeout, working directory, and permissions
2. Create `prompts/<name>.md` with the full prompt template
3. Run `./generate-crontab.sh --install` to register the schedule

## Task config reference

```bash
DESCRIPTION="What this task does"
SCHEDULE="0 9 * * 1,4"          # cron expression
TIMEOUT=1800                     # max seconds
OUTPUT_MODE="branch-pr"          # branch-pr | direct-commit | file-only
WORKING_DIR="/path/to/repo"      # where Claude runs
MAX_TURNS=50                     # Claude CLI max turns
ENABLED=true                     # set false to disable
PERMISSION_MODE="scoped"         # scoped | default
ALLOWED_TOOLS="Read Write Bash"  # tools allowed in scoped mode
TASK_VAR_FOO="bar"               # available as {{FOO}} in prompt
```

## Current schedule

| Task | Schedule | Description |
|------|----------|-------------|
| job-search | Mon/Thu 9 AM | Expand AI PM role catalogue |
| application-materials | Tue/Fri 10 AM | Generate materials for top new postings |
| company-ranking | Wed 10:30 AM | Re-rank company role lists by fit |
