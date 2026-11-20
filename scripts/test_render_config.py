"""Regression checks for the free, explicitly test-only Render service."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RenderBlueprintTests(unittest.TestCase):
    def test_blueprint_declares_only_one_free_web_service(self):
        config = (ROOT / "render.yaml").read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^\s*- type:\s*web\s*$", config)), 1)
        self.assertRegex(config, r"(?m)^\s*plan:\s*free\s*$")
        self.assertRegex(config, r"(?m)^\s*rootDir:\s*stream-server\s*$")
        self.assertRegex(config, r"(?m)^\s*autoDeploy:\s*false\s*$")
        self.assertNotRegex(config, r"(?m)^\s*(?:- type:\s*(?:worker|private_service|keyvalue|pserv)|disk:|numInstances:)")

    def test_health_check_targets_hls_manifest(self):
        config = (ROOT / "render.yaml").read_text(encoding="utf-8")
        self.assertRegex(config, r"(?m)^\s*healthCheckPath:\s*/live/multiktv\.m3u8\s*$")

    def test_container_downloads_and_streams_licensed_program_with_test_fallback(self):
        dockerfile = (ROOT / "stream-server" / "Dockerfile").read_text(encoding="utf-8")
        startup = (ROOT / "stream-server" / "render-start.sh").read_text(encoding="utf-8")
        self.assertIn('CMD ["/usr/local/srs/render-start.sh"]', dockerfile)
        self.assertIn('HTTP_PORT="${PORT:-10000}"', startup)
        self.assertIn("PROGRAM_VIDEO_URL", startup)\n        self.assertIn("creativecommons.org/licenses/by-sa/4.0", (ROOT / "broadcast" / "credits-pepper-carrot-episode-6.md").read_text(encoding="utf-8"))\n        self.assertIn("PROGRAM SOURCE UNAVAILABLE - TEST SIGNAL", startup)\n        self.assertIn("Starting the licensed program loop.", startup)
        self.assertIn("rtmp://127.0.0.1/live/multiktv", startup)


    def test_render_start_script_has_valid_shell_syntax_and_matching_hls_output(self):
        startup = ROOT / "stream-server" / "render-start.sh"
        import subprocess
        result = subprocess.run(["bash", "-n", str(startup)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        config = (ROOT / "stream-server" / "srs.conf").read_text(encoding="utf-8")
        self.assertIn("hls_m3u8_file   [app]/[stream].m3u8;", config)
        self.assertIn("rtmp://127.0.0.1/live/multiktv", startup.read_text(encoding="utf-8"))
        self.assertIn("/live/multiktv.m3u8", (ROOT / "render.yaml").read_text(encoding="utf-8"))

    def test_test_stream_is_not_misrepresented_as_channel_content(self):
        readme = (ROOT / "stream-server" / "README.md").read_text(encoding="utf-8")
        self.assertIn("не настоящий телеканал 24/7", readme)
        self.assertIn("не гарантирует круглосуточную работу", readme.lower())


if __name__ == "__main__":
    unittest.main()
