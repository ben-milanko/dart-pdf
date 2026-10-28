// CSC remote signing: the protocol client against the in-process CSC service
// (pdf_test_fixtures' TestCscService), and PAdES signatures produced through
// it with the key never leaving the "service".
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final signedAt = DateTime.utc(2026, 6, 15, 10, 0, 0);

PdfTimestampClient testTsa() =>
    (request) async => buildTestTimeStampToken(request, genTime: signedAt);

PdfEditor freshEditor() => PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));

/// A [PdfCscTransport] routed into [service], as the host's HTTP POST would
/// be routed to a real one.
PdfCscTransport transportTo(TestCscService service) => (request) async {
      final response =
          service.handle(request.method, request.body, request.accessToken);
      return PdfCscResponse(response.status, response.body);
    };

PdfCscClient clientFor(TestCscService service,
        {PdfCscApiVersion version = PdfCscApiVersion.v1}) =>
    PdfCscClient(
      transport: transportTo(service),
      accessToken: service.serviceToken,
      version: version,
    );

Future<PdfCscCredential> credential(PdfCscClient client, String id) async =>
    (await client.listCredentials()).singleWhere((c) => c.id == id);

void main() {
  for (final (specs, version) in [
    ('1.0.4.0', PdfCscApiVersion.v1),
    ('2.0.0.2', PdfCscApiVersion.v2),
  ]) {
    group('CSC ${version.name}', () {
      late TestCscService service;
      late PdfCscClient client;

      setUp(() {
        service = TestCscService.standard(specs: specs, pageSize: 2);
        client = clientFor(service, version: version);
      });

      test('info reports the API version', () async {
        final info = await client.info();
        expect(info.version, version);
        expect(info.oauth2, 'https://csc.test');
      });

      test('lists every credential across pages with chains and auth',
          () async {
        final credentials = await client.listCredentials();
        expect(credentials.map((c) => c.id),
            ['rsa-pin', 'rsa-pss', 'ec-raw', 'oauth', 'otp']);
        // v2 carries the details inline; v1 asks credentials/info per id
        expect(service.calls.contains('credentials/info'),
            version == PdfCscApiVersion.v1);

        final pin = credentials.first;
        expect(pin.usable, isTrue);
        expect(pin.authMode, PdfCscAuthMode.explicit);
        expect(pin.scal, 2);
        expect(pin.certificates, hasLength(2));
        expect(pin.inputs.single.isPin, isTrue);
        expect(pin.inputs.single.numeric, isTrue);
        expect(pin.certificate.subjectCommonName, isNotEmpty);

        final otp = credentials.last;
        expect(otp.inputs.map((i) => i.id), ['PIN', 'OTP']);
        expect(otp.inputs.last.onlineOtp, isTrue);
        expect(credentials[3].authMode, PdfCscAuthMode.oauth2code);
      });

      test('signs B-B with a PIN, bound to the document hash (SCAL2)',
          () async {
        final pinCredential = await credential(client, 'rsa-pin');
        PdfCscAuthorizationRequest? asked;
        final bytes = await freshEditor().saveSignedPadesRemote(
          signer: cscRemoteSigner(
            client: client,
            credential: pinCredential,
            authorizer: (request) async {
              asked = request;
              return const PdfCscAuthorization.secrets(pin: '1234');
            },
          ),
          signingTime: signedAt,
          reason: 'Approved',
        );
        expect(asked!.hashes.single, hasLength(32));

        final result = PdfSignature.of(PdfDocument.open(bytes)).single.validate(
                trustStore: PdfTrustStore.trusting([
              pemBytes(testCaCertPem),
            ]));
        expect(result.intact, isTrue);
        expect(result.problems, isEmpty);
        expect(result.padesLevel, PdfPadesLevel.bB);
        expect(result.chainTrusted, isTrue);
      });

      test('a wrong PIN surfaces the service error and writes nothing',
          () async {
        final pinCredential = await credential(client, 'rsa-pin');
        await expectLater(
          freshEditor().saveSignedPadesRemote(
            signer: cscRemoteSigner(
              client: client,
              credential: pinCredential,
              authorizer: (_) async =>
                  const PdfCscAuthorization.secrets(pin: '0000'),
            ),
          ),
          throwsA(isA<PdfCscException>()
              .having((e) => e.description, 'description', 'Invalid PIN')
              .having((e) => e.method, 'method', 'credentials/authorize')),
        );
        expect(service.calls, isNot(contains('signatures/signHash')));
      });

      test('signs with RSASSA-PSS when that is all the key offers', () async {
        final pss = await credential(client, 'rsa-pss');
        final algorithm = cscSigningAlgorithmFor(pss);
        expect(algorithm.signAlgo, TestCscOid.rsassaPss);
        expect(algorithm.signAlgoParams, isNotNull);

        final bytes = await freshEditor().saveSignedPadesRemote(
          signer: cscRemoteSigner(client: client, credential: pss),
          signingTime: signedAt,
        );
        final signature = PdfSignature.of(PdfDocument.open(bytes)).single;
        expect(signature.validate().intact, isTrue);
      });

      test('normalizes a raw r || s ECDSA value to DER', () async {
        final ec = await credential(client, 'ec-raw');
        final bytes = await freshEditor().saveSignedPadesRemote(
          signer: cscRemoteSigner(client: client, credential: ec),
          level: PdfPadesLevel.bT,
          timestampClient: testTsa(),
          signingTime: signedAt,
        );
        final result = PdfSignature.of(PdfDocument.open(bytes))
            .single
            .validate(trustStore: PdfTrustStore.trusting([ec.certificates[1]]));
        expect(result.intact, isTrue);
        expect(result.padesLevel, PdfPadesLevel.bT);
        expect(result.timestamp!.valid, isTrue);
        expect(result.chainTrusted, isTrue);
      });

      test('an OAuth2 credential token replaces the SAD', () async {
        final oauth = await credential(client, 'oauth');
        expect(() => cscRemoteSigner(client: client, credential: oauth),
            throwsArgumentError);
        final bytes = await freshEditor().saveSignedPadesRemote(
          signer: cscRemoteSigner(
            client: client,
            credential: oauth,
            // stands in for the browser flow cscOAuthAuthorizationUrl starts
            authorizer: (request) async => PdfCscAuthorization.credentialToken(
                service.issueCredentialToken(
                    request.credential.id, request.hashes)),
          ),
        );
        expect(
            PdfSignature.of(PdfDocument.open(bytes)).single.validate().intact,
            isTrue);
        expect(service.calls, isNot(contains('credentials/authorize')));
      });

      test('an online OTP is requested before it is entered', () async {
        final otp = await credential(client, 'otp');
        final bytes = await freshEditor().saveSignedPadesRemote(
          signer: cscRemoteSigner(
            client: client,
            credential: otp,
            authorizer: (request) async {
              if (request.credential.inputs.any((i) => i.onlineOtp)) {
                await request.client.sendOtp(request.credential);
              }
              return const PdfCscAuthorization.secrets(
                  pin: '1234', otp: '654321');
            },
          ),
        );
        expect(
            PdfSignature.of(PdfDocument.open(bytes)).single.validate().intact,
            isTrue);
      });
    });
  }

  group('CSC remote signing', () {
    test('a SCAL2 SAD signs only the hash it was authorized for', () async {
      final service = TestCscService.standard();
      final client = clientFor(service);
      final pin = await credential(client, 'rsa-pin');
      final authorized = Uint8List(32)..[0] = 1;
      final sad = await client.authorizeCredential(pin,
          hashes: [authorized], pin: '1234');
      await expectLater(
        client.signHash(pin,
            hashes: [Uint8List(32)],
            signAlgo: TestCscOid.rsaEncryption,
            sad: sad.value),
        throwsA(isA<PdfCscException>()),
      );
      final signatures = await client.signHash(pin,
          hashes: [authorized],
          signAlgo: TestCscOid.rsaEncryption,
          sad: sad.value);
      expect(signatures, hasLength(1));
      // the SAD was for one signature
      await expectLater(
        client.signHash(pin,
            hashes: [authorized],
            signAlgo: TestCscOid.rsaEncryption,
            sad: sad.value),
        throwsA(isA<PdfCscException>()
            .having((e) => e.description, 'description', 'SAD exhausted')),
      );
    });

    test('a value that does not verify is refused before writing', () async {
      final service = TestCscService.standard();
      final client = clientFor(service);
      final pss = await credential(client, 'rsa-pss');
      // name PKCS#1 v1.5 in the SignerInfo while the service returns PSS
      final lying = _MislabelledSigner(
          cscRemoteSigner(client: client, credential: pss),
          rsaPkcs1SignatureAlgorithm());
      await expectLater(freshEditor().saveSignedPadesRemote(signer: lying),
          throwsA(isA<PdfRemoteSigningException>()));
    });

    test('a missing or wrong service token is a typed error', () async {
      final service = TestCscService.standard();
      final client =
          PdfCscClient(transport: transportTo(service), accessToken: 'expired');
      await expectLater(
        client.listCredentials(),
        throwsA(isA<PdfCscException>()
            .having((e) => e.error, 'error', 'invalid_token')
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('B-LT through a remote signer embeds the revocation material',
        () async {
      final service = TestCscService(credentials: [
        TestCscCredential(
          id: 'ltv',
          key: RsaPrivateKey.fromDer(pkixLeafKey),
          chain: [pkixLeafCert, pkixCaCert],
          keyAlgorithms: const [TestCscOid.rsaEncryption],
        ),
      ]);
      final client = clientFor(service);
      final bytes = await freshEditor().saveSignedPadesRemote(
        signer: cscRemoteSigner(
            client: client, credential: await credential(client, 'ltv')),
        level: PdfPadesLevel.bLT,
        timestampClient: testTsa(),
        signingTime: signedAt,
        revocationClient: (chain) async => PdfRevocationMaterial(
          ocspResponses: [pkixOcspGood],
          crls: [pkixCrl],
          certificates: [pkixCaCert],
        ),
      );
      final result = PdfSignature.of(PdfDocument.open(bytes)).single.validate();
      expect(result.intact, isTrue);
      expect(result.padesLevel, PdfPadesLevel.bLT);
      expect(result.isLtvEnabled, isTrue);
      expect(result.embeddedRevocation, PdfRevocationStatus.good);
    });

    test('an unusable credential is refused up front', () {
      final client = clientFor(TestCscService.standard());
      final expired = PdfCscCredential.fromJson('x', {
        'key': {'status': 'enabled', 'algo': <String>[]},
        'cert': {
          'status': 'expired',
          'certificates': [base64.encode(pemBytes(testSignerCertPem))],
        },
        'authMode': 'implicit',
      });
      expect(expired.usable, isFalse);
      expect(() => cscRemoteSigner(client: client, credential: expired),
          throwsArgumentError);
    });

    test('the signing algorithm follows the key type and what it offers', () {
      PdfCscCredential with_(String pem, List<String> algos) =>
          PdfCscCredential(
              id: 'c', certificates: [pemBytes(pem)], keyAlgorithms: algos);
      expect(
          cscSigningAlgorithmFor(with_(testSignerCertPem, const [])).signAlgo,
          TestCscOid.rsaEncryption);
      expect(
          cscSigningAlgorithmFor(with_(testSignerCertPem,
              const [TestCscOid.rsassaPss, TestCscOid.sha256WithRsa])).signAlgo,
          TestCscOid.sha256WithRsa);
      expect(
          () => cscSigningAlgorithmFor(
              with_(testSignerCertPem, const [TestCscOid.ecdsaWithSha256])),
          throwsUnsupportedError);
    });
  });

  group('CSC OAuth2 helpers', () {
    final credentialToSign = PdfCscCredential(
        id: 'cred-1', certificates: [pemBytes(testSignerCertPem)]);
    final hash = Uint8List.fromList(crypto.sha256.convert([1, 2, 3]).bytes);

    test('a service-scope URL', () {
      final url = cscOAuthAuthorizationUrl(
        oauth2Base: 'https://csc.test/',
        clientId: 'dartpdf',
        redirectUri: Uri.parse('http://127.0.0.1:5000/callback'),
        state: 's',
        codeChallenge: 'challenge',
      );
      expect(url.path, '/oauth2/authorize');
      expect(url.queryParameters, {
        'response_type': 'code',
        'client_id': 'dartpdf',
        'redirect_uri': 'http://127.0.0.1:5000/callback',
        'scope': 'service',
        'state': 's',
        'code_challenge': 'challenge',
        'code_challenge_method': 'S256',
      });
    });

    test('a credential-scope URL names the hashes per API version', () {
      final encoded = base64Url.encode(hash).replaceAll('=', '');
      final v1 = cscOAuthAuthorizationUrl(
        oauth2Base: 'https://csc.test',
        clientId: 'dartpdf',
        redirectUri: Uri.parse('http://127.0.0.1/cb'),
        credential: credentialToSign,
        hashes: [hash],
      );
      expect(v1.queryParameters['scope'], 'credential');
      expect(v1.queryParameters['credentialID'], 'cred-1');
      expect(v1.queryParameters['numSignatures'], '1');
      expect(v1.queryParameters['hash'], encoded);

      final v2 = cscOAuthAuthorizationUrl(
        oauth2Base: 'https://csc.test',
        clientId: 'dartpdf',
        redirectUri: Uri.parse('http://127.0.0.1/cb'),
        credential: credentialToSign,
        hashes: [hash],
        version: PdfCscApiVersion.v2,
      );
      expect(v2.queryParameters['hashes'], encoded);
      expect(v2.queryParameters['hashAlgorithmOID'], DigestOid.sha256);
    });

    test('token request and response', () {
      final body = Uri.splitQueryString(cscOAuthTokenRequestBody(
        code: 'abc',
        clientId: 'dartpdf',
        redirectUri: Uri.parse('http://127.0.0.1/cb'),
        codeVerifier: 'verifier',
      ));
      expect(body['grant_type'], 'authorization_code');
      expect(body['code_verifier'], 'verifier');

      final tokens = PdfCscOAuthTokens.fromResponse(
          '{"access_token":"t","refresh_token":"r","expires_in":3600}');
      expect(tokens.accessToken, 't');
      expect(tokens.expiresIn, 3600);
      expect(
          () => PdfCscOAuthTokens.fromResponse('{"error":"invalid_grant"}'),
          throwsA(isA<PdfCscException>()
              .having((e) => e.error, 'error', 'invalid_grant')));
    });
  });
}

/// Delegates signing but names [signatureAlgorithm] in the SignerInfo - a
/// signer whose value does not match its label.
class _MislabelledSigner implements PdfRemoteSigner {
  _MislabelledSigner(this.inner, this.signatureAlgorithm);

  final PdfRemoteSigner inner;

  @override
  final Uint8List signatureAlgorithm;

  @override
  List<Uint8List> get certificates => inner.certificates;

  @override
  Future<Uint8List> signDigest(Uint8List digest) => inner.signDigest(digest);
}
