import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf_document/pdf_document.dart';

// Loading the EU trusted list cache needs dart:io (a file in the app support
// directory, an isolate for the verification); the web build gets a stub.
import 'signature_trust_store_stub.dart'
    if (dart.library.io) 'signature_trust_store_io.dart' as store;

/// A [PdfRevocationClient] over `package:http`: OCSP (POST) through each
/// certificate's responder, CRL (GET) as the fallback - see
/// [pdfOnlineRevocationClient].
PdfRevocationClient httpRevocationClient({
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) =>
    pdfOnlineRevocationClient(fetch: (request) async {
      final owned = client == null;
      final c = client ?? http.Client();
      try {
        final response = await (request.isPost
                ? c.post(request.url,
                    headers: {
                      'Content-Type': request.contentType!,
                      'User-Agent': 'DartPDF',
                    },
                    body: request.body)
                : c.get(request.url, headers: const {'User-Agent': 'DartPDF'}))
            .timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
              'HTTP ${response.statusCode}', request.url);
        }
        return Uint8List.fromList(response.bodyBytes);
      } finally {
        if (owned) c.close();
      }
    });

/// The app's signature-validation trust, shared by every open document:
/// live OCSP/CRL revocation checking and the EU trusted list roots.
///
/// Both are on by default off-web ([platformDefault]); the web build has
/// neither (browsers block cross-origin OCSP/CRL and trusted-list fetches).
/// The EU trusted list is fetched from the Commission's LOTL and the Member
/// State lists it points to, each signature-verified, and cached for
/// a week - no roots ship inside the app. It loads in the background the
/// first time an attached document carries a signature; documents attached
/// before it lands are re-validated when it does.
class SignatureTrust {
  SignatureTrust({this.revocationClient, this.loadAnchors});

  static SignatureTrust? _default;
  static bool _defaultOverridden = false;

  /// The app-wide instance, or null on the web (and under `flutter test`,
  /// which must not reach the network).
  static SignatureTrust? get platformDefault {
    if (_defaultOverridden) return _default;
    if (kIsWeb || !store.networkTrustAvailable) return null;
    return _default ??= SignatureTrust(
      revocationClient: httpRevocationClient(),
      loadAnchors: store.loadEuTrustStore,
    );
  }

  @visibleForTesting
  static set debugPlatformDefault(SignatureTrust? value) {
    _default = value;
    _defaultOverridden = true;
  }

  /// Checks certificates for revocation while validating signatures.
  final PdfRevocationClient? revocationClient;

  /// Loads the trust anchors (cached or freshly fetched); null when none
  /// could be had.
  final Future<PdfTrustStore?> Function()? loadAnchors;

  final Map<PdfEditingController, VoidCallback> _attached = {};
  Future<void>? _loading;
  PdfTrustStore? _trustStore;

  /// The loaded anchors, once they are in.
  PdfTrustStore? get trustStore => _trustStore;

  /// Gives [controller] this trust. The anchors load lazily - the first time
  /// an attached document carries a signature - so opening unsigned PDFs
  /// never downloads the trusted lists. Pair with [detach] when the
  /// controller is disposed.
  void attach(PdfEditingController controller) {
    controller.revocationClient = revocationClient;
    if (_trustStore != null) controller.trustStore = _trustStore;
    void watch() {
      if (_loading == null && controller.signatureByFieldName.isNotEmpty) {
        _loading = _load();
      }
    }

    _attached[controller] = watch;
    if (_loading == null) controller.addListener(watch);
    watch();
  }

  void detach(PdfEditingController controller) {
    final watch = _attached.remove(controller);
    if (watch != null) controller.removeListener(watch);
  }

  Future<void> _load() async {
    final load = loadAnchors;
    if (load == null) return;
    PdfTrustStore? loaded;
    try {
      loaded = await load();
    } catch (error) {
      debugPrint('signature trust: could not load the EU trusted list: $error');
    }
    if (loaded == null) return;
    _trustStore = loaded;
    for (final controller in _attached.keys) {
      controller.trustStore = loaded;
    }
  }
}
