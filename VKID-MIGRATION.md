# VK ID authentication migration

## Goal

Replace the former Logto/GitHub sign-in flow with VK ID. The site must not collect a separate site password or require users to type an email address into a site form.

## Repository audit

The migration branch has already replaced the old login page with a VK ID placeholder, but live authentication is not implemented yet.

Current state of the relevant files:

- `login.html` — VK ID landing page. It no longer starts GitHub sign-in automatically. The sign-in button remains disabled until the app configuration and server callback/session flow are ready.
- `vkid-config.js` — public configuration scaffold. `VKID_APP_ID` is still set to `0`; the callback URL is a placeholder for the current GitHub Pages address and must be confirmed in the VK ID application settings.
- `logto-config.js` — legacy configuration; verify all references before removing it.
- `admin-guard.js` — still part of the legacy protected-page flow and needs migration.
- `admin.html` and `access-keys.html` — still need to be connected to the new server-managed session and authorization checks.
- `storage-api/server.js` — legacy Logto token validation remains to be replaced.
- `cloud-server/server.js` — has a separate legacy Logto token/user-info validation implementation that also needs migration.

The public website contains many pages and media features. Keep those intact; replace only the identity and authorization integration. Do not delete legacy auth code until the replacement is deployed and verified.

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

- [x] Create the VK ID login-page scaffold and public config module.
- [x] Remove the old automatic GitHub sign-in behavior from `login.html`.
- [ ] Confirm the VK ID application ID and exact callback URL in the VK ID dashboard.
- [ ] Enable the VK ID button only after the callback and session endpoints are ready.
- [ ] Implement callback handling using the official SDK and PKCE, following its documented state/code-verifier behavior.
- [ ] Implement server-side identity validation and a secure server-managed session.
- [ ] Replace Logto checks in the admin pages, storage API, and cloud server.
- [ ] Preserve the separate server-side administrator allowlist/role check.
- [ ] Add tests for invalid state, expired/invalid tokens, incorrect client/application binding, CSRF, and non-admin users.
- [ ] Deploy the API only after the required configuration is present; verify health and sign-in end to end.
- [ ] Remove obsolete Logto configuration only after VK ID is deployed and verified.

## Deployment status

This migration branch is a preparation branch. Production login has not been switched. The VK ID application ID and callback registration are not yet available, and the API has not yet been deployed with the new authentication flow. Do not claim that VK ID sign-in is live until the end-to-end checks pass.
