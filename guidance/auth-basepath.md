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

## The Finance-Tracker Pattern (customFetch + Apache proxy)

The core problem: `provider.callbackUrl` in @auth/core is built from `basePath + origin` and used in BOTH the authorization request AND the token exchange. The token exchange hardcodes `provider.callbackUrl` in `callback.js` — you cannot fix it with `token.params`.

### Preferred: `customFetch` symbol (fixes token exchange directly)

`@auth/core` exports a `customFetch` symbol that lets you intercept the token exchange fetch and rewrite `redirect_uri` in the POST body:

```typescript
import { customFetch } from "@auth/core";

const CALLBACK_URL = `${process.env.NEXTAUTH_URL}/api/auth/callback/google`;

function fixRedirectUriFetch(...args: Parameters<typeof fetch>): ReturnType<typeof fetch> {
  if (CALLBACK_URL) {
    const init = args[1];
    if (init?.body && typeof (init.body as URLSearchParams).get === "function") {
      const body = init.body as URLSearchParams;
      if (body.has("redirect_uri")) {
        body.set("redirect_uri", CALLBACK_URL);
      }
    }
  }
  return fetch(...args);
}

// In your provider config:
Google({
  authorization: { params: { redirect_uri: CALLBACK_URL } },  // fixes auth request
  [customFetch]: fixRedirectUriFetch,  // fixes token exchange
})
```

This approach keeps both the authorization request and token exchange aligned, regardless of basePath stripping. You still need Apache proxy for routing Google's callbacks to the app, but the redirect_uri mismatch is solved in code.

### Approaches that DO NOT work

- **`token.params.redirect_uri`** — has no effect on the token exchange (hardcoded to `provider.callbackUrl`)
- **`redirectProxyUrl`** — silently ignored when both URLs share the same origin (`isOnRedirectProxy=true`)
- **`authorization.params.redirect_uri` alone** — only fixes the auth request, creating a mismatch with the token exchange

### Apache proxy (still needed for callback routing)

```apache
# Apache — proxy bare /api/auth/ to the app (Google callbacks arrive here)
ProxyPass /api/auth/ http://127.0.0.1:3008/finance/api/auth/
ProxyPassReverse /api/auth/ http://127.0.0.1:3008/finance/api/auth/
```

```
# Google Cloud Console — register the bare callback URL (NOT the /finance version)
https://example.com/api/auth/callback/google
```

The callback flow: Google redirects to `https://example.com/api/auth/callback/google` → Apache proxies to `http://127.0.0.1:PORT/finance/api/auth/callback/google` → standalone strips `/finance` → handler sees `/api/auth/callback/google` → basePath matches → customFetch rewrites redirect_uri → Google accepts.

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
