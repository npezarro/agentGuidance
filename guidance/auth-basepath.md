# Auth.js v5 + Next.js basePath

Preventing the AUTH_URL/basePath mismatch that breaks OAuth on subpath deployments.

## The Problem

When a Next.js app runs under a basePath (e.g., `/runeval`), Auth.js v5 (next-auth) has conflicting needs:

1. **Action parsing**: Next.js strips the basePath before routing. The auth handler receives `/api/auth/providers`, not `/runeval/api/auth/providers`. Auth.js must match against `/api/auth` to parse actions.

2. **Callback URL construction**: OAuth callback URLs must include the basePath (`/runeval/api/auth/callback/google`) so the reverse proxy (Apache) routes them to the correct app.

3. **AUTH_URL interference**: `next-auth`'s `setEnvDefaults()` extracts the pathname from `AUTH_URL` and uses it as `basePath`. If `AUTH_URL=https://example.com/runeval`, basePath becomes `/runeval` -- which breaks action parsing because the handler receives `/api/auth/providers`, not `/runeval/providers`.

## Preferred: Centralized Auth-Proxy (2026-04-24)

All subpath-deployed apps now use a **centralized OAuth callback proxy** at `auth-proxy` (port 3050). This replaces per-app `customFetch` hacks and direct `redirect_uri` overrides.

### How it works

1. **Single redirect URI**: `https://example.com/api/auth/callback/google` registered in Google Cloud Console
2. **Apache routes** `/api/auth/` to `localhost:3050` (the auth-proxy)
3. Each downstream app sets an `__auth_target` cookie via Next.js middleware when the user initiates sign-in:
   ```typescript
   // middleware.ts
   if (req.nextUrl.pathname.startsWith("/api/auth/signin")) {
     const res = NextResponse.next();
     res.cookies.set("__auth_target", "/finance", { path: "/" });
     return res;
   }
   ```
4. Google redirects to the proxy; proxy reads `__auth_target` cookie and 302 redirects to `/<app>/api/auth/callback/google?code=...&state=...`
5. The downstream app handles the callback normally

### Downstream app setup

Each app needs:
- Shared `AUTH_SECRET` (for state JWT encoding/decoding across apps)
- Middleware/proxy that sets `__auth_target` cookie with the app's base path during signin
- Remove any `customFetch` overrides, `authorization.params.redirect_uri` hacks, or `AUTH_REDIRECT_PROXY_URL` env vars

### Gotchas discovered during deployment (2026-04-24)

- **basePath in pathname**: Next.js 14 with `auth()` middleware wrapper includes the basePath in `req.nextUrl.pathname`. Check for both `/api/auth/signin/` and `/<basePath>/api/auth/signin/`.
- **Next.js 16 proxy.ts**: Next.js 16 renamed `middleware.ts` to `proxy.ts` and exports `proxy()` instead of `middleware()`. Having both files causes a build error.
- **Matcher excludes auth paths**: If the middleware matcher excludes `api/auth` (common for auth-protected apps), add `/api/auth/signin/:path*` as a separate matcher entry so the cookie-setting code runs.
- **Prisma generate**: After pulling new Prisma schema models on the VM, run `npx prisma generate` before building.
- **Trailing slash redirect**: Set `skipTrailingSlashRedirect: true` in `next.config.ts` for basePath apps. Without this, Next.js issues 308 permanent redirects for URLs without a trailing slash, which can cause redirect loops or unexpected behavior behind a reverse proxy.

### Apps using the proxy

- runeval (`/runeval`, port 3001)
- health-hub (`/health-hub`, port 3002)
- finance-tracker (`/finance`, port 3008)
- student-transcript (`/student`, port 3009)

### Why this replaced per-app workarounds

- `redirectProxyUrl` (Auth.js built-in) is silently skipped for same-origin setups
- `customFetch` works but is brittle and must be maintained per-app
- Adding new apps previously required a new Google Console redirect URI; now just set the `__auth_target` cookie in the app's middleware

Repo: `auth-proxy`. See `privateContext/` for env var values.

---

## Legacy Per-App Patterns (before auth-proxy)

The sections below document per-app workarounds that are no longer needed for apps using the centralized proxy. They remain as reference for apps that cannot use the proxy or for debugging.

## The Fix (runeval) [Legacy]

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

## The Finance-Tracker Pattern (customFetch + Apache proxy) [Legacy]

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

5. **`getToken` secureCookie mismatch**: When using `getToken` from `next-auth/jwt` in middleware behind a reverse proxy, pass `secureCookie: true`. The internal request URL is HTTP, so `getToken` defaults to looking for `authjs.session-token` (non-secure name). But NextAuth sets `__Secure-authjs.session-token` based on HTTPS `NEXTAUTH_URL`. Without this, the middleware will never find the session token and every page redirects to login.

6. **Token exchange redirect_uri**: `@auth/core` hardcodes `provider.callbackUrl` for the token exchange (callback.js:107). `authorization.params.redirect_uri` only fixes the auth request. `token.params` has no effect. `redirectProxyUrl` is skipped for same-origin. Fix: use `customFetch` from `@auth/core` on the provider to intercept the token exchange POST and rewrite `redirect_uri` in the body.

7. **Edge runtime middleware cannot use `auth()` with PrismaAdapter.** The `auth()` wrapper imports PrismaAdapter which transitively imports `node:path` — incompatible with Edge runtime. Use `getToken()` from `next-auth/jwt` (JWT-only, no Node.js deps) instead:
   ```typescript
   // middleware.ts — WRONG (crashes on Edge)
   import { auth } from "@/auth";
   export default auth((req) => { /* req.auth */ });

   // middleware.ts — CORRECT
   import { getToken } from "next-auth/jwt";
   const token = await getToken({ req, secret: process.env.AUTH_SECRET });
   ```
   This applies to any Next.js app using PrismaAdapter with `session: { strategy: "jwt" }`. If the adapter uses only lightweight deps (e.g., DrizzleAdapter), `auth()` may work — but `getToken()` is always safe for middleware.

8. **Standalone mode changes basePath behavior.** In `next dev`, Next.js strips the basePath from `req.url` before the route handler sees it. In standalone mode (`node server.js`), it does NOT strip it — `@auth/core` sees the full URL including the basePath prefix. So the NextAuth `basePath` must include the Next.js basePath:
   ```typescript
   // next dev: handler sees /api/auth/signin/google → basePath: "/api/auth"
   // standalone: handler sees /finance/api/auth/signin/google → basePath: "/finance/api/auth"

   // Dynamic config that works in both modes:
   basePath: `${process.env.BASE_PATH || ""}/api/auth`,
   ```
   **Why this trips people up:** The runeval fix (above) uses a hardcoded `"/api/auth"` because runeval's Apache proxy rewrites the URL. Apps without that rewrite need the dynamic basePath.

9. **Never use `NEXT_PUBLIC_*` env vars in server-side auth config.** `NEXT_PUBLIC_*` variables are inlined at build time by the Next.js bundler. If the build environment doesn't have the var set, the value becomes `undefined` permanently — it won't be read at runtime even if `.env` has it. Use a non-prefixed env var (e.g., `BASE_PATH` instead of `NEXT_PUBLIC_BASE_PATH`) for any value that server-side code needs at runtime.

10. **Return JSON 401 for unauthenticated API routes, not redirects.** NextAuth's `auth()` middleware wrapper redirects unauthenticated requests to the login page (HTML). API routes that receive an HTML redirect instead of a JSON error will cause `SyntaxError: Unexpected token '<'` on the client. In your middleware, detect API paths and return a JSON response:
   ```typescript
   export default auth((req) => {
     if (!req.auth) {
       if (req.nextUrl.pathname.startsWith("/api/")) {
         return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
       }
       return NextResponse.redirect(new URL("/login", req.url));
     }
     return NextResponse.next();
   });
   ```
   Also exclude static assets from the middleware matcher (`.*\\.png$|.*\\.svg$`) — auth middleware blocking images causes broken layouts.

11. **Exclude internal API routes from auth when the page is already protected.** If a page is behind auth and its API route only serves that page, session cookies may not forward correctly through the NextAuth middleware chain. Add the route to the middleware matcher's negative lookahead (e.g., `api/ai-edit`) rather than fighting cookie forwarding.

## Simpler Alternative: Provider-Level redirect_uri Override [Legacy]

When you only need the OAuth callback URL to include the basePath (and don't need the full Apache redirect setup), override `redirect_uri` directly in the provider config:

```typescript
// auth.ts — student-transcript uses this approach
Google({
  clientId: process.env.AUTH_GOOGLE_ID,
  clientSecret: process.env.AUTH_GOOGLE_SECRET,
  authorization: {
    params: {
      redirect_uri: `${process.env.NEXTAUTH_URL}/api/auth/callback/google`,
    },
  },
}),
```

This tells the OAuth provider exactly where to redirect, bypassing Auth.js's URL construction entirely. Works when `NEXTAUTH_URL` already includes the basePath (e.g., `https://example.com/student`).

**Trade-off:** Simpler (no Apache redirect needed), but couples the callback URL to the env var. The three-part pattern is more robust for complex proxy setups.
