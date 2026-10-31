import unittest
import datetime
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

    def test_date_window_rolls_over_month_and_year(self):
        self.assertEqual(g.date_window(datetime.date(2026,11,1)),('2026-08-04','2026-10-31'))
        self.assertEqual(g.date_window(datetime.date(2027,1,1)),('2026-10-04','2026-12-31'))

    def test_funnel_has_matching_window_and_no_series_grouping(self):
        response={'Value':[{'MetricType':'PageView','UserCount':40},{'MetricType':'Acquisition','UserCount':3}], 'TotalCount':2}
        with patch.object(g,'request',return_value=response) as req:
            data=g.windows_funnel('test-token','2026-09-24','2026-10-07')
            self.assertEqual(data['rows'],response['Value'])
            self.assertIn('/analytics/funnel?',req.call_args.args[0])
            self.assertNotIn('groupby=',req.call_args.args[0])

    def test_funnel_rejects_duplicate_and_invalid_counts(self):
        for rows in [[{'MetricType':'PageView','UserCount':1}]*2,
                     [{'MetricType':'PageView','UserCount':-1}],
                     [{'MetricType':'PageView','UserCount':True}]]:
            with patch.object(g,'request',return_value={'Value':rows,'TotalCount':len(rows)}):
                with self.assertRaises(ValueError):g.windows_funnel('x','2026-09-24','2026-10-07')

    def test_no_unsupported_windows_endpoint(self):
        with self.assertRaises(ValueError):g.windows_series('x','applications','2026-09-24','2026-10-07')

    def test_collect_retains_failure_and_reads_snap_independently(self):
        with patch.object(g,'microsoft_token',side_effect=ValueError('private error')),patch.object(g,'snap_series',return_value={'status':'ok'}) as snap:
            result=g.collect(datetime.date(2026,11,1))
            self.assertEqual(result['windows']['authentication']['status'],'unavailable')
            self.assertEqual(snap.call_count,3)
            self.assertNotIn('private error',str(result))

    def test_rate_limit_defers_remaining_windows_calls(self):
        error=g.urllib.error.HTTPError(g.ORIGIN,429,'rate limit',{'Retry-After':'120'},None)
        with patch.object(g,'microsoft_token',return_value='test'),patch.object(g,'windows_series',side_effect=error) as series,patch.object(g,'windows_funnel') as funnel,patch.object(g,'snap_series',return_value={'status':'ok'}):
            result=g.collect(datetime.date(2026,11,1))
            self.assertTrue(result['windows']['rateLimited'])
            self.assertEqual(result['windows']['installs']['retryAfterSeconds'],120)
            self.assertEqual(series.call_count,1)
            funnel.assert_not_called()


if __name__ == '__main__':unittest.main()
