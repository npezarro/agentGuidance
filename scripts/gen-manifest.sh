#!/usr/bin/env bash
# gen-manifest.sh — regenerate the guidance-file table in MANIFEST.md from
# each guidance/*.md "Load when:" header (single source of truth).
# Usage: gen-manifest.sh          # rewrite MANIFEST.md in place
#        gen-manifest.sh --check  # exit 1 if MANIFEST.md is stale (no write)
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - "${1:-}" <<'EOF'
import os, re, sys
check = sys.argv[1] == '--check'
rows = []
for f in sorted(os.listdir('guidance')):
    if not f.endswith('.md'):
        continue
    first = open(f'guidance/{f}').readline().strip()
    m = re.match(r'<!-- Load when: (.+) -->', first)
    if f == 'ESSENTIAL.md':
        desc = 'AUTO-LOADED at SessionStart: top most-violated rules'
    elif m:
        desc = m.group(1)
    else:
        desc = 'MISSING Load-when header — add one'
    rows.append(f'| `guidance/{f}` | {desc} |')
block = '\n'.join(['<!-- BEGIN GENERATED guidance table (scripts/gen-manifest.sh) -->',
                   f'{len(rows)} guidance files. Descriptions come from each file\'s "Load when:" header.',
                   '', '| File | Load when |', '|---|---|'] + rows +
                  ['<!-- END GENERATED -->'])
t = open('MANIFEST.md').read()
new = re.sub(r'<!-- BEGIN GENERATED guidance table.*?<!-- END GENERATED -->', block, t, flags=re.S)
if new == t and '<!-- BEGIN GENERATED' not in t:
    sys.exit('MANIFEST.md has no generated-block markers; add them first')
if check:
    sys.exit(0 if new == t else 1)
open('MANIFEST.md', 'w').write(new)
EOF
