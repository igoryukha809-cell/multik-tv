import json
import os
import tempfile
import unittest
from unittest.mock import patch

import broadcast_recovery_controller as controller


class RecoveryControllerTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.report = os.path.join(self.tempdir.name, "report.json")
        self.state = os.path.join(self.tempdir.name, "state", "state.json")
        self.output = os.path.join(self.tempdir.name, "output.json")
        self.paths = (
            patch.object(controller, "REPORT_PATH", self.report),
            patch.object(controller, "STATE_PATH", self.state),
            patch.object(controller, "OUTPUT_PATH", self.output),
        )
        for item in self.paths:
            item.start()
            self.addCleanup(item.stop)

    def write_json(self, path, value):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as stream:
            json.dump(value, stream)

    def run_controller(self):
        self.assertEqual(controller.main(), 0)
        with open(self.output, encoding="utf-8") as stream:
            return json.load(stream)

    def test_missing_or_invalid_report_fails_closed(self):
        result = self.run_controller()
        self.assertFalse(result["eligibleForFutureRecovery"])
        self.assertFalse(result["restartRequested"])

        with open(self.report, "w", encoding="utf-8") as stream:
            stream.write("{broken")
        result = self.run_controller()
        self.assertEqual(result["criticalCodes"], [])
        self.assertFalse(result["eligibleForFutureRecovery"])

    def test_non_object_report_and_malformed_findings_are_ignored(self):
        for payload in ([], {"findings": {}}, {"findings": ["bad", None, 7]}):
            self.write_json(self.report, payload)
            result = self.run_controller()
            self.assertEqual(result["criticalCodes"], [])
            self.assertFalse(result["eligibleForFutureRecovery"])

    def test_known_critical_failure_is_eligible_but_never_restarts(self):
        self.write_json(self.report, {"findings": [
            {"severity": "critical", "code": "PLAYLIST_UNAVAILABLE"}
        ]})
        result = self.run_controller()
        self.assertTrue(result["eligibleForFutureRecovery"])
        self.assertFalse(result["restartRequested"])
        self.assertEqual(result["criticalCodes"], ["PLAYLIST_UNAVAILABLE"])
        self.assertTrue(os.path.isfile(self.state))

    def test_unknown_critical_failure_blocks_eligibility(self):
        self.write_json(self.report, {"findings": [
            {"severity": "critical", "code": "UNRECOGNIZED_FAILURE"}
        ]})
        result = self.run_controller()
        self.assertFalse(result["eligibleForFutureRecovery"])
        self.assertFalse(result["restartRequested"])

    def test_naive_or_invalid_timestamp_does_not_activate_cooldown(self):
        self.write_json(self.report, {"findings": [
            {"severity": "critical", "code": "NO_MEDIA_SEGMENTS"}
        ]})
        for timestamp in ("2026-01-01T00:00:00", "not-a-date"):
            self.write_json(self.state, {
                "lastEligibleAt": timestamp,
                "lastEligibleCodes": ["NO_MEDIA_SEGMENTS"],
            })
            result = self.run_controller()
            self.assertFalse(result["cooldownActive"])
            self.assertTrue(result["eligibleForFutureRecovery"])

    def test_recent_identical_incident_is_suppressed(self):
        from datetime import datetime, timedelta, timezone
        recent = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
        self.write_json(self.report, {"findings": [
            {"severity": "critical", "code": "FFPROBE_FAILED"}
        ]})
        self.write_json(self.state, {
            "lastEligibleAt": recent,
            "lastEligibleCodes": ["FFPROBE_FAILED"],
        })
        result = self.run_controller()
        self.assertTrue(result["cooldownActive"])
        self.assertFalse(result["eligibleForFutureRecovery"])
        self.assertFalse(result["restartRequested"])


if __name__ == "__main__":
    unittest.main()
