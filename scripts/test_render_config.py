"""Regression checks for the current Render HLS broadcast architecture."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RenderBlueprintTests(unittest.TestCase):
    def test_blueprint_declares_one_free_web_service_and_real_health_document(self):
        config = (ROOT / "render.yaml").read_text(encoding="utf-8")
        self.assertEqual(len(re.findall(r"(?m)^\s*- type:\s*web\s*$", config)), 1)
        self.assertRegex(config, r"(?m)^\s*plan:\s*free\s*$")
        self.assertRegex(config, r"(?m)^\s*rootDir:\s*stream-server\s*$")
        self.assertRegex(config, r"(?m)^\s*healthCheckPath:\s*/broadcast/health\.json\s*$")
        self.assertRegex(config, r"(?m)^\s*autoDeploy:\s*true\s*$")
        self.assertNotRegex(config, r"(?m)^\s*(?:- type:\s*(?:worker|private_service|keyvalue|pserv)|disk:|numInstances:)")

    def test_startup_builds_a_single_continuous_playlist(self):
        dockerfile = (ROOT / "stream-server" / "Dockerfile").read_text(encoding="utf-8")
        startup = (ROOT / "stream-server" / "render-start.sh").read_text(encoding="utf-8")
        self.assertIn('CMD ["/usr/local/srs/render-start.sh"]', dockerfile)
        self.assertIn('HTTP_PORT="${PORT:-10000}"', startup)
        self.assertIn("PROGRAM_RIGHTS_CONFIRMED", startup)
        self.assertIn("Starting continuous broadcast playlist:", startup)
        self.assertIn("-stream_loop -1", startup)
        self.assertIn("multik-tv-continuous.mp4", startup)
        self.assertIn("ORIGINAL_COUNT", startup)
        self.assertIn("No valid programme files are available", startup)
        self.assertIn("rtmp://127.0.0.1/live/multiktv", startup)

    def test_watchdog_checks_real_hls_and_recovers_stalled_publisher(self):
        startup = (ROOT / "stream-server" / "render-start.sh").read_text(encoding="utf-8")
        self.assertIn("/live/multiktv.m3u8", startup)
        self.assertIn("finalized media segment", startup)
        self.assertIn("HLS segment progress every 5 seconds", startup)
        self.assertIn("HLS segment stalled for 30 seconds", startup)
        self.assertIn('write_health "live"', startup)
        self.assertIn('write_health "recovering"', startup)
        self.assertIn('write_health "error"', startup)

    def test_hls_output_matches_srs_configuration(self):
        startup = (ROOT / "stream-server" / "render-start.sh").read_text(encoding="utf-8")
        config = (ROOT / "stream-server" / "srs.conf").read_text(encoding="utf-8")
        self.assertIn("hls_m3u8_file   [app]/[stream].m3u8;", config)
        self.assertIn("hls_ts_file     [app]/[stream]-[seq].ts;", config)
        self.assertIn("rtmp://127.0.0.1/live/multiktv", startup)
        self.assertIn("/live/multiktv.m3u8", startup)

    def test_weather_program_and_free_hosting_limits_are_explicit(self):
        startup = (ROOT / "stream-server" / "render-start.sh").read_text(encoding="utf-8")
        readme = (ROOT / "stream-server" / "README.md").read_text(encoding="utf-8").lower()
        self.assertIn("generate_weather_show()", startup)
        self.assertIn("api.open-meteo.com", startup)
        self.assertIn("WEATHER_TIME", startup)
        self.assertIn("не гарантирует круглосуточную работу", readme)
        self.assertIn("15 минут", readme)

    def test_render_start_script_has_valid_shell_syntax(self):
        startup = ROOT / "stream-server" / "render-start.sh"
        result = subprocess.run(["bash", "-n", str(startup)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()