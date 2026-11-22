#!/usr/bin/env python3
"""Fail-closed recovery decision gate for the broadcast monitor.

The controller is deliberately non-mutating: it never restarts or deploys a
Render service. A durable state file is restored/saved by GitHub Actions cache.
The cooldown suppresses repeated recovery recommendations for the same hard
failure; it does not count or trigger real restart attempts.
"""
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
    report = read_json(REPORT_PATH, {"findings": [], "reportError": "diagnostic report unavailable"})
    state = read_json(STATE_PATH, {"lastEligibleAt": None, "lastEligibleCodes": []})
    findings = report.get("findings") or []
    critical_codes = sorted({
        str(item.get("code", "UNKNOWN"))
        for item in findings
        if item.get("severity") == "critical"
    })
    eligible = bool(critical_codes) and set(critical_codes).issubset(RESTARTABLE)

    last_at = None
    if state.get("lastEligibleAt"):
        try:
            last_at = datetime.fromisoformat(state["lastEligibleAt"].replace("Z", "+00:00"))
        except (TypeError, ValueError):
            last_at = None

    same_incident = eligible and critical_codes == sorted(state.get("lastEligibleCodes") or [])
    cooling_down = bool(same_incident and last_at and now - last_at < timedelta(hours=COOLDOWN_HOURS))
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
            "Repeated identical incident suppressed by durable cooldown; no action taken."
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
