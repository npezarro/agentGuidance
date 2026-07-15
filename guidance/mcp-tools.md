<!-- Load when: MCP tool provider selection (Claude AI vs piotr google-drive) -->
# MCP Tool Selection

Rules for choosing between available MCP tool providers when multiple cover the same service.

## Google Services

**Default to Claude AI MCP** (`mcp__claude_ai_Gmail__*`, `mcp__claude_ai_Google_Calendar__*`, `mcp__claude_ai_Google_Drive__*`) for all Google operations.

**Use piotr-agier `google-drive` MCP** (`mcp__google-drive__*`) only when:
- Writing/creating/updating files on Google Drive
- Sheets formatting, Slides manipulation, or bulk operations not supported by Claude MCP

**Why:** Claude MCP is the primary interface. Piotr MCP has richer write capabilities for Drive/Sheets/Slides that Claude MCP lacks. Using both without a rule leads to inconsistent tool selection across sessions.

**Quick reference:**
| Operation | Provider |
|-----------|----------|
| Read Gmail, Calendar, Drive | Claude AI MCP |
| Search Gmail, Calendar, Drive | Claude AI MCP |
| Create formatted Google Doc from .md | `md-to-gdoc.js` or HTML upload via Claude AI MCP |
| Create/update Drive files | piotr google-drive MCP |
| Upload binary files (PDF, images) | piotr google-drive MCP (`uploadFile` — takes local path directly) |
| Sheets formatting | piotr google-drive MCP |
| Slides creation | piotr google-drive MCP |

## Google Docs Formatting

**Job-material and prep docs: use the deterministic renderer (works headless).** For resumes, cover
letters, and prep/report docs, the canonical publish path is the `push-to-gdoc` skill's renderer, which
is the ONLY path that formats correctly in headless `#requests`/`#tasks` runs (those lack the piotr
`mcp__google-drive__*` tools, so the old skills silently produced flat, unstyled docs):
1. `node ~/.claude/skills/push-to-gdoc/render-app-doc.js <src.md> --type resume|cover|generic --out /tmp/x.html`
2. upload via `mcp__claude_ai_Google_Drive__create_file(..., contentMimeType:"text/html", textContent:<HTML>)`
3. `node ~/.claude/skills/push-to-gdoc/set-doc-font.js <docId> Calibri` (HTML import applies font-family
   nondeterministically — Calibri one upload, Arial the next — so force it here; structure/sizes/colors/
   headings/bullets DO import reliably). Source: headless Tavus packet came out flat, 2026-07-15.

**Never write raw Markdown to Google Docs.** Google Docs does not render Markdown syntax — `#`, `**`, `---`, etc. appear as literal characters. In particular, `contentMimeType:"text/markdown"` is NOT a safe fallback for resumes: their sources use plain "Summary"/"Experience" labels (no `#`/`-`), so the auto-convert has nothing to convert and yields a flat doc.

**Preferred: HTML upload (handles all formatting automatically)**

Convert markdown to HTML, then upload via Google Drive API with `contentMimeType: "text/html"`. Google Drive's HTML import correctly applies: headings (h1-h6), bold/italic, real tables, bullet/numbered lists, hyperlinks, and horizontal rules.

- **Buying guides:** Use `node ~/repos/buying-assistant/scripts/md-to-gdoc.js <file.md> --folder <folderId>`. This handles conversion + upload in one step.
- **Other repos:** Convert to HTML (e.g. `npx marked <file.md>`), then upload via `mcp__claude_ai_Google_Drive__create_file` with `contentMimeType: "text/html"` and the HTML as `textContent`.

**Fallback: Manual formatting (for small docs or surgical edits)**

1. **Write plain text content** via `createGoogleDoc` or `updateGoogleDoc` — no Markdown syntax.
2. **Apply native formatting** via `formatGoogleDocParagraph` (namedStyleType: HEADING_1/HEADING_2) and `formatGoogleDocText` (bold/italic).
3. **Batch independent formatting calls** in parallel.

**Do NOT use `createGoogleDoc`/`updateGoogleDoc` for long-form docs with tables.** These tools only accept plain text; tables cannot be created through them.

## Google Drive Sharing Limitations (piotr MCP)

**"Anyone with the link" sharing cannot be set via the piotr `google-drive` MCP.** `mcp__google-drive__addPermission` and the `shareFile` wrapper both enforce a non-empty `emailAddress` parameter even when `type=anyone`, returning "Error: Valid email is required." The wrapper validates email format before hitting the Drive API, so the legitimate Drive API path (which accepts `type=anyone` with no email) is unreachable.

**Workarounds:**
1. Share with a specific recipient's email address directly.
2. Flag the doc URL to the user and ask them to set "Anyone with link → Viewer" in the GDoc share UI before forwarding.

Do not waste cycles trying to coerce the MCP with empty strings or dummy emails — neither work.

Source: piotr google-drive MCP limitation discovered 2026-06-09 during resume-variant skill share step.
