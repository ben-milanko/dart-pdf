import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Password-field values kept in a [PdfFormSecretStore] instead of /V
/// (#931, ISO 32000 §12.7.4.3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The AcroForm fixture with its `name` field turned into a password
  /// field (still carrying its legacy `/V (prefilled)`), optionally with a
  /// trailer /ID so two "different documents" can be told apart.
  Uint8List passwordForm({Uint8List? id}) {
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final field = editor.acroForm!.fieldNamed('name')!;
    field.dict['Ff'] = const CosInteger(PdfFormField.passwordFlag);
    if (id != null) {
      // withholding writes the /ID when the file has none
      editor.setPasswordValue(field, 'seed', documentId: id);
    }
    editor.setTextValue(field, 'prefilled');
    return editor.save();
  }

  bool fileContains(Uint8List bytes, String text) =>
      latin1.decode(bytes).contains(text);

  Future<PdfEditingController> open(
      Uint8List bytes, PdfFormSecretStore? store) async {
    final controller = PdfEditingController(bytes, formSecretStore: store);
    addTearDown(controller.dispose);
    await controller.formSecretsLoaded;
    return controller;
  }

  test('without a store, a password field still fills /V', () async {
    final c = await open(passwordForm(), null);
    expect(c.setFormFieldText('name', 'hunter2'), isTrue);
    expect(c.acroForm!.fieldNamed('name')!.value, 'hunter2');
    expect(c.formSecretDocumentId, isNull);
  });

  test('with a store the value goes to the store, never the file', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    expect(c.setFormFieldText('name', 'hunter2'), isTrue);
    await c.formSecretsSettled;

    final field = c.acroForm!.fieldNamed('name')!;
    expect(field.value, isNull, reason: 'the legacy /V is removed');
    expect(c.formFieldTextValue(field), 'hunter2');
    expect(fileContains(c.bytes, 'hunter2'), isFalse);
    expect(c.isModified, isTrue);
    expect(await store.read(c.formSecretDocumentId!, 'name'), 'hunter2');

    // flattening burns only the mask
    expect(c.flattenFormFields(), isTrue);
    expect(fileContains(c.bytes, 'hunter2'), isFalse);
  });

  test('reopening the saved file restores the value without dirtying it',
      () async {
    final store = InMemoryFormSecretStore();
    final first = await open(passwordForm(), store);
    first.setFormFieldText('name', 'hunter2');
    await first.formSecretsSettled;
    final saved = first.bytes;

    final again = await open(saved, store);
    expect(again.formSecretDocumentId, first.formSecretDocumentId,
        reason: 'the fallback identity was written as the file /ID');
    expect(again.formFieldTextValue(again.acroForm!.fieldNamed('name')!),
        'hunter2');
    expect(again.isModified, isFalse);
    expect(again.revisionCount, 1);
  });

  test('a different document never sees the value', () async {
    final store = InMemoryFormSecretStore();
    final a = await open(passwordForm(id: Uint8List(16)), store);
    a.setFormFieldText('name', 'hunter2');
    await a.formSecretsSettled;

    final otherId = Uint8List.fromList(List.filled(16, 7));
    final b = await open(passwordForm(id: otherId), store);
    expect(b.formSecretDocumentId, isNot(a.formSecretDocumentId));
    // b shows its own legacy /V, not a's stored value
    expect(b.formFieldTextValue(b.acroForm!.fieldNamed('name')!), 'prefilled');
    expect(await store.readAll(b.formSecretDocumentId!), isEmpty);
  });

  test('a stale entry for a field the file no longer withholds is ignored',
      () async {
    final store = InMemoryFormSecretStore();
    final bytes = passwordForm(id: Uint8List(16)); // /V (prefilled)
    await store.write(pdfFormSecretDocumentId(Uint8List(16)), 'name', 'old');
    final c = await open(bytes, store);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), 'prefilled');
  });

  test('undo and redo carry the stored value with the revision', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    final id = c.formSecretDocumentId!;
    String? shown() => c.formFieldTextValue(c.acroForm!.fieldNamed('name')!);

    c.setFormFieldText('name', 'first');
    c.setFormFieldText('name', 'second');
    await c.formSecretsSettled;
    expect(await store.read(id, 'name'), 'second');

    c.undo();
    await c.formSecretsSettled;
    expect(shown(), 'first');
    expect(await store.read(id, 'name'), 'first');

    c.undo(); // back to the file as opened: its legacy /V, nothing stored
    await c.formSecretsSettled;
    expect(shown(), 'prefilled');
    expect(await store.read(id, 'name'), isNull);

    c.redo();
    await c.formSecretsSettled;
    expect(shown(), 'first');
    expect(await store.read(id, 'name'), 'first');
  });

  test('clearing the field removes the stored value', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    c.setFormFieldText('name', 'hunter2');
    expect(c.setFormFieldText('name', ''), isTrue);
    await c.formSecretsSettled;
    expect(await store.readAll(c.formSecretDocumentId!), isEmpty);
  });

  test('forgetFormSecrets clears the document from the store', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    c.setFormFieldText('name', 'hunter2');
    await c.forgetFormSecrets();
    expect(await store.readAll(c.formSecretDocumentId!), isEmpty);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), isNull);
  });

  test('SecureFormSecretStore round-trips through flutter_secure_storage',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureFormSecretStore();
    await store.write('doc-a', 'pin', '1234');
    await store.write('doc-a', 'pw', 'hunter2');
    await store.write('doc-b', 'pw', 'other');
    expect(await store.readAll('doc-a'), {'pin': '1234', 'pw': 'hunter2'});
    await store.remove('doc-a', 'pin');
    expect(await store.read('doc-a', 'pin'), isNull);
    await store.clearDocument('doc-a');
    expect(await store.readAll('doc-a'), isEmpty);
    expect(await store.read('doc-b', 'pw'), 'other');
    await store.clearAll();
    expect(await store.readAll('doc-b'), isEmpty);
  });
}
