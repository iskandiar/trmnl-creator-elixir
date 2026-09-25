import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class StartDevTest(unittest.TestCase):
    def check_config(self, data, overrides=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "client.json"
            path.write_text(json.dumps(data))
            env = {k: v for k, v in os.environ.items() if not k.startswith("GOOGLE_") and k != "PORT"}
            env.update(overrides or {})
            result = subprocess.run(["python3", "scripts/start_dev.py", "--google-client-json", str(path), "--check"], env=env, capture_output=True, text=True)
            self.assertNotIn("fixture-secret", result.stdout + result.stderr)
            self.assertNotIn("fixture-id", result.stdout + result.stderr)
            return result

    def test_web_client_loads_without_printing_credentials(self):
        result = self.check_config({"web": {"client_id": "fixture-id", "client_secret": "fixture-secret", "redirect_uris": ["http://localhost:4010/oauth/callback"]}})
        self.assertEqual(result.returncode, 0)
        self.assertIn("Google OAuth: configured", result.stdout)
        self.assertIn("http://localhost:4010/oauth/callback", result.stdout)

    def test_desktop_client_is_rejected(self):
        result = self.check_config({"installed": {"client_id": "fixture-id", "client_secret": "fixture-secret"}})
        self.assertEqual(result.returncode, 1)
        self.assertIn("Web application", result.stderr)

    def test_wrong_callback_is_rejected_before_launch(self):
        result = self.check_config({"web": {"client_id": "fixture-id", "client_secret": "fixture-secret", "redirect_uris": ["http://localhost:4000/oauth/callback"]}})
        self.assertEqual(result.returncode, 1)
        self.assertIn("authorized redirect URIs", result.stderr)

    def test_explicit_callback_is_respected(self):
        result = self.check_config({"web": {"client_id": "fixture-id", "client_secret": "fixture-secret", "redirect_uris": ["http://localhost:4999/oauth/callback"]}}, {"GOOGLE_REDIRECT_URI": "http://localhost:4999/oauth/callback"})
        self.assertEqual(result.returncode, 0)
        self.assertIn("http://localhost:4999/oauth/callback", result.stdout)
