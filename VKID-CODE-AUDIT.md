# VK ID migration: server code audit

Branch: `rebuild-vkid-auth`

Audit date: 2026-11-26

This is an inventory of the current server-side authentication code. It is not a production change and does not enable VK ID sign-in.

## Findings

### `storage-api/server.js`

The storage API currently has a Logto-only administrator check:

- Reads `LOGTO_ENDPOINT`, `LOGTO_API_RESOURCE`, `ADMIN_EMAIL`, and a Logto JWKS URL.
- Verifies a Logto RS256 access token and then separately calls the Logto `/oidc/me` endpoint using `X-Logto-Userinfo-Token`.
- Grants administrator access by matching a verified email address to `ADMIN_EMAIL`.
- Protects `GET /api/admin/keys`, `POST /api/admin/keys`, and `DELETE /api/admin/keys/:id` with that check.
- The health endpoint reports the access-key manager as configured only when the Logto settings and `ADMIN_EMAIL` are present.
- CORS currently allows `Authorization`, `Content-Type`, and `X-Logto-Userinfo-Token`; it does not yet support cookie credentials or CSRF tokens.

The separate upload API key and scoped storage keys are not human login. Keep those mechanisms separate from VK ID account sessions.

### `cloud-server/server.js`

The cloud server also has a separate Logto-only administrator implementation:

- Fetches and caches Logto JWKS, verifies RS256 signatures and token claims, then calls `/oidc/me`.
- Uses `ADMIN_EMAIL` plus `email_verified` to authorize administrators.
- Uses the same `Authorization: Bearer` plus `X-Logto-Userinfo-Token` request pattern.
- Protects channel administration endpoints: `GET /api/admin/status`, `POST /api/admin/upload`, `PUT /api/admin/playlist`, `POST /api/admin/broadcast/start`, and `POST /api/admin/broadcast/stop`.
- The learning event and recommendation write endpoints also call the same authorization check.

The two APIs currently duplicate identity verification. The migration should converge on one documented VK ID identity/session contract rather than introduce two slightly different VK checks.

## Required migration sequence

1. Register the VK ID application and confirm its numeric App ID and exact callback URL.
2. Decide the production topology for frontend and APIs. GitHub Pages plus unrelated API hostnames can cause browser third-party-cookie restrictions; CORS by itself does not solve this.
3. Choose persistent session storage shared by the APIs, or put the session/authentication gateway in front of both APIs.
4. Implement one VK ID callback/session service. Verify the VK-issued access token server-side using the official VK ID user-info flow; derive the numeric VK user ID only from the verified VK response.
5. Use an explicit server-side `VK_ADMIN_USER_IDS` allowlist. Do not use email, display name, browser-supplied IDs, or client-side role flags.
6. Migrate every protected route in both APIs and update the admin pages/guard to consume the same session contract.
7. Add tests for invalid tokens, non-admin users, session expiry/revocation, CSRF/Origin enforcement, restart persistence, and both mobile and desktop browser flows.
8. Only after the full flow passes, remove Logto references and credentials. Keep the old production path untouched until then.

## VK ID SDK compatibility note

The official Web SDK documents OAuth 2.1 and PKCE. Its code-exchange method returns a token result without an `id_token` in its declared result type, and its user-info method posts the access token to the SDK-configured VK ID domain's `/oauth2/user_info` endpoint. Do not hardcode an assumed host based on old examples; follow the current official SDK/application configuration and verify the production domain before implementing the server call.

Official references:
- https://github.com/VKCOM/vkid-web-sdk
- https://github.com/VKCOM/vkid-web-sdk/blob/master/src/auth/auth.ts
- https://github.com/VKCOM/vkid-web-sdk/blob/master/src/auth/types.ts
- https://github.com/VKCOM/vkid-web-sdk/releases

## Current blockers

- No real VK ID App ID is configured.
- No verified administrator VK numeric ID has been supplied for the server allowlist.
- The production frontend/API same-site or proxy design is not selected.
- No persistent session store has been configured.
- The two APIs still use Logto, so the VK ID button must remain disabled.

No secrets, real tokens, or administrator identifiers belong in this repository.
