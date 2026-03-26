# Tampermonkey Userscript Standards

## Auto-Update Headers (Required)

Every `.user.js` file must include `@updateURL` and `@downloadURL` pointing to the raw GitHub URL so Tampermonkey auto-updates when changes are pushed.

```js
// @updateURL    https://raw.githubusercontent.com/npezarro/scripts/main/<URL-encoded-filename>.user.js
// @downloadURL  https://raw.githubusercontent.com/npezarro/scripts/main/<URL-encoded-filename>.user.js
```

- Spaces in filenames → `%20`
- Bump `@version` on every change so Tampermonkey detects the update

## Repository

All userscripts live in `~/repos/scripts/` (github.com/npezarro/scripts).
