"""Offline regression checks: no API calls or release writes are permitted."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('recovery', Path(__file__).with_name('upload_retained_android.py'))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
PLAN = json.loads(r.MANIFEST.read_text())


def large_assets():
    return [dict(a, id=9000+i, state='uploaded') for i, a in enumerate(PLAN['large_assets'])]


class Guards(unittest.TestCase):
    def test_existing_nine_and_verified_recovery_states(self):
        baseline = PLAN['preserved_assets']
        for extra in ([], large_assets()[:1], large_assets()):
            r.check_assets(PLAN, baseline + extra)
        r.check_assets(PLAN, baseline + large_assets(), complete=True)
        with self.assertRaises(RuntimeError):
            r.check_assets(PLAN, baseline, complete=True)

    def test_asset_refusals(self):
        baseline = copy.deepcopy(PLAN['preserved_assets'])
        bad_cases = [baseline[1:], baseline + [baseline[0]],
                     baseline + [dict(large_assets()[0], name='unknown')]]
        for field, value in [('id', 1), ('size', 1), ('digest', 'sha256:bad'), ('state', 'starter')]:
            changed = copy.deepcopy(baseline)
            changed[0][field] = value
            bad_cases.append(changed)
        for field, value in [('size', 1), ('digest', 'bad'), ('state', 'starter')]:
            bad_cases.append(baseline + [dict(large_assets()[0], **{field: value})])
        for assets in bad_cases:
            with self.subTest(assets=assets), self.assertRaises(RuntimeError):
                r.check_assets(PLAN, assets)

    def test_release_identity_refusals(self):
        release = dict(PLAN['release'], body='not the original notes')
        for field, value in [('id', 1), ('tag_name', 'other'), ('target_commitish', 'main'),
                             ('name', 'other'), ('draft', False), ('prerelease', True),
                             ('published_at', 'now'), ('body', 'changed')]:
            with patch.object(r, 'api', return_value=dict(release, **{field: value})), self.assertRaises(RuntimeError):
                r.release_snapshot(PLAN)

    def test_provenance_refusals(self):
        run = dict(id=PLAN['run_id'], head_sha=PLAN['source'], status='completed', conclusion='success',
                   path='.github/workflows/release-app.yml', repository={'full_name': PLAN['repository']},
                   head_repository={'full_name': PLAN['repository']})
        artifact = dict(PLAN['artifact'], expired=False)
        with patch.object(r, 'api', side_effect=[run, artifact]):
            r.check_provenance(PLAN)
        for field, value in [('id', 1), ('head_sha', 'other'), ('status', 'in_progress'),
                             ('conclusion', 'failure'), ('path', 'other'),
                             ('head_repository', {'full_name': 'other'})]:
            with patch.object(r, 'api', side_effect=[dict(run, **{field: value}), artifact]), self.assertRaises(RuntimeError):
                r.check_provenance(PLAN)
        for field, value in [('id', 1), ('digest', 'bad'), ('expired', True), ('workflow_run', {})]:
            with patch.object(r, 'api', side_effect=[run, dict(artifact, **{field: value})]), self.assertRaises(RuntimeError):
                r.check_provenance(PLAN)

    def test_archive_digest_paths_and_file_digest(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            archive = directory / 'test.zip'
            plan = copy.deepcopy(PLAN)
            plan['large_assets'] = [dict(name='app-release.apk', path='flutter-apk/app-release.apk',
                                         size=4, digest='sha256:' + r.hashlib.sha256(b'test').hexdigest())]
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('flutter-apk/app-release.apk', b'test')
            plan['artifact'].update(size_in_bytes=archive.stat().st_size, digest=r.sha256(archive))
            out = directory / 'out'
            out.mkdir()
            r.extract_verified(plan, archive, out)
            self.assertEqual((out/'app-release.apk').read_bytes(), b'test')
            for mutation in ('archive_digest', 'path', 'file_digest', 'size'):
                bad = copy.deepcopy(plan)
                target = directory / mutation
                target.mkdir()
                if mutation == 'archive_digest':
                    bad['artifact']['digest'] = 'bad'
                elif mutation == 'path':
                    bad['large_assets'][0]['path'] = '../escape.apk'
                elif mutation == 'file_digest':
                    bad['large_assets'][0]['digest'] = 'bad'
                else:
                    bad['large_assets'][0]['size'] = 1
                with self.assertRaises(RuntimeError):
                    r.extract_verified(bad, archive, target)

    def test_serial_upload_skip_and_no_retry_on_ambiguous_write(self):
        for existing in (0, 1, 2):
            current = copy.deepcopy(PLAN['preserved_assets']) + large_assets()[:existing]
            calls = []

            def fake_command(args, **kwargs):
                calls.append(args)
                if args[:3] == ['gh', 'release', 'upload']:
                    name = Path(args[4]).name
                    current.append(next(a for a in large_assets() if a['name'] == name))
                    self.assertNotIn('--clobber', args)
                return None

            def snapshot(plan, complete=False):
                r.check_assets(plan, current, complete)
                return copy.deepcopy(current)

            with tempfile.TemporaryDirectory() as temp, \
                 patch.object(r, 'check_provenance'), patch.object(r, 'check_tag_resolution'), \
                 patch.object(r, 'extract_verified'), patch.object(r, 'release_snapshot', side_effect=snapshot), \
                 patch.object(r, 'command', side_effect=fake_command), contextlib.redirect_stdout(io.StringIO()):
                r.recover(PLAN, Path(temp))
            self.assertEqual(sum(c[:3] == ['gh', 'release', 'upload'] for c in calls), 2-existing)

        with tempfile.TemporaryDirectory() as temp, patch.object(r, 'check_provenance'), \
             patch.object(r, 'release_snapshot', return_value=PLAN['preserved_assets']), \
             patch.object(r, 'extract_verified', side_effect=RuntimeError('unverified bytes')), \
             patch.object(r, 'command') as command:
            with self.assertRaises(RuntimeError):
                r.recover(PLAN, Path(temp))
            self.assertEqual(command.call_count, 1)  # Download only, zero upload.

        with tempfile.TemporaryDirectory() as temp, patch.object(r, 'check_provenance'), \
             patch.object(r, 'release_snapshot', return_value=PLAN['preserved_assets']), \
             patch.object(r, 'extract_verified'), patch.object(r, 'check_tag_resolution'), \
             patch.object(r, 'command', side_effect=[None, RuntimeError('ambiguous upload')]) as command:
            with self.assertRaises(RuntimeError):
                r.recover(PLAN, Path(temp))
            self.assertEqual(command.call_count, 2)  # No retry after ambiguous write.

    def test_wrong_host_environment_refused_without_io(self):
        with patch.dict(r.os.environ, {}, clear=True), patch.object(r, 'recover') as recover:
            with self.assertRaises(RuntimeError):
                r.main()
            recover.assert_not_called()


if __name__ == '__main__':
    unittest.main()
