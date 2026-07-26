import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('InMemoryIdentityStore', () {
    test('round-trips a generated identity by id', () async {
      final store = InMemoryIdentityStore();
      final identity = PdfSigningIdentity.generate(name: 'Ada Lovelace');
      await store.save('ada', identity);

      expect(await store.ids(), ['ada']);
      final loaded = await store.load('ada');
      expect(loaded, isNotNull);
      expect(loaded!.privateKey.d, identity.privateKey.d);
      expect(loaded.certificate, identity.certificate);

      await store.delete('ada');
      expect(await store.ids(), isEmpty);
      expect(await store.load('ada'), isNull);
    });
  });

  group('CreateSigningIdentityForm', () {
    testWidgets('generates, persists, and returns a working identity',
        (tester) async {
      final store = InMemoryIdentityStore();
      PdfSigningIdentity? created;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CreateSigningIdentityForm(
            store: store,
            onCreated: (identity) => created = identity,
          ),
        ),
      ));

      // The self-signed caveat must be shown to the user.
      expect(find.textContaining('validity unknown'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Grace Hopper');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(created, isNotNull);
      expect(created!.name, 'Grace Hopper');
      expect(await store.ids(), ['Grace Hopper']);

      // the generated identity actually signs a document that validates
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSelfSigned(identity: created!);
      final signature = PdfSignature.of(PdfDocument.open(signed)).single;
      expect(signature.signerName, 'Grace Hopper');
      expect(signature.validate().intact, isTrue);
    });

    testWidgets('requires a name', (tester) async {
      var created = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CreateSigningIdentityForm(onCreated: (_) => created = true),
        ),
      ));

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(created, isFalse);
      expect(find.text('Enter a name'), findsOneWidget);
    });
  });
}
