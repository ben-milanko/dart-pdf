import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/trust_lists.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_l10n.dart';

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

/// The persisted "Trust Adobe Approved Trust List" choice. Off by default:
/// turning it on makes the app download Adobe's list from Adobe.
class AatlTrustSetting extends ValueNotifier<bool> {
  AatlTrustSetting() : super(false);

  static const _key = 'dart_pdf_editor_app.signatures.aatl';

  /// Reads the saved choice (call once at start-up).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(_key) ?? false;
    } catch (error) {
      debugPrint('AATL setting unreadable: $error');
    }
  }

  /// Sets and saves the choice.
  Future<void> save(bool enabled) async {
    value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (error) {
      debugPrint('AATL setting not saved: $error');
    }
  }
}

/// The app's signature-validation trust, shared by every open document:
/// live OCSP/CRL revocation checking, the EU trusted list roots, and - when
/// the user opts in - the Adobe Approved Trust List roots.
///
/// All of it is off-web only ([platformDefault]); the web build has none
/// (browsers block cross-origin OCSP/CRL and trusted-list fetches).
/// - The EU trusted list is fetched from the Commission's LOTL and the Member
///   State lists it points to, each signature-verified, and cached for a
///   week - no roots ship inside the app. It loads in the background the
///   first time an attached document carries a signature.
/// - The AATL is opt-in ([aatl], default off). When on, it is downloaded
///   from Adobe on this device, verified against Adobe Root CA G2, cached
///   and re-checked weekly; turning it off drops its roots at once and
///   deletes the cache. While it is off, the signature panel offers it as a
///   one-click action under a signer it can't vouch for.
///
/// Documents attached before a list lands are re-validated when it does.
class SignatureTrust {
  SignatureTrust({
    this.revocationClient,
    this.loadAnchors,
    this.loadAatl,
    this.deleteAatlCache,
    this.aatl,
  }) {
    aatl?.addListener(_onAatlSetting);
  }

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
      loadAatl: store.loadAatlTrustStore,
      deleteAatlCache: store.deleteAatlCache,
      aatl: AatlTrustSetting()..load(),
    );
  }

  @visibleForTesting
  static set debugPlatformDefault(SignatureTrust? value) {
    _default = value;
    _defaultOverridden = true;
  }

  /// Checks certificates for revocation while validating signatures.
  final PdfRevocationClient? revocationClient;

  /// Loads the EU trust anchors (cached or freshly fetched); null when none
  /// could be had.
  final Future<PdfTrustStore?> Function()? loadAnchors;

  /// Loads the AATL roots (cached or freshly downloaded from Adobe).
  final Future<PdfTrustStore?> Function()? loadAatl;

  /// Deletes the downloaded AATL.
  final Future<void> Function()? deleteAatlCache;

  /// The persisted opt-in; null where the AATL can't be offered.
  final AatlTrustSetting? aatl;

  final Map<PdfEditingController, VoidCallback> _attached = {};
  Future<void>? _loadingEu;
  Future<void>? _loadingAatl;
  PdfTrustStore? _eu;
  PdfTrustStore? _aatlRoots;
  PdfTrustStore? _trustStore;

  /// Bumped when the AATL is switched off, so a download still in flight
  /// can't bring its roots back.
  int _aatlGeneration = 0;

  bool get _aatlOn => aatl?.value ?? false;

  /// The loaded anchors (EU and, when on, AATL), once any are in.
  PdfTrustStore? get trustStore => _trustStore;

  /// Whether any attached document carries a signature.
  bool get _anySigned =>
      _attached.keys.any((c) => c.signatureByFieldName.isNotEmpty);

  /// Gives [controller] this trust. The anchors load lazily - the first time
  /// an attached document carries a signature - so opening unsigned PDFs
  /// never downloads a list. Pair with [detach] when the controller is
  /// disposed.
  void attach(PdfEditingController controller) {
    controller.revocationClient = revocationClient;
    if (_trustStore != null) controller.trustStore = _trustStore;
    controller.signatureTrustAction = _aatlAction;
    void watch() {
      if (controller.signatureByFieldName.isNotEmpty) _ensureLoading();
    }

    _attached[controller] = watch;
    controller.addListener(watch);
    watch();
  }

  void detach(PdfEditingController controller) {
    final watch = _attached.remove(controller);
    if (watch != null) controller.removeListener(watch);
  }

  /// Turns the AATL on or off and saves the choice. On: the list is
  /// downloaded now (in the background) and every open signature is
  /// re-validated when it lands. Off: its roots are dropped at once, the
  /// signatures re-validated, and the downloaded copy deleted.
  Future<void> setAatlEnabled(bool enabled) async {
    final setting = aatl;
    if (setting == null) return;
    await setting.save(enabled);
    if (enabled) {
      await (_loadingAatl ??= _loadAatlRoots());
    } else {
      await deleteAatlCache?.call();
    }
  }

  void _onAatlSetting() {
    if (_aatlOn) {
      if (_anySigned) _loadingAatl ??= _loadAatlRoots();
    } else {
      _aatlGeneration++;
      _loadingAatl = null;
      if (_aatlRoots != null) {
        _aatlRoots = null;
        _publish();
      }
    }
    for (final controller in _attached.keys) {
      controller.signatureTrustAction = _aatlAction;
    }
  }

  /// The panel's one-click offer, while the AATL is available but off.
  PdfSignatureTrustAction? get _aatlAction =>
      aatl == null || _aatlOn ? null : _action;

  late final PdfSignatureTrustAction _action = PdfSignatureTrustAction(
    label: (context) => appL10n(context).signatureTrustAatlAction,
    explanation: (context) => appL10n(context).signatureTrustAatlExplanation,
    onPressed: () => setAatlEnabled(true),
  );

  void _ensureLoading() {
    _loadingEu ??= _loadEu();
    if (_aatlOn) _loadingAatl ??= _loadAatlRoots();
  }

  Future<void> _loadEu() async {
    final load = loadAnchors;
    if (load == null) return;
    try {
      _eu = await load();
    } catch (error) {
      debugPrint('signature trust: could not load the EU trusted list: $error');
    }
    if (_eu != null) _publish();
  }

  Future<void> _loadAatlRoots() async {
    final load = loadAatl;
    if (load == null) return;
    final generation = _aatlGeneration;
    PdfTrustStore? roots;
    try {
      roots = await load();
    } catch (error) {
      debugPrint('signature trust: could not load the AATL: $error');
    }
    if (generation != _aatlGeneration || !_aatlOn) return;
    if (roots == null) {
      // let a later signed document or toggle try again
      _loadingAatl = null;
      return;
    }
    _aatlRoots = roots;
    _publish();
  }

  /// Hands every attached controller the current union of lists.
  void _publish() {
    final lists = [
      if (_eu != null) _eu!,
      if (_aatlRoots != null) _aatlRoots!,
    ];
    _trustStore = lists.isEmpty ? null : PdfTrustLists.combine(lists);
    for (final controller in _attached.keys) {
      controller.trustStore = _trustStore;
    }
  }
}
