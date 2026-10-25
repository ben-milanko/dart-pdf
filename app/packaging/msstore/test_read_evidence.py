import base64
import unittest
from unittest.mock import patch
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import read_evidence as reader

class EvidenceTests(unittest.TestCase):
    def test_mutations_and_foreign_hosts_refused(self):
        for method in ('POST', 'PUT', 'PATCH', 'DELETE'):
            with self.assertRaises(ValueError):
                reader.request(reader.BASE + reader.PRODUCT, method)
        for url in ('https://evil.test/', reader.BASE + 'OTHER', reader.BASE + reader.PRODUCT + '/submissions/../commit'):
            with self.assertRaises(ValueError): reader.request(url)

    def test_gets_only_and_preserves_asset_order(self):
        calls = []
        listing = {'en-US': {'images': [{'id': 'b'}, {'id': 'a'}]}}
        def get(url):
            calls.append(url)
            if url.endswith(reader.PRODUCT):
                return {'pendingApplicationSubmission': {'id': '123'}, 'lastPublishedApplicationSubmission': {'id': '122'}}
            return {'id': url.split('/')[-1], 'status': 'Certification', 'listings': listing, 'applicationPackages': []}
        result = reader.collect(get)
        self.assertEqual(len(calls), 3)
        self.assertEqual(result['submissions']['pendingApplicationSubmission']['listings'], listing)

    def test_missing_or_mismatched_evidence_fails(self):
        with self.assertRaises(ValueError): reader.collect(lambda url: {})
        def get(url):
            return {'pendingApplicationSubmission': {'id': '../unsafe'}}
        with self.assertRaises(ValueError): reader.collect(get)

    def test_encryption_roundtrip(self):
        key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        data = {'listings': {'private': 'evidence'}}
        out = reader.encrypt(data, key.public_key())
        secret = key.decrypt(base64.b64decode(out['key']), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
        plain = AESGCM(secret).decrypt(base64.b64decode(out['nonce']), base64.b64decode(out['ciphertext']), out['schema'].encode())
        self.assertEqual(plain, reader.canonical(data))
        self.assertNotIn('private', str(out))

    def test_weak_recipient_refused(self):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        with self.assertRaises(ValueError): reader.encrypt({}, key.public_key())

if __name__ == '__main__': unittest.main()
