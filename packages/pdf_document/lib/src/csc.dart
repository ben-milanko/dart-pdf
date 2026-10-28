/// Remote signing through the Cloud Signature Consortium API (CSC v1.0.4 and
/// v2) - the protocol publicly-trusted signing services expose so a
/// certificate on the Adobe Approved Trust List or an EU trusted list can sign
/// a PDF without its private key ever leaving the provider's HSM.
///
/// The flow this file assembles:
///
///  1. [PdfCscClient.listCredentials] finds the user's signing credentials,
///     each carrying its certificate chain, key algorithms and how signing is
///     authorized ([PdfCscCredential.authMode]: implicit, a PIN/OTP, or an
///     OAuth2 `credential` grant),
///  2. [cscRemoteSigner] wraps one as a [PdfRemoteSigner], which
///     [PdfPadesSigning.saveSignedPadesRemote] hands the digest of the CAdES
///     signed attributes,
///  3. the signer asks the host's [PdfCscAuthorizer] for the authorization
///     (a PIN prompt, a browser sign-in), exchanges it for Signature
///     Activation Data bound to that digest (`credentials/authorize`), and
///  4. calls `signatures/signHash`, normalizing the value (an ECDSA signature
///     may come back as raw `r || s`) and checking it against the
///     certificate before the editor writes it.
///
/// True to this library's rule, nothing here touches the network: the host
/// supplies a [PdfCscTransport] that POSTs JSON to the service and, for the
/// OAuth2 modes, runs the browser flow (the URL and token-request helpers at
/// the end of this file build the pieces).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'pades.dart';

/// The CSC API generation a service speaks. The two differ in field names
/// (`hash` vs `hashes`, `PIN`/`OTP` vs `authData`) and in how a credential
/// describes its authorization; [PdfCscServiceInfo.version] reads it from
/// the service's `info` response.
enum PdfCscApiVersion { v1, v2 }

/// One CSC API call: [method] is the path under the service base URL (for
/// example `credentials/list`), [body] the UTF-8 JSON request, and
/// [accessToken] the bearer token to send, when the call needs one.
class PdfCscRequest {
  const PdfCscRequest(this.method, this.body, {this.accessToken});

  final String method;
  final Uint8List body;
  final String? accessToken;
}

/// The HTTP outcome of a [PdfCscRequest]: the status code and the raw body.
/// Error statuses are returned, not thrown, so the client can read the
/// service's `error`/`error_description`.
class PdfCscResponse {
  const PdfCscResponse(this.statusCode, this.body);

  final int statusCode;
  final Uint8List body;
}

/// POSTs [PdfCscRequest.body] to `<base URL>/<method>` with
/// `Content-Type: application/json` and, when [PdfCscRequest.accessToken] is
/// set, `Authorization: Bearer <token>`. Injected by the host so the library
/// stays transport-free, mirroring [PdfTimestampClient].
typedef PdfCscTransport = Future<PdfCscResponse> Function(
    PdfCscRequest request);

/// A CSC call failed: the service answered with an error status or an
/// `error` field. [error] is the OAuth-style code (`invalid_request`,
/// `invalid_grant`, ...) and [description] the service's explanation, which
/// is what to show a person (a wrong PIN arrives this way).
class PdfCscException implements Exception {
  const PdfCscException(this.method, this.error, this.description,
      {this.statusCode});

  final String method;
  final String error;
  final String? description;
  final int? statusCode;

  @override
  String toString() => 'PdfCscException($method): $error'
      '${description == null ? '' : ' - $description'}';
}

/// The service's self-description from the `info` method.
class PdfCscServiceInfo {
  const PdfCscServiceInfo({
    required this.specs,
    this.name,
    this.description,
    this.region,
    this.authTypes = const [],
    this.oauth2,
    this.oauth2Issuer,
    this.methods = const [],
  });

  factory PdfCscServiceInfo.fromJson(Map<String, Object?> json) =>
      PdfCscServiceInfo(
        specs: json['specs'] as String? ?? '1',
        name: json['name'] as String?,
        description: json['description'] as String?,
        region: json['region'] as String?,
        authTypes: _strings(json['authType']),
        oauth2: json['oauth2'] as String?,
        oauth2Issuer: json['oauth2Issuer'] as String?,
        methods: _strings(json['methods']),
      );

  /// The CSC specification version the service implements, e.g. `1.0.4.0`.
  final String specs;
  final String? name;
  final String? description;

  /// ISO 3166-1 country code of the service.
  final String? region;

  /// Supported service authorization types: `basic`, `digest`, `TLS`,
  /// `oauth2code`, `oauth2implicit`, `oauth2client`, `external`.
  final List<String> authTypes;

  /// Base URI of the OAuth2 authorization server (append
  /// `/oauth2/authorize` and `/oauth2/token`), when the service has one.
  final String? oauth2;

  /// The OAuth2 issuer, for v2 services that publish discovery metadata.
  final String? oauth2Issuer;

  /// The API methods the service implements.
  final List<String> methods;

  PdfCscApiVersion get version =>
      specs.startsWith('2') ? PdfCscApiVersion.v2 : PdfCscApiVersion.v1;
}

/// How a credential's signing is authorized.
enum PdfCscAuthMode {
  /// The service authorizes on its own (for example by the service access
  /// token alone); no prompt is needed.
  implicit,

  /// A PIN and/or OTP sent to `credentials/authorize`.
  explicit,

  /// An OAuth2 authorization-code flow with scope `credential`, whose access
  /// token authorizes the signature.
  oauth2code,
}

/// A secret an [PdfCscAuthMode.explicit] credential asks for: its `PIN` or
/// `OTP`. [label] and [description] are the service's own wording for the
/// prompt.
class PdfCscSecretInput {
  const PdfCscSecretInput({
    required this.id,
    this.required = true,
    this.numeric = false,
    this.label,
    this.description,
    this.onlineOtp = false,
  });

  /// `PIN` or `OTP`.
  final String id;

  /// False when the service marks the input optional.
  final bool required;

  /// The service asked for digits only (format `N`).
  final bool numeric;
  final String? label;
  final String? description;

  /// An OTP the service sends on request ([PdfCscClient.sendOtp]) rather
  /// than one an authenticator app generates.
  final bool onlineOtp;

  bool get isPin => id == 'PIN';
  bool get isOtp => id == 'OTP';
}

/// A signing credential: a key held by the service plus its certificate
/// chain and authorization requirements (the `credentials/info` response).
class PdfCscCredential {
  PdfCscCredential({
    required this.id,
    required this.certificates,
    this.description,
    this.keyEnabled = true,
    this.keyAlgorithms = const [],
    this.keyLength,
    this.certificateValid = true,
    this.authMode = PdfCscAuthMode.implicit,
    this.inputs = const [],
    this.scal = 1,
    this.multisign = 1,
  });

  /// Parses a `credentials/info` response (or a v2 `credentialInfos` entry)
  /// for credential [id]. Lenient: services disagree on whether booleans
  /// are strings, and v2 moves the authorization into an `auth` object.
  factory PdfCscCredential.fromJson(String id, Map<String, Object?> json) {
    final key = _map(json['key']);
    final cert = _map(json['cert']);
    final auth = _map(json['auth']);
    final certificates = [
      for (final c in _strings(cert['certificates'])) base64.decode(c),
    ];
    final inputs = <PdfCscSecretInput>[];
    if (auth.isNotEmpty) {
      // v2: auth { mode, objects: [{ type, id, format, label, ... }] }
      for (final object in _list(auth['objects'])) {
        final o = _map(object);
        final objectId = o['id'] as String?;
        if (objectId == null) continue;
        inputs.add(PdfCscSecretInput(
          id: objectId,
          numeric: o['format'] == 'N',
          label: o['label'] as String?,
          description: o['description'] as String?,
          onlineOtp: o['generator'] == 'online',
        ));
      }
    } else {
      // v1: PIN { presence, format, ... } and OTP { presence, type, ... }
      for (final (inputId, value) in [
        ('PIN', json['PIN']),
        ('OTP', json['OTP'])
      ]) {
        final o = _map(value);
        final presence = '${o['presence'] ?? 'false'}';
        if (o.isEmpty || presence == 'false') continue;
        inputs.add(PdfCscSecretInput(
          id: inputId,
          required: presence != 'optional',
          numeric: o['format'] == 'N',
          label: o['label'] as String?,
          description: o['description'] as String?,
          onlineOtp: o['type'] == 'online',
        ));
      }
    }
    final mode = (auth['mode'] ?? json['authMode']) as String?;
    return PdfCscCredential(
      id: id,
      certificates: certificates,
      description: json['description'] as String?,
      keyEnabled: (key['status'] ?? 'enabled') == 'enabled',
      keyAlgorithms: _strings(key['algo']),
      keyLength: _int(key['len']),
      certificateValid: (cert['status'] ?? 'valid') == 'valid',
      authMode: switch (mode) {
        'explicit' => PdfCscAuthMode.explicit,
        'oauth2code' => PdfCscAuthMode.oauth2code,
        _ => PdfCscAuthMode.implicit,
      },
      inputs: inputs,
      scal: _int(json['SCAL']) ?? 1,
      multisign: _int(json['multisign']) ?? 1,
    );
  }

  /// The credential identifier every call names.
  final String id;

  /// The DER certificate chain, signer first.
  final List<Uint8List> certificates;
  final String? description;
  final bool keyEnabled;

  /// The signing-algorithm OIDs the key accepts (the CSC `key/algo`).
  final List<String> keyAlgorithms;

  /// The key size in bits, when reported.
  final int? keyLength;

  /// False when the service reports the certificate expired, revoked or
  /// suspended.
  final bool certificateValid;
  final PdfCscAuthMode authMode;

  /// The secrets an [PdfCscAuthMode.explicit] credential asks for.
  final List<PdfCscSecretInput> inputs;

  /// The Sole Control Assurance Level: 2 means every authorization is bound
  /// to the exact hashes it will sign, so it is requested per document.
  final int scal;

  /// How many signatures one authorization may produce.
  final int multisign;

  /// The parsed signer certificate.
  late final X509Certificate certificate =
      X509Certificate.parse(certificates.first);

  /// Whether the credential can sign at all: an enabled key, a valid
  /// certificate, and a chain the service returned.
  bool get usable => keyEnabled && certificateValid && certificates.isNotEmpty;
}

/// Signature Activation Data from `credentials/authorize`.
class PdfCscSad {
  const PdfCscSad(this.value, {this.expiresIn});

  final String value;

  /// Lifetime in seconds, when the service says.
  final int? expiresIn;
}

/// A client for one CSC service, holding the service-scope [accessToken]
/// (from the OAuth2 `service` flow, `auth/login`, or whatever the host's
/// [transport] arranges).
class PdfCscClient {
  PdfCscClient({
    required this.transport,
    this.accessToken,
    this.version = PdfCscApiVersion.v1,
    this.lang,
  });

  final PdfCscTransport transport;

  /// The service-scope bearer token sent with every call but `info`.
  String? accessToken;

  /// The API generation to speak; set it from [PdfCscServiceInfo.version].
  PdfCscApiVersion version;

  /// An optional RFC 5646 language tag for service-side messages.
  final String? lang;

  bool get _v2 => version == PdfCscApiVersion.v2;

  /// The `info` method. Needs no token.
  Future<PdfCscServiceInfo> info() async => PdfCscServiceInfo.fromJson(
      await call('info', {if (lang != null) 'lang': lang}, anonymous: true));

  /// Lists the account's credentials with their chains and authorization
  /// requirements, following page tokens up to [maxPages] pages. On v2 the
  /// details come inline; on v1 each is fetched with `credentials/info`.
  Future<List<PdfCscCredential>> listCredentials(
      {String? userId, int maxPages = 10}) async {
    final out = <PdfCscCredential>[];
    String? pageToken;
    for (var page = 0; page < maxPages; page++) {
      final response = await call('credentials/list', {
        if (userId != null) 'userID': userId,
        if (pageToken != null) 'pageToken': pageToken,
        if (_v2) ...{
          'credentialInfo': true,
          'certificates': 'chain',
          'certInfo': true,
          'authInfo': true,
        },
      });
      final ids = _strings(response['credentialIDs']);
      final infos = _list(response['credentialInfos']);
      for (var i = 0; i < ids.length; i++) {
        final inline = i < infos.length ? _map(infos[i]) : null;
        out.add(inline != null && inline.isNotEmpty
            ? PdfCscCredential.fromJson(ids[i], inline)
            : await credentialInfo(ids[i]));
      }
      pageToken = response['nextPageToken'] as String?;
      if (pageToken == null) break;
    }
    return out;
  }

  /// The `credentials/info` method for one credential, with its full chain.
  Future<PdfCscCredential> credentialInfo(String credentialId) async =>
      PdfCscCredential.fromJson(
          credentialId,
          await call('credentials/info', {
            'credentialID': credentialId,
            'certificates': 'chain',
            'certInfo': true,
            'authInfo': true,
            if (lang != null) 'lang': lang,
          }));

  /// Asks the service to send an online OTP to the credential holder (v1
  /// `credentials/sendOTP`), ahead of prompting for it.
  Future<void> sendOtp(PdfCscCredential credential) async {
    await call('credentials/sendOTP', {'credentialID': credential.id});
  }

  /// Exchanges the credential's [pin]/[otp] for Signature Activation Data
  /// bound to [hashes] (SHA-256 digests) - `credentials/authorize`.
  Future<PdfCscSad> authorizeCredential(
    PdfCscCredential credential, {
    required List<Uint8List> hashes,
    String? pin,
    String? otp,
    String? description,
  }) async {
    final encoded = [for (final h in hashes) base64.encode(h)];
    final response = await call('credentials/authorize', {
      'credentialID': credential.id,
      'numSignatures': hashes.length,
      if (_v2) ...{
        'hashes': encoded,
        'hashAlgorithmOID': DigestOid.sha256,
        if (pin != null || otp != null)
          'authData': [
            if (pin != null) {'id': 'PIN', 'value': pin},
            if (otp != null) {'id': 'OTP', 'value': otp},
          ],
      } else ...{
        'hash': encoded,
        if (pin != null) 'PIN': pin,
        if (otp != null) 'OTP': otp,
      },
      if (description != null) 'description': description,
    });
    final sad = response['SAD'];
    if (sad is! String) {
      throw const PdfCscException(
          'credentials/authorize', 'invalid_response', 'no SAD returned');
    }
    return PdfCscSad(sad, expiresIn: _int(response['expiresIn']));
  }

  /// `signatures/signHash`: signs [hashes] (SHA-256 digests) with
  /// [signAlgo] (plus DER [signAlgoParams] for RSASSA-PSS). Authorize with
  /// [sad], or with a credential-scope [credentialToken] from the OAuth2
  /// flow in place of the service token. Returns one raw signature value per
  /// hash, as the service encoded it.
  Future<List<Uint8List>> signHash(
    PdfCscCredential credential, {
    required List<Uint8List> hashes,
    required String signAlgo,
    Uint8List? signAlgoParams,
    String? sad,
    String? credentialToken,
  }) async {
    final encoded = [for (final h in hashes) base64.encode(h)];
    final response = await call(
      'signatures/signHash',
      {
        'credentialID': credential.id,
        if (sad != null) 'SAD': sad,
        if (_v2) ...{
          'hashes': encoded,
          'hashAlgorithmOID': DigestOid.sha256,
        } else ...{
          'hash': encoded,
          'hashAlgo': DigestOid.sha256,
        },
        'signAlgo': signAlgo,
        if (signAlgoParams != null)
          'signAlgoParams': base64.encode(signAlgoParams),
      },
      token: credentialToken,
    );
    final signatures = _strings(response['signatures']);
    if (signatures.length != hashes.length) {
      throw PdfCscException('signatures/signHash', 'invalid_response',
          'expected ${hashes.length} signatures, got ${signatures.length}');
    }
    return [for (final s in signatures) base64.decode(s)];
  }

  /// Sends one CSC call and returns the decoded JSON object, throwing a
  /// [PdfCscException] for an error status or an `error` field. The bearer
  /// is [token], else [accessToken]; [anonymous] sends none (`info`).
  Future<Map<String, Object?>> call(String method, Map<String, Object?> body,
      {String? token, bool anonymous = false}) async {
    final bearer = anonymous ? null : token ?? accessToken;
    final response = await transport(PdfCscRequest(
      method,
      Uint8List.fromList(utf8.encode(json.encode(body))),
      accessToken: bearer,
    ));
    Map<String, Object?> decoded = const {};
    if (response.body.isNotEmpty) {
      try {
        decoded = _map(json.decode(utf8.decode(response.body)));
      } on FormatException {
        if (response.statusCode < 400) {
          throw PdfCscException(method, 'invalid_response', 'not JSON',
              statusCode: response.statusCode);
        }
      }
    }
    final error = decoded['error'];
    if (response.statusCode >= 400 || error != null) {
      throw PdfCscException(
        method,
        error is String ? error : 'http_${response.statusCode}',
        decoded['error_description'] as String?,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

/// The authorization a [PdfCscAuthorizer] produces for one signing request.
sealed class PdfCscAuthorization {
  const PdfCscAuthorization();

  /// The credential's PIN and/or OTP; the signer exchanges them for SAD
  /// bound to the hashes. With neither, this is how an
  /// [PdfCscAuthMode.implicit] credential is authorized.
  const factory PdfCscAuthorization.secrets({String? pin, String? otp}) =
      PdfCscSecretsAuthorization;

  /// SAD the host already obtained.
  const factory PdfCscAuthorization.sad(String sad) = PdfCscSadAuthorization;

  /// A credential-scope access token from the OAuth2 `credential` flow
  /// ([cscOAuthAuthorizationUrl] with the request's hashes); it replaces the
  /// SAD and the service token on `signatures/signHash`.
  const factory PdfCscAuthorization.credentialToken(String accessToken) =
      PdfCscCredentialTokenAuthorization;
}

/// See [PdfCscAuthorization.secrets].
class PdfCscSecretsAuthorization extends PdfCscAuthorization {
  const PdfCscSecretsAuthorization({this.pin, this.otp});

  final String? pin;
  final String? otp;
}

/// See [PdfCscAuthorization.sad].
class PdfCscSadAuthorization extends PdfCscAuthorization {
  const PdfCscSadAuthorization(this.sad);

  final String sad;
}

/// See [PdfCscAuthorization.credentialToken].
class PdfCscCredentialTokenAuthorization extends PdfCscAuthorization {
  const PdfCscCredentialTokenAuthorization(this.accessToken);

  final String accessToken;
}

/// What a [PdfCscAuthorizer] is asked to authorize: one signature by
/// [credential] over [hashes] (SHA-256). For a SCAL2 credential the
/// authorization must name these exact hashes.
class PdfCscAuthorizationRequest {
  const PdfCscAuthorizationRequest({
    required this.client,
    required this.credential,
    required this.hashes,
  });

  /// The client, for [PdfCscClient.sendOtp] before prompting for an online
  /// OTP.
  final PdfCscClient client;
  final PdfCscCredential credential;
  final List<Uint8List> hashes;

  /// The digest algorithm of [hashes].
  String get hashAlgorithmOid => DigestOid.sha256;
}

/// Obtains the authorization for a signing request: prompt for the PIN/OTP
/// the credential's [PdfCscCredential.inputs] list, or run the OAuth2
/// `credential` flow. Throwing (for example on cancel) aborts the signature
/// before anything is written.
typedef PdfCscAuthorizer = Future<PdfCscAuthorization> Function(
    PdfCscAuthorizationRequest request);

/// How a credential's key is asked to sign: the CSC `signAlgo` OID, its DER
/// `signAlgoParams` (RSASSA-PSS only), and the AlgorithmIdentifier the CMS
/// SignerInfo names for the result.
class PdfCscSigningAlgorithm {
  const PdfCscSigningAlgorithm({
    required this.signAlgo,
    required this.cmsAlgorithm,
    this.signAlgoParams,
  });

  final String signAlgo;
  final Uint8List? signAlgoParams;
  final Uint8List cmsAlgorithm;
}

abstract final class _CscOid {
  static const rsaEncryption = '1.2.840.113549.1.1.1';
  static const sha256WithRsa = '1.2.840.113549.1.1.11';
  static const rsassaPss = '1.2.840.113549.1.1.10';
  static const ecPublicKey = '1.2.840.10045.2.1';
  static const ecdsaWithSha256 = '1.2.840.10045.4.3.2';
}

/// Picks how [credential] signs SHA-256 digests from the algorithms its key
/// accepts, preferring PKCS#1 v1.5 (the most widely verified) over
/// RSASSA-PSS for RSA keys. A credential that lists no algorithms gets the
/// default for its key type. Throws an [UnsupportedError] when the key
/// offers nothing this library can put in a CMS signature.
PdfCscSigningAlgorithm cscSigningAlgorithmFor(PdfCscCredential credential) {
  final offered = credential.keyAlgorithms;
  bool offers(String oid) => offered.isEmpty || offered.contains(oid);
  switch (credential.certificate.publicKey) {
    case RsaPublicKey():
      for (final oid in [_CscOid.sha256WithRsa, _CscOid.rsaEncryption]) {
        if (offered.contains(oid)) {
          return PdfCscSigningAlgorithm(
              signAlgo: oid, cmsAlgorithm: rsaPkcs1SignatureAlgorithm());
        }
      }
      if (offered.isEmpty) {
        return PdfCscSigningAlgorithm(
            signAlgo: _CscOid.rsaEncryption,
            cmsAlgorithm: rsaPkcs1SignatureAlgorithm());
      }
      if (offered.contains(_CscOid.rsassaPss)) {
        final algorithm = rsaPssSignatureAlgorithm(crypto.sha256);
        return PdfCscSigningAlgorithm(
          signAlgo: _CscOid.rsassaPss,
          // the RSASSA-PSS-params SEQUENCE inside the AlgorithmIdentifier
          signAlgoParams: DerObject.parse(algorithm).children[1].encoded,
          cmsAlgorithm: algorithm,
        );
      }
    case EcPublicKey():
      final cms = ecdsaSignatureAlgorithm(crypto.sha256);
      if (offers(_CscOid.ecdsaWithSha256)) {
        return PdfCscSigningAlgorithm(
            signAlgo: _CscOid.ecdsaWithSha256, cmsAlgorithm: cms);
      }
      if (offered.contains(_CscOid.ecPublicKey)) {
        return PdfCscSigningAlgorithm(
            signAlgo: _CscOid.ecPublicKey, cmsAlgorithm: cms);
      }
  }
  throw UnsupportedError('credential ${credential.id} offers no supported '
      'signing algorithm (${offered.join(', ')})');
}

/// Wraps [credential] as a [PdfRemoteSigner] for
/// [PdfPadesSigning.saveSignedPadesRemote].
///
/// Each signature asks [authorizer] for the authorization, turns PIN/OTP
/// secrets into SAD bound to the digest, and calls `signatures/signHash`.
/// [authorizer] may be omitted only for an [PdfCscAuthMode.implicit]
/// credential. [description] is shown to the signer by services that display
/// one during authorization.
PdfRemoteSigner cscRemoteSigner({
  required PdfCscClient client,
  required PdfCscCredential credential,
  PdfCscAuthorizer? authorizer,
  String? description,
}) {
  if (!credential.usable) {
    throw ArgumentError('credential ${credential.id} cannot sign: its key is '
        'disabled, its certificate is not valid, or it has no chain');
  }
  if (authorizer == null && credential.authMode != PdfCscAuthMode.implicit) {
    throw ArgumentError('credential ${credential.id} needs an authorizer '
        '(${credential.authMode.name} authorization)');
  }
  return _CscRemoteSigner(client, credential,
      cscSigningAlgorithmFor(credential), authorizer, description);
}

class _CscRemoteSigner implements PdfRemoteSigner {
  _CscRemoteSigner(this.client, this.credential, this.algorithm,
      this.authorizer, this.description);

  final PdfCscClient client;
  final PdfCscCredential credential;
  final PdfCscSigningAlgorithm algorithm;
  final PdfCscAuthorizer? authorizer;
  final String? description;

  @override
  List<Uint8List> get certificates => credential.certificates;

  @override
  Uint8List get signatureAlgorithm => algorithm.cmsAlgorithm;

  @override
  Future<Uint8List> signDigest(Uint8List digest) async {
    final hashes = [digest];
    final authorization = authorizer == null
        ? const PdfCscAuthorization.secrets()
        : await authorizer!(PdfCscAuthorizationRequest(
            client: client, credential: credential, hashes: hashes));
    String? sad;
    String? credentialToken;
    switch (authorization) {
      case PdfCscSecretsAuthorization(:final pin, :final otp):
        sad = (await client.authorizeCredential(credential,
                hashes: hashes, pin: pin, otp: otp, description: description))
            .value;
      case PdfCscSadAuthorization(sad: final value):
        sad = value;
      case PdfCscCredentialTokenAuthorization(:final accessToken):
        credentialToken = accessToken;
    }
    final signature = (await client.signHash(
      credential,
      hashes: hashes,
      signAlgo: algorithm.signAlgo,
      signAlgoParams: algorithm.signAlgoParams,
      sad: sad,
      credentialToken: credentialToken,
    ))
        .single;
    return _normalize(signature, digest);
  }

  /// ECDSA values arrive as DER from most services but as raw `r || s` from
  /// some; keep whichever encoding verifies. Anything that verifies neither
  /// way is passed through for the editor's check to reject.
  Uint8List _normalize(Uint8List signature, Uint8List digest) {
    final key = credential.certificate.publicKey;
    if (key is! EcPublicKey) return signature;
    if (ecdsaVerify(key, digest, signature)) return signature;
    if (signature.length.isEven) {
      final der = ecdsaRawSignatureToDer(signature);
      if (ecdsaVerify(key, digest, der)) return der;
    }
    return signature;
  }
}

/// The OAuth2 authorization URL for a CSC service whose
/// [PdfCscServiceInfo.oauth2] base is [oauth2Base]: scope `service` to list
/// credentials, or - with [credential] and [hashes] - scope `credential`,
/// authorizing exactly those SHA-256 hashes (the flow behind
/// [PdfCscAuthorization.credentialToken]). Pass PKCE's [codeChallenge] (S256)
/// and a [state] the redirect handler checks.
Uri cscOAuthAuthorizationUrl({
  required String oauth2Base,
  required String clientId,
  required Uri redirectUri,
  PdfCscCredential? credential,
  List<Uint8List> hashes = const [],
  PdfCscApiVersion version = PdfCscApiVersion.v1,
  String? state,
  String? codeChallenge,
  String? description,
  String? lang,
}) {
  final hashList = [
    for (final h in hashes) base64Url.encode(h).replaceAll('=', ''),
  ].join(',');
  final base = oauth2Base.endsWith('/')
      ? oauth2Base.substring(0, oauth2Base.length - 1)
      : oauth2Base;
  return Uri.parse('$base/oauth2/authorize').replace(queryParameters: {
    'response_type': 'code',
    'client_id': clientId,
    'redirect_uri': redirectUri.toString(),
    'scope': credential == null ? 'service' : 'credential',
    if (credential != null) ...{
      'credentialID': credential.id,
      'numSignatures': '${hashes.isEmpty ? 1 : hashes.length}',
      if (hashes.isNotEmpty) ...{
        if (version == PdfCscApiVersion.v2) ...{
          'hashes': hashList,
          'hashAlgorithmOID': DigestOid.sha256,
        } else
          'hash': hashList,
      },
    },
    if (state != null) 'state': state,
    if (codeChallenge != null) ...{
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    },
    if (description != null) 'description': description,
    if (lang != null) 'lang': lang,
  });
}

/// The `application/x-www-form-urlencoded` body of the token request that
/// redeems an authorization [code] at `<oauth2 base>/oauth2/token`.
String cscOAuthTokenRequestBody({
  required String code,
  required String clientId,
  required Uri redirectUri,
  String? codeVerifier,
  String? clientSecret,
}) =>
    Uri(queryParameters: {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      if (codeVerifier != null) 'code_verifier': codeVerifier,
      if (clientSecret != null) 'client_secret': clientSecret,
    }).query;

/// Tokens from an OAuth2 token response.
class PdfCscOAuthTokens {
  const PdfCscOAuthTokens(this.accessToken,
      {this.refreshToken, this.expiresIn});

  /// Parses the token endpoint's JSON [responseBody], throwing a
  /// [PdfCscException] for an OAuth error response.
  factory PdfCscOAuthTokens.fromResponse(String responseBody) {
    final json = _map(jsonDecode(responseBody));
    final token = json['access_token'];
    if (token is! String) {
      throw PdfCscException(
          'oauth2/token',
          '${json['error'] ?? 'invalid_response'}',
          json['error_description'] as String?);
    }
    return PdfCscOAuthTokens(token,
        refreshToken: json['refresh_token'] as String?,
        expiresIn: _int(json['expires_in']));
  }

  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) => [
      for (final v in _list(value))
        if (v is String) v,
    ];

int? _int(Object? value) => switch (value) {
      final int v => v,
      final String v => int.tryParse(v),
      _ => null,
    };
