import 'package:pdf_document/pdf_document.dart';

/// The web has no EU trusted list cache and no revocation transport.
bool get networkTrustAvailable => false;

Future<PdfTrustStore?> loadEuTrustStore() async => null;
