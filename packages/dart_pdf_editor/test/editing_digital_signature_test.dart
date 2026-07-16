import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
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
}
