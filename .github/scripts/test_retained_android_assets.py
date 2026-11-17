import copy, io, unittest, zipfile
import retained_android_assets as p

class Boundaries(unittest.TestCase):
    def test_draft_source_identity(self):
        good={'id':p.RELEASE_ID,'draft':True,'tag_name':p.TAG,'target_commitish':p.SOURCE}
        p.validate_release(good)
        for field,value in [('id',0),('draft',False),('tag_name','app-v16.0.0'),('target_commitish','wrong')]:
            bad={**good,field:value}
            with self.assertRaises(ValueError):p.validate_release(bad)
    def test_draft_lookup_uses_release_id(self):
        from unittest.mock import patch
        # GitHub's by-tag route can return 404 for a retained draft.
        # Fail immediately after the initial lookup, before any SDK/network use.
        class LookupComplete(Exception): pass
        with patch.object(p, 'gh', side_effect=LookupComplete) as lookup:
            with self.assertRaises(LookupComplete): p.main()
        lookup.assert_called_once_with('api', f'repos/{p.REPO}/releases/{p.RELEASE_ID}')

    def test_artifact_provenance(self):
        good={'id':1,'expired':False,'digest':'sha256:abc','workflow_run':{'id':2,'head_sha':p.SOURCE}}
        p.validate_artifact(good,1,2,'abc')
        for bad in [{**good,'expired':True},{**good,'digest':'sha256:bad'},{**good,'id':3},{**good,'workflow_run':{'id':2,'head_sha':'wrong'}}]:
            with self.assertRaises(ValueError):p.validate_artifact(bad,1,2,'abc')
    def test_exact_archive_member_and_hash(self):
        raw=io.BytesIO()
        with zipfile.ZipFile(raw,'w') as z:z.writestr('safe.apk',b'payload');z.writestr('../unsafe',b'other')
        with zipfile.ZipFile(io.BytesIO(raw.getvalue())) as z:
            self.assertEqual(p.member(z,'safe.apk',p.sha(b'payload')),b'payload')
            for name,digest in [('absent',None),('safe.apk','wrong')]:
                with self.assertRaises(ValueError):p.member(z,name,digest)
    def test_no_overwrite_or_retry_conflicts(self):
        self.assertEqual(p.asset_action([], 'x','a'),'upload')
        good={'name':'x','state':'uploaded','digest':'sha256:a'}
        self.assertEqual(p.asset_action([good],'x','a'),'reuse')
        for bad in [[{**good,'digest':'sha256:b'}],[{**good,'state':'starter'}],[good,good]]:
            with self.assertRaises(ValueError):p.asset_action(bad,'x','a')

if __name__=='__main__':unittest.main()
