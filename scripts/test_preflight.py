import base64
import unittest
from preflight import validate


class PreflightTest(unittest.TestCase):
    def settings(self):
        return dict(ADMIN_PASSWORD='a' * 24, SECRET_KEY_BASE='s' * 64,
                    POSTGRES_PASSWORD='p' * 32, RENDERER_SECRET='r' * 32,
                    TOKEN_ENCRYPTION_KEY=base64.b64encode(b'k' * 32).decode(),
                    PUBLIC_URL='http://192.168.1.10:4000',
                    GOOGLE_BROWSER_ORIGIN='http://localhost:4000')

    def test_lan_without_google(self):
        self.assertEqual(validate(self.settings()), [])

    def test_invalid_settings_do_not_echo_secrets(self):
        values = self.settings()
        values.update(PUBLIC_URL='http://user:private-secret@host/path',
                      POSTGRES_PASSWORD='private/secret', TOKEN_ENCRYPTION_KEY='bad', PORT='99999')
        errors = validate(values)
        self.assertGreaterEqual(len(errors), 4)
        self.assertNotIn('private-secret', str(errors))
        self.assertNotIn('private/secret', str(errors))

    def test_oauth_requires_pair_and_consistent_callback(self):
        values = self.settings()
        values['GOOGLE_CLIENT_ID'] = 'client'
        self.assertTrue(validate(values))
        values.update(GOOGLE_CLIENT_SECRET='secret', GOOGLE_REDIRECT_URI='http://localhost:4000/oauth/callback')
        self.assertEqual(validate(values), [])


if __name__ == '__main__':
    unittest.main()
