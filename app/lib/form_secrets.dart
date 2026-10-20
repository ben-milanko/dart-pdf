import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Where the app keeps password-field values instead of the PDF (#931).
///
/// Off the web they go to the platform Keychain/Keystore, so reopening a
/// document on the same device restores them. On the web nothing is
/// persisted: `flutter_secure_storage`'s web backend keeps its key next to
/// the data in browser storage, so the values live in memory for the page
/// session only.
PdfFormSecretStore defaultFormSecretStore({bool web = kIsWeb}) =>
    web ? InMemoryFormSecretStore() : SecureFormSecretStore();

/// The store every document tab's editing session uses. Replaceable for
/// tests.
PdfFormSecretStore appFormSecretStore = defaultFormSecretStore();
