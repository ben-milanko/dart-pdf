"""Publish source-bound retained Android artifacts; no Flutter build or store writes."""
from pathlib import Path
import hashlib, json, os, re, subprocess, tempfile, zipfile

REPO = 'ben-milanko/dart-pdf'
SIGNER = '4fbf4e9da8c7d2b1e7c3bee006aefbf8b8faa99f610ac0877e3e88d6d6fa6140'

def sha(data): return hashlib.sha256(data).hexdigest()

# The production certificate is policy, not operator input.
MANIFEST_KEYS = {
    'schema_version', 'source', 'version', 'build', 'tag', 'release_id',
    'native_run', 'native_artifact', 'native_digest', 'native_ledger_id',
    'portable_run', 'portable_artifact', 'portable_digest', 'aab_sha',
    'apk_sha', 'signed_apk_sha', 'transfer_sha',
}

def validate_manifest(m):
    if type(m) is not dict or set(m) != MANIFEST_KEYS:
        raise ValueError('Manifest fields must match schema version 1 exactly')
    integers = ('schema_version', 'build', 'release_id', 'native_run',
                'native_artifact', 'portable_run', 'portable_artifact')
    for key in integers:
        if type(m[key]) is not int or not 0 < m[key] <= 2**53 - 1:
            raise ValueError('Manifest integer invalid: ' + key)
    if m['schema_version'] != 1 or m['build'] > 2100000000:
        raise ValueError('Unsupported manifest schema or Android build')
    patterns = {'source': r'[0-9a-f]{40}',
                'version': r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',
                'native_ledger_id': r'[0-9a-f]{24}'}
    for key in ('native_digest', 'portable_digest', 'aab_sha', 'apk_sha',
                'signed_apk_sha', 'transfer_sha'):
        patterns[key] = r'[0-9a-f]{64}'
    for key, pattern in patterns.items():
        if type(m[key]) is not str or re.fullmatch(pattern, m[key]) is None:
            raise ValueError('Manifest string invalid: ' + key)
    if m['tag'] != 'app-v' + m['version']:
        raise ValueError('Manifest tag/version mismatch')
    return m

def load_manifest(raw, expected_digest):
    if (type(raw) is not str or not 0 < len(raw.encode()) <= 16384
            or type(expected_digest) is not str
            or re.fullmatch(r'[0-9a-f]{64}', expected_digest) is None
            or sha(raw.encode()) != expected_digest):
        raise ValueError('Manifest size or SHA-256 mismatch')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('Duplicate manifest key')
            result[key] = value
        return result
    return validate_manifest(json.loads(raw, object_pairs_hook=unique))

def dispatch_manifest():
    # No local/environment fallback: operator input must originate in dispatch.
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        raise ValueError('Explicit workflow_dispatch required')
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    return load_manifest(event['inputs']['manifest_json'], event['inputs']['manifest_sha256'])

def validate_ledger(ledger, m):
    if not (ledger['source_sha'] == m['source']
            and ledger['version'] == f"{m['version']}+{m['build']}"
            and ledger['steps']['build.android']['status'] == 'succeeded'
            and ledger['artifacts']['android']['sha256'] == m['aab_sha']):
        raise ValueError('Native ledger provenance mismatch')

def command(args):
    p = subprocess.run(args, capture_output=True)
    if p.returncode:
        # CI credentials stay in GH_TOKEN, never argv. Keep child failure
        # output private rather than echoing authentication diagnostics.
        raise RuntimeError('Release command failed: ' + Path(args[0]).name)
    return p.stdout

def gh(*args): return json.loads(command(['gh', *args]))

def validate_release(d, m):
    if not (d.get('id') == m['release_id'] and d.get('draft') is True and d.get('tag_name') == m['tag']
            and d.get('target_commitish') == m['source']):
        raise ValueError('Release must remain the exact source-bound draft')

def validate_artifact(d, aid, run, digest, m):
    if not (d['id'] == aid and d['expired'] is False and d['digest'] == 'sha256:' + digest
            and d['workflow_run']['id'] == run
            and d['workflow_run']['head_sha'] == m['source']):
        raise ValueError('CI artifact identity mismatch')

def download(aid, run, digest, target, m):
    meta = gh('api', f'repos/{REPO}/actions/artifacts/{aid}')
    validate_artifact(meta, aid, run, digest, m)
    with target.open('wb') as f:
        p = subprocess.run(['gh', 'api', f'repos/{REPO}/actions/artifacts/{aid}/zip'], stdout=f, stderr=subprocess.PIPE)
    if p.returncode or sha(target.read_bytes()) != digest:
        raise ValueError('CI archive digest mismatch')

def download_transfer(release, target, m):
    rows = [a for a in release['assets'] if a['name'] == 'android-signed-apk-transfer.zip']
    if not (len(rows) == 1 and rows[0]['state'] == 'uploaded'
            and rows[0]['digest'] == 'sha256:' + m['transfer_sha']
            and str(rows[0]['id']).isdigit()):
        raise ValueError('Signed APK transfer identity mismatch')
    with target.open('wb') as f:
        p = subprocess.run(['gh', 'api', f"repos/{REPO}/releases/assets/{rows[0]['id']}",
                            '-H', 'Accept: application/octet-stream'], stdout=f, stderr=subprocess.PIPE)
    if p.returncode or sha(target.read_bytes()) != m['transfer_sha']:
        raise ValueError('Signed APK transfer digest mismatch')

def member(z, name, expected=None):
    rows = [m for m in z.infolist() if m.filename == name]
    if len(rows) != 1 or rows[0].is_dir() or rows[0].file_size > 350 * 1024 * 1024:
        raise ValueError('Missing, duplicate or oversized artifact member')
    data = z.read(rows[0])
    if expected is not None and sha(data) != expected:
        raise ValueError('Retained file digest mismatch')
    return data

def apk_payload(path):
    signature = re.compile(r'^META-INF/(MANIFEST\.MF|[^/]+\.(SF|RSA|DSA|EC))$', re.I)
    with zipfile.ZipFile(path) as z:
        names = [i.filename for i in z.infolist() if not i.is_dir()]
        if len(names) != len(set(names)): raise ValueError('Duplicate APK members')
        return {n: sha(z.read(n)) for n in names if not signature.fullmatch(n)}

def asset_action(assets, name, digest):
    rows = [a for a in assets if a['name'] == name]
    if not rows: return 'upload'
    if len(rows) == 1 and rows[0].get('state') == 'uploaded' and rows[0].get('digest') == 'sha256:' + digest:
        return 'reuse'
    raise ValueError('Conflicting remote asset; preserve it for reconciliation')

def main():
    m = dispatch_manifest()
    release = gh('api', f"repos/{REPO}/releases/{m['release_id']}")
    validate_release(release, m)
    report = {'source': m['source'], 'tag': m['tag'], 'version': m['version'], 'build': m['build'], 'manifest': m, 'rebuilt': False, 'assets': []}
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME']) / 'build-tools/36.1.0'
    signer, aapt = str(sdk / 'apksigner'), str(sdk / 'aapt2')
    with tempfile.TemporaryDirectory(prefix='dartpdf-retained-android-') as work:
        root = Path(work)
        native, portable = root / 'native.zip', root / 'portable.zip'
        download(m['native_artifact'], m['native_run'], m['native_digest'], native, m)
        download(m['portable_artifact'], m['portable_run'], m['portable_digest'], portable, m)
        with zipfile.ZipFile(native) as z:
            ledger_id = m['native_ledger_id']
            ledger = json.loads(member(z, f'app/.storeflight/releases/{ledger_id}.json'))
            validate_ledger(ledger, m)
            aab = member(z, f'app/.storeflight/artifacts/{ledger_id}/android/app-release.aab', m['aab_sha'])
        with zipfile.ZipFile(portable) as z:
            apk = member(z, 'flutter-apk/app-release.apk', m['apk_sha'])
        aab_path, unsigned, signed = root / 'app-release.aab', root / 'ci.apk', root / 'app-release.apk'
        aab_path.write_bytes(aab); unsigned.write_bytes(apk)
        badging = command([aapt, 'dump', 'badging', str(unsigned)])
        identity = f"name='dev.milanko.dartpdf' versionCode='{m['build']}' versionName='{m['version']}'".encode()
        if identity not in badging:
            raise ValueError('APK application/version mismatch')
        transfer = root / 'signed-transfer.zip'
        download_transfer(release, transfer, m)
        with zipfile.ZipFile(transfer) as z:
            if z.namelist() != ['app-release.apk']:
                raise ValueError('Unexpected signed transfer contents')
            signed.write_bytes(member(z, 'app-release.apk', m['signed_apk_sha']))
        certificate = command([signer, 'verify', '--verbose', '--print-certs', str(signed)]).decode()
        if ('certificate SHA-256 digest: ' + SIGNER not in certificate
                or 'CN=DartPDF' not in certificate or 'Android Debug' in certificate
                or apk_payload(unsigned) != apk_payload(signed)
                or command([aapt, 'dump', 'badging', str(signed)]) != badging):
            raise ValueError('Release APK identity or unchanged payload verification failed')
        for path in [aab_path, signed]:
            current = gh('api', f"repos/{REPO}/releases/{m['release_id']}"); validate_release(current, m)
            digest = sha(path.read_bytes()); action = asset_action(current['assets'], path.name, digest)
            if action == 'upload':
                command(['gh', 'release', 'upload', m['tag'], str(path), '--repo', REPO])
            after = gh('api', f"repos/{REPO}/releases/{m['release_id']}"); validate_release(after, m)
            asset_action(after['assets'], path.name, digest)
            actual = next(a for a in after['assets'] if a['name'] == path.name)
            if actual['size'] != path.stat().st_size: raise ValueError('Uploaded asset size mismatch')
            report['assets'].append({'name':path.name,'sha256':digest,'size':actual['size'],'action':action})
        report.update(signer_sha256=SIGNER, payload_unchanged_except_signatures=True, complete=True)
        Path('retained-android-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Retained Android assets verified and attached; release remains draft.')

if __name__ == '__main__': main()
