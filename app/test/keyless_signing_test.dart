import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/keyless_signing.dart';

String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

void main() {
  final ca = TestFulcioCa.generate(notBefore: DateTime.utc(2026));

  group('fulcioHttpTransport', () {
    test('posts the request and returns the response body', () async {
      Uint8List? seenBody;
      final client = MockClient((request) async {
        seenBody = request.bodyBytes;
        return http.Response.bytes(
            buildTestFulcioResponse(request.bodyBytes, ca: ca), 200);
      });
      final key = EcPrivateKey.generate(EcCurve.p256);
      final request = buildFulcioSigningRequest(
        oidcToken: _jwt({'email': 'dev@example.com'}),
        publicKey: key.publicKey,
        proofOfPossession: fulcioProofOfPossession(key, 'dev@example.com'),
      );

      final response = await fulcioHttpTransport(request, client: client);
      expect(seenBody, request); // the body is passed through unchanged
      final chain = parseFulcioCertificateChain(response);
      expect(chain, hasLength(2));
    });

    test('throws on a non-200 status', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      expect(
        () => fulcioHttpTransport(Uint8List(0), client: client),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('defaultTimestampClient', () {
    // Wrap the test token in a minimal RFC 3161 TimeStampResp (status granted).
    Uint8List tsaResponse(Uint8List request) => derSequence([
          derSequence([derInteger(BigInt.zero)]), // PKIStatusInfo: granted
          buildTestTimeStampToken(request, genTime: DateTime.utc(2026, 6, 10)),
        ]);

    test('posts the query and unwraps the timestamp token', () async {
      String? contentType;
      final client = MockClient((request) async {
        contentType = request.headers['content-type'];
        return http.Response.bytes(tsaResponse(request.bodyBytes), 200);
      });
      final request = buildTimeStampRequest(
          messageImprint: List.filled(32, 7));
      final token = await defaultTimestampClient(request, client: client);
      expect(contentType, 'application/timestamp-query');
      // the returned bytes parse as a real timestamp token
      expect(TimeStampToken.parse(token).cms.certificates, isNotEmpty);
    });

    test('throws on a non-200 status', () async {
      final client = MockClient((_) async => http.Response('down', 503));
      expect(
        () => defaultTimestampClient(Uint8List(0), client: client),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('keylessSigningIdentity', () {
    testWidgets('mints an identity from the token + Fulcio transport',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }));

      final identity = await keylessSigningIdentity(
        ctx,
        tokenProvider: (context) async => _jwt({'email': 'dev@example.com'}),
        transport: (request) async =>
            buildTestFulcioResponse(request, ca: ca),
      );
      expect(identity, isNotNull);
      expect(identity!.name, 'dev@example.com');
      expect(identity.certificates, hasLength(2));
    });

    testWidgets('returns null when the user cancels sign-in', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }));

      final identity = await keylessSigningIdentity(
        ctx,
        tokenProvider: (context) async => null,
        transport: (request) async => throw StateError('should not be called'),
      );
      expect(identity, isNull);
    });
  });
}
