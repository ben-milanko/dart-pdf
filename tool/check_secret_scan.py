#!/usr/bin/env python3
"""Verify signing-fixture exceptions never hide new credentials in the same file."""

import argparse
import json
from pathlib import Path
import secrets
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gitleaks', default='gitleaks')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    relative = Path('packages/pdf_cos/test/pki_test.dart')
    with tempfile.TemporaryDirectory(prefix='dartpdf-secret-scan-') as temporary:
        root = Path(temporary)
        target = root / relative
        target.parent.mkdir(parents=True)
        target.write_bytes((repo / relative).read_bytes())
        report = root / 'findings.json'
        command = [args.gitleaks, 'dir', '.', '--config',
                   str(repo / '.gitleaks.toml'), '--redact=100', '--no-banner',
                   '--report-format', 'json', '--report-path', str(report)]

        baseline = subprocess.run(command, cwd=root, capture_output=True)
        if baseline.returncode != 0:
            raise RuntimeError('Known public test keys must pass.')

        key = root / 'probe.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt',
                        'rsa_keygen_bits:2048', '-out', str(key)],
                       check=True, capture_output=True)
        private_key = key.read_bytes()
        key.unlink()
        probe = (private_key + b'\napi_key="'
                 + secrets.token_urlsafe(48).encode() + b'"\n')
        target.write_bytes(target.read_bytes() + b'\n' + probe)
        (root / 'unrelated.dart').write_bytes(probe)
        result = subprocess.run(command, cwd=root, capture_output=True)
        findings = json.loads(report.read_text())
        observed = {(item['RuleID'], item['File']) for item in findings}
        required = {('private-key', relative.as_posix()),
                    ('generic-api-key', relative.as_posix()),
                    ('private-key', 'unrelated.dart'),
                    ('generic-api-key', 'unrelated.dart')}
        if result.returncode != 1 or not required.issubset(observed):
            raise RuntimeError('New private/generic keys were not all detected.')
    print('Passed: known test keys accepted; new keys rejected in both paths.')


if __name__ == '__main__':
    main()
