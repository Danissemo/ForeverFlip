"""The helper must be usable from a frozen build without disabling HTTPS verification."""

import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT/'sync'))
import foreverflip_sync as helper


class RuntimeCheckTests(unittest.TestCase):
    def test_tls_runtime_check_requires_verified_certificates_and_hostnames(self):
        result = helper.runtime_check(check_gui=False)
        self.assertTrue(result['tls_verified'])
        self.assertFalse(result['network_checked'])

    def test_self_test_writes_report_without_opening_config_or_reading_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            report = pathlib.Path(folder)/'report.json'
            with patch.object(helper, 'runtime_check', return_value={'ok':True,'tls_verified':True}), \
                 patch.object(helper, 'config_dir') as config, patch.object(helper, 'find_token') as credentials:
                self.assertEqual(helper.main(['--self-test','--self-test-report',str(report)]),0)
            self.assertTrue(json.loads(report.read_text())['tls_verified'])
            config.assert_not_called()
            credentials.assert_not_called()

    def test_self_test_failure_returns_error_and_preserves_failure_detail(self):
        with tempfile.TemporaryDirectory() as folder:
            report = pathlib.Path(folder)/'report.json'
            with patch.object(helper, 'runtime_check', side_effect=FileNotFoundError('TLS resource missing')):
                self.assertEqual(helper.main(['--self-test','--self-test-report',str(report)]),1)
            self.assertIn('TLS resource missing',json.loads(report.read_text())['error'])


if __name__ == '__main__':
    unittest.main()
