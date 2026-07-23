<!-- Load when: authentication and base path patterns -->
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

### Adding a new app (step-by-step)

Follow these steps exactly. Do NOT attempt per-app callback routing, customFetch, or Apache auth rewrites.

1. **`.env`**:
   ```env
   AUTH_SECRET=<shared secret from privateContext/auth-proxy-env.md>
   AUTH_URL=https://example.com          # bare origin, NO path
   AUTH_TRUST_HOST=true
   ```
2. **`auth.ts`** (NextAuth config):
   ```typescript
   basePath: "/api/auth",               // explicit, prevents AUTH_URL override
   ```
3. **`proxy.ts`** (Next.js 16) or **`middleware.ts`** (Next.js 15):
   - If the project uses `src/` directory, place in `src/proxy.ts`
   - Set `__auth_target` cookie to the app's basePath (e.g., `"/myapp"`)
   - Matcher: `["/api/auth/signin/:path*"]`
4. **`layout.tsx`**:
   ```tsx
   <SessionProvider basePath="/<app>/api/auth">
   ```
5. **Apache** (VM): Add `ProxyPass /<app> http://127.0.0.1:<port>/<app>` only. Do NOT add `/api/auth/callback/` rules.
6. **auth-proxy/server.js** (`ALLOWED_TARGETS`): Add the app's base path (e.g., `"/myapp"`) to the `ALLOWED_TARGETS` array in the auth-proxy repo. This prevents open redirect attacks — the proxy validates the `__auth_target` cookie against this list before redirecting. If the app is not in the allowlist, auth silently fails with no error in the app. (Source: security commit 1817371, 2026-05-18.)
7. **Google Console**: No changes needed — `https://example.com/api/auth/callback/google` is already registered.
8. **Test**: POST the signin flow and verify `redirect_uri` in the Google redirect matches the registered URI. Do NOT just test GET endpoints.
9. **Update this file**: Add the app to the "Apps using the proxy" list below.

### Downstream app setup (summary)

Each app needs:
- Shared `AUTH_SECRET` (for state JWT encoding/decoding across apps)
- Middleware/proxy that sets `__auth_target` cookie with the app's base path during signin
- Remove any `customFetch` overrides, `authorization.params.redirect_uri` hacks, or `AUTH_REDIRECT_PROXY_URL` env vars

### Gotchas discovered during deployment (2026-04-24)

- **basePath in pathname**: Next.js 14 with `auth()` middleware wrapper includes the basePath in `req.nextUrl.pathname`. Check for both `/api/auth/signin/` and `/<basePath>/api/auth/signin/`.
- **Next.js 16 proxy.ts**: Next.js 16 renamed `middleware.ts` to `proxy.ts` and exports `proxy()` instead of `middleware()`. Having both files causes a build error.
- **Matcher excludes auth paths**: If the middleware matcher excludes `api/auth` (common for auth-protected apps), add `/api/auth/signin/:path*` as a separate matcher entry so the cookie-setting code runs.
- **NextAuth `basePath` must always be `"/api/auth"`, never `"/<app>/api/auth"`**: In Next.js standalone output (`output: 'standalone'`), the basePath is stripped from `req.url` before reaching server code. NextAuth always receives `/api/auth/...` regardless of the Next.js basePath. Setting `basePath: "/<app>/api/auth"` in `auth.ts` prevents NextAuth from matching action routes and silently breaks auth. Source: shopper debugging loop (2026-05-18, commit 832c47b).
- **Middleware/proxy matcher must NOT include basePath prefix** (Next.js 16 standalone, re-verified 2026-06-05): The basePath is stripped from `req.nextUrl.pathname` before middleware/proxy fires (same behavior as Route Handlers, just above). Both `config.matcher` and any `req.nextUrl.pathname.startsWith()` body check must use the UNPREFIXED path, e.g., `matcher: ["/api/auth/signin/:path*"]`. Verified against shopper (`src/middleware.ts`), humans (`src/proxy.ts`), and foodie (`src/proxy.ts`, fix commit f27c340) -- all Next.js 16.2.6, all unprefixed, all working. *Earlier revision of this note (2026-05-17) claimed Next.js 16 needed the prefix after a shopper debugging loop; that was a misattribution and broke foodie auth for ~2 weeks before this 2026-06-05 fix.*
- **Prisma generate**: After pulling new Prisma schema models on the VM, run `npx prisma generate` before building.
- **`redirect()` auto-prepends basePath**: Next.js `redirect("/search")` becomes `/<basePath>/search` automatically. Do NOT include the basePath prefix in redirect paths (e.g., `redirect("/shopper/search")` becomes `/shopper/shopper/search`). This applies to all server-side redirects in basePath-deployed apps.
- **Trailing slash handling**: Set `trailingSlash: false` in `next.config.ts` for basePath apps behind a reverse proxy. Do NOT use `skipTrailingSlashRedirect: true` -- it is broken with basePath (causes empty response body for the basePath root URL, and middleware never fires). `trailingSlash: false` correctly issues 308 redirects from `/app/` to `/app`, which proxies handle cleanly.

### Apps using the proxy

- runeval (`/runeval`, port 3001)
- health-hub (`/health-hub`, port 3002)
- finance-tracker (`/finance`, port 3008)
- student-transcript (`/student`, port 3009)
- shopper (`/shopper`, port 3090, tunneled from WSL)
- foodie (`/foodie`, port 3094)

### AUTH_URL origin-only pattern for tunneled apps

When an app is tunneled (e.g., WSL -> VM via SSH), Apache's `ProxyPreserveHost On` and `X-Forwarded-Host` may not correctly reach the Next.js standalone server. NextAuth then uses `localhost:PORT` as the origin, producing wrong callback URLs. Fix: set `AUTH_URL=https://example.com` (bare origin, no path). With pathname="/", `setEnvDefaults()` won't override the explicit `basePath: "/api/auth"`, but origin is set correctly. This is simpler than debugging header forwarding through SSH tunnels.

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

## Session Cookie Isolation (2026-05-20)

When multiple NextAuth apps share a domain (e.g., `example.com`), they MUST have unique session cookie names. The default `__Secure-authjs.session-token` will collide: logging into one app overwrites the session for every other app.

**Required in every app's NextAuth config:**
```typescript
cookies: {
  sessionToken: {
    name: "__Secure-<appname>.session-token",
    // path is the app's basePath, NOT "/" — see "Cookie accumulation" below.
    // Valid because the name uses __Secure- (only __Host- would force path "/").
    options: { httpOnly: true, sameSite: "lax", path: "/<basePath>", secure: true },
  },
},
session: { strategy: "jwt", maxAge: 90 * 24 * 60 * 60 }, // 90 days for personal apps
```

**Add to the new-app checklist:** assign a unique cookie name AND scope its `path`
to the app's basePath (both prevent cross-app problems on the shared domain).

## Cookie accumulation exceeds Apache's header limit (2026-07-18)

The flip side of many single-domain NextAuth apps: each sets its session cookie with
`path: "/"`, so the browser sends ALL of them in one `Cookie:` header on every
request to the domain. Once ~8-10 apps exist, the combined header exceeds Apache's
default `LimitRequestFieldSize` (8190 bytes) and the origin returns:

```
400 Bad Request — Size of a request header field exceeds server limit.
```

(This is Apache's own error page, served through the CDN — the CDN passed the large
header, the origin rejected it. Symptom appears right after a user signs into the
Nth app.)

**The non-obvious fix — set it on the DEFAULT vhost for the port, not the matched one.**
For name-based SSL vhosts, Apache reads the request headers under the DEFAULT server
for that `ip:port` (the first/`_default_` vhost, selected before the Host header is
parsed). So `LimitRequestFieldSize` on the app's own matched vhost — or globally in
`apache2.conf` — has NO effect on this limit. It must go inside the `<VirtualHost *:443>`
that `apache2ctl -S` reports as the "default server" for `:443`:

```apache
<VirtualHost *:443>
    LimitRequestFieldSize 65536
    ...
</VirtualHost>
```

Then `apache2ctl configtest` and restart. Verify by reproducing directly against the
origin (bypass the CDN): `curl --resolve <host>:443:127.0.0.1 https://<host>/... -H "Cookie: junk=<~10KB of a's>"` should return the app's normal code, not 400.

**Next ceiling after Apache:** Node's default `--max-http-header-size` is ~16 KB, so a
Next.js standalone server returns `431` above that (well above real cookie sizes for
now).

**Structural fix (DONE 2026-07-18):** each app's session cookie is now scoped to its
basePath (`path: "/<app>"`) so the browser only sends it to that app's subtree — they
stop accumulating. Rolled out to collab, employ, shopper, foodie, travel, finance,
health-hub, runeval (verified: page render + OAuth POST redirect_uri intact per app;
the OAuth callback does NOT read the session cookie — the auth-proxy uses only the
`__auth_target` cookie — so subpath scoping is safe). New apps should ship scoped from
day one (see the config above). Deploy gotchas learned during the rollout:
- Apps whose `basePath` comes from an env var (finance, runeval) must be built with
  `BASE_PATH` / `NEXT_PUBLIC_BASE_PATH` set, or every route 404s.
- Some apps keep runtime data INSIDE `.next/standalone/` (runeval: `standalone/data`,
  `standalone/prisma/data`) — exclude those dirs from an `rsync --delete` or it breaks.
- Health checks: some apps' `/api/health` is auth-gated (401 by design, e.g. health-hub,
  runeval) — use page-render 200/307/308 as the liveness signal, not health==200.

## Mobile native sign-in (Capacitor WebView apps) — the SHA-1 gotcha (2026-07-11)

WebView-shell apps (e.g. `pezant-mobile`) can't do OAuth in the WebView — Google blocks
embedded WebViews with `disallowed_useragent`. Instead they do **native** Google Sign-In
via Credential Manager (`@capgo/capacitor-social-login`), get an ID token, and POST it to
a server endpoint that mints the web app's session cookie(s). The mint endpoint verifies
the token's `aud` against the **web** OAuth client id (the `serverClientId`).

**The trap that silently breaks sign-in for every user:** Credential Manager authorizes
the *calling app* by package name + its **signing-cert SHA-1**, matched against an
**Android** OAuth client in the Google Cloud project. If the SHA-1 of the *installed*
build is not registered, the plugin returns **no idToken** and sign-in fails silently —
the server never even sees a request (its mint logs stay empty).

**An Android OAuth client holds exactly ONE package + ONE SHA-1** — there is no "add
fingerprint" (that only exists for API-key restrictions). So you need a **separate Android
OAuth client per signing cert**, all sharing the same package name. With **Play App Signing
ON** (the default), the installed app is re-signed by Google, so its cert is NOT your
upload key. Create a client for the SHA-1 of **every distribution channel**:
- **Play App Signing key** SHA-1 (Play Console -> App integrity -> App signing key
  certificate) — required for all Play installs (testers + prod). A client for only the
  upload key breaks 100% of Play installs.
- **Debug key** SHA-1 (`~/.android/debug.keystore`) — for `assembleDebug` sideloads.
- Upload-key SHA-1 alone is never sufficient once Play App Signing is on.

Debugging checklist for "mobile sign-in does nothing / broken across the board":
1. Confirm the mint endpoint is up and web OAuth works (`curl .../api/auth/providers`).
2. Check the mint endpoint's logs — zero "minted" lines means the failure is on-device,
   before the POST (points at SHA-1 / Credential Manager, not the server).
3. Get the installed build's channel + that channel's SHA-1; verify an Android OAuth client
   (same package) exists for it, and create one if not. Don't swallow the plugin's error in
   JS — log it so `adb logcat` shows it.

**Automation caveat (browser-agent):** it can read the Cloud Console client *list* to
confirm what's registered, but it CANNOT reliably drive the "Create OAuth client" form (the
Application-type dropdown / Material form is not automatable) and CANNOT read the Play App
Signing SHA-1 (Play Console renders the cert inside a frame the content script can't reach).
Treat client creation as a manual Cloud Console step, driven on the project-owner's browser
profile (not an alt account that lacks project access).

## Rules for Future Work

1. **Never set AUTH_URL to include the app basePath** without also setting an explicit `basePath` in the NextAuth config. The `||` assignment in `setEnvDefaults` will silently corrupt basePath otherwise.

   **AUTH_URL options for Auth.js v5 subpath apps (updated 2026-06-03):** there are two working patterns; both require the explicit `basePath: "/api/auth"` above.
   - **Bare origin** (canonical, simpler): `AUTH_URL=https://example.com` — `setEnvDefaults()` extracts `"/"` as the pathname, which doesn't conflict with the explicit basePath. Works for most apps and is the default recommendation (see "AUTH_URL origin-only pattern for tunneled apps" above).
   - **Full path** (needed in some Auth.js v5 configurations): `AUTH_URL=https://example.com/runeval/api/auth` — includes both the app subpath AND the NextAuth basePath. The `setEnvDefaults()` extraction of `/runeval/api/auth` is overridden by the explicit `basePath: "/api/auth"`. This pattern fixed CSRF token mismatches in runeval under Auth.js v5 (Gemini fix `3f50b89`, 2026-06-03), where the bare-origin pattern caused auth failures.

   The danger zone remains the middle ground described above: `AUTH_URL=https://example.com/runeval` (app subpath only, no `/api/auth`) lets `setEnvDefaults()` extract `/runeval` as basePath, overriding the explicit config and breaking action parsing.

   **Rule of thumb:** if starting fresh, use bare origin first; if CSRF failures appear with bare origin already set, try the full-path pattern next.

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

5. **`getToken` must mirror both `secureCookie` and custom `cookieName`**: When using `getToken` from `next-auth/jwt` in middleware, pass both `secureCookie: true` and—when you've set a custom sessionToken cookie name—the matching `cookieName`.
   - **`secureCookie: true`**: required behind a reverse proxy. The internal request URL is HTTP, so `getToken` defaults to looking for `authjs.session-token` (no `__Secure-` prefix). But NextAuth sets `__Secure-authjs.session-token` based on HTTPS `NEXTAUTH_URL`. Without this, middleware never finds the token.
   - **`cookieName`**: required when you've set a per-app custom cookie name in auth.ts (which you should—see Session Cookie Isolation above). `getToken` defaults to `__Secure-authjs.session-token` even if your auth.ts configured `__Secure-finance.session-token`. Mismatch = token never found = post-login redirect loop.
   - **Rule**: if you change the cookie name in auth.ts, change it in the `getToken` call in middleware.ts too.
   ```typescript
   // middleware.ts — correct for custom-named cookie behind a proxy
   const token = await getToken({
     req,
     secret: process.env.AUTH_SECRET!,
     secureCookie: true,
     cookieName: "__Secure-<appname>.session-token",
   });
   ```
   Real incident: finance-tracker 2026-05-29 — post-login redirect loop caused by missing `cookieName` in `getToken` after `__Secure-finance.session-token` was configured in auth.ts.

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

8. **Standalone basePath stripping — RESOLVED for Next.js 16.2.8+ (updated 2026-07-09).** Historically this file carried two contradictory claims: (a) standalone STRIPS the basePath so NextAuth `basePath` must be `/api/auth` (shopper/foodie/humans note above), and (b) standalone does NOT strip it so `basePath` must be `/<app>/api/auth` (the finance-tracker note this bullet used to assert). **Both cannot be true, and the version matters.** As of **Next.js 16.2.8+ (verified on 16.2.9)**, `output: 'standalone'` **STRIPS the basePath** from `req.url` before Route Handlers AND middleware run — identical to `next dev`. The "does NOT strip" behavior belonged to an earlier Next.js and is no longer correct.

   **This caused a total OAuth outage on runeval (2026-07-09)** after a Dependabot bump 16.2.7 → 16.2.9. runeval used `basePath: "${NEXT_PUBLIC_BASE_PATH}/api/auth"` = `/runeval/api/auth`; once standalone started stripping, the incoming path became `/api/auth/...` and every `/runeval/api/auth/*` endpoint threw `[auth][error] UnknownAction: Cannot parse action at /api/auth/session` (HTTP 400). Insidious detail: server-side `auth()` session reads keep working (they build the URL via `createActionURL(AUTH_URL + basePath)`, not the request path), so **pages return 200 while sign-in is dead** — a homepage uptime check misses it entirely.

   Two valid fixes:
   - **(A) `basePath: "/api/auth"`** (the stripped form). Simplest, but `createActionURL` then builds the OAuth `redirect_uri` WITHOUT the subpath (`https://host/api/auth/callback/google`), so you must restore `/<app>` via a `customFetch` or an Apache redirect (finance-tracker does this).
   - **(B) keep `basePath: "/<app>/api/auth"` and re-prepend the subpath to the request pathname in a thin `route.ts` wrapper** before delegating to next-auth's `handlers.GET/POST`. Keeps `redirect_uri` correct with NO customFetch — preferred when the app forbids customFetch hacks (e.g. runeval). runeval's `restoreAuthBasePath()` (`lib/basePath.ts`) does this; it is idempotent so it survives a future Next reverting to non-stripping. runeval commit `5032c55`.

   **Always verify a Next.js bump against a REAL standalone build, not `next dev`:** `curl http://127.0.0.1:PORT/<app>/api/auth/providers` must return 200 JSON, and a signin POST must 302 to the IdP with `redirect_uri` including `/<app>`.

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

12. **Never concatenate `NEXTAUTH_URL` directly with `BASE_PATH` to build app URLs.** `NEXTAUTH_URL` may include a pathname on the VM (e.g., `https://example.com/finance`) even when the "origin-only" rule above is followed in older deployments. Concatenating it with `BASE_PATH` (also `/finance`) produces double-path URLs like `/finance/finance/cards` that are silently wrong — no build error, no 404 from the server, just broken links in emails or redirect callbacks.

    **Fix:** Always strip the pathname from `NEXTAUTH_URL` before appending `BASE_PATH`:
    ```typescript
    // src/lib/origin.ts — helper used in benefit-reminder emails and SnapTrade redirects
    export function getAppOrigin(): string {
      const raw = process.env.NEXTAUTH_URL ?? process.env.AUTH_URL ?? "";
      try {
        return new URL(raw).origin;  // strips pathname, search, hash
      } catch {
        return raw;  // fallback: return as-is
      }
    }

    // Usage
    const url = `${getAppOrigin()}${process.env.NEXT_PUBLIC_BASE_PATH}/cards`;
    ```

    **Why it happens:** `NEXTAUTH_URL` must include the pathname for the NextAuth `setEnvDefaults()` basePath derivation to work (per rule #1), but server-side code constructing non-auth URLs must use only the origin. Storing them in the same var creates the double-path risk for any code that hasn't read this rule.

    Source: finance-tracker commit `95b3477` (2026-06-02).

13. **Trap JWT decode errors to prevent AUTH_SECRET rotation crash loops.** When `AUTH_SECRET` is rotated, cookies encrypted with the old secret cause Auth.js to throw `JWTSessionError` inside the JWT callback, which kills the `next-server` worker. PM2 restarts it, but if the old worker hasn't released its port yet, the new one hits `EADDRINUSE` → crash → repeat. Foodie saw **349 restarts** from this pattern on 2026-06-02. Fix: wrap `jwt.decode` in `try/catch` in the NextAuth config's `jwt` callback; on failure return `null` (treats the request as anonymous). Never let a stale cookie crash the server — treat it as an expired session instead.
    ```typescript
    callbacks: {
      jwt: async ({ token, user }) => {
        try {
          // normal jwt logic
        } catch (err) {
          console.warn("JWT decode error (stale secret?), treating as anonymous:", err);
          return null; // anonymous session
        }
      }
    }
    ```

14. **Export HEAD and OPTIONS handlers on auth routes to prevent UnknownAction errors.** Health checks and CORS preflights that hit `GET /api/auth/[...nextauth]` throw Auth.js `UnknownAction` because Auth.js only exports `GET` and `POST`. Fix: add explicit stubs in your route handler:
    ```typescript
    export const { GET, POST } = handlers;
    export const HEAD = () => new Response(null, { status: 200 });
    export const OPTIONS = () => new Response(null, { status: 200 });
    ```

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

## Third-Party API OAuth Token Refresh

When integrating with external APIs that issue short-lived access tokens (~24h), **auto-refresh on expiry — do not return errors to callers**.

### The pattern

Third-party APIs (Garmin Connect, Strava, etc.) issue access tokens that expire in ~24h alongside long-lived refresh tokens. A route that stores and uses these tokens should:

1. Check expiry before calling the downstream API
2. If expired, call the provider's token refresh endpoint with the stored `refresh_token`
3. Persist the new `access_token` and `expires_at` to DB
4. Proceed with the original request using the fresh token
5. Only return a "user must re-link" error if the **refresh itself** fails (e.g., refresh token also expired or revoked)

```typescript
// health-hub: src/app/api/garmin/training/push/route.ts
let accessToken = tokenRow.accessToken;
if (tokenRow.expiresAt && tokenRow.expiresAt.getTime() < Date.now()) {
  try {
    const refreshed = await refreshAccessToken(tokenRow.refreshToken);
    const newExp = new Date(Date.now() + (refreshed.expires_in ?? 86400) * 1000);
    await prisma.oAuthToken.update({ where: { id: tokenRow.id },
      data: { accessToken: refreshed.access_token, expiresAt: newExp } });
    accessToken = refreshed.access_token;
  } catch {
    return Response.json({ error: "Token refresh failed; user must re-link" }, { status: 401 });
  }
}
```

### Why this matters

Without silent refresh, **any automated job that runs daily against a ~24h-lived access token will fail after the first day**. The Garmin daily push-to-watch cron (runeval → health-hub) hit this: the initial OAuth flow sets the access token, the cron runs fine on day 1, then fails with 401 every day after until the user manually re-links. Silent refresh means the cron never surfaces this failure.

### What NOT to do

- Do NOT return `{ error: "OAuth token expired; user must re-link" }` on expiry of a short-lived access token. This surfaces unnecessary friction when a refresh is all that's needed.
- Do NOT cache the `access_token` in env vars or process memory — always read it from DB so refreshes are immediately visible to all processes.

**Source:** health-hub commit `69aa711` (2026-06-07) — Garmin push route switched from 401-on-expiry to silent auto-refresh, fixing the automated daily push-to-watch cron.

**Trade-off:** Simpler (no Apache redirect needed), but couples the callback URL to the env var. The three-part pattern is more robust for complex proxy setups.

## Gating a secret/page to one Google identity: reuse the Apache OIDC gate (2026-06-23)

Before reaching for Cloudflare Access / Zero Trust (which needs first-time onboarding: a team-domain choice + a payment method on file), check the Apache config. The VM already runs `mod_auth_openidc` gating admin surfaces:
```apache
<Location /tools>
    AuthType openid-connect
    Require user <owner-email>
</Location>
```
Same pattern protects `/tm-scripts` and the auto-shorts admin. To gate a secret behind Google-login-restricted-to-one-email, serve it from a path UNDER `/tools` (e.g. a Node route `/tools/<name>` sourcing the value from env) — it's automatically OIDC-gated, single login, no new infra. Carve-outs use `AuthType None; Require all granted` (e.g. `/tools/downloads`, `/tools/health`, `/api/notify`).

**M2M caveat:** headless pollers and shell hooks CANNOT be interactively OAuth-gated (they'd get an HTML login page instead of JSON). Keep those on a rotated bearer token (`Require all granted` at Apache, token-auth in the app) and gate only the human *retrieval* of the token.

## OIDC gate has its own cookie-accumulation trap, separate from NextAuth's (2026-07-18)

The `mod_auth_openidc` gate above (previous section) can hit the same "400 Size of a request header field exceeds server limit" symptom as the NextAuth `path=/` issue documented above under "Cookie accumulation exceeds Apache's header limit" — but from a different root cause, so that section's fix doesn't cover it.

`mod_auth_openidc` sets a `mod_auth_openidc_state_<random>` cookie (~460 bytes, scoped to the gated path) on every login round-trip. Incomplete flows — extra tabs, the back button, expired states — leave the old state cookie behind instead of clearing it, so they accumulate across repeated attempts until the combined `Cookie:` header blows the same `LimitRequestFieldSize` limit. Symptom is identical (400 from Apache, gate itself still healthy — a cookie-less request still gets a clean redirect to the identity provider); a curl without cookies will look fine, which makes this easy to misdiagnose as an unrelated NextAuth issue on a shared domain.

**Fix:** add `OIDCStateMaxNumberOfCookies <n> true` right after the relevant `OIDCCookie` directive in the vhost. This bounds concurrent state cookies to `<n>` and auto-deletes the oldest once the limit is hit. It's a vhost-scope (`RSRC_CONF`) directive, so one instance in the default `:443` vhost protects every `mod_auth_openidc`-gated path served from it, not just the one that triggered the report. `apache2ctl configtest` then reload.

**The fix only stops future accumulation** — a browser already carrying the bloated cookie set must clear cookies for the domain (or use a private window) once to recover immediately; existing state cookies age out on their own otherwise.

## OIDCCookiePath must be the common ancestor of ALL gated paths, or new paths loop forever (2026-07-22)

When one vhost gates multiple paths behind the same `mod_auth_openidc` config (the "reuse the Apache OIDC gate" pattern above), the directives are vhost-global, not per-`<Location>` — there is exactly one `OIDCCookiePath` shared by every gated path on that vhost. If it's scoped to whichever path was gated first (e.g. `OIDCCookiePath /first-gated-path`), the session cookie's `Path=` attribute never covers a path added later, so that new path never receives the cookie and loops back to the identity provider forever. This is easy to misdiagnose as a routing or callback bug: each redirect in the flow looks correct in isolation, and the ORIGINAL gated path keeps working fine throughout.

**Fix:** set `OIDCCookiePath /` — the common ancestor of every current and future gated path, plus the shared callback URL. Do not scope it to a subpath, even the one gated first.

**Recovery:** a browser already holding the stale `Path=/<old>` cookie must clear cookies for the domain (or use a private window) once; the old cookie doesn't get invalidated on its own when the config changes.
