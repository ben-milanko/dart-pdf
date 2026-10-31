import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    'sanitize_diagnostics', Path(__file__).with_name('sanitize_diagnostics.py'))
scrubber = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scrubber)


class DiagnosticsPrivacyTest(unittest.TestCase):
    def test_masks_raw_and_json_escaped_credentials_without_breaking_resume(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = root / 'app/.storeflight'
            (state / 'diagnostics').mkdir(parents=True)
            secret = 'synthetic-test-value\nwith "quotes" and \\slashes'
            record = {'text': f'export ASC_API_KEY_P8={secret}', 'attempt': 2}
            log = state / 'diagnostics/build.macos.1.jsonl'
            log.write_text(json.dumps(record) + '\n')
            ledger = state / 'release.json'
            ledger.write_text(json.dumps({'source_sha': 'abc123',
                                         'issuer': 'synthetic-issuer'}))
            pointer = state / 'latest'
            pointer.write_text('release-id')
            self.assertEqual(scrubber.sanitize(root, {
                'ASC_API_KEY_P8': secret, 'ASC_API_ISSUER_ID': 'synthetic-issuer',
            }), 2)
            self.assertEqual(json.loads(log.read_text()),
                             {'text': 'export ASC_API_KEY_P8=[REDACTED]',
                              'attempt': 2})
            self.assertEqual(json.loads(ledger.read_text()),
                             {'source_sha': 'abc123', 'issuer': '[REDACTED]'})
            self.assertEqual(pointer.read_text(), 'release-id')

    def test_service_account_components_are_scrubbed_but_binaries_untouched(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = root / 'app/.storeflight'
            state.mkdir(parents=True)
            account = {'private_key': 'synthetic-multiline\nprivate-key',
                       'client_email': 'test@example.invalid'}
            log = state / 'build.log'
            log.write_text(account['private_key'] + account['client_email'])
            binary = state / 'output.zip'
            binary.write_bytes(b'\xff\x00synthetic-multiline')
            self.assertEqual(scrubber.sanitize(root, {
                'PLAY_STORE_SERVICE_ACCOUNT_JSON': json.dumps(account),
            }), 1)
            self.assertEqual(log.read_text(), '[REDACTED][REDACTED]')
            self.assertEqual(binary.read_bytes(), b'\xff\x00synthetic-multiline')

    def test_empty_credentials_and_private_checkout_are_not_modified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = root / '.storeflight-cli/.storeflight'
            state.mkdir(parents=True)
            log = state / 'fixture.log'
            log.write_text('synthetic-test-value')
            self.assertEqual(scrubber.sanitize(root, {
                'ASC_API_KEY_P8': '', 'SHOREBIRD_TOKEN': 'synthetic-test-value',
            }), 0)
            self.assertEqual(log.read_text(), 'synthetic-test-value')

    def test_every_workflow_job_secret_is_covered_before_any_upload(self):
        # Keep this standard-library-only: no YAML package is needed in CI.
        workflow = (Path(__file__).parents[2]
                    / '.github/workflows/storeflight.yml').read_text()
        import re
        for name in re.findall(r'^      (\w+): \$\{\{ secrets\.\w+ }}$',
                               workflow, re.M):
            self.assertIn(name, scrubber.CREDENTIAL_NAMES)
        jobs = re.split(r'^  \w+:\n', workflow.split('\njobs:\n', 1)[1],
                        flags=re.M)[1:]
        checked = 0
        for job in jobs:
            if 'secrets.' not in job or 'actions/upload-artifact@' not in job:
                continue
            self.assertLess(job.index('python3 tool/storeflight/sanitize_diagnostics.py'),
                            job.index('actions/upload-artifact@'))
            blocks = re.split(r'(?=^      - )', job, flags=re.M)
            for block in blocks:
                if 'uses: actions/upload-artifact@' in block:
                    self.assertIn(
                        "steps.sanitize_release_state.outcome == 'success'",
                        block)
            checked += 1
        self.assertGreater(checked, 0)

    def test_short_credential_fails_closed_without_editing_state(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state = root / 'app/.storeflight'
            state.mkdir(parents=True)
            log = state / 'build.log'
            log.write_text('original diagnostic')
            with self.assertRaises(ValueError):
                scrubber.sanitize(root, {'ASC_API_KEY_P8': 'x'})
            self.assertEqual(log.read_text(), 'original diagnostic')


if __name__ == '__main__':
    unittest.main()
