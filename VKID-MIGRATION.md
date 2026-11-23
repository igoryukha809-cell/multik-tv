# VK ID authentication migration

## Goal

Replace the former Logto/GitHub sign-in flow with VK ID. Do not collect a separate site password or ask users to type an email address into the site.

## Current state

- The public site is hosted from GitHub Pages.
- The previous login page used Logto with GitHub as its social provider.
- The Railway project currently has an empty production environment; its previous API service was removed.
- The existing storage API source is still in this repository and currently validates Logto tokens. It is not compatible with VK ID until its authentication middleware is replaced.

## Planned flow

1. Use the official VK ID Web SDK (OAuth 2.1 with PKCE) in the browser.
2. Register the exact HTTPS callback URL in the VK ID application settings.
3. Process the authorization callback and exchange the authorization code using the supported VK ID flow.
4. Validate the resulting identity on the server. Never trust a user ID, profile fields, or an unsigned browser value supplied by the client.
5. Keep administrator authorization separate from ordinary sign-in. A successful VK ID login must not automatically grant administrator privileges.
6. Keep tokens and any confidential application credentials out of GitHub Pages, source control, browser bundles, and logs.
7. Preserve public pages and the existing media/catalog features while removing Logto-specific code from protected pages and API middleware.

## Configuration required before live authentication

The VK ID application owner must configure the production callback URL and provide the public application ID. Any confidential credential, if required by the selected VK ID application type, must be stored only in the hosting provider's protected environment settings.

Do not commit credentials. Do not put secrets in this file.

## Implementation checklist

- [ ] Confirm the VK ID application ID and exact callback URL.
- [ ] Add a single public VK ID configuration module.
- [ ] Replace automatic redirect-to-GitHub behavior with an explicit VK ID sign-in button.
- [ ] Implement callback handling using the official SDK and PKCE.
- [ ] Implement server-side token/identity validation for the current VK ID protocol.
- [ ] Replace Logto checks in the admin pages and storage API.
- [ ] Preserve the separate server-side administrator allowlist/role check.
- [ ] Add tests for invalid state, expired/invalid tokens, wrong audience/issuer, and non-admin users.
- [ ] Deploy the API only after the required configuration is present; verify the health endpoint and sign-in flow.
- [ ] Remove obsolete Logto configuration only after the VK ID flow is deployed and verified.

## Official SDK

Use the official VKCOM Web SDK and its current documentation. Pin a reviewed SDK version rather than loading an unpinned package version from a CDN.
