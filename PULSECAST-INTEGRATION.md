# PulseCast integration — status and next steps

## Current state

The website queue is maintained in `broadcast.json` and the browser admin page. The current `broadcast-control.html` uses the cloud server API for authenticated administration.

The public PulseCast documentation reviewed for this project describes playlist-based 24/7 RTMP streaming, but does not document an API for uploading videos or editing/reordering the playlist. Therefore this repository cannot safely synchronize its queue with PulseCast yet.

## Required vendor confirmation

Before implementing a live adapter, PulseCast support must confirm in writing:

1. Whether a supported public or private API exists for this account and plan.
2. The official API base URL and authentication method.
3. The documented endpoints and request schemas for listing, uploading, adding, removing, and reordering playlist items.
4. Whether playlist changes apply immediately to an active stream.
5. Rate limits, upload limits, and webhook/event support.
6. Whether a GitHub Actions integration is supported, or whether calls must come from a private backend.

Support: support@pulsecast.tv

Suggested subject: API access for playlist management — МУЛЬТИК ТВ

Suggested message:

Hello PulseCast Support,

I manage a channel called МУЛЬТИК ТВ and would like to synchronize its video playlist from a private GitHub-backed administration panel.

Could you confirm whether PulseCast provides an officially supported public or private API for:
- listing the current playlist;
- uploading videos;
- adding and removing playlist items;
- changing playlist order;
- checking the current stream status;
- receiving webhooks when the playlist or stream status changes?

If available, please share the official API documentation, authentication requirements, plan restrictions, and a safe test environment.

I will only integrate through documented and authorized endpoints. I will not use undocumented endpoints or reverse-engineer the service.

Thank you.

## Implementation plan after vendor confirmation

- Keep all PulseCast credentials on a private server; never place them in GitHub Pages JavaScript, repository files, or public Actions logs.
- Add a server-side PulseCast adapter using only the vendor's documented endpoints.
- Add authenticated admin actions for previewing changes, applying playlist changes, and reading stream status.
- Require a confirmation step before changing the live playlist.
- Keep Kinescope as the RTMP destination unless the channel owner explicitly changes it.
- Test with a separate test playlist before touching the live channel.

## Important

Until PulseCast provides and confirms an official API, the GitHub queue is an export/preparation list only. It does not control the PulseCast playlist or the live stream. The existing stream should not be stopped to test this integration.
