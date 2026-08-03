# Hook tests

```bash
bash hooks/tests/test-guards.sh      # exit 0 = all pass
```

Covers the two cross-session guards, `claim-guard.sh` and `check-unpushed.sh`. Run it
before and after touching either.

## Two traps these tests exist because of

**The hooks read a JSON payload on stdin, not a raw command string.** Pipe a bare command
and `jq -r '.session_id'` returns empty, so the hook exits 0 — indistinguishable from
"allowed". This produced a confidently wrong "verified, the fix works" during the
2026-08-01 review, on a fix that had not been exercised at all. Build payloads with `jq`:

```bash
jq -nc --arg c "$CMD" --arg cwd "$REPO" --arg s "$SID" \
  '{session_id:$s, tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}'
```

**claim-guard only guards repos under `$HOME`.** `wti_repo_root` deliberately ignores
`/tmp/*`, so a fixture repo in a temp dir is silently invisible and every case "passes".
The suite uses `agentGuidance` itself as the contested repo and never runs git against it;
only the command string is inspected.

## Negative control

A suite that has never been observed to fail proves nothing. Point it at the hooks as they
were before the fixes and confirm it goes red:

```bash
OLD=$(mktemp -d); mkdir -p "$OLD/lib"
git show eb76be0^:hooks/claim-guard.sh            > "$OLD/claim-guard.sh"
git show eb76be0^:hooks/check-unpushed.sh         > "$OLD/check-unpushed.sh"
git show eb76be0^:hooks/lib/write-target-inference.sh > "$OLD/lib/write-target-inference.sh"
GUARD_HOOKS_DIR="$OLD" bash hooks/tests/test-guards.sh   # expect exit 1, 4 failures
rm -rf "$OLD"
```

Expected: the 4 cases the fixes introduced fail, the other 6 still pass. That split is the
useful part, it shows the fixes added behavior without regressing what already worked.

## Fixtures

Everything lives in `/tmp` under a PID-suffixed name and is removed by an `EXIT` trap. A
leftover `claude-session-alive-*` marker would make every session think a phantom peer is
live and start denying real commits, so if a run is killed mid-way, check:

```bash
ls /tmp/claude-session-alive-guardtest-* /tmp/claude-repos-claimed-guardtest-* 2>/dev/null
```
