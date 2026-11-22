# Read-only audio/video diagnostics

First-stage probe for the live HLS output.

- Checks playlist availability and media segments.
- Uses FFprobe to confirm audio and video tracks.
- Uses FFmpeg to sample up to 18 seconds and detect sustained black frames and long silence.
- Saves a JSON report in each GitHub Actions run; runs every 15 minutes or manually.

Important: this is deterministic signal diagnostics, **not a trained neural network**. It cannot understand speech, identify scenes, or judge whether programme audio is intelligible. Those features require a separately configured multimodal model and approved API credentials. No key is included or requested.

Read-only: it never publishes, restarts, edits playlists, or changes Render settings. Intermittent faults may be missed by the short sample.

Run: GitHub Actions → Read-only broadcast audio-video diagnostics → Run workflow.
Local: STREAM_URL='https://example.invalid/live.m3u8' python3 scripts/broadcast_media_probe.py (requires Python 3 and FFmpeg/FFprobe).
