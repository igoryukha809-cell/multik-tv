import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check_broadcast.py").resolve()

class BroadcastPlaylistTests(unittest.TestCase):
    def run_checker(self, items):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "broadcast").mkdir()
            (root / "broadcast" / "playlist.json").write_text(
                json.dumps({"items": items}), encoding="utf-8"
            )
            subprocess.run([sys.executable, str(SCRIPT)], cwd=root, check=True, capture_output=True, text=True)
            return json.loads((root / "broadcast" / "status.json").read_text(encoding="utf-8"))

    def test_empty_playlist_is_not_configured(self):
        result = self.run_checker([])
        self.assertEqual(result["state"], "not_configured")
        self.assertFalse(result["streaming"])

    def test_rights_documented_item_is_ready_but_not_streaming(self):
        item = {
            "title": "Тестовый ролик",
            "url": "https://example.org/video.mp4",
            "rightsConfirmed": True,
            "license": "CC BY 4.0",
            "attribution": "Автор тестового ролика",
            "rightsEvidence": "https://example.org/license"
        }
        result = self.run_checker([item])
        self.assertEqual(result["state"], "playlist_ready_server_required")
        self.assertFalse(result["streaming"])
        self.assertEqual(result["itemsChecked"], 1)

    def test_item_without_rights_confirmation_is_rejected(self):
        item = {
            "title": "Не подтверждённый ролик",
            "url": "https://example.org/video.mp4",
            "license": "CC BY 4.0",
            "attribution": "Автор",
            "rightsEvidence": "https://example.org/license"
        }
        result = self.run_checker([item])
        self.assertEqual(result["state"], "playlist_has_errors")
        self.assertFalse(result["streaming"])

    def test_non_https_url_is_rejected(self):
        item = {
            "title": "Небезопасный URL",
            "url": "http://example.org/video.mp4",
            "rightsConfirmed": True,
            "license": "CC BY 4.0",
            "attribution": "Автор",
            "rightsEvidence": "https://example.org/license"
        }
        result = self.run_checker([item])
        self.assertEqual(result["state"], "playlist_has_errors")

if __name__ == "__main__":
    unittest.main()
