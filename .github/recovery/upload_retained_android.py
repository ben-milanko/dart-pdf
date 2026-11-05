"""One-off retained-byte recovery. No rebuild, replacement, tag or publish APIs.

Only the guarded hosted workflow may call main. Unit tests import pure guards
and mock all subprocess/network boundaries. Failure is terminal: never retry
an ambiguous write; a new manual dispatch reconciles existing complete assets.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

MANIFEST = Path(__file__).with_name('android-upload-manifest.json')


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    with path.open('rb') as stream:
        return 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def api(plan, endpoint):
    result = command([
        'gh', 'api', '-H', 'Cache-Control: no-cache',
        f"repos/{plan['repository']}/{endpoint}",
    ], capture_output=True, text=True)
    return json.loads(result.stdout)


def check_assets(plan, assets, complete=False):
    preserved = {a['name']: a for a in plan['preserved_assets']}
    large = {a['name']: a for a in plan['large_assets']}
    expected = preserved | large
    names = [a['name'] for a in assets]
    ids = [a['id'] for a in assets]
    require(len(names) == len(set(names)), 'Duplicate asset names')
    require(len(ids) == len(set(ids)), 'Duplicate asset IDs')
    require(set(names) <= expected.keys(), 'Unknown release assets')
    require(preserved.keys() <= set(names), 'Preserved asset missing')
    if complete:
        require(set(names) == expected.keys(), 'Final release is not exactly 11 assets')
    for actual in assets:
        wanted = expected[actual['name']]
        require(actual.get('state') == 'uploaded', 'Partial/starter asset')
        for field in ('size', 'digest'):
            require(actual.get(field) == wanted[field], f"Asset {field} mismatch: {actual['name']}")
        if actual['name'] in preserved:
            require(actual['id'] == wanted['id'], 'Preserved asset ID changed')
    return set(names)


def release_snapshot(plan, complete=False):
    release = api(plan, f"releases/{plan['release']['id']}")
    for key, value in plan['release'].items():
        require(release.get(key) == value, f'Release {key} changed')
    require(hashlib.sha256(release['body'].encode()).hexdigest() == plan['body_sha256'],
            'Release notes changed')
    # Read all pages independently of the embedded release assets array.
    assets = []
    for page in range(1, 101):
        batch = api(plan, f"releases/{plan['release']['id']}/assets?per_page=100&page={page}")
        assets.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise RuntimeError('Asset pagination did not terminate')
    check_assets(plan, assets, complete)
    return assets


def check_provenance(plan):
    run = api(plan, f"actions/runs/{plan['run_id']}")
    require(run['id'] == plan['run_id'] and run['head_sha'] == plan['source'],
            'Original run/source mismatch')
    require(run['status'] == 'completed' and run['conclusion'] == 'success',
            'Original run is not successful')
    require(run['path'] == '.github/workflows/release-app.yml', 'Wrong source workflow')
    require(run['repository']['full_name'] == plan['repository'] and
            run['head_repository']['full_name'] == plan['repository'], 'Wrong source repository')
    artifact = api(plan, f"actions/artifacts/{plan['artifact']['id']}")
    require(artifact.get('expired') is False, 'Original artifact expired')
    for key, value in plan['artifact'].items():
        require(artifact.get(key) == value, f'Original artifact {key} mismatch')


def extract_verified(plan, archive, directory):
    require(archive.stat().st_size == plan['artifact']['size_in_bytes'], 'Archive size mismatch')
    require(sha256(archive) == plan['artifact']['digest'], 'Archive digest mismatch')
    with zipfile.ZipFile(archive) as zipped:
        infos = zipped.infolist()
        require(sorted(i.filename for i in infos) == sorted(a['path'] for a in plan['large_assets']),
                'Unexpected/duplicate archive paths')
        for asset in plan['large_assets']:
            info = zipped.getinfo(asset['path'])
            require(not info.is_dir() and info.file_size == asset['size'], 'Archive entry size mismatch')
            require((info.external_attr >> 16) & 0o170000 != 0o120000, 'Archive symlink refused')
            target = directory / asset['name']
            with zipped.open(info) as src, target.open('xb') as dst:
                shutil.copyfileobj(src, dst)
            require(target.stat().st_size == asset['size'] and sha256(target) == asset['digest'],
                    'Retained file hash/size mismatch')


def check_tag_resolution(plan):
    result = command([
        'gh', 'release', 'view', plan['release']['tag_name'], '--repo', plan['repository'],
        '--json', 'databaseId,tagName,isDraft,targetCommitish,name',
    ], capture_output=True, text=True)
    require(json.loads(result.stdout) == {
        'databaseId': plan['release']['id'], 'tagName': plan['release']['tag_name'],
        'isDraft': True, 'targetCommitish': plan['source'], 'name': plan['release']['name'],
    }, 'gh tag resolution does not match exact draft')


def recover(plan, directory):
    # Both bytes must pass verification before even the first release write.
    check_provenance(plan)
    release_snapshot(plan)
    archive = directory / 'android.zip'
    with archive.open('xb') as out:
        command(['gh', 'api', f"repos/{plan['repository']}/actions/artifacts/{plan['artifact']['id']}/zip"],
                stdout=out)
    extract_verified(plan, archive, directory)
    uploaded_ids = {}
    for asset in plan['large_assets']:
        # Fresh complete reconciliation before EACH write. Never --clobber.
        current = release_snapshot(plan)
        current_ids = {a['name']: a['id'] for a in current}
        require(all(current_ids.get(name) == ident for name, ident in uploaded_ids.items()),
                'Previously observed large asset ID changed')
        if asset['name'] in current_ids:
            uploaded_ids[asset['name']] = current_ids[asset['name']]
            continue
        check_tag_resolution(plan)
        command(['gh', 'release', 'upload', plan['release']['tag_name'],
                 str(directory / asset['name']), '--repo', plan['repository']])
        after = release_snapshot(plan)
        matches = [a for a in after if a['name'] == asset['name']]
        require(len(matches) == 1, 'Uploaded asset absent on independent readback')
        uploaded_ids[asset['name']] = matches[0]['id']
    final = release_snapshot(plan, complete=True)
    require(all(next(a['id'] for a in final if a['name'] == name) == ident
                for name, ident in uploaded_ids.items()), 'Final large asset ID changed')
    print(json.dumps({'draft_verified': True, 'published': False, 'release_id': plan['release']['id'],
                      'assets': [{k: a[k] for k in ('id', 'name', 'size', 'digest')} for a in final]}, indent=2))


def main():
    plan = json.loads(MANIFEST.read_text())
    require(os.environ.get('GITHUB_ACTIONS') == 'true' and
            os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' and
            os.environ.get('GITHUB_REPOSITORY') == plan['repository'] and
            os.environ.get('GITHUB_REF') == 'refs/heads/' + plan['branch'] and
            os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted',
            'Only the exact hosted operational-branch dispatch may execute this helper')
    require(plan['release']['draft'] is True and len(plan['preserved_assets']) == 9 and
            len(plan['large_assets']) == 2, 'Invalid frozen plan')
    with tempfile.TemporaryDirectory(prefix='retained-android-') as temp:
        recover(plan, Path(temp))


if __name__ == '__main__':
    main()
