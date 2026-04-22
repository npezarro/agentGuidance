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

## The Finance-Tracker Pattern (Apache callback proxy)

Same core pattern as runeval but with ProxyPass instead of RewriteRule. The key insight: `provider.callbackUrl` in @auth/core is built from `basePath + origin` and is used in BOTH the authorization request AND the token exchange. You cannot override just one side — `authorization.params.redirect_uri` only affects the authorization URL, while the token exchange hardcodes `provider.callbackUrl` in `callback.js:107`. Any mismatch causes `redirect_uri_mismatch` from Google.

**DO NOT attempt to override redirect_uri via provider params.** `token.params.redirect_uri` does NOT affect the token exchange. `redirectProxyUrl` is ignored when both URLs share the same origin (`isOnRedirectProxy=true`).

The working pattern:
```typescript
// auth.ts — NO redirect_uri overrides, NO redirectProxyUrl
NextAuth({
  basePath: "/api/auth",  // Must match what standalone sees (no /finance)
  providers: [Google({ /* plain config, no redirect_uri overrides */ })],
})
```

```apache
# Apache — proxy bare /api/auth/ to the app (Google callbacks arrive here)
ProxyPass /api/auth/ http://127.0.0.1:3008/finance/api/auth/
ProxyPassReverse /api/auth/ http://127.0.0.1:3008/finance/api/auth/
```

```
# Google Cloud Console — register the bare callback URL (NOT the /finance version)
https://example.com/api/auth/callback/google
```

The callback flow: Google redirects to `https://example.com/api/auth/callback/google` → Apache proxies to `http://127.0.0.1:PORT/finance/api/auth/callback/google` → standalone strips `/finance` → handler sees `/api/auth/callback/google` → basePath matches → token exchange sends same `redirect_uri` → Google accepts.

## OAuth Flow Testing (NOT Just Endpoint Testing)

Testing individual endpoints (csrf, providers, session) does NOT prove the OAuth flow works. Those can return 200 while login is completely broken. Always test the **actual signin flow**:

```bash
# 1. Get CSRF token and cookie
CSRF_RESP=$(curl -s -v http://localhost:PORT/APP/api/auth/csrf 2>&1)
CSRF_TOKEN=$(echo "$CSRF_RESP" | grep -o 'csrfToken":"[^"]*' | cut -d\" -f3)
CSRF_COOKIE=$(echo "$CSRF_RESP" | grep "__Host-authjs.csrf-token=" | sed 's/.*__Host-authjs.csrf-token=\([^;]*\).*/\1/')

# 2. POST signin — inspect the redirect_uri in the Google redirect
curl -s -D - -X POST http://localhost:PORT/APP/api/auth/signin/google \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Cookie: __Host-authjs.csrf-token=$CSRF_COOKIE" \
  -d "csrfToken=$CSRF_TOKEN&callbackUrl=/APP" 2>&1 | grep location

# 3. Verify redirect_uri matches a registered URI
# Check privateContext/accounts.md for the provider's registered redirect URIs
```

## Pre-Deploy Auth Checklist

Before deploying auth changes to any subpath app:
1. **Check registered URIs**: Read `privateContext/accounts.md` — is the app's callback URI registered with the OAuth provider?
2. **Test POST signin flow**: Does the `redirect_uri` in the provider redirect match the registered URI exactly?
3. **Test callback route**: Does the callback URL return 302 (not 404)?
4. **Cookie path consistency**: Do CSRF and callback hit the same cookie domain/path?
5. Only then declare auth working.

## Rules for Future Work

1. **Never set AUTH_URL to include the app basePath** without also setting an explicit `basePath` in the NextAuth config. The `||` assignment in `setEnvDefaults` will silently corrupt basePath otherwise.

2. **When upgrading next-auth or Next.js**: test the full OAuth flow on staging before deploying to production. `curl https://staging.example.com/runeval/api/auth/providers` must return provider JSON, not "Bad request."

3. **Add a smoke test**: After deploying, verify auth endpoints AND the signin flow:
   ```bash
   # Must return JSON with provider definitions
   curl -s https://example.com/APP/api/auth/providers | jq .
   # Must return CSRF token
   curl -s https://example.com/APP/api/auth/csrf | jq .
   # POST signin must redirect to Google with correct redirect_uri
   # (see "OAuth Flow Testing" section above)
   ```

4. **If adding more subpath-deployed Next.js apps with OAuth**: use the Apache proxy/rewrite pattern. `basePath: "/api/auth"` for action parsing + Apache rule to route bare `/api/auth/` callbacks to the correct app. Register the bare callback URL (without the app basePath) in the OAuth provider's console.

5. **`getToken` secureCookie mismatch**: When using `getToken` from `next-auth/jwt` in middleware behind a reverse proxy, pass `secureCookie: true`. The internal request URL is HTTP, so `getToken` defaults to looking for `authjs.session-token` (non-secure name). But NextAuth sets `__Secure-authjs.session-token` based on HTTPS `NEXTAUTH_URL`. Without this, the middleware will never find the session token and every page redirects to login.

6. **Token exchange redirect_uri**: `@auth/core` hardcodes `provider.callbackUrl` for the token exchange (callback.js:107). `authorization.params.redirect_uri` only fixes the auth request. `token.params` has no effect. `redirectProxyUrl` is skipped for same-origin. Fix: use `customFetch` from `@auth/core` on the provider to intercept the token exchange POST and rewrite `redirect_uri` in the body.
