import copy, io, json, os, tempfile, unittest, zipfile
from pathlib import Path
from unittest.mock import patch
import retained_android_assets as p


def manifest():
    return dict(schema_version=1, source='e8ca426c752131d0574424956c015cce838547aa',
                version='16.1.2', build=56, tag='app-v16.1.2', release_id=123,
                native_run=44010967774, native_artifact=456, native_digest='a'*64,
                native_ledger_id='0123456789abcdef01234567', portable_run=44006015513,
                portable_artifact=789, portable_digest='b'*64, aab_sha='c'*64,
                apk_sha='d'*64, signed_apk_sha='e'*64, transfer_sha='f'*64)


def archive(rows):
    raw = io.BytesIO()
    with zipfile.ZipFile(raw, 'w') as z:
        for name, data in rows: z.writestr(name, data)
    return raw.getvalue()


class Boundaries(unittest.TestCase):
    def test_manifest_roundtrip_and_future_release(self):
        for version, build in [('16.1.2', 56), ('17.2.3', 99)]:
            m = dict(manifest(), version=version, build=build, tag='app-v'+version)
            raw = json.dumps(m)
            self.assertEqual(p.load_manifest(raw, p.sha(raw.encode())), m)

    def test_manifest_rejects_missing_unknown_and_invalid_fields(self):
        good = manifest()
        for key in good:
            bad = dict(good); del bad[key]
            with self.subTest(missing=key), self.assertRaises(ValueError): p.validate_manifest(bad)
        cases = [('url', 'https://example.invalid'), ('schema_version', 2), ('build', True),
                 ('release_id', '123'), ('native_run', 0), ('portable_artifact', -1),
                 ('native_artifact', 2**53), ('build', 2100000001), ('source', 'main'),
                 ('source', 'A'*40), ('version', '01.1.2'), ('version', '16.1.2+56'),
                 ('tag', '--repo=attacker/repo'), ('native_ledger_id', '../../bad'),
                 ('native_ledger_id', 'a'*25)]
        for key in ['native_digest', 'portable_digest', 'aab_sha', 'apk_sha', 'signed_apk_sha', 'transfer_sha']:
            cases.extend([(key, 'sha256:'+'a'*64), (key, 'A'*64), (key, None)])
        for key, value in cases:
            with self.subTest(field=key, value=value), self.assertRaises(ValueError):
                p.validate_manifest(dict(good, **{key: value}))

    def test_raw_manifest_digest_and_duplicate_keys(self):
        raw = json.dumps(manifest())
        for text, digest in [(raw, 'a'*64), (raw+'\n', p.sha(raw.encode())),
                             (' '*16385, p.sha((' '*16385).encode())),
                             ('{"build":1,"build":2}', p.sha(b'{"build":1,"build":2}')),
                             ('null', p.sha(b'null'))]:
            with self.assertRaises(ValueError): p.load_manifest(text, digest)

    def test_only_explicit_dispatch_before_network(self):
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME':'push'}), patch.object(p, 'gh') as network:
            with self.assertRaises(ValueError): p.main()
            network.assert_not_called()
        with tempfile.TemporaryDirectory() as td:
            event = Path(td)/'event.json'; raw = json.dumps(manifest())
            event.write_text(json.dumps({'inputs':{'manifest_json':raw, 'manifest_sha256':p.sha(raw.encode())}}))
            with patch.dict(os.environ, {'GITHUB_EVENT_NAME':'workflow_dispatch', 'GITHUB_EVENT_PATH':str(event)}):
                self.assertEqual(p.dispatch_manifest(), manifest())
                event.write_text(json.dumps({'inputs':{'manifest_json':raw, 'manifest_sha256':'a'*64}}))
                with patch.object(p, 'gh') as network:
                    with self.assertRaises(ValueError): p.main()
                    network.assert_not_called()

    def test_draft_source_identity(self):
        m = manifest()
        good = {'id':m['release_id'], 'draft':True, 'tag_name':m['tag'], 'target_commitish':m['source']}
        p.validate_release(good, m)
        for field, value in [('id',0), ('draft',False), ('tag_name','app-v16.1.1'), ('target_commitish','main')]:
            with self.assertRaises(ValueError): p.validate_release(dict(good, **{field:value}), m)

    def test_draft_lookup_uses_release_id(self):
        class LookupComplete(Exception): pass
        with patch.object(p, 'dispatch_manifest', return_value=manifest()), patch.object(p, 'gh', side_effect=LookupComplete) as lookup:
            with self.assertRaises(LookupComplete): p.main()
        lookup.assert_called_once_with('api', f'repos/{p.REPO}/releases/123')

    def test_artifact_provenance(self):
        m = manifest()
        good = {'id':1, 'expired':False, 'digest':'sha256:abc', 'workflow_run':{'id':2, 'head_sha':m['source']}}
        p.validate_artifact(good, 1, 2, 'abc', m)
        for bad in [dict(good, expired=True), dict(good, digest='sha256:bad'), dict(good, id=3),
                    dict(good, workflow_run={'id':99,'head_sha':m['source']}),
                    dict(good, workflow_run={'id':2,'head_sha':'wrong'})]:
            with self.assertRaises(ValueError): p.validate_artifact(bad, 1, 2, 'abc', m)

    def test_ledger_source_version_build_and_payload(self):
        m = manifest()
        good = {'source_sha':m['source'], 'version':'16.1.2+56',
                'steps':{'build.android':{'status':'succeeded'}}, 'artifacts':{'android':{'sha256':m['aab_sha']}}}
        p.validate_ledger(good, m)
        for keys, value in [(('source_sha',),'wrong'), (('version',),'16.1.2+55'),
                            (('steps','build.android','status'),'failed'), (('artifacts','android','sha256'),'wrong')]:
            bad = copy.deepcopy(good); target = bad
            for key in keys[:-1]: target = target[key]
            target[keys[-1]] = value
            with self.assertRaises(ValueError): p.validate_ledger(bad, m)

    def test_exact_archive_member_and_hash(self):
        with zipfile.ZipFile(io.BytesIO(archive([('safe.apk',b'payload'),('../unsafe',b'other')]))) as z:
            self.assertEqual(p.member(z,'safe.apk',p.sha(b'payload')),b'payload')
            for name,digest in [('absent',None),('safe.apk','wrong')]:
                with self.assertRaises(ValueError): p.member(z,name,digest)

    def test_no_overwrite_or_retry_conflicts(self):
        self.assertEqual(p.asset_action([], 'x','a'),'upload')
        good = {'name':'x','state':'uploaded','digest':'sha256:a'}
        self.assertEqual(p.asset_action([good],'x','a'),'reuse')
        for bad in [[dict(good,digest='sha256:b')],[dict(good,state='starter')],[good,good]]:
            with self.assertRaises(ValueError): p.asset_action(bad,'x','a')

    def test_payload_comparison_excludes_only_signatures(self):
        with tempfile.TemporaryDirectory() as td:
            a, b = Path(td)/'a.apk', Path(td)/'b.apk'
            a.write_bytes(archive([('classes.dex', b'original'),('META-INF/NOTICE',b'notice')]))
            b.write_bytes(archive([('classes.dex', b'original'),('META-INF/NOTICE',b'notice'),('META-INF/CERT.RSA',b'cert')]))
            self.assertEqual(p.apk_payload(a), p.apk_payload(b))
            b.write_bytes(archive([('classes.dex', b'changed'),('META-INF/NOTICE',b'notice')]))
            self.assertNotEqual(p.apk_payload(a), p.apk_payload(b))

    def test_archive_download_checks_metadata_and_bytes(self):
        m = manifest()
        meta = {'id':1,'expired':False,'digest':'sha256:'+p.sha(b'archive'),'workflow_run':{'id':2,'head_sha':m['source']}}
        def download(args, **kwargs):
            kwargs['stdout'].write(b'tampered')
            return type('Result', (), {'returncode':0})()
        with tempfile.TemporaryDirectory() as td, patch.object(p,'gh', return_value=meta), patch.object(p.subprocess,'run',side_effect=download):
            with self.assertRaisesRegex(ValueError, 'archive digest'): p.download(1,2,p.sha(b'archive'),Path(td)/'out.zip',m)

    def test_transfer_checks_remote_identity_and_bytes(self):
        m = manifest()
        good = {'name':'android-signed-apk-transfer.zip','id':5,'state':'uploaded','digest':'sha256:'+m['transfer_sha']}
        for rows in [[], [good,good], [dict(good, digest='sha256:wrong')], [dict(good,state='starter')]]:
            with patch.object(p.subprocess,'run') as network:
                with self.assertRaises(ValueError): p.download_transfer({'assets':rows}, Path('unused'), m)
                network.assert_not_called()
        def download(args, **kwargs):
            kwargs['stdout'].write(b'tampered')
            return type('Result', (), {'returncode':0})()
        with tempfile.TemporaryDirectory() as td, patch.object(p.subprocess,'run',side_effect=download):
            with self.assertRaisesRegex(ValueError,'transfer digest'): p.download_transfer({'assets':[good]},Path(td)/'out.zip',m)


if __name__ == '__main__': unittest.main()
