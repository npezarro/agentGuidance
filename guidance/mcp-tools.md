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
| Create/update Drive files | piotr google-drive MCP |
| Sheets formatting | piotr google-drive MCP |
| Slides creation | piotr google-drive MCP |

## Google Docs Formatting

**Never write raw Markdown to Google Docs.** Google Docs does not render Markdown syntax — `#`, `**`, `---`, etc. appear as literal characters.

**Pattern for formatted Google Docs:**

1. **Write plain text content** via `createGoogleDoc` or `updateGoogleDoc` — no Markdown syntax. Use natural paragraph breaks and indentation only.
2. **Apply native formatting** via `formatGoogleDocParagraph` and `formatGoogleDocText`:
   - Title: `namedStyleType: "TITLE"` on the first line
   - Section headers: `namedStyleType: "HEADING_1"`
   - Sub-headers: `namedStyleType: "HEADING_2"`
   - Bold key phrases: `bold: true` with `textToFind`
   - Italic for quoted/template text: `italic: true`
   - Subdued metadata (dates, versions): `foregroundColor: "#888888"` + `italic: true`
3. **Batch independent formatting calls** in parallel — paragraph styles and text styles don't depend on each other once content is written.

**Quick checklist before creating a Google Doc:**
- No `#` headers — use `formatGoogleDocParagraph` with `namedStyleType`
- No `**bold**` — use `formatGoogleDocText` with `bold: true`
- No `*italic*` — use `formatGoogleDocText` with `italic: true`
- No `---` dividers — use heading styles and spacing to create visual separation
- No `- ` bullet markers — use indented text or numbered lists in plain text
