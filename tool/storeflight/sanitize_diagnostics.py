#!/usr/bin/env python3
"""Remove release credentials from text state before public artifact uploads.

GitHub masks console logs, not artifact contents. Scrub copies of the same
environment values from Storeflight's JSON/JSONL diagnostics and state without
changing their layout or deleting the files required for a resume.
"""

import argparse
import json
import os
from pathlib import Path


CREDENTIAL_NAMES = frozenset({
    'GH_TOKEN', 'GITHUB_TOKEN', 'ACTIONS_RUNTIME_TOKEN',
    'ACTIONS_ID_TOKEN_REQUEST_TOKEN', 'ACTIONS_ID_TOKEN_REQUEST_URL',
    'ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD', 'APPLE_CERTIFICATE_BASE64',
    'APPLE_CERTIFICATE_PASSWORD', 'APPLE_PROVISIONING_PROFILE_BASE64',
    'APPLE_PROVISIONING_PROFILE_MAC_BASE64', 'ASC_API_ISSUER_ID',
    'ASC_API_KEY_ID', 'ASC_API_KEY_P8', 'FIREBASE_TOKEN',
    'MSSTORE_CERTIFICATE_BASE64', 'MSSTORE_CERTIFICATE_PASSWORD',
    'MSSTORE_CLIENT_ID', 'MSSTORE_SELLER_ID', 'MSSTORE_TENANT_ID',
    'PLAY_STORE_SERVICE_ACCOUNT_JSON', 'SHOREBIRD_TOKEN',
    'SNAPCRAFT_STORE_CREDENTIALS',
})
TEXT_SUFFIXES = {'.json', '.jsonl', '.log', '.txt', '.md', '.yaml', '.yml'}


def credential_values(environment):
    values = set()
    for name in CREDENTIAL_NAMES:
        value = environment.get(name, '')
        if not value:
            continue
        if len(value) < 4:
            raise ValueError('A credential is too short to scrub safely.')
        values.add(value)
        # A service-account JSON may be printed pretty-formatted, while its
        # private key is logged separately. Redact that key in either form.
        if name.endswith('_JSON'):
            try:
                decoded = json.loads(value)
            except (ValueError, TypeError):
                continue
            if isinstance(decoded, dict):
                for key in ('private_key', 'private_key_id', 'client_email',
                            'client_id'):
                    field = decoded.get(key)
                    if isinstance(field, str) and field:
                        values.add(field)
    # JSON and JSONL escape newlines, quotes, backslashes and Unicode.
    for value in tuple(values):
        values.add(json.dumps(value, ensure_ascii=True)[1:-1])
        values.add(json.dumps(value, ensure_ascii=False)[1:-1])
    return sorted(values, key=len, reverse=True)


def sanitize(root, environment):
    values = credential_values(environment)
    changed = 0
    for state in root.rglob('.storeflight'):
        if not state.is_dir() or state.is_symlink():
            continue
        # Never scan the separately checked-out private release-tool source.
        if '.storeflight-cli' in state.relative_to(root).parts:
            continue
        for path in state.rglob('*'):
            if (not path.is_file() or path.is_symlink()
                    or path.suffix not in TEXT_SUFFIXES
                    or 'artifacts' in path.relative_to(state).parts):
                continue
            original = path.read_text(encoding='utf-8')
            text = original
            for value in values:
                text = text.replace(value, '[REDACTED]')
            if text != original:
                path.write_text(text, encoding='utf-8')
                changed += 1
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path('.'))
    args = parser.parse_args()
    # Only counts leave this process. Never print a credential or matching line.
    print(f'Sanitized {sanitize(args.root, os.environ)} Storeflight state files.')


if __name__ == '__main__':
    main()
