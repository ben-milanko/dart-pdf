#!/usr/bin/env python3
"""Verify signing-fixture exceptions never hide new credentials in the same file."""

import argparse
import json
from pathlib import Path
import secrets
import subprocess
import tempfile

# gitleaks' generic-api-key rule drops matches whose secret contains one of its
# stopwords, so roughly 2% of random tokens are never flagged. Probe candidates
# alone first and plant only one the rule is known to detect.
TOKEN_ATTEMPTS = 10


def gitleaks_command(gitleaks, config, report):
    return [gitleaks, 'dir', '.', '--config', str(config), '--redact=100',
            '--no-banner', '--report-format', 'json',
            '--report-path', str(report)]


def detectable_token(gitleaks, config):
    """Return a random token that generic-api-key flags on its own."""
    for _ in range(TOKEN_ATTEMPTS):
        token = secrets.token_urlsafe(48)
        prefix = 'dartpdf-token-probe-'
        with tempfile.TemporaryDirectory(prefix=prefix) as scratch:
            root = Path(scratch)
            (root / 'probe.dart').write_text(f'api_key="{token}"\n')
            report = root / 'findings.json'
            subprocess.run(gitleaks_command(gitleaks, config, report),
                           cwd=root, capture_output=True)
            findings = json.loads(report.read_text()) if report.exists() else []
            if any(item['RuleID'] == 'generic-api-key' for item in findings):
                return token
    raise RuntimeError(
        f'No random token was flagged as generic-api-key in {TOKEN_ATTEMPTS} '
        'tries; the rule or config no longer detects generic keys.')


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
        config = repo / '.gitleaks.toml'
        command = gitleaks_command(args.gitleaks, config, report)

        baseline = subprocess.run(command, cwd=root, capture_output=True)
        if baseline.returncode != 0:
            raise RuntimeError('Known public test keys must pass.')

        key = root / 'probe.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt',
                        'rsa_keygen_bits:2048', '-out', str(key)],
                       check=True, capture_output=True)
        private_key = key.read_bytes()
        key.unlink()
        token = detectable_token(args.gitleaks, config)
        probe = private_key + b'\napi_key="' + token.encode() + b'"\n'
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
