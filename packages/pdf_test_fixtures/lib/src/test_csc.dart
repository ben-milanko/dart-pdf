/// A self-contained, in-process Cloud Signature Consortium (CSC) signing
/// service for tests. It answers the CSC v1.0.4 / v2 JSON methods a remote
/// signing client calls (`info`, `credentials/list`, `credentials/info`,
/// `credentials/authorize`, `credentials/sendOTP`, `signatures/signHash`)
/// with real signatures from throwaway keys. Test-only - never use outside
/// this repo.
///
/// It is strict where real services are: a bearer token is required, a wrong
/// PIN or OTP is refused, a SCAL2 credential's SAD only signs the hashes it
/// was authorized for (and only as many times as it was authorized), the
/// signing algorithm must be one the key lists, and an OAuth2 `credential`
/// token stands in for the SAD. [TestCscCredential.rawEcdsa] returns ECDSA
/// values as raw `r || s`, as some services do.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'signer_identity.dart';

/// OIDs a CSC credential lists in `key/algo` and a client sends as
/// `signAlgo`.
abstract final class TestCscOid {
  static const rsaEncryption = '1.2.840.113549.1.1.1';
  static const sha256WithRsa = '1.2.840.113549.1.1.11';
  static const rsassaPss = '1.2.840.113549.1.1.10';
  static const ecPublicKey = '1.2.840.10045.2.1';
  static const ecdsaWithSha256 = '1.2.840.10045.4.3.2';
}

/// One credential the test service holds.
class TestCscCredential {
  TestCscCredential({
    required this.id,
    required this.key,
    required this.chain,
    this.authMode = 'implicit',
    this.pin,
    this.otp,
    this.onlineOtp = false,
    this.scal = 1,
    this.keyAlgorithms = const [],
    this.rawEcdsa = false,
    this.multisign = 1,
    this.description,
  }) : assert(key is RsaPrivateKey || key is EcPrivateKey);

  final String id;

  /// An [RsaPrivateKey] or [EcPrivateKey].
  final Object key;

  /// The DER chain, signer first.
  final List<Uint8List> chain;

  /// `implicit`, `explicit` or `oauth2code`.
  final String authMode;
  final String? pin;
  final String? otp;

  /// The OTP is "sent" by `credentials/sendOTP` and is only accepted after.
  final bool onlineOtp;
  final int scal;
  final List<String> keyAlgorithms;
  final bool rawEcdsa;
  final int multisign;
  final String? description;
}

class _Sad {
  _Sad(this.credentialId, this.hashes, this.remaining);

  final String credentialId;

  /// The hashes a SCAL2 SAD is bound to; null for SCAL1.
  final Set<String>? hashes;
  int remaining;
}

/// The in-process CSC service. Route a client's transport to [handle].
class TestCscService {
  TestCscService({
    required List<TestCscCredential> credentials,
    this.specs = '1.0.4.0',
    this.serviceToken = 'test-service-token',
    this.pageSize = 0,
  }) : credentials = {for (final c in credentials) c.id: c};

  /// The standard set of credentials the CSC tests use:
  ///
  ///  - `rsa-pin`: explicit PIN `1234`, SCAL2, RSA PKCS#1 v1.5, chaining to
  ///    the test CA ([testChainSignerCertPem] + [testCaCertPem]),
  ///  - `rsa-pss`: implicit, RSASSA-PSS only, the test signer,
  ///  - `ec-raw`: implicit, a P-256 key under a generated EC CA, answering
  ///    with raw `r || s` ECDSA values,
  ///  - `oauth`: OAuth2 `credential` authorization, sha256WithRSAEncryption,
  ///  - `otp`: explicit PIN `1234` plus an online OTP `654321`.
  factory TestCscService.standard(
      {String specs = '1.0.4.0', int pageSize = 0}) {
    final random = Random(42);
    final caKey = EcPrivateKey.generate(EcCurve.p256, random: random);
    final notBefore = DateTime.utc(2026);
    final notAfter = DateTime.utc(2036);
    final caCert = buildCaCertificate(
      key: caKey,
      commonName: 'Test CSC EC CA',
      notBefore: notBefore,
      notAfter: notAfter,
      random: random,
    );
    final ecKey = EcPrivateKey.generate(EcCurve.p256, random: random);
    final ecCert = issueCertificate(
      issuerKey: caKey,
      issuerCertificate: caCert,
      subjectPublicKey: ecKey.publicKey,
      commonName: 'Test CSC EC Signer',
      notBefore: notBefore,
      notAfter: notAfter,
      random: random,
    );
    final rsaChain = [
      pemBytes(testChainSignerCertPem),
      pemBytes(testCaCertPem),
    ];
    return TestCscService(
      specs: specs,
      pageSize: pageSize,
      credentials: [
        TestCscCredential(
          id: 'rsa-pin',
          key: RsaPrivateKey.fromPem(testChainSignerKeyPem),
          chain: rsaChain,
          authMode: 'explicit',
          pin: '1234',
          scal: 2,
          keyAlgorithms: const [TestCscOid.rsaEncryption],
          description: 'Qualified signing certificate',
        ),
        TestCscCredential(
          id: 'rsa-pss',
          key: RsaPrivateKey.fromPem(testSignerKeyPem),
          chain: [pemBytes(testSignerCertPem)],
          keyAlgorithms: const [TestCscOid.rsassaPss],
        ),
        TestCscCredential(
          id: 'ec-raw',
          key: ecKey,
          chain: [ecCert, caCert],
          keyAlgorithms: const [TestCscOid.ecdsaWithSha256],
          rawEcdsa: true,
        ),
        TestCscCredential(
          id: 'oauth',
          key: RsaPrivateKey.fromPem(testSignerKeyPem),
          chain: [pemBytes(testSignerCertPem)],
          authMode: 'oauth2code',
          scal: 2,
          keyAlgorithms: const [TestCscOid.sha256WithRsa],
        ),
        TestCscCredential(
          id: 'otp',
          key: RsaPrivateKey.fromPem(testChainSignerKeyPem),
          chain: rsaChain,
          authMode: 'explicit',
          pin: '1234',
          otp: '654321',
          onlineOtp: true,
          keyAlgorithms: const [TestCscOid.rsaEncryption],
        ),
      ],
    );
  }

  final Map<String, TestCscCredential> credentials;

  /// The CSC specification version `info` reports; `2.x` switches every
  /// method to the v2 field names.
  final String specs;

  /// The bearer token every method but `info` requires.
  final String serviceToken;

  /// Page size for `credentials/list`; 0 returns everything at once.
  final int pageSize;

  /// The methods called, in order.
  final List<String> calls = [];

  final Map<String, _Sad> _sads = {};
  final Map<String, _Sad> _credentialTokens = {};
  final Set<String> _otpSent = {};
  var _counter = 0;

  bool get _v2 => specs.startsWith('2');

  /// Emulates the OAuth2 `credential` grant: a token that authorizes
  /// [numSignatures] signatures by [credentialId] over [hashes] (SHA-256,
  /// raw bytes).
  String issueCredentialToken(String credentialId, List<Uint8List> hashes,
      {int numSignatures = 1}) {
    final token = 'credential-token-${++_counter}';
    _credentialTokens[token] = _Sad(credentialId,
        {for (final h in hashes) base64.encode(h)}, numSignatures);
    return token;
  }

  /// Answers one CSC call: [method] is the path (e.g. `credentials/list`),
  /// [body] the UTF-8 JSON request, [accessToken] the bearer token. Returns
  /// the HTTP status and the response body.
  ({int status, Uint8List body}) handle(
      String method, Uint8List body, String? accessToken) {
    calls.add(method);
    final request = body.isEmpty
        ? const <String, Object?>{}
        : (json.decode(utf8.decode(body)) as Map).cast<String, Object?>();
    try {
      if (method == 'info') return _ok(_info());
      if (method == 'signatures/signHash') {
        return _ok(_signHash(request, accessToken));
      }
      if (accessToken != serviceToken) {
        throw const _CscError(401, 'invalid_token', 'missing or bad token');
      }
      return switch (method) {
        'credentials/list' => _ok(_list(request)),
        'credentials/info' => _ok(_credentialInfo(_credential(request),
            request['certificates'] as String? ?? 'single')),
        'credentials/authorize' => _ok(_authorize(request)),
        'credentials/sendOTP' => _sendOtp(request),
        _ => throw _CscError(404, 'invalid_request', 'unknown method $method'),
      };
    } on _CscError catch (e) {
      return (
        status: e.status,
        body: _json({'error': e.error, 'error_description': e.description}),
      );
    }
  }

  Map<String, Object?> _info() => {
        'specs': specs,
        'name': 'Test CSC service',
        'region': 'AU',
        'lang': 'en-US',
        'description': 'In-process CSC service for dart-pdf tests',
        'authType': ['oauth2code'],
        'oauth2': 'https://csc.test',
        'methods': [
          'credentials/list',
          'credentials/info',
          'credentials/authorize',
          'credentials/sendOTP',
          'signatures/signHash',
        ],
      };

  Map<String, Object?> _list(Map<String, Object?> request) {
    final ids = credentials.keys.toList();
    final start = int.tryParse(request['pageToken'] as String? ?? '') ?? 0;
    final end = pageSize == 0 ? ids.length : min(ids.length, start + pageSize);
    final page = ids.sublist(start, end);
    return {
      'credentialIDs': page,
      if (end < ids.length) 'nextPageToken': '$end',
      if (_v2 && request['credentialInfo'] == true)
        'credentialInfos': [
          for (final id in page)
            _credentialInfo(credentials[id]!,
                request['certificates'] as String? ?? 'single'),
        ],
    };
  }

  Map<String, Object?> _credentialInfo(
      TestCscCredential credential, String certificates) {
    final chain = switch (certificates) {
      'chain' => credential.chain,
      'single' => [credential.chain.first],
      _ => const <Uint8List>[],
    };
    final key = credential.key;
    final info = <String, Object?>{
      if (_v2) 'credentialID': credential.id,
      'description': credential.description,
      'key': {
        'status': 'enabled',
        'algo': credential.keyAlgorithms,
        'len': key is RsaPrivateKey ? key.modulus.bitLength : 256,
        if (key is EcPrivateKey) 'curve': key.curve.oid,
      },
      'cert': {
        'status': 'valid',
        'certificates': [for (final c in chain) base64.encode(c)],
      },
      'SCAL': '${credential.scal}',
      'multisign': credential.multisign,
    };
    if (_v2) {
      info['auth'] = {
        'mode': credential.authMode,
        'objects': [
          if (credential.pin != null)
            {'type': 'Password', 'id': 'PIN', 'format': 'N', 'label': 'PIN'},
          if (credential.otp != null)
            {
              'type': 'Password',
              'id': 'OTP',
              'format': 'N',
              'label': 'One-time password',
              'generator': credential.onlineOtp ? 'online' : 'totp',
            },
        ],
      };
    } else {
      info['authMode'] = credential.authMode;
      if (credential.pin != null) {
        info['PIN'] = {'presence': 'true', 'format': 'N', 'label': 'PIN'};
      }
      if (credential.otp != null) {
        info['OTP'] = {
          'presence': 'true',
          'type': credential.onlineOtp ? 'online' : 'offline',
          'format': 'N',
          'label': 'One-time password',
        };
      }
    }
    return info;
  }

  Map<String, Object?> _authorize(Map<String, Object?> request) {
    final credential = _credential(request);
    if (credential.authMode == 'oauth2code') {
      throw const _CscError(400, 'invalid_request',
          'this credential is authorized through OAuth2');
    }
    String? pin;
    String? otp;
    if (_v2) {
      for (final item in (request['authData'] as List? ?? const [])) {
        final entry = (item as Map).cast<String, Object?>();
        if (entry['id'] == 'PIN') pin = entry['value'] as String?;
        if (entry['id'] == 'OTP') otp = entry['value'] as String?;
      }
    } else {
      pin = request['PIN'] as String?;
      otp = request['OTP'] as String?;
    }
    if (credential.pin != null && pin != credential.pin) {
      throw const _CscError(400, 'invalid_request', 'Invalid PIN');
    }
    if (credential.otp != null) {
      if (credential.onlineOtp && !_otpSent.remove(credential.id)) {
        throw const _CscError(400, 'invalid_request', 'No OTP was sent');
      }
      if (otp != credential.otp) {
        throw const _CscError(400, 'invalid_request', 'Invalid OTP');
      }
    }
    final numSignatures = request['numSignatures'] as int? ?? 1;
    if (numSignatures > credential.multisign) {
      throw const _CscError(
          400, 'invalid_request', 'numSignatures exceeds multisign');
    }
    final hashes = _hashesOf(request);
    if (credential.scal == 2 && hashes.length != numSignatures) {
      throw const _CscError(
          400, 'invalid_request', 'SCAL2 needs one hash per signature');
    }
    final sad = 'sad-${++_counter}';
    _sads[sad] = _Sad(credential.id,
        credential.scal == 2 ? hashes.toSet() : null, numSignatures);
    return {'SAD': sad, 'expiresIn': 300};
  }

  ({int status, Uint8List body}) _sendOtp(Map<String, Object?> request) {
    final credential = _credential(request);
    if (!credential.onlineOtp) {
      throw const _CscError(400, 'invalid_request', 'no online OTP');
    }
    _otpSent.add(credential.id);
    return (status: 204, body: Uint8List(0));
  }

  Map<String, Object?> _signHash(
      Map<String, Object?> request, String? accessToken) {
    final credential = _credential(request);
    final hashes = _hashesOf(request);
    final sadValue = request['SAD'] as String?;
    final _Sad grant;
    if (sadValue != null) {
      if (accessToken != serviceToken) {
        throw const _CscError(401, 'invalid_token', 'missing or bad token');
      }
      grant = _sads[sadValue] ??
          (throw const _CscError(400, 'invalid_request', 'Invalid SAD'));
    } else {
      grant = _credentialTokens[accessToken] ??
          (throw const _CscError(401, 'invalid_token', 'no SAD or token'));
    }
    if (grant.credentialId != credential.id) {
      throw const _CscError(
          400, 'invalid_request', 'SAD issued for another credential');
    }
    if (grant.hashes != null && !hashes.every(grant.hashes!.contains)) {
      throw const _CscError(
          400, 'invalid_request', 'hash not covered by the authorization');
    }
    if (hashes.length > grant.remaining) {
      throw const _CscError(400, 'invalid_request', 'SAD exhausted');
    }
    grant.remaining -= hashes.length;

    final signAlgo = request['signAlgo'] as String?;
    if (signAlgo == null ||
        (credential.keyAlgorithms.isNotEmpty &&
            !credential.keyAlgorithms.contains(signAlgo))) {
      throw _CscError(400, 'invalid_request', 'unsupported signAlgo $signAlgo');
    }
    final hashAlgo = request[_v2 ? 'hashAlgorithmOID' : 'hashAlgo'];
    if (hashAlgo != null && hashAlgo != DigestOid.sha256) {
      throw const _CscError(400, 'invalid_request', 'unsupported hashAlgo');
    }
    final params = request['signAlgoParams'] as String?;
    return {
      'signatures': [
        for (final h in hashes)
          base64.encode(_sign(credential, signAlgo, params, base64.decode(h))),
      ],
    };
  }

  Uint8List _sign(TestCscCredential credential, String signAlgo, String? params,
      Uint8List digest) {
    switch (credential.key) {
      case final RsaPrivateKey key:
        if (signAlgo == TestCscOid.rsassaPss) {
          if (params == null) {
            throw const _CscError(
                400, 'invalid_request', 'RSASSA-PSS needs signAlgoParams');
          }
          return rsaSignPss(key, crypto.sha256, digest,
              salt: List.filled(_pssSaltLength(base64.decode(params)), 7));
        }
        return rsaSign(key, DigestOid.sha256, digest);
      case final EcPrivateKey key:
        if (!credential.rawEcdsa) return ecdsaSign(key, digest);
        final (r, s) = ecdsaSignRs(key, digest);
        final size = (key.curve.p.bitLength + 7) >> 3;
        return Uint8List.fromList([..._fixed(r, size), ..._fixed(s, size)]);
    }
    throw StateError('unsupported key');
  }

  TestCscCredential _credential(Map<String, Object?> request) =>
      credentials[request['credentialID']] ??
      (throw const _CscError(400, 'invalid_request', 'Invalid credentialID'));

  List<String> _hashesOf(Map<String, Object?> request) => [
        for (final h in (request[_v2 ? 'hashes' : 'hash'] as List? ?? const []))
          h as String,
      ];
}

class _CscError implements Exception {
  const _CscError(this.status, this.error, this.description);

  final int status;
  final String error;
  final String description;
}

({int status, Uint8List body}) _ok(Map<String, Object?> body) =>
    (status: 200, body: _json(body));

Uint8List _json(Map<String, Object?> body) =>
    Uint8List.fromList(utf8.encode(json.encode(body)));

/// The saltLength [2] of an RSASSA-PSS-params SEQUENCE (default 20).
int _pssSaltLength(Uint8List params) {
  for (final field in DerObject.parse(params).children) {
    if (field.tag == DerTag.context(2)) {
      return field.children.first.asInteger.toInt();
    }
  }
  return 20;
}

List<int> _fixed(BigInt value, int size) {
  final out = List<int>.filled(size, 0);
  var v = value;
  for (var i = size - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xFF)).toInt();
    v >>= 8;
  }
  return out;
}
