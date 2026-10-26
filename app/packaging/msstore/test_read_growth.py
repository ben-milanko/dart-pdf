import unittest
from unittest.mock import patch
import read_growth as g


class Boundaries(unittest.TestCase):
    def test_reject_mutation_and_other_hosts(self):
        for url,method in [('https://evil.invalid/v1.0/my/analytics/installs?applicationId='+g.PRODUCT,'GET'),
                           (g.ORIGIN+'/v1.0/my/applications/'+g.PRODUCT,'POST'),
                           (g.ORIGIN+'/v1.0/my/analytics/installs?applicationId='+g.PRODUCT,'DELETE'),
                           (g.ORIGIN+'/v1.0/my/analytics/installs?applicationId=OTHER','GET')]:
            with self.assertRaises(ValueError):g.request(url,method)

    def test_reject_unapproved_snap_metric(self):
        with self.assertRaises(ValueError):g.snap_series('upload','2026-01-01','2026-01-02')

    def test_missing_credential_does_not_prompt(self):
        with patch.dict(g.os.environ,{},clear=True),patch.object(g.subprocess,'run') as run:
            self.assertEqual(g.snap_series(g.SNAP_METRICS[0],'2026-01-01','2026-01-02')['status'],'unavailable')
            run.assert_not_called()

    def test_windows_totals_group_by_date_and_page(self):
        replies=[{'Value':[{'applicationId':g.PRODUCT,'date':'2026-09-01','monthlyActiveUsers':7}],'TotalCount':2,'@nextLink':'https://evil.invalid'},
                 {'Value':[{'applicationId':g.PRODUCT,'date':'2026-10-01','monthlyActiveUsers':9}],'TotalCount':2}]
        with patch.object(g,'request',side_effect=replies) as req:
            value=g.windows_series('test-token','usagemonthly','2026-09-01','2026-10-25')
            self.assertEqual(value['totalRows'],2)
            for call in req.call_args_list:
                self.assertTrue(call.args[0].startswith(g.ORIGIN+'/v1.0/my/analytics/usagemonthly?'))
                self.assertIn('groupby=date',call.args[0])
            self.assertIn('skip=1',req.call_args.args[0])

    def test_incomplete_page_set_is_not_success(self):
        with patch.object(g,'request',return_value={'Value':[],'TotalCount':3}):
            with self.assertRaises(ValueError):g.windows_series('test-token','installs','2026-09-01','2026-10-25')


if __name__ == '__main__':unittest.main()
