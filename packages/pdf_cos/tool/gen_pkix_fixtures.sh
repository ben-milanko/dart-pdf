#!/usr/bin/env bash
# Generates PKIX reference artifacts with OpenSSL for the dart-pdf KATs:
# a CA, a leaf cert, a TSA cert, a CRL, an OCSP response, and an RFC 3161
# timestamp token. Output is a Dart fixture of base64 constants. Run once;
# the produced artifacts are checked in so the tests stay pure-Dart.
#   bash tool/gen_pkix_fixtures.sh > test/pkix_fixtures.g.dart
set -euo pipefail
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$W"

# deterministic-ish dates so tests can pin them
DAYS=7300

# --- CA -----------------------------------------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt \
  -days $DAYS -sha256 -subj "/CN=Dart PDF PKIX Test CA/O=dart-pdf" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

# --- leaf (the "signer" whose revocation we check) ----------------------
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr \
  -subj "/CN=Dart PDF Signer/O=dart-pdf" 2>/dev/null
openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key \
  -set_serial 0x1111 -days $DAYS -sha256 -out leaf.crt \
  -extfile <(printf "keyUsage=digitalSignature,nonRepudiation\nauthorityInfoAccess=OCSP;URI:http://ocsp.example/\ncrlDistributionPoints=URI:http://crl.example/ca.crl\n") 2>/dev/null

# --- a second leaf we will REVOKE --------------------------------------
openssl req -newkey rsa:2048 -nodes -keyout revoked.key -out revoked.csr \
  -subj "/CN=Dart PDF Revoked/O=dart-pdf" 2>/dev/null
openssl x509 -req -in revoked.csr -CA ca.crt -CAkey ca.key \
  -set_serial 0x2222 -days $DAYS -sha256 -out revoked.crt 2>/dev/null

# --- TSA cert -----------------------------------------------------------
openssl req -newkey rsa:2048 -nodes -keyout tsa.key -out tsa.csr \
  -subj "/CN=Dart PDF TSA/O=dart-pdf" 2>/dev/null
openssl x509 -req -in tsa.csr -CA ca.crt -CAkey ca.key \
  -set_serial 0x3333 -days $DAYS -sha256 -out tsa.crt \
  -extfile <(printf "extendedKeyUsage=critical,timeStamping\n") 2>/dev/null

# --- CA database (for CRL + OCSP) --------------------------------------
touch index.txt
echo 1000 > crlnumber
# mark the revoked cert in the index
openssl ca -batch -config /dev/stdin -gencrl -out empty.crl >/dev/null 2>&1 <<CACFG || true
[ca]
default_ca = CA_default
[CA_default]
database = index.txt
certificate = ca.crt
private_key = ca.key
crlnumber = crlnumber
default_md = sha256
default_crl_days = $DAYS
CACFG

# add entries to index.txt: V=valid, R=revoked. Format columns are
# status, expiry(YYMMDDHHMMSSZ), revoke-date(for R), serial, filename, subject
EXP="360101000000Z"
LEAF_SUBJ=$(openssl x509 -in leaf.crt -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
REV_SUBJ=$(openssl x509 -in revoked.crt -noout -subject -nameopt RFC2253 | sed 's/^subject=//')
printf "V\t%s\t\t1111\tunknown\t%s\n" "$EXP" "$LEAF_SUBJ" >> index.txt
printf "R\t%s\t250101000000Z\t2222\tunknown\t%s\n" "$EXP" "$REV_SUBJ" >> index.txt

cat > ca.cnf <<CACFG
[ca]
default_ca = CA_default
[CA_default]
database = index.txt
certificate = ca.crt
private_key = ca.key
crlnumber = crlnumber
default_md = sha256
default_crl_days = $DAYS
CACFG

openssl ca -config ca.cnf -gencrl -out ca.crl 2>/dev/null
openssl crl -in ca.crl -outform DER -out ca.crl.der 2>/dev/null

# --- OCSP responses (CA signs directly with -rsigner ca.crt) -----------
openssl ocsp -CAfile ca.crt -issuer ca.crt -cert leaf.crt \
  -reqout req_good.der -respout resp_good.der \
  -rsigner ca.crt -rkey ca.key -ndays $DAYS \
  -index index.txt 2>/dev/null || \
openssl ocsp -issuer ca.crt -cert leaf.crt -reqout req_good.der \
  -respout resp_good.der -rsigner ca.crt -rkey ca.key \
  -index index.txt -CA ca.crt 2>/dev/null

openssl ocsp -issuer ca.crt -cert revoked.crt -reqout req_rev.der \
  -respout resp_revoked.der -rsigner ca.crt -rkey ca.key \
  -index index.txt -CA ca.crt 2>/dev/null

# --- RFC 3161 timestamp token over a known imprint ----------------------
printf 'dart-pdf timestamp payload' > tsdata.bin
cat > tsa.cnf <<TSACFG
[tsa]
default_tsa = tsa_config
[tsa_config]
serial = tsserial
crypto_device = builtin
signer_cert = tsa.crt
certs = ca.crt
signer_key = tsa.key
signer_digest = sha256
default_policy = 1.2.3.4.1
other_policies = 1.2.3.4.2
digests = sha256, sha1
accuracy = secs:1
ordering = no
tsa_name = no
ess_cert_id_chain = yes
TSACFG
echo 1000 > tsserial
openssl ts -query -data tsdata.bin -sha256 -cert -out ts.tsq 2>/dev/null
openssl ts -reply -config tsa.cnf -section tsa_config -queryfile ts.tsq \
  -out ts.tsr 2>/dev/null
# the token (TimeStampToken) extracted from the reply
openssl ts -reply -in ts.tsr -token_out -out ts.token 2>/dev/null

b64() { openssl base64 -A -in "$1"; }

CA=$(openssl x509 -in ca.crt -outform DER | openssl base64 -A)
LEAF=$(openssl x509 -in leaf.crt -outform DER | openssl base64 -A)
LEAFKEY=$(openssl pkcs8 -topk8 -nocrypt -in leaf.key -outform DER | openssl base64 -A)
REVOKED=$(openssl x509 -in revoked.crt -outform DER | openssl base64 -A)
TSA=$(openssl x509 -in tsa.crt -outform DER | openssl base64 -A)
CRL=$(b64 ca.crl.der)
OCSP_GOOD=$(b64 resp_good.der)
OCSP_REVOKED=$(b64 resp_revoked.der)
OCSP_REQ=$(b64 req_good.der)
TS_TOKEN=$(b64 ts.token)
TSQ=$(b64 ts.tsq)

ROOT="${DART_PDF_ROOT:-$OLDPWD}"

# (1) pure-Dart KAT fixtures for pdf_cos (stdout)
cat <<DART
// GENERATED by tool/gen_pkix_fixtures.sh — do not edit by hand.
// OpenSSL-produced PKIX reference artifacts for the pure-Dart KATs:
// a CA, a leaf cert (serial 0x1111), a revoked leaf (serial 0x2222),
// a TSA cert (serial 0x3333), a CRL revoking 0x2222, OCSP responses for
// both leaves, and an RFC 3161 timestamp token over sha256("dart-pdf
// timestamp payload"). See doc/dev-log.md for the regeneration recipe.
library;

/// sha256 of the bytes the timestamp token stamps.
const tsPayload = 'dart-pdf timestamp payload';

const caCertB64 = '$CA';
const leafCertB64 = '$LEAF';
/// Test-only PKCS#8 private key matching [leafCertB64] — never use outside
/// this repository.
const leafKeyB64 = '$LEAFKEY';
const revokedCertB64 = '$REVOKED';
const tsaCertB64 = '$TSA';
const crlB64 = '$CRL';
const ocspGoodB64 = '$OCSP_GOOD';
const ocspRevokedB64 = '$OCSP_REVOKED';
const ocspReqGoodB64 = '$OCSP_REQ';
const tsTokenB64 = '$TS_TOKEN';
const tsqB64 = '$TSQ';
DART

# (2) shared LTV identity for pdf_document / dart_pdf_editor tests
LTV_OUT="$ROOT/packages/pdf_test_fixtures/lib/src/pkix_ltv.dart"
if [ -d "$(dirname "$LTV_OUT")" ]; then
cat > "$LTV_OUT" <<DART
/// GENERATED by pdf_cos/tool/gen_pkix_fixtures.sh — do not edit by hand.
///
/// An OpenSSL-issued CA, leaf signer (serial 0x1111, key included), CRL, and
/// OCSP "good" response, for exercising PAdES LTV end to end with real
/// revocation material. Test-only — never use outside this repository.
library;

import 'dart:convert';
import 'dart:typed_data';

const _caCert = '$CA';
const _leafCert = '$LEAF';
const _leafKey = '$LEAFKEY';
const _tsaCert = '$TSA';
const _tsaKey =
    '$(openssl pkcs8 -topk8 -nocrypt -in tsa.key -outform DER | openssl base64 -A)';
const _crl = '$CRL';
const _ocspGood = '$OCSP_GOOD';

/// CA certificate (DER) that issued [pkixLeafCert] and [pkixTsaCert].
Uint8List get pkixCaCert => base64.decode(_caCert);

/// Leaf signer certificate (DER), serial 0x1111, issued by [pkixCaCert].
Uint8List get pkixLeafCert => base64.decode(_leafCert);

/// PKCS#8 private key (DER) matching [pkixLeafCert].
Uint8List get pkixLeafKey => base64.decode(_leafKey);

/// TSA certificate (DER), serial 0x3333, timeStamping EKU, issued by the CA.
Uint8List get pkixTsaCert => base64.decode(_tsaCert);

/// PKCS#8 private key (DER) matching [pkixTsaCert].
Uint8List get pkixTsaKey => base64.decode(_tsaKey);

/// CRL (DER) signed by the CA, not listing the leaf serial.
Uint8List get pkixCrl => base64.decode(_crl);

/// OCSP response (DER) reporting [pkixLeafCert] as good.
Uint8List get pkixOcspGood => base64.decode(_ocspGood);
DART
echo "wrote $LTV_OUT" 1>&2
fi
