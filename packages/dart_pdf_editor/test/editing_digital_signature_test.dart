import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An unsigned OIDC token carrying [claims] - enough for the keyless flow to
/// read the identity from (Fulcio, not the client, verifies the signature).
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PdfDigitalSignatureIdentity identity() =>
      PdfDigitalSignatureIdentity.fromFiles(
        privateKey: Uint8List.fromList(testSignerKeyPem.codeUnits),
        certificates: [Uint8List.fromList(testSignerCertPem.codeUnits)],
      );

  test('identity reads PEM material and reports the signer', () {
    final signer = identity();
    expect(signer.signerName, 'Dart PDF Test Signer');
    expect(signer.certificateCount, 1);
    expect(signer.validUntil.isAfter(signer.validFrom), isTrue);
  });

  test('identity rejects a private key that does not match the certificate',
      () {
    expect(
      () => PdfDigitalSignatureIdentity.fromFiles(
        privateKey: Uint8List.fromList(testSignerKeyPem.codeUnits),
        certificates: [
          Uint8List.fromList(testChainSignerCertPem.codeUnits),
        ],
      ),
      throwsA(
        isA<PdfSignatureIdentityException>()
            .having((e) => e.message, 'message', contains('does not match'))
            .having((e) => e.code, 'code',
                PdfSignatureIdentityError.keyCertificateMismatch),
      ),
    );
  });

  test('identity file errors carry a machine-readable code for localization',
      () {
    final key = Uint8List.fromList(testSignerKeyPem.codeUnits);
    final cert = Uint8List.fromList(testSignerCertPem.codeUnits);

    void expectCode(
      PdfSignatureIdentityError code, {
      required Uint8List privateKey,
      required List<Uint8List> certificates,
      int? certificateIndex,
    }) {
      var matcher = isA<PdfSignatureIdentityException>()
          .having((e) => e, 'is a FormatException', isA<FormatException>())
          .having((e) => e.code, 'code', code);
      if (certificateIndex != null) {
        matcher = matcher.having(
            (e) => e.certificateIndex, 'certificateIndex', certificateIndex);
      }
      expect(
        () => PdfDigitalSignatureIdentity.fromFiles(
            privateKey: privateKey, certificates: certificates),
        throwsA(matcher),
      );
    }

    // No certificate chosen at all.
    expectCode(PdfSignatureIdentityError.noCertificateSelected,
        privateKey: key, certificates: const []);
    // A chosen certificate file that isn't valid X.509 (1-based index).
    expectCode(PdfSignatureIdentityError.invalidCertificate,
        privateKey: key,
        certificates: [Uint8List.fromList(const [1, 2, 3, 4])],
        certificateIndex: 1);
    // An encrypted PEM private key (unsupported).
    expectCode(PdfSignatureIdentityError.encryptedKeyUnsupported,
        privateKey: Uint8List.fromList(
            '-----BEGIN ENCRYPTED PRIVATE KEY-----\nAAAA\n'
                    '-----END ENCRYPTED PRIVATE KEY-----\n'
                .codeUnits),
        certificates: [cert]);
  });

  test('controller adds a valid PAdES signature as an undoable revision',
      () async {
    final editing = PdfEditingController(buildClassicPdf());
    addTearDown(editing.dispose);
    final original = Uint8List.fromList(editing.bytes);
    final signedAt = DateTime.utc(2026, 7, 13, 4, 30);

    expect(
      await editing.addDigitalSignature(
        identity(),
        reason: 'Approved',
        location: 'Melbourne',
        signingTime: signedAt,
      ),
      isTrue,
    );

    expect(editing.bytes.sublist(0, original.length), original);
    var signatures = PdfSignature.of(editing.document);
    expect(signatures, hasLength(1));
    expect(signatures.single.reason, 'Approved');
    expect(signatures.single.location, 'Melbourne');
    final validation = signatures.single.validate();
    expect(validation.intact, isTrue);
    expect(validation.coversWholeDocument, isTrue);
    expect(validation.padesLevel, PdfPadesLevel.bB);
    expect(editing.canUndo, isTrue);

    editing.undo();
    expect(PdfSignature.of(editing.document), isEmpty);
    editing.redo();
    signatures = PdfSignature.of(editing.document);
    expect(signatures, hasLength(1));
    expect(signatures.single.validate().intact, isTrue);
  });

  test('a placed appearance signs into a visible box (rect + /AP)', () async {
    final editing = PdfEditingController(buildClassicPdf());
    addTearDown(editing.dispose);
    final signedAt = DateTime.utc(2026, 7, 13, 4, 30);

    expect(
      await editing.addDigitalSignature(
        identity(),
        reason: 'Approved',
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          page: 0,
          rect: PdfRect(72, 640, 320, 720),
        ),
      ),
      isTrue,
    );

    final signature = PdfSignature.of(editing.document).single;
    expect(signature.validate().intact, isTrue);

    // the widget carries the placed /Rect and a rendered appearance stream
    final widget = signature.field.widgets.first;
    final rect = pdfRectFrom(editing.document.cos, widget['Rect'])!;
    expect(rect.left, closeTo(72, 0.5));
    expect(rect.top, closeTo(720, 0.5));
    // a rendered appearance stream was installed (visible box)
    expect(widget['AP'], isNotNull);
  });

  test('removeSignature drops the field and its apply-to-pages copies',
      () async {
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);
    final signedAt = DateTime.utc(2026, 7, 13, 4, 30);

    expect(
      await editing.addDigitalSignature(
        identity(),
        signingTime: signedAt,
        appearance: const PdfSignatureAppearance(
          page: 0,
          rect: PdfRect(72, 640, 320, 720),
          repeatPages: [1, 2],
        ),
      ),
      isTrue,
    );
    expect(editing.signatures, hasLength(1));
    List<PdfAnnotation> stamps(int page) => editing.document
        .page(page)
        .annotations
        .where((a) => a.subtype == 'Stamp')
        .toList();
    expect(stamps(1), hasLength(1));
    expect(stamps(2), hasLength(1));

    // removing the signature drops the field and both appearance copies
    expect(editing.removeSignature(editing.signatures.single), isTrue);
    expect(editing.signatures, isEmpty);
    expect(stamps(1), isEmpty);
    expect(stamps(2), isEmpty);

    // and it's undoable
    editing.undo();
    expect(editing.signatures, hasLength(1));
    expect(stamps(1), hasLength(1));
  });

  test('controller adds a timestamped keyless (B-T) signature', () async {
    final signedAt = DateTime.utc(2026, 7, 13, 4, 30);
    final ca = TestFulcioCa.generate(notBefore: DateTime.utc(2026));

    // Mint a keyless identity through the in-process Fulcio, exactly as the
    // app's keylessSigningIdentity would but with the fake transport.
    final keyless = await fulcioSigningIdentity(
      oidcToken: _jwt({'email': 'dev@example.com'}),
      transport: (request) async =>
          buildTestFulcioResponse(request, ca: ca, notBefore: signedAt),
    );

    final editing = PdfEditingController(buildClassicPdf());
    addTearDown(editing.dispose);
    final original = Uint8List.fromList(editing.bytes);

    expect(
      await editing.addKeylessSignature(
        keyless,
        timestampClient: (request) async =>
            buildTestTimeStampToken(request, genTime: signedAt),
        reason: 'Approved',
        signingTime: signedAt,
      ),
      isTrue,
    );

    expect(editing.bytes.sublist(0, original.length), original);
    final signature = PdfSignature.of(editing.document).single;
    expect(signature.signerName, 'dev@example.com');
    expect(signature.subFilter, 'ETSI.CAdES.detached');

    // intact + trusted against the Sigstore CA, with a signature timestamp.
    final result = signature.validate(
        trustStore: PdfTrustStore.trusting([ca.certificate]));
    expect(result.intact, isTrue, reason: result.problems.join('; '));
    expect(result.coversWholeDocument, isTrue);
    expect(result.timestamp, isNotNull);
    expect(result.chainTrusted, isTrue,
        reason: result.chainProblems.join('; '));

    // still an undoable revision
    expect(editing.canUndo, isTrue);
    editing.undo();
    expect(PdfSignature.of(editing.document), isEmpty);
  });
}
