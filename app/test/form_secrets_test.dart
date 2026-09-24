import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/form_secrets.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password values persist off the web and stay in memory on it', () {
    expect(defaultFormSecretStore(web: false), isA<SecureFormSecretStore>());
    expect(defaultFormSecretStore(web: true), isA<InMemoryFormSecretStore>());
  });

  test('document tabs file password values in the app store', () async {
    SharedPreferences.setMockInitialValues({});
    final previous = appFormSecretStore;
    final store = InMemoryFormSecretStore();
    appFormSecretStore = store;
    addTearDown(() => appFormSecretStore = previous);

    final tab = DocumentTab.document(
      title: 'form.pdf',
      bytes: buildAcroFormPdf(),
      preferences: PdfEditingPreferences(),
    );
    addTearDown(tab.dispose);
    expect(tab.session!.formSecretStore, same(store));
    expect(tab.session!.formSecretDocumentId, isNotNull);
  });
}
