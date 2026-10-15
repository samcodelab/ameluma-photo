import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('review_release', Path(__file__).parents[1] / 'review_release.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

class ReleaseURLTests(unittest.TestCase):
    def test_absent_placeholder_or_private_addresses_do_not_pass(self):
        for value in ['', None, 'http://studio.com/privacy', 'https://example.com/privacy',
                      'https://www.example.com', 'https://localhost', 'https://studio.local',
                      'https://127.0.0.1', 'https://192.168.1.1', 'https://[::1]',
                      'https://user:password@studio.com']:
            with self.subTest(value=value):
                self.assertFalse(review.valid_public_url(value))

    def test_https_configuration_is_distinct_from_live_site_verification(self):
        self.assertTrue(review.valid_public_url('https://broadframestudio.com/framepebble/privacy'))
        self.assertTrue(review.valid_public_url('https://support.broadframestudio.com/'))

if __name__ == '__main__':
    unittest.main()
