import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/digital_signature.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  PdfDigitalSignatureIdentity identity() =>
      PdfDigitalSignatureIdentity.fromFiles(
        privateKey: Uint8List.fromList(testSignerKeyPem.codeUnits),
        certificates: [Uint8List.fromList(testSignerCertPem.codeUnits)],
      );

  testWidgets('digital signing dialog loads and matches the identity',
      (tester) async {
    DigitalSignatureOptions? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDigitalSigningDialog(
                context,
                privateKeyPicker: () async => XFile.fromData(
                  Uint8List.fromList(testSignerKeyPem.codeUnits),
                  name: 'signer-key.pem',
                ),
                certificatePicker: () async => [
                  XFile.fromData(
                    Uint8List.fromList(testSignerCertPem.codeUnits),
                    name: 'signer-cert.pem',
                  ),
                ],
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DigitalSignatureDialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('digital-signature-sign')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('digital-signature-private-key')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('digital-signature-certificates')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dart PDF Test Signer'), findsOneWidget);
    expect(find.byKey(const ValueKey('digital-signature-error')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('digital-signature-location')),
      'Melbourne',
    );
    await tester.tap(find.byKey(const ValueKey('digital-signature-sign')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.identity.signerName, 'Dart PDF Test Signer');
    expect(result!.reason, 'Approved');
    expect(result!.location, 'Melbourne');
  });

  testWidgets('app menu digitally signs then saves the current document',
      (tester) async {
    Uint8List? saved;
    final original = buildClassicPdf();
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: original, title: 'Contract.pdf'),
        digitalSignatureOptionsProvider: (context) async =>
            DigitalSignatureOptions(
          identity: identity(),
          reason: 'Approved for release',
          location: 'Melbourne',
        ),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saved = Uint8List.fromList(bytes);
          return SaveResult.downloaded(suggestedName);
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-digital-signature')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sublist(0, original.length), original);
    final signatures = PdfSignature.of(PdfDocument.open(saved!));
    expect(signatures, hasLength(1));
    expect(signatures.single.reason, 'Approved for release');
    expect(signatures.single.location, 'Melbourne');
    final validation = signatures.single.validate();
    expect(validation.intact, isTrue);
    expect(validation.coversWholeDocument, isTrue);
    expect(validation.padesLevel, PdfPadesLevel.bB);
  });
}
