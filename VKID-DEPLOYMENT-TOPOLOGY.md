# VK ID migration: deployment topology audit

Audit date: 2026-11-26
Branch: `rebuild-vkid-auth`

This document records which server components are actually represented by the repository's current deployment configuration. It does not create cloud resources or change production.

## What the repository currently configures

### GitHub Pages frontend

The public frontend is configured for GitHub Pages at:

`https://igoryukha809-cell.github.io/multik-tv/`

A GitHub Pages static site cannot run Node.js session endpoints. It can host the VK ID browser SDK and static pages, but the authorization-code exchange, token verification, persistent session creation, and administrator checks must run on a server.

### Root Render Blueprint

The root `render.yaml` defines one service:

- Name: `multik-tv-test-stream`
- Root directory: `stream-server`
- Dockerfile: `stream-server/Dockerfile`
- Plan: `free`

It does not deploy `cloud-server` or `storage-api`. Therefore it cannot be treated as the production API host or as the shared VK ID session service.

### Cloud server

`cloud-server/docker-compose.yml` defines SRS, a Node.js API, and an FFmpeg director. The API currently uses Logto environment variables and binds its port to localhost inside the compose host. The repository does not contain a Render Blueprint for this service.

### Storage API

`storage-api/Dockerfile` builds the storage API, but there is no dedicated deployment manifest in the repository. Its current administrator routes still depend on Logto.

## Consequence for VK ID sessions

The current setup has a static frontend and two separately defined APIs. Implementing cookie sessions independently in both APIs before deciding their public hostnames would risk third-party-cookie failures and inconsistent sessions.

A sound next architecture is one shared authentication/session service, or one API gateway in front of both protected APIs, on a site that can issue a first-party Secure, HttpOnly cookie to the frontend. The session store must be persistent and shared by all services that need to authorize the same user.

Do not assume CORS makes unrelated domains same-site. Do not put a session secret, VK client secret, refresh token, or administrator allowlist in GitHub Pages or the public repository.

## Decisions required before server implementation

1. Pick the actual host/domain for the VK ID callback and session API.
2. Ensure the frontend and session API can use a first-party cookie arrangement; a custom domain with same-site subdomains or a same-origin proxy are possible designs.
3. Decide which existing host will run the shared session service. The current Render Blueprint is only a test-stream service and is not that host.
4. Choose persistent session storage accessible to the APIs.
5. Configure the VK ID application with the exact callback URL and supply the numeric App ID.
6. Set the server-only administrator allowlist using numeric VK user IDs.

## Current safe state

- The VK ID login button remains disabled.
- The Logto code is retained only as the existing legacy path; it must not be deleted until VK ID is deployed and tested end-to-end.
- No Render/Railway resources, billing settings, domains, or production services were changed by this audit.
