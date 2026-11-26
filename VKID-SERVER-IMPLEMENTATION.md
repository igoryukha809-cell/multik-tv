# VK ID server authentication implementation

## Scope and current status

This document specifies the server migration for the `rebuild-vkid-auth` branch. It does not activate sign-in and does not change production. The current storage API and cloud server still validate Logto tokens; do not remove that code until the VK ID flow has passed end-to-end tests.

The goal is VK ID-only sign-in: no site password and no email address as the account identifier.

## Verified VK ID SDK behavior

The official `@vkid/sdk` Web SDK uses OAuth 2.1 with PKCE. Its `Auth.exchangeCode(code, deviceId, codeVerifier?)` method exchanges the authorization code and checks the returned state. Its TypeScript result is explicitly typed as `Omit<TokenResult, 'id_token'>`. The SDK also provides `Auth.userInfo(accessToken)`, which sends the access token to VK ID's `/oauth2/user_info` endpoint and returns a user object with a `user_id` field.

Implementation implications:

- Let the official SDK handle the authorization redirect, PKCE verifier, authorization-code exchange, and state check.
- Do not assume an ID token is returned by `exchangeCode`.
- After exchange, send only the access token to the API over HTTPS. The API must call VK ID's user-info endpoint itself and use the returned `user.user_id`; never trust a user ID supplied by browser JavaScript.
- Do not request or require the email scope. The VK numeric user ID is the stable account key for this service.
- Never log access tokens or store them in localStorage.

Official source references:
- https://github.com/VKCOM/vkid-web-sdk
- https://github.com/VKCOM/vkid-web-sdk/blob/master/src/auth/auth.ts
- https://github.com/VKCOM/vkid-web-sdk/blob/master/src/auth/types.ts

## Proposed API contract

An initial shared implementation now exists in `auth-service/`. It is not deployed and is not yet connected to the browser login page. The service requires PostgreSQL and a shared cookie parent domain; see `auth-service/README.md`. The APIs can call its private `/internal/session` and `/internal/authorize` endpoints when `AUTH_SERVICE_URL` and `AUTH_SERVICE_SECRET` are configured. State-changing API calls must include `X-CSRF-Token`.

### `POST /api/auth/vk/session`

Request JSON: `{ "accessToken": "<short-lived VK ID access token>" }`

Server steps:

1. Require HTTPS, JSON size limits, an exact allowed Origin, and a rate limit.
2. Reject missing, malformed, or oversized access tokens.
3. Call `https://id.vk.ru/oauth2/user_info` using POST form data containing `client_id` and `access_token`, following the official SDK's current endpoint behavior.
4. Require a successful VK response and a non-empty `user.user_id`.
5. Discard browser-supplied profile fields. Use only the server-verified VK response.
6. Create a random opaque session ID. Store only its hash server-side with the VK user ID, creation time, expiry, and revocation state.
7. Set the opaque session cookie as `HttpOnly; Secure; SameSite` according to the final domain topology. Never return the session ID in JSON.

### `GET /api/auth/session`

Read the opaque cookie, look up the hashed session, enforce expiry/revocation, and return only non-sensitive profile fields needed by the UI. Return the user's numeric VK ID and an `isAdmin` boolean computed on the server.

### `POST /api/auth/logout`

Revoke the current server-side session and clear the cookie.

## Administrator authorization

Use a server-side environment variable such as `VK_ADMIN_USER_IDS`, containing an explicit comma-separated allowlist of numeric VK user IDs. Compare the verified VK ID from the stored session against that allowlist.

- A successful VK ID sign-in grants an ordinary user session only.
- Never grant administrator access based on a display name, email address, browser flag, or client-supplied VK ID.
- Keep admin checks on every protected API route, including key creation/listing/revocation and cloud broadcast controls.
- Keep API access keys separate from human administrator sessions.

## Session storage and domain constraint

The public frontend currently runs on GitHub Pages, while the APIs are hosted separately. A cookie issued by a separate API hostname may be treated as a third-party cookie by browsers, and browser privacy controls can block it. CORS alone does not solve that.

Before implementing cookie sessions, choose one of these deployment designs:

1. Serve the frontend and API under the same site using a custom domain and an API subdomain (same-site cookies), or
2. Proxy API requests through the frontend's site origin.

Use a persistent session store (managed database or Redis-compatible store) rather than an in-memory map so sessions survive restarts and work across multiple instances. Do not store sessions in a public repository or a static JSON file.

## Required environment configuration

- `VKID_APP_ID` — public numeric application ID; may also be used by the frontend config.
- `VK_ADMIN_USER_IDS` — server-only numeric administrator allowlist.
- `SESSION_SECRET` — server-only random secret for session/CSRF protections, if required by the chosen session implementation.
- `DATABASE_URL` — private PostgreSQL connection string for the persistent session store.
- `SESSION_COOKIE_DOMAIN` — shared parent domain for frontend and API subdomains (for example `.example.com`); GitHub Pages `github.io` cannot provide this arrangement.
- `VKID_API_ORIGIN` — exact current HTTPS origin used by VK ID UserInfo, taken from the active VK ID SDK/application configuration.
- `PUBLIC_SITE_ORIGIN` — exact frontend origin used for Origin/CORS checks.
- `VKID_REDIRECT_URI` — exact callback URL registered in the VK ID application dashboard.

No secret belongs in GitHub Pages or a committed config file.

## Migration map

- `storage-api/server.js`: replace `adminAuth` with session middleware and VK-ID allowlist check; update CORS for credentials only after same-site/proxy architecture is in place.
- `cloud-server/server.js`: remove the custom Logto JWT/JWKS verifier only after replacing `adminUser` with the same session/allowlist model. Do not keep two independent identity implementations.
- `admin-guard.js`: check `GET /api/auth/session`; show the admin interface only when the API reports `isAdmin: true`.
- `admin.html`: use the same session check; do not import Logto.
- `access-keys.html`: remove Logto token handling and use cookie-authenticated API requests with `credentials: "include"` and CSRF protection.
- `login.html`: enable the VK ID button only after the server endpoints, domain topology, and app registration are ready.
- `logto-config.js`: remove only after repository-wide reference checks and a successful VK ID rollout.

## Security and acceptance tests

- Invalid, expired, revoked, or VK-rejected access tokens cannot create a session.
- A browser-supplied `user_id`, `email`, `isAdmin`, or display name cannot affect identity or role.
- Only IDs in `VK_ADMIN_USER_IDS` can access admin routes.
- Missing/incorrect Origin and CSRF attempts are rejected for cookie-authenticated state changes.
- Session IDs are random, opaque, HttpOnly, Secure, expire, and can be revoked.
- Sessions survive API restart and behave consistently across instances.
- No access token, refresh token, cookie, or session secret appears in logs.
- Public pages, video listing, upload keys, and channel features continue to work.
- Test the actual GitHub Pages/custom-domain browser flow on mobile and desktop before enabling the button.

## Blockers before implementation

1. VK ID application registration and real `VKID_APP_ID`.
2. Confirmation of the callback URL in VK ID settings.
3. The numeric VK user ID(s) that should have administrator privileges.
4. Decision on the frontend/API same-site domain or proxy arrangement.
5. Persistent PostgreSQL provisioning, shared cookie-domain configuration, and hosting configuration.

Until these are provided/configured, the VK ID button must remain disabled and the existing production authentication must remain untouched.


## Current implementation status (2026-11-26)

- Added `auth-service/`: server-side VK UserInfo verification, opaque PostgreSQL-backed sessions, secure shared-domain cookie, server-side VK numeric-ID admin allowlist, logout revocation, and internal session verification.
- Both API servers can delegate administrator checks to the shared service when its private URL and secret are configured. Legacy Logto remains as the fallback until the VK ID deployment and frontend migration are complete.
- Mutating API requests delegated to VK ID must pass CSRF verification through `/internal/authorize`.
- Added `.github/workflows/vkid-auth-check.yml` for helper tests and JavaScript syntax checks.
- Not yet complete: VK ID SDK callback integration in the browser, app registration, database provisioning, shared custom-domain/proxy setup, server environment configuration, full end-to-end tests, and deployment.
