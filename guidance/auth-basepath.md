# Auth.js v5 + Next.js basePath

Preventing the AUTH_URL/basePath mismatch that breaks OAuth on subpath deployments.

## The Problem

When a Next.js app runs under a basePath (e.g., `/runeval`), Auth.js v5 (next-auth) has conflicting needs:

1. **Action parsing**: Next.js strips the basePath before routing. The auth handler receives `/api/auth/providers`, not `/runeval/api/auth/providers`. Auth.js must match against `/api/auth` to parse actions.

2. **Callback URL construction**: OAuth callback URLs must include the basePath (`/runeval/api/auth/callback/google`) so the reverse proxy (Apache) routes them to the correct app.

3. **AUTH_URL interference**: `next-auth`'s `setEnvDefaults()` extracts the pathname from `AUTH_URL` and uses it as `basePath`. If `AUTH_URL=https://example.com/runeval`, basePath becomes `/runeval` -- which breaks action parsing because the handler receives `/api/auth/providers`, not `/runeval/providers`.

## The Fix (runeval)

Three-part configuration:

```typescript
// auth.ts
export const { handlers, auth, signIn, signOut } = NextAuth({
  basePath: "/api/auth",  // Explicit -- prevents AUTH_URL from overriding
  // ...
});
```

```env
# .env -- AUTH_URL includes the app basePath for correct origin resolution
AUTH_URL=https://example.com/runeval
```

```apache
# Apache -- redirect bare /api/auth to /runeval/api/auth
# (because Auth.js constructs callback URLs without the Next.js basePath)
RewriteRule ^/api/auth/(.*) /runeval/api/auth/$1 [R=302,L]
```

## Why Testing Didn't Catch It

- `npm run build` compiles but doesn't test runtime OAuth flows
- Auth endpoint tests only checked that the route existed, not that actions parsed correctly
- `next-auth` 5.0.0-beta.30 is a beta -- basePath behavior changed between releases
- The Next.js 15 -> 16 upgrade changed how `req.url` is constructed in route handlers
- Local dev runs without basePath (`localhost:3000`), so the bug only manifests in production

## Rules for Future Work

1. **Never set AUTH_URL to include the app basePath** without also setting an explicit `basePath` in the NextAuth config. The `||` assignment in `setEnvDefaults` will silently corrupt basePath otherwise.

2. **When upgrading next-auth or Next.js**: test the full OAuth flow on staging before deploying to production. `curl https://staging.example.com/runeval/api/auth/providers` must return provider JSON, not "Bad request."

3. **Add a smoke test**: After deploying runeval, verify auth endpoints:
   ```bash
   # Must return JSON with provider definitions
   curl -s https://example.com/runeval/api/auth/providers | jq .
   # Must return CSRF token
   curl -s https://example.com/runeval/api/auth/csrf | jq .
   ```

4. **If adding more subpath-deployed Next.js apps with OAuth**: follow the same three-part pattern (explicit basePath, AUTH_URL with origin, Apache redirect).
