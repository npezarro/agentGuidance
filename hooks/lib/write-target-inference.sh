#!/usr/bin/env bash
# write-target-inference.sh — shared helpers for inferring which repo files a Bash
# command writes. Sourced by track-repo-writes.sh (to record own writes) and
# claim-guard.sh (to check them against other live sessions).
#
# Exists because the Edit/Write tool path is not the only way a session writes a repo
# file: heredocs, redirects, sed -i and python rewrites are all invisible to a
# file_path-based tracker. 2026-07-30: browser-agent progress.md was rewritten by one
# session through a python heredoc while another committed the same path.
#
# No side effects, no output except the functions' own stdout. Callers set -u safe.

# wti_is_write_cmd <command> -> 0 if the command can write a file
#
# Precision matters more than recall here. Every claimed path becomes a warning shown to
# another session, and a guard that cries wolf gets ignored, which is worse than no guard.
# Two rules learned from the first live run:
#   - /dev/null redirects are stripped first. `git check-ignore -q x 2>/dev/null` is not a
#     write, but the redirect made it look like one and it claimed two files a chmod had
#     merely touched.
#   - A bare interpreter is not a write. `python3 -m json.tool f.json > /dev/null` and
#     `python3 - <<PY ...read and print...PY` are how this ecosystem does most of its
#     ANALYSIS; only an interpreter whose body actually writes counts.
wti_is_write_cmd() {
  local cmd
  cmd=$(printf '%s' "$1" | sed -E 's#[0-9]?[><]&?>?[[:space:]]*/dev/null##g')

  # Shell-level writers
  printf '%s' "$cmd" | grep -qE '(>>?[[:space:]]*[^|&>[:space:]]|[[:space:]]tee[[:space:]]|sed[[:space:]]+-i|perl[[:space:]]+-i|(^|[[:space:];&|])(mv|cp|touch|install)[[:space:]])' \
    && return 0

  # Interpreter writers: the interpreter AND a write call in the same command
  printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])(python3?|ruby|node|perl)[[:space:]]' \
    && printf '%s' "$cmd" | grep -qE '(write_text|\.write\(|writeFileSync|appendFileSync|open\([^)]*,[[:space:]]*["'"'"'][wax]|json\.dump|yaml\.dump|shutil\.(copy|move)|os\.(rename|replace|remove|unlink))' \
    && return 0

  return 1
}

# wti_expand <path> [command] -> echoes the path with ~, the common env vars, and any
# variable assigned earlier in the SAME command resolved.
# Never eval: these strings come from model-authored commands, and `eval` on one is a
# command-injection primitive. Only literal substitution happens here, so a path built
# from a variable assigned in an earlier turn stays unresolved and callers must handle it.
wti_expand() {
  local p="$1" cmd="${2:-}" asg name val
  # `R=~/repos/x; cd $R && git add -A` — resolve R from the command itself.
  if [ -n "$cmd" ]; then
    case "$p" in
      *'$'*)
        while IFS= read -r asg; do
          [ -z "$asg" ] && continue
          name="${asg%%=*}"; val="${asg#*=}"
          val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
          p="${p//\$\{$name\}/$val}"
          p="${p//\$$name/$val}"
        done <<< "$(printf '%s' "$cmd" | grep -oE '(^|[;&[:space:]])[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]+' | sed -E 's/^[;&[:space:]]+//' || true)"
        ;;
    esac
  fi
  case "$p" in
    "~"|"~/"*) p="${HOME}${p#\~}" ;;
  esac
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  p="${p//\$\{PWD\}/$PWD}"
  printf '%s' "$p"
}

# wti_effective_cwd <command> <payload_cwd> -> echoes the dir relative paths resolve against
# Honours the last `cd <dir>` in the chain: `cd ~/repos/x && python3 ...` is the shape
# that matters, and its paths are relative to the cd target, not the session cwd.
# `$HOME` must be expanded here: the first live test of the deny arm missed a real
# `cd $HOME/... && git add -A` because the unexpanded target failed the -d check.
wti_effective_cwd() {
  local cmd="$1" cwd="${2:-}" target
  target=$(printf '%s' "$cmd" \
    | grep -oE '(^|&&[[:space:]]*|;[[:space:]]*|\|\|[[:space:]]*)cd[[:space:]]+[^ &;|)]+' \
    | tail -1 | sed -E 's/.*cd[[:space:]]+//' | tr -d "'\"" || true)
  if [ -n "$target" ]; then
    target=$(wti_expand "$target" "$cmd")
    case "$target" in
      /*) cwd="$target" ;;
      *)  cwd="${cwd}/${target}" ;;
    esac
  fi
  printf '%s' "$cwd"
}

# wti_candidate_paths <command> <effective_cwd> -> absolute candidate paths, one per line
wti_candidate_paths() {
  local cmd="$1" cwd="$2" cand
  printf '%s' "$cmd" \
    | grep -oE '[A-Za-z0-9_./~-]+\.(md|js|mjs|cjs|ts|tsx|jsx|json|sh|py|rb|go|html|css|scss|yml|yaml|txt|toml|sql|conf|service)' \
    | sort -u \
    | while IFS= read -r cand; do
        cand=$(wti_expand "$cand" "$cmd")
        case "$cand" in
          /*) printf '%s\n' "$cand" ;;
          *)  [ -n "$cwd" ] && printf '%s/%s\n' "$cwd" "$cand" ;;
        esac
      done
}

# wti_repo_root <path> -> echoes the repo root, or nothing when outside a repo /
# under an excluded prefix / gitignored
wti_repo_root() {
  local fp="$1" dir repo_root
  [ -z "$fp" ] && return 0
  case "$fp" in
    /tmp/*|*/.claude/projects/*|*/node_modules/*|*/.git/*) return 0 ;;
  esac
  dir=$(dirname "$fp")
  [ -d "$dir" ] || return 0
  repo_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -z "$repo_root" ] && return 0
  git -C "$repo_root" check-ignore -q "$fp" 2>/dev/null && return 0
  printf '%s' "$repo_root"
}
