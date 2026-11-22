#!/usr/bin/env python3
"""Verify that the public HLS stream is reachable after a recovery action.

This is read-only. It never calls Render or changes the stream.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

URL = os.environ.get(
    "STREAM_URL",
    "https://multik-tv-test-stream-yltl.onrender.com/live/multiktv.m3u8",
)
ATTEMPTS = int(os.environ.get("VERIFY_ATTEMPTS", "5"))
DELAY = int(os.environ.get("VERIFY_DELAY_SECONDS", "10"))


def check_once():
    request = urllib.request.Request(URL, headers={"User-Agent": "BroadcastRecoveryVerifier/1.0"})
    with urllib.request.urlopen(request, timeout=12) as response:
        playlist = response.read(256000).decode("utf-8", "replace")
        status = response.status
    segments = [
        line.strip() for line in playlist.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not segments:
        return {"ok": False, "httpStatus": status, "reason": "playlist_has_no_segments"}
    segment_url = urllib.parse.urljoin(URL, segments[-1])
    segment_request = urllib.request.Request(
        segment_url, headers={"User-Agent": "BroadcastRecoveryVerifier/1.0"}
    )
    with urllib.request.urlopen(segment_request, timeout=12) as response:
        sample = response.read(4096)
        segment_status = response.status
    ok = status == 200 and segment_status == 200 and bool(sample)
    return {
        "ok": ok,
        "httpStatus": status,
        "segmentHttpStatus": segment_status,
        "segmentSampleBytes": len(sample),
    }


def main():
    attempts = []
    for index in range(ATTEMPTS):
        try:
            result = check_once()
        except Exception as exc:
            result = {"ok": False, "reason": str(exc)[:300]}
        attempts.append(result)
        if result.get("ok"):
            break
        if index + 1 < ATTEMPTS:
            time.sleep(DELAY)
    healthy = bool(attempts and attempts[-1].get("ok"))
    report = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "url": URL,
        "readOnly": True,
        "attemptCount": len(attempts),
        "healthy": healthy,
        "attempts": attempts,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if healthy else 1


if __name__ == "__main__":
    sys.exit(main())
