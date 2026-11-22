#!/usr/bin/env python3
"""Read-only HLS audio/video diagnostics."""
import json, os, re, subprocess, sys, urllib.request
from datetime import datetime, timezone

URL = os.environ.get("STREAM_URL", "https://multik-tv-test-stream-yltl.onrender.com/live/multiktv.m3u8")
SECONDS = int(os.environ.get("SAMPLE_SECONDS", "18"))

def run(args, timeout):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)

def main():
    report = {"checkedAt": datetime.now(timezone.utc).isoformat(), "url": URL, "readOnly": True, "checks": {}, "findings": []}
    try:
        req = urllib.request.Request(URL, headers={"User-Agent": "BroadcastReadOnlyMonitor/1.0"})
        with urllib.request.urlopen(req, timeout=12) as response:
            playlist = response.read(256000).decode("utf-8", "replace")
            report["checks"]["playlistHttp"] = response.status
        segments = re.findall(r"^[^#\\s].*\\.(?:ts|m4s|mp4)(?:\\?.*)?$", playlist, re.M)
        report["checks"]["playlistHasMediaSegments"] = bool(segments)
        if not segments:
            report["findings"].append({"severity": "critical", "code": "NO_MEDIA_SEGMENTS", "message": "No media segments in HLS playlist"})
            print(json.dumps(report, ensure_ascii=False, indent=2)); return 2
    except Exception as exc:
        report["findings"].append({"severity": "critical", "code": "PLAYLIST_UNAVAILABLE", "message": str(exc)[:400]})
        print(json.dumps(report, ensure_ascii=False, indent=2)); return 2
    probe = run(["ffprobe", "-v", "error", "-show_streams", "-of", "json", URL], 25)
    if probe.returncode:
        report["findings"].append({"severity": "critical", "code": "FFPROBE_FAILED", "message": probe.stderr[-1000:]})
        print(json.dumps(report, ensure_ascii=False, indent=2)); return 2
    streams = json.loads(probe.stdout or "{}").get("streams", [])
    video = any(s.get("codec_type") == "video" for s in streams)
    audio = any(s.get("codec_type") == "audio" for s in streams)
    report["checks"].update({"videoTrack": video, "audioTrack": audio})
    if not video: report["findings"].append({"severity": "critical", "code": "VIDEO_TRACK_MISSING"})
    if not audio: report["findings"].append({"severity": "warning", "code": "AUDIO_TRACK_MISSING"})
    args = ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "info", "-rw_timeout", "15000000", "-i", URL, "-t", str(SECONDS)]
    if video: args += ["-vf", "blackdetect=d=2:pix_th=0.10"]
    if audio: args += ["-af", "silencedetect=n=-45dB:d=4"]
    args += ["-f", "null", "-"]
    sample = run(args, SECONDS + 25); log = sample.stderr or ""
    black = re.findall(r"black_start:([0-9.]+) black_end:([0-9.]+) black_duration:([0-9.]+)", log)
    silence = re.findall(r"silence_start:([0-9.]+)", log)
    report["checks"].update({"sampleSecondsRequested": SECONDS, "sampleDecodeExitCode": sample.returncode,
      "blackIntervals": [{"start":float(a),"end":float(b),"duration":float(c)} for a,b,c in black],
      "silenceStarts": [float(x) for x in silence]})
    if sample.returncode: report["findings"].append({"severity":"warning","code":"SAMPLE_DECODE_INCOMPLETE","message":log[-800:]})
    if black: report["findings"].append({"severity":"warning","code":"BLACK_FRAMES","message":"Sustained black intervals detected"})
    if silence: report["findings"].append({"severity":"warning","code":"AUDIO_SILENCE","message":"Silence lasting at least four seconds detected"})
    if not report["findings"]: report["findings"].append({"severity":"ok","code":"TRACKS_AND_SAMPLE_OK","message":"Tracks present; sample decoded without detected black or long silence"})
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 2 if any(x["severity"] == "critical" for x in report["findings"]) else 0

if __name__ == "__main__": sys.exit(main())
