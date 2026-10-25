"""GET-only Store evidence. Existing certificate auth; encrypted output only.

API: learn.microsoft.com/windows/uwp/monetize/get-an-app-submission
No submission creation, commit, upload, update or deletion exists in this reader.
"""
import base64
import datetime
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import uuid
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates

BASE = 'https://manage.devcenter.microsoft.com/v1.0/my/applications/'
PRODUCT = '9N071VSV6RGK'
LIMIT = 8 * 1024 * 1024

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('Redirect refused')


def request(url, method='GET', data=None, headers=None):
    # Only OAuth token exchange may POST; store resource calls must be GET.
    token_url = re.fullmatch(r'https://login.microsoftonline.com/[0-9a-fA-F-]{36}/oauth2/token', url)
    store_url = re.fullmatch(re.escape(BASE + PRODUCT) + r'(?:/submissions/[0-9]+)?', url)
    if not ((token_url and method == 'POST') or (store_url and method == 'GET' and data is None)):
        raise ValueError('Request outside read-only contract')
    with urllib.request.build_opener(NoRedirect).open(
        urllib.request.Request(url, data=data, headers=headers or {}, method=method), timeout=45
    ) as response:
        raw = response.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise ValueError('Response exceeds evidence bound')
        return json.loads(raw)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def collect(get):
    app = get(BASE + PRODUCT)
    result = {'product': PRODUCT, 'observedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'submissions': {}}
    for role in ('lastPublishedApplicationSubmission', 'pendingApplicationSubmission'):
        ref = app.get(role)
        if not ref:
            result['submissions'][role] = None
            continue
        sid = str(ref.get('id', ''))
        if not re.fullmatch(r'[0-9]+', sid):
            raise ValueError('Invalid submission reference')
        submission = get(BASE + PRODUCT + '/submissions/' + sid)
        if str(submission.get('id')) != sid:
            raise ValueError('Submission identity mismatch')
        listings = submission.get('listings')
        if not isinstance(listings, dict) or not listings:
            raise ValueError('Missing listing evidence')
        result['submissions'][role] = {
            'id': sid, 'status': submission.get('status'),
            'listings': listings,  # includes image records and their ordering
            'listingsSha256': hashlib.sha256(canonical(listings)).hexdigest(),
            'applicationPackages': submission.get('applicationPackages'),
        }
    if not any(result['submissions'].values()):
        raise ValueError('No submission evidence')
    return result


def encrypt(value, recipient):
    if not isinstance(recipient, rsa.RSAPublicKey) or recipient.key_size < 3072:
        raise ValueError('Require RSA public key of at least3072 bits')
    key, nonce = AESGCM.generate_key(bit_length=256), os.urandom(12)
    aad = b'dartpdf-msstore-evidence-v1'
    ciphertext = AESGCM(key).encrypt(nonce, canonical(value), aad)
    wrapped = recipient.encrypt(key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    return {'schema': aad.decode(), 'key': base64.b64encode(wrapped).decode(), 'nonce': base64.b64encode(nonce).decode(), 'ciphertext': base64.b64encode(ciphertext).decode()}


def main():
    recipient = serialization.load_pem_public_key(os.environ['EVIDENCE_PUBLIC_KEY'].encode())
    if not isinstance(recipient, rsa.RSAPublicKey) or recipient.key_size < 3072:
        raise ValueError('Invalid evidence recipient')
    env = os.environ
    tenant, client = env['MSSTORE_TENANT_ID'], env['MSSTORE_CLIENT_ID']
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', tenant):
        raise ValueError('Invalid tenant')
    key, cert, _ = load_key_and_certificates(base64.b64decode(env['MSSTORE_CERTIFICATE_BASE64'], validate=True), env['MSSTORE_CERTIFICATE_PASSWORD'].encode())
    url = 'https://login.microsoftonline.com/' + tenant + '/oauth2/token'
    def b64(raw): return base64.urlsafe_b64encode(raw).rstrip(b'=')
    header = {'alg': 'RS256', 'typ': 'JWT', 'x5t': b64(cert.fingerprint(hashes.SHA1())).decode()}
    now = int(time.time())
    claims = {'aud': url, 'iss': client, 'sub': client, 'jti': str(uuid.uuid4()), 'nbf': now - 30, 'exp': now + 300}
    unsigned = b64(canonical(header)) + b'.' + b64(canonical(claims))
    assertion = unsigned + b'.' + b64(key.sign(unsigned, padding.PKCS1v15(), hashes.SHA256()))
    body = urllib.parse.urlencode({'grant_type': 'client_credentials', 'client_id': client, 'resource': 'https://manage.devcenter.microsoft.com', 'client_assertion_type': 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer', 'client_assertion': assertion.decode()}).encode()
    token = request(url, 'POST', body, {'Content-Type': 'application/x-www-form-urlencoded'})['access_token']
    evidence = collect(lambda url: request(url, headers={'Authorization': 'Bearer ' + token}))
    with open('msstore-evidence.encrypted.json', 'x') as output:
        json.dump(encrypt(evidence, recipient), output)
    print('Encrypted read-only evidence saved; no Store writes performed.')

if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Provider errors can contain signed asset URLs or credential material.
        print('Evidence read failed; no raw provider response logged.', file=sys.stderr)
        sys.exit(1)
