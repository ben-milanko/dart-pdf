"""Read existing Windows/Snap metrics; persist only recipient-encrypted results.

No store listing, release, account, permission or report-generation writes.
Run from the checked-out repository; credentials remain on the runner.
"""
import argparse
import base64
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates

from read_evidence import NoRedirect, PRODUCT, canonical, encrypt

ORIGIN = 'https://manage.devcenter.microsoft.com'
LIMIT = 8 * 1024 * 1024
SNAP_METRICS = ('installed_base_by_architecture', 'weekly_installed_base_by_architecture', 'daily_device_change')


def request(url, method='GET', data=None, headers=None):
    parsed = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qs(parsed.query, strict_parsing=True) if parsed.query else {}
    token = re.fullmatch(r'https://login.microsoftonline.com/[0-9a-fA-F-]{36}/oauth2/token', url)
    allowed = (
        parsed.scheme == 'https' and parsed.netloc == 'manage.devcenter.microsoft.com'
        and parsed.path in ('/v1.0/my/analytics/installs', '/v1.0/my/analytics/usagemonthly', '/v1.0/my/analytics/funnel')
        and not parsed.fragment and query.get('applicationId') == [PRODUCT]
        and set(query) <= ({'applicationId','startDate','endDate'} if parsed.path.endswith('/funnel') else {'applicationId','startDate','endDate','top','skip','groupby','aggregationLevel'})
        and all(len(v) == 1 for v in query.values())
    )
    if not ((token and method == 'POST') or (allowed and method == 'GET' and data is None)):
        raise ValueError('Outside metrics read contract')
    with urllib.request.build_opener(NoRedirect).open(
        urllib.request.Request(url, method=method, data=data, headers=headers or {}), timeout=35
    ) as response:
        raw = response.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise ValueError('Response exceeds bound')
        return json.loads(raw)


def failure(error):
    value = {'status':'unavailable', 'errorType':type(error).__name__,
             'httpStatus':error.code if isinstance(error, urllib.error.HTTPError) else None}
    if isinstance(error, urllib.error.HTTPError):
        retry = error.headers.get('Retry-After','') if error.headers else ''
        if retry.isdigit():
            value['retryAfterSeconds'] = int(retry)
    return value


def microsoft_token():
    env = os.environ
    tenant, client = env['MSSTORE_TENANT_ID'], env['MSSTORE_CLIENT_ID']
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', tenant):
        raise ValueError('Invalid tenant')
    key, cert, _ = load_key_and_certificates(base64.b64decode(env['MSSTORE_CERTIFICATE_BASE64'], validate=True), env['MSSTORE_CERTIFICATE_PASSWORD'].encode())
    url = 'https://login.microsoftonline.com/' + tenant + '/oauth2/token'
    def b64(raw):
        return base64.urlsafe_b64encode(raw).rstrip(b'=')
    now = int(time.time())
    header = {'alg':'RS256','typ':'JWT','x5t':b64(cert.fingerprint(hashes.SHA1())).decode()}
    claims = {'aud':url,'iss':client,'sub':client,'jti':str(uuid.uuid4()),'nbf':now-30,'exp':now+300}
    unsigned = b64(canonical(header)) + b'.' + b64(canonical(claims))
    assertion = unsigned + b'.' + b64(key.sign(unsigned, padding.PKCS1v15(), hashes.SHA256()))
    body = urllib.parse.urlencode({'grant_type':'client_credentials','client_id':client,'resource':ORIGIN,
        'client_assertion_type':'urn:ietf:params:oauth:client-assertion-type:jwt-bearer','client_assertion':assertion.decode()}).encode()
    return request(url, 'POST', body, {'Content-Type':'application/x-www-form-urlencoded'})['access_token']


def windows_series(token, endpoint, start, end):
    if endpoint not in ('installs', 'usagemonthly'):
        raise ValueError('Unsupported dated series')
    # Group by date ONLY so platform totals are provider-deduplicated across versions/markets.
    values, expected, skip = [], None, 0
    for _ in range(20):
        query = {'applicationId':PRODUCT,'startDate':start,'endDate':end,'top':'10000','skip':str(skip),'groupby':'date'}
        if endpoint == 'installs':
            query['aggregationLevel'] = 'day'
        url = ORIGIN + '/v1.0/my/analytics/' + endpoint + '?' + urllib.parse.urlencode(query)
        response = request(url, headers={'Authorization':'Bearer ' + token})
        rows = response['Value']
        if not isinstance(rows, list) or any(r.get('applicationId') != PRODUCT for r in rows):
            raise ValueError('Unexpected application data')
        if expected is None:
            expected = response.get('TotalCount')
        values.extend(rows)
        if not response.get('@nextLink'):
            if isinstance(expected,int) and expected != len(values):
                raise ValueError('Incomplete metric page set')
            return {'status':'ok','start':start,'end':end,'groupby':'date','rows':values,'totalRows':len(values),
                    'dataFreshnessTimestamp':response.get('DataFreshnessTimestamp'),
                    'missingDatesAreZero':False,'timezone':'provider date labels; not independently verified'}
        if not rows:
            raise ValueError('Empty pagination page')
        # Reconstruct the same allowlisted query; never follow a provider-supplied URL.
        skip += len(rows)
    raise ValueError('Metric page bound exceeded')


def snap_series(name, start, end):
    if name not in SNAP_METRICS:
        raise ValueError('Unsupported snap metric')
    if not os.environ.get('SNAPCRAFT_STORE_CREDENTIALS'):
        return {'status':'unavailable','reason':'runner_credential_not_configured'}
    result = subprocess.run(['/snap/bin/snapcraft','metrics','dartpdf','--name',name,'--start',start,'--end',end,'--format=json'],
        stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=100)
    if result.returncode:
        # CLI errors may contain sensitive data. Only classify known failure indicators.
        lower = (result.stdout + result.stderr).lower()
        return {'status':'unavailable','exitCode':result.returncode,
            'metricsPermissionMissing':'package_metrics' in lower,
            'credentialRejected':any(s in lower for s in ('invalid credentials','unauthorized','credentials have expired'))}
    value = json.loads(result.stdout)
    if value.get('metric_name') != name or value.get('status')!='OK' or not isinstance(value.get('buckets'),list) or not isinstance(value.get('series'),list):
        raise ValueError('Unexpected snap metric response')
    dates=value['buckets']
    if dates!=sorted(set(dates)) or any(not start<=d<=end or datetime.date.fromisoformat(d).isoformat()!=d for d in dates):
        raise ValueError('Invalid snap reporting dates')
    if any(len(s.get('values',[])) != len(value['buckets']) for s in value['series']):
        raise ValueError('Snap series length mismatch')
    if any(v is not None and (isinstance(v,bool) or not isinstance(v,int) or v<0) for s in value['series'] for v in s['values']):
        raise ValueError('Invalid snap device counts')
    return {'status':'ok','start':start,'end':end,'metric':value}


def windows_funnel(token, start, end):
    query = {'applicationId':PRODUCT,'startDate':start,'endDate':end}
    response = request(ORIGIN+'/v1.0/my/analytics/funnel?'+urllib.parse.urlencode(query),
                       headers={'Authorization':'Bearer '+token})
    rows = response.get('Value')
    if not isinstance(rows,list) or response.get('TotalCount') != len(rows):
        raise ValueError('Incomplete funnel response')
    allowed = {'PageView','Acquisition','Install','Usage'}
    if any(r.get('MetricType') not in allowed or isinstance(r.get('UserCount'),bool)
           or not str(r.get('UserCount','')).isdigit() for r in rows):
        raise ValueError('Unexpected funnel values')
    if len({r['MetricType'] for r in rows}) != len(rows):
        raise ValueError('Duplicate funnel step')
    return {'status':'ok','start':start,'end':end,'rows':rows,'totalRows':len(rows),
            'dataFreshnessTimestamp':response.get('DataFreshnessTimestamp'),
            'scope':'Legacy Microsoft funnel; aggregate window, not the install-event API population',
            'timezone':'provider date labels; not independently verified'}


def date_window(today=None):
    today = today or datetime.datetime.now(datetime.timezone.utc).date()
    end = today-datetime.timedelta(days=1)
    start = max(datetime.date(2026,7,1),today-datetime.timedelta(days=89))
    return start.isoformat(),end.isoformat()


def collect(today=None):
    start,end = date_window(today)
    result = {'observedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'product':PRODUCT,'windows':{},'snap':{}}
    result['queryWindow']={'start':start,'end':end,'endExcludesCurrentPartialUtcDay':True}
    try:
        token = microsoft_token()
    except Exception as error:
        result['windows']['authentication'] = failure(error)
    else:
        try:
            result['windows']['installs'] = windows_series(token,'installs',start,end)
        except Exception as error:
            result['windows']['installs'] = failure(error)
        throttled=result['windows']['installs'].get('httpStatus')==429
        # One month per request avoids the previously rate-limited multi-month scope.
        month_start = datetime.date.fromisoformat(end).replace(day=1)
        result['windows']['usagemonthlyByMonth'] = {}
        for offset in (0,1):
            if throttled:
                break
            month_end = datetime.date.fromisoformat(end) if offset==0 else month_start-datetime.timedelta(days=1)
            first = month_start if offset==0 else month_end.replace(day=1)
            try:
                value = windows_series(token,'usagemonthly',first.isoformat(),month_end.isoformat())
            except Exception as error:
                value = failure(error)
            result['windows']['usagemonthlyByMonth'][first.strftime('%Y-%m')] = value
            if value.get('httpStatus')==429:
                throttled=True
                break
        result['windows']['funnels'] = {}
        # Retain the original Windows experiment windows while they remain in range.
        for label,first,last in [('baseline','2026-09-24','2026-10-07'),
                                 ('treatment14','2026-10-09','2026-10-22')]:
            if throttled:
                result['windows']['funnels'][label]={'status':'unavailable','reason':'provider_rate_limit_deferred'}
                continue
            if first < start or last > end:
                result['windows']['funnels'][label]={'status':'unavailable','reason':'outside_current_supported_window','start':first,'end':last}
                continue
            try:
                value = windows_funnel(token,first,last)
            except Exception as error:
                value = failure(error)
            result['windows']['funnels'][label]=value
            if value.get('httpStatus')==429:
                throttled=True
        result['windows']['rateLimited']=throttled
    for metric in SNAP_METRICS:
        try:
            result['snap'][metric] = snap_series(metric,start,end)
        except Exception as error:
            result['snap'][metric] = failure(error)
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',default='growth-evidence.encrypted.json');args=parser.parse_args()
    recipient = serialization.load_pem_public_key(os.environ['EVIDENCE_PUBLIC_KEY'].encode())
    if not isinstance(recipient,rsa.RSAPublicKey) or recipient.key_size < 3072:
        raise ValueError('Invalid recipient')
    evidence = collect()
    with open(args.output,'x') as stream:
        json.dump(encrypt(evidence,recipient),stream)
    print('Read-only collection finished. Encrypted results saved; no store writes.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Metrics collection failed; raw provider output withheld.',file=sys.stderr)
        sys.exit(1)
