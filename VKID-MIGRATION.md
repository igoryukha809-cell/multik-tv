# VK ID authentication migration

## Goal

Replace the former Logto/GitHub sign-in flow with VK ID. The site must not collect a separate site password or require users to type an email address into a site form.

## Repository audit

The following files currently depend on Logto and must be migrated together:

- `login.html` — imports Logto and automatically starts GitHub sign-in on page load.
- `logto-config.js` — contains the former public Logto SPA configuration.
- `admin-guard.js` — uses Logto access tokens to protect admin-only pages.
- `admin.html` — checks admin access through the old Logto-backed storage API.
- `access-keys.html` — obtains Logto tokens and calls the storage API.
- `storage-api/server.js` — validates Logto JWTs and calls the Logto user-info endpoint.
- `cloud-server/server.js` — has a separate Logto token and user-info validation implementation.

The public website contains many pages and media features. Keep those intact; replace only the identity and authorization integration.

## Confirmed SDK details

- Official package: `@vkid/sdk`.
- Current official Web SDK documentation inspected for this migration: version `2.6.1`.
- The SDK supports OAuth 2.1 and PKCE.
- The documented setup uses `VKID.Config.init({ app, redirectUrl, state, codeVerifier, scope })`, followed by `VKID.Auth.login()`.
- The SDK exposes `Auth.exchangeCode`, `Auth.userInfo`, and `Auth.publicInfo`; callback handling must follow the current official SDK documentation.
- The official release notes state that VK integrations/authentication have moved to the `vk.ru` domain. Use the current SDK rather than hand-building legacy VK OAuth URLs.

Official references:
- https://github.com/VKCOM/vkid-web-sdk
- https://vkcom.github.io/vkid-web-sdk/docs/index.html
- https://github.com/VKCOM/vkid-web-sdk/releases

## Target architecture

1. Use the official VK ID Web SDK in the browser with OAuth 2.1 and PKCE.
2. Register the exact HTTPS callback URL in the VK ID application settings.
3. Process the callback and exchange the authorization code using the supported VK ID flow.
4. Validate the resulting identity on the server. Never trust a user ID, profile fields, or an unsigned browser value supplied by the client.
5. Create a server-managed session using secure, HttpOnly, SameSite cookies. Do not store long-lived access or refresh tokens in localStorage.
6. Keep administrator authorization separate from ordinary sign-in. A successful VK ID login must not automatically grant administrator privileges.
7. Keep tokens and any confidential application credentials out of GitHub Pages, source control, browser bundles, and logs.
8. Preserve public pages and existing media/catalog features while removing Logto-specific code from protected pages and API middleware.

## Configuration required before live authentication

The VK ID application owner must configure the production callback URL and provide the public application ID. Any confidential credential, if required by the selected VK ID application type, must be stored only in the hosting provider's protected environment settings.

Do not commit credentials. Do not put secrets in this file.

## Implementation checklist

- [ ] Confirm the VK ID application ID and exact callback URL.
- [ ] Add a single public VK ID configuration module.
- [ ] Replace automatic redirect-to-GitHub behavior with an explicit VK ID sign-in button.
- [ ] Implement callback handling using the official SDK and PKCE.
- [ ] Implement server-side token/identity validation and a secure server session.
- [ ] Replace Logto checks in the admin pages, storage API, and cloud server.
- [ ] Preserve the separate server-side administrator allowlist/role check.
- [ ] Add tests for invalid state, expired/invalid tokens, wrong issuer/audience, CSRF, and non-admin users.
- [ ] Deploy the API only after the required configuration is present; verify health and sign-in end to end.
- [ ] Remove obsolete Logto configuration only after VK ID is deployed and verified.

## Deployment status

This migration branch is a preparation branch. Production login has not been switched. The VK ID application ID and callback registration are not yet available, and the API has not yet been deployed with the new authentication flow. Do not claim that VK ID sign-in is live until the end-to-end checks pass.
