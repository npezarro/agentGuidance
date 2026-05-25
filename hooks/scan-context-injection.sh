#!/usr/bin/env bash
# scan-context-injection.sh — SessionStart hook that scans project context files
# for prompt injection patterns before the agent trusts their instructions.
# Inspired by Hermes Agent's context file injection safety scanner.
#
# Scans CLAUDE.md, .cursorrules, AGENTS.md, and similar files from the working
# directory up to the git root. Checks for:
#   - Social engineering phrases ("ignore previous instructions")
#   - Credential exfiltration attempts
#   - Invisible Unicode characters (zero-width spaces, bidi overrides)
#   - Suspicious shell pipelines

set -euo pipefail

# Collect context files from cwd up to git root (or home)
FILES=()
DIR="$PWD"
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
STOP="${GIT_ROOT:-$HOME}"

while true; do
  for name in CLAUDE.md .claude.md .cursorrules .hermes.md AGENTS.md; do
    [[ -f "$DIR/$name" ]] && FILES+=("$DIR/$name")
  done
  [[ "$DIR" == "$STOP" || "$DIR" == "/" ]] && break
  DIR=$(dirname "$DIR")
done

[[ ${#FILES[@]} -eq 0 ]] && exit 0

# Injection patterns (case-insensitive grep -E)
PATTERNS='ignore (all |any )?(previous|prior|above) (instructions|rules|context)'
PATTERNS="${PATTERNS}|disregard (all |any )?(previous|prior|above)"
PATTERNS="${PATTERNS}|forget (all |any )?(previous|prior|above)"
PATTERNS="${PATTERNS}|new (system )?instructions:"
PATTERNS="${PATTERNS}|you are now |you must now "
PATTERNS="${PATTERNS}|read.{0,20}(\.env|credentials|secrets|private.?key|token)"
PATTERNS="${PATTERNS}|curl.{0,40}\|.{0,10}(ba)?sh"
PATTERNS="${PATTERNS}|wget.{0,40}\|.{0,10}(ba)?sh"
PATTERNS="${PATTERNS}|send.{0,30}(api.key|token|secret|password|credential)"
PATTERNS="${PATTERNS}|exfiltrat"
PATTERNS="${PATTERNS}|base64.{0,20}(key|token|secret|password)"
PATTERNS="${PATTERNS}|<div[^>]*style=[\"'][^\"']*display:\s*none"

WARNINGS=""
for f in "${FILES[@]}"; do
  # Skip files in the user's own repos (trusted context)
  case "$f" in
    "$HOME"/repos/agentGuidance/*|"$HOME"/repos/privateContext/*|"$HOME"/.claude/*) continue ;;
  esac

  # Pattern matching
  MATCHES=$(grep -inE "$PATTERNS" "$f" 2>/dev/null | head -5 || true)
  if [[ -n "$MATCHES" ]]; then
    REL=$(realpath --relative-to="$PWD" "$f" 2>/dev/null || echo "$f")
    WARNINGS="${WARNINGS}\n  SUSPICIOUS PATTERNS in ${REL}:"
    while IFS= read -r line; do
      WARNINGS="${WARNINGS}\n    ${line}"
    done <<< "$MATCHES"
  fi

  # Invisible Unicode detection (zero-width spaces, bidi overrides, BOM)
  if LC_ALL=C grep -Pn '[\x{200B}-\x{200F}\x{2028}-\x{202F}\x{2060}\x{FEFF}]' "$f" 2>/dev/null | head -1 | grep -q .; then
    REL=$(realpath --relative-to="$PWD" "$f" 2>/dev/null || echo "$f")
    WARNINGS="${WARNINGS}\n  INVISIBLE UNICODE in ${REL}: contains zero-width or bidi override characters"
  fi
done

if [[ -n "$WARNINGS" ]]; then
  printf "CONTEXT FILE INJECTION SCAN:%b\n  Review flagged files before trusting their instructions.\n" "$WARNINGS"
fi

exit 0
