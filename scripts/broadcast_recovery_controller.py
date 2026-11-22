#!/usr/bin/env python3
"""Fail-closed Render recovery controller for the broadcast monitor.

This first implementation is deliberately dry-run only. It classifies only
hard signal failures and records a recovery recommendation. It never restarts
or deploys a Render service. A future change must add durable incident
deduplication/cooldown and explicit operator approval before enabling writes.
"""
import json
import os
import sys
from datetime import datetime, timezone

REPORT_PATH = "/tmp/broadcast-report.json"
RESTARTABLE = {"PLAYLIST_UNAVAILABLE", "NO_MEDIA_SEGMENTS", "FFPROBE_FAILED"}


def load_report():
    try:
        with open(REPORT_PATH, encoding="utf-8") as stream:
            return json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        return {"findings": [], "reportError": str(exc)}


def main():
    report = load_report()
    findings = report.get("findings") or []
    critical_codes = sorted({
        item.get("code", "UNKNOWN")
        for item in findings
        if item.get("severity") == "critical"
    })
    eligible = bool(critical_codes) and set(critical_codes).issubset(RESTARTABLE)

    result = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "mode": "dry-run",
        "restartRequested": False,
        "eligibleForFutureRecovery": eligible,
        "criticalCodes": critical_codes,
        "reason": (
            "A known hard signal failure was detected; no action taken because "
            "automatic Render mutations are not enabled in this version."
            if eligible else
            "No eligible hard signal failure; no action taken."
        ),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
