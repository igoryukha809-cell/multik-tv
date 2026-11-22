#!/usr/bin/env python3
"""Fail-closed, non-mutating recovery decision gate for broadcast diagnostics."""
import json
import os
import sys
from datetime import datetime, timedelta, timezone

REPORT_PATH = "/tmp/broadcast-report.json"
STATE_PATH = "/tmp/broadcast-recovery-state/state.json"
OUTPUT_PATH = "/tmp/broadcast-recovery-report.json"
RESTARTABLE = {"PLAYLIST_UNAVAILABLE", "NO_MEDIA_SEGMENTS", "FFPROBE_FAILED"}
COOLDOWN_HOURS = 6


def read_json(path, fallback):
    try:
        with open(path, encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, json.JSONDecodeError):
        return fallback


def write_json(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main():
    now = datetime.now(timezone.utc)
    report = read_json(REPORT_PATH, {})
    state = read_json(STATE_PATH, {})
    if not isinstance(report, dict):
        report = {}
    if not isinstance(state, dict):
        state = {}

    findings = report.get("findings")
    if not isinstance(findings, list):
        findings = []
    critical_codes = sorted({
        str(item.get("code") or "UNKNOWN")
        for item in findings
        if isinstance(item, dict) and item.get("severity") == "critical"
    })
    eligible = bool(critical_codes) and set(critical_codes).issubset(RESTARTABLE)

    last_at = None
    raw_last_at = state.get("lastEligibleAt")
    if isinstance(raw_last_at, str):
        try:
            parsed = datetime.fromisoformat(raw_last_at.replace("Z", "+00:00"))
            if parsed.tzinfo is not None:
                last_at = parsed.astimezone(timezone.utc)
        except ValueError:
            pass

    previous_codes = state.get("lastEligibleCodes")
    if not isinstance(previous_codes, list):
        previous_codes = []
    same_incident = eligible and critical_codes == sorted(str(code) for code in previous_codes)
    cooling_down = bool(
        same_incident and last_at and
        timedelta(0) <= now - last_at < timedelta(hours=COOLDOWN_HOURS)
    )
    should_record = eligible and not cooling_down

    if should_record:
        state = {"lastEligibleAt": now.isoformat(), "lastEligibleCodes": critical_codes}
        write_json(STATE_PATH, state)

    result = {
        "checkedAt": now.isoformat(),
        "mode": "dry-run",
        "restartRequested": False,
        "eligibleForFutureRecovery": eligible and not cooling_down,
        "cooldownActive": cooling_down,
        "cooldownHours": COOLDOWN_HOURS,
        "criticalCodes": critical_codes,
        "reason": (
            "Repeated identical incident suppressed by cooldown; no action taken."
            if cooling_down else
            "Known hard signal failure recorded for review; automatic Render mutations remain disabled."
            if eligible else
            "No eligible hard signal failure; no action taken."
        ),
    }
    write_json(OUTPUT_PATH, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
