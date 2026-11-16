"""Publish source-bound retained Android artifacts; no Flutter build or store writes."""
from pathlib import Path
import hashlib, json, os, re, subprocess, tempfile, zipfile

REPO = 'ben-milanko/dart-pdf'
SOURCE = '36a14db31bf2483378e5fde3591a46899146cd21'
TAG = 'app-v16.1.1'
NATIVE_RUN = 43788575735
NATIVE_ARTIFACT = 14191637652
NATIVE_DIGEST = 'c24cb64ad70181312c38bd6bfcb3a9cec4e2e9cf5864f0e39f3755973dd1e5c2'
PORTABLE_RUN = 43792481026
PORTABLE_ARTIFACT = 14192658425
PORTABLE_DIGEST = '941a68ec2cc6de330d7293a895829c3159cdc217dd4bc13c6b33ea678c374b21'
AAB_SHA = 'f7553f036ca8aed7ddbebd35d3a3e150f2d3a4a33b87cf3c6b77345a07231d0d'
APK_SHA = '7a37f2b3d772ebb6913bd7cbc7cfda075e0ddbf2210bdb2e223481963b4586b6'
SIGNED_APK_SHA = '30211dc7815dc28579e9ed2314092a4c1f5a3f62d2b9997309ac1c911a371c0b'
TRANSFER_SHA = '74c694df22c1bc7fce9ad58243484ece0095e7bcc7be2c61dad45a9db2b48320'
SIGNER = '4fbf4e9da8c7d2b1e7c3bee006aefbf8b8faa99f610ac0877e3e88d6d6fa6140'

def sha(data): return hashlib.sha256(data).hexdigest()

def command(args):
    p = subprocess.run(args, capture_output=True)
    if p.returncode:
        # CI credentials stay in GH_TOKEN, never argv. Keep child failure
        # output private rather than echoing authentication diagnostics.
        raise RuntimeError('Release command failed: ' + Path(args[0]).name)
    return p.stdout

def gh(*args): return json.loads(command(['gh', *args]))

def validate_release(d):
    if not (d.get('draft') is True and d.get('tag_name') == TAG
            and d.get('target_commitish') == SOURCE):
        raise ValueError('Release must remain the exact source-bound draft')

def validate_artifact(d, aid, run, digest):
    if not (d['id'] == aid and not d['expired'] and d['digest'] == 'sha256:' + digest
            and d['workflow_run']['id'] == run
            and d['workflow_run']['head_sha'] == SOURCE):
        raise ValueError('CI artifact identity mismatch')

def download(aid, run, digest, target):
    meta = gh('api', f'repos/{REPO}/actions/artifacts/{aid}')
    validate_artifact(meta, aid, run, digest)
    with target.open('wb') as f:
        p = subprocess.run(['gh', 'api', f'repos/{REPO}/actions/artifacts/{aid}/zip'], stdout=f, stderr=subprocess.PIPE)
    if p.returncode or sha(target.read_bytes()) != digest:
        raise ValueError('CI archive digest mismatch')

def download_transfer(release, target):
    rows = [a for a in release['assets'] if a['name'] == 'android-signed-apk-transfer.zip']
    if not (len(rows) == 1 and rows[0]['state'] == 'uploaded'
            and rows[0]['digest'] == 'sha256:' + TRANSFER_SHA
            and str(rows[0]['id']).isdigit()):
        raise ValueError('Signed APK transfer identity mismatch')
    with target.open('wb') as f:
        p = subprocess.run(['gh', 'api', f"repos/{REPO}/releases/assets/{rows[0]['id']}",
                            '-H', 'Accept: application/octet-stream'], stdout=f, stderr=subprocess.PIPE)
    if p.returncode or sha(target.read_bytes()) != TRANSFER_SHA:
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
    release = gh('api', f'repos/{REPO}/releases/tags/{TAG}')
    validate_release(release)
    report = {'source': SOURCE, 'tag': TAG, 'rebuilt': False, 'assets': []}
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME']) / 'build-tools/36.1.0'
    signer, aapt = str(sdk / 'apksigner'), str(sdk / 'aapt2')
    with tempfile.TemporaryDirectory(prefix='dartpdf-retained-android-') as work:
        root = Path(work)
        native, portable = root / 'native.zip', root / 'portable.zip'
        download(NATIVE_ARTIFACT, NATIVE_RUN, NATIVE_DIGEST, native)
        download(PORTABLE_ARTIFACT, PORTABLE_RUN, PORTABLE_DIGEST, portable)
        with zipfile.ZipFile(native) as z:
            ledger = json.loads(member(z, 'app/.storeflight/releases/20cbec6556de4f5be5463123.json'))
            if not (ledger['source_sha'] == SOURCE and ledger['version'] == '16.1.1+55'
                    and ledger['steps']['build.android']['status'] == 'succeeded'
                    and ledger['artifacts']['android']['sha256'] == AAB_SHA):
                raise ValueError('Native ledger provenance mismatch')
            aab = member(z, 'app/.storeflight/artifacts/20cbec6556de4f5be5463123/android/app-release.aab', AAB_SHA)
        with zipfile.ZipFile(portable) as z:
            apk = member(z, 'flutter-apk/app-release.apk', APK_SHA)
        aab_path, unsigned, signed = root / 'app-release.aab', root / 'ci.apk', root / 'app-release.apk'
        aab_path.write_bytes(aab); unsigned.write_bytes(apk)
        badging = command([aapt, 'dump', 'badging', str(unsigned)])
        if b"name='dev.milanko.dartpdf' versionCode='55' versionName='16.1.1'" not in badging:
            raise ValueError('APK application/version mismatch')
        transfer = root / 'signed-transfer.zip'
        download_transfer(release, transfer)
        with zipfile.ZipFile(transfer) as z:
            if z.namelist() != ['app-release.apk']:
                raise ValueError('Unexpected signed transfer contents')
            signed.write_bytes(member(z, 'app-release.apk', SIGNED_APK_SHA))
        certificate = command([signer, 'verify', '--verbose', '--print-certs', str(signed)]).decode()
        if ('certificate SHA-256 digest: ' + SIGNER not in certificate
                or 'CN=DartPDF' not in certificate or 'Android Debug' in certificate
                or apk_payload(unsigned) != apk_payload(signed)
                or command([aapt, 'dump', 'badging', str(signed)]) != badging):
            raise ValueError('Release APK identity or unchanged payload verification failed')
        for path in [aab_path, signed]:
            current = gh('api', f'repos/{REPO}/releases/tags/{TAG}'); validate_release(current)
            digest = sha(path.read_bytes()); action = asset_action(current['assets'], path.name, digest)
            if action == 'upload':
                command(['gh', 'release', 'upload', TAG, str(path), '--repo', REPO])
            after = gh('api', f'repos/{REPO}/releases/tags/{TAG}'); validate_release(after)
            asset_action(after['assets'], path.name, digest)
            actual = next(a for a in after['assets'] if a['name'] == path.name)
            if actual['size'] != path.stat().st_size: raise ValueError('Uploaded asset size mismatch')
            report['assets'].append({'name':path.name,'sha256':digest,'size':actual['size'],'action':action})
        report.update(signer_sha256=SIGNER, payload_unchanged_except_signatures=True, complete=True)
        Path('retained-android-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Retained Android assets verified and attached; release remains draft.')

if __name__ == '__main__': main()
