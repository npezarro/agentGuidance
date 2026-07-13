#!/usr/bin/env bash
# source-registry.sh — central source/reference capture for the provenance system.
# Writes to the private sourceLibrary repo (~/repos/sourceLibrary):
#   - registry.jsonl    : append/update-only, deduped index of every cited source
#   - materials/<id>.md : cached copy of the source content (survives link rot)
# Spec: agentGuidance/guidance/provenance.md
#
# Usage:
#   source-registry.sh add  --url URL [--title T] [--topic T] [--snippet S] \
#                           [--accessed YYYY-MM-DD] [--content-file FILE]
#   source-registry.sh get  <id|url>
#   source-registry.sh find <query>
#   source-registry.sh list [--topic T]
#   source-registry.sh id   <url>          # print the stable ID for a URL (no write)
#
# `add` is idempotent: the same URL always maps to the same ID and is never duplicated.
# On success `add` prints the source ID — use it as [AI·<id>] inline (internal docs)
# or in the frontmatter/sidecar provenance block (external deliverables).
set -euo pipefail

LIB="${SOURCE_LIBRARY_DIR:-$HOME/repos/sourceLibrary}"
REG="$LIB/registry.jsonl"
MAT="$LIB/materials"

die(){ echo "source-registry: $*" >&2; exit 1; }
[ -d "$LIB" ] || die "sourceLibrary repo not found at $LIB (set SOURCE_LIBRARY_DIR)"
mkdir -p "$MAT"; touch "$REG"

norm_url(){ # normalize for dedup: lowercase host, strip trailing slash + fragment
  python3 - "$1" <<'PY'
import sys, urllib.parse as u
p = u.urlsplit(sys.argv[1].strip())
print(u.urlunsplit((p.scheme.lower(), p.netloc.lower(), p.path.rstrip('/'), p.query, '')))
PY
}
url_id(){ printf 's-%s' "$(norm_url "$1" | sha1sum | cut -c1-8)"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  id)
    [ $# -ge 1 ] || die "usage: id <url>"; echo "$(url_id "$1")" ;;

  add)
    url=""; title=""; topic=""; snippet=""; accessed=""; contentfile=""
    while [ $# -gt 0 ]; do case "$1" in
      --url) url="$2"; shift 2;;
      --title) title="$2"; shift 2;;
      --topic) topic="$2"; shift 2;;
      --snippet) snippet="$2"; shift 2;;
      --accessed) accessed="$2"; shift 2;;
      --content-file) contentfile="$2"; shift 2;;
      *) die "unknown arg: $1";;
    esac; done
    [ -n "$url" ] || die "add requires --url"
    id="$(url_id "$url")"
    [ -n "$accessed" ] || accessed="$(date +%F)"
    added="$(date -u +%FT%TZ)"
    material=""
    if [ -n "$contentfile" ]; then
      [ -f "$contentfile" ] || die "content file not found: $contentfile"
      material="materials/$id.md"
      { printf -- "---\nid: %s\nurl: %s\ntitle: %s\naccessed: %s\n---\n\n" \
          "$id" "$url" "$title" "$accessed"; cat "$contentfile"; } > "$LIB/$material"
    fi
    python3 - "$REG" "$id" "$url" "$title" "$topic" "$snippet" "$accessed" "$added" "$material" <<'PY'
import sys, json, os
reg, id, url, title, topic, snippet, accessed, added, material = sys.argv[1:10]
rows, found = [], False
if os.path.exists(reg):
    with open(reg) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: r = json.loads(line)
            except Exception: continue
            if r.get("id") == id:
                found = True
                r["url"] = url or r.get("url")
                if title:    r["title"]    = title
                if topic:    r["topic"]    = topic
                if snippet:  r["snippet"]  = snippet
                if accessed: r["accessed"] = accessed
                if material: r["material"] = material
                rows.append(r)
            else:
                rows.append(r)
if not found:
    rows.append({"id": id, "url": url, "title": title, "topic": topic,
                 "snippet": snippet, "accessed": accessed, "added": added,
                 "material": material})
with open(reg, "w") as f:
    for r in rows: f.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
    echo "$id" ;;

  get)
    [ $# -ge 1 ] || die "usage: get <id|url>"
    case "$1" in s-*) id="$1";; *) id="$(url_id "$1")";; esac
    jq -c --arg id "$id" 'select(.id==$id)' "$REG" ;;

  find)
    [ $# -ge 1 ] || die "usage: find <query>"
    jq -c --arg q "$1" '
      select((.url//""|ascii_downcase|contains($q|ascii_downcase))
          or (.title//""|ascii_downcase|contains($q|ascii_downcase))
          or (.topic//""|ascii_downcase|contains($q|ascii_downcase))
          or (.snippet//""|ascii_downcase|contains($q|ascii_downcase)))' "$REG" ;;

  list)
    if [ "${1:-}" = "--topic" ] && [ -n "${2:-}" ]; then
      jq -c --arg t "$2" 'select(.topic==$t)' "$REG"
    else
      jq -c '.' "$REG"
    fi ;;

  *) die "usage: add|get|find|list|id  (see header comment)";;
esac
