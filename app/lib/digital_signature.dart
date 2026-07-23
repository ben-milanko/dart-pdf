import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf_cos/pdf_cos.dart' show X509Certificate;
import 'package:pdf_document/pdf_document.dart';

import 'l10n/app_l10n.dart';
import 'signature_appearance_store.dart';
import 'signature_raster.dart';

/// How opaque the logo backdrop is drawn - a light watermark so the signer
/// name and details stay readable. Kept in sync between the live preview and
/// the signed box ([PdfSignatureAppearance.backgroundImageOpacity]).
const double _signatureLogoOpacity = 0.2;

/// The Acrobat-style signing date the signed box renders, so the preview
/// matches it: `2026.07.18 05:40:17 +00'00'`, in UTC.
String _acrobatSignDate(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year}.${two(utc.month)}.${two(utc.day)} '
      "${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} +00'00'";
}

// `label` is the localized file-dialog filter name; the caller resolves it.
XTypeGroup digitalSignatureKeyTypeGroup(String label) => XTypeGroup(
      label: label,
      extensions: const ['pem', 'key', 'der'],
      mimeTypes: const ['application/x-pem-file', 'application/pkcs8'],
      uniformTypeIdentifiers: const ['public.data'],
    );

XTypeGroup digitalSignatureCertificateTypeGroup(String label) => XTypeGroup(
      label: label,
      extensions: const ['pem', 'crt', 'cer', 'der'],
      mimeTypes: const ['application/pkix-cert', 'application/x-x509-ca-cert'],
      uniformTypeIdentifiers: const ['public.x509-certificate', 'public.data'],
    );

typedef DigitalSignatureOptionsProvider = Future<DigitalSignatureOptions?>
    Function(BuildContext context);

typedef DigitalSignaturePrivateKeyPicker = Future<XFile?> Function();
typedef DigitalSignatureCertificatePicker = Future<List<XFile>> Function();

/// Supplies PNG or JPEG bytes for the signature box's logo backdrop
/// ([PdfSignatureAppearance.backgroundImage]) - typically a file picker.
/// Returns null to cancel.
typedef SignatureLogoPicker = Future<Uint8List?> Function();

/// The page and rectangle (PDF user space) a visible signature box will be
/// drawn into - handed to the dialog by the signature-box placement tool.
typedef SignaturePlacement = ({int page, PdfRect rect});

/// Mints (or shows a dialog to mint) a one-tap self-signed identity. Injected
/// in tests; defaults to [showCreateSigningIdentityDialog].
typedef SelfSignedIdentityCreator = Future<PdfSigningIdentity?> Function(
    BuildContext context, PdfIdentityStore store);

/// Runs the Sigstore/Fulcio keyless flow (OIDC sign-in + short-lived
/// certificate) and returns the resulting identity, or null if the user
/// cancels. Injected; only offered when a deployment wires one in (DartPDF
/// ships no default OAuth client).
typedef KeylessIdentityCreator = Future<PdfSigningIdentity?> Function(
    BuildContext context);

/// Everything the app needs to add one approval signature. Exactly one of
/// [identity] (a bring-your-own RSA key + chain), [selfSignedIdentity] (a
/// one-tap self-signed P-256 identity), or [keylessIdentity] (a
/// Sigstore/Fulcio identity from an OIDC-verified email) is set. The private
/// key is only used in memory when signing; a self-signed identity may also be
/// kept in the platform keychain via [SecureIdentityStore].
///
/// A keyless signature must be timestamped (its certificate expires in
/// minutes), so [timestampClient] is set alongside [keylessIdentity].
class DigitalSignatureOptions {
  const DigitalSignatureOptions({
    this.identity,
    this.selfSignedIdentity,
    this.keylessIdentity,
    this.timestampClient,
    this.fieldName,
    this.reason,
    this.location,
    this.contactInfo,
    this.signingTime,
    this.appearance,
  }) : assert(
            (identity == null ? 0 : 1) +
                    (selfSignedIdentity == null ? 0 : 1) +
                    (keylessIdentity == null ? 0 : 1) ==
                1,
            'exactly one identity kind must be provided'),
        assert(keylessIdentity == null || timestampClient != null,
            'a keyless identity requires a timestampClient');

  /// A bring-your-own RSA/X.509 identity from files, or null.
  final PdfDigitalSignatureIdentity? identity;

  /// A one-tap self-signed P-256 identity, or null.
  final PdfSigningIdentity? selfSignedIdentity;

  /// A short-lived Sigstore/Fulcio keyless identity, or null.
  final PdfSigningIdentity? keylessIdentity;

  /// The timestamp client used to stamp a keyless (B-T) signature. Set only
  /// when [keylessIdentity] is.
  final PdfTimestampClient? timestampClient;

  final String? fieldName;
  final String? reason;
  final String? location;
  final String? contactInfo;

  /// An explicit signing time, or null to stamp the moment of signing. Set by
  /// tests for determinism; production leaves it null.
  final DateTime? signingTime;

  /// The visible signature box to draw the signature into - its page, its
  /// rectangle (in PDF user space), and any hand-drawn mark or logo backdrop
  /// the user added. Null for an invisible signature (menu-triggered, no
  /// placement). Set when the box came from the signature-box tool.
  final PdfSignatureAppearance? appearance;

  /// The signer name to show, regardless of which identity kind is set.
  String? get signerName =>
      identity?.signerName ??
      selfSignedIdentity?.name ??
      keylessIdentity?.name;
}

Future<DigitalSignatureOptions?> showDigitalSigningDialog(
  BuildContext context, {
  DigitalSignaturePrivateKeyPicker? privateKeyPicker,
  DigitalSignatureCertificatePicker? certificatePicker,
  PdfIdentityStore? identityStore,
  SelfSignedIdentityCreator? createSelfSignedIdentity,
  KeylessIdentityCreator? createKeylessIdentity,
  PdfTimestampClient? timestampClient,
  bool keylessUnavailable = false,
  KeylessIdentityCreator? autoCreateKeylessIdentity,
  SignaturePlacement? placement,
  SignatureLogoPicker? logoPicker,
  int pageCount = 1,
  SignatureAppearanceStore? appearanceStore,
}) =>
    showDialog<DigitalSignatureOptions>(
      context: context,
      builder: (context) => DigitalSignatureDialog(
        privateKeyPicker: privateKeyPicker ??
            () => _pickPrivateKey(appL10n(context).appSigKeyFileType),
        certificatePicker: certificatePicker ??
            () => _pickCertificates(appL10n(context).appSigCertificateFileType),
        identityStore: identityStore ?? SecureIdentityStore(),
        createSelfSignedIdentity: createSelfSignedIdentity ??
            (context, store) =>
                showCreateSigningIdentityDialog(context, store: store),
        createKeylessIdentity: createKeylessIdentity,
        timestampClient: timestampClient,
        keylessUnavailable: keylessUnavailable,
        autoCreateKeylessIdentity: autoCreateKeylessIdentity,
        placement: placement,
        logoPicker: logoPicker,
        pageCount: pageCount,
        appearanceStore: appearanceStore ?? PrefsSignatureAppearanceStore(),
      ),
    );

Future<XFile?> _pickPrivateKey(String label) => openFile(
      acceptedTypeGroups: [digitalSignatureKeyTypeGroup(label)],
    );

Future<List<XFile>> _pickCertificates(String label) => openFiles(
      acceptedTypeGroups: [digitalSignatureCertificateTypeGroup(label)],
    );

class DigitalSignatureDialog extends StatefulWidget {
  const DigitalSignatureDialog({
    super.key,
    required this.privateKeyPicker,
    required this.certificatePicker,
    required this.identityStore,
    required this.createSelfSignedIdentity,
    this.createKeylessIdentity,
    this.timestampClient,
    this.keylessUnavailable = false,
    this.autoCreateKeylessIdentity,
    this.placement,
    this.logoPicker,
    this.pageCount = 1,
    this.appearanceStore,
  });

  final DigitalSignaturePrivateKeyPicker privateKeyPicker;
  final DigitalSignatureCertificatePicker certificatePicker;
  final PdfIdentityStore identityStore;
  final SelfSignedIdentityCreator createSelfSignedIdentity;

  /// When set, offers the Sigstore/Fulcio keyless option. Null hides it.
  final KeylessIdentityCreator? createKeylessIdentity;

  /// Timestamp client used for a keyless (B-T) signature. Required when
  /// [createKeylessIdentity] is set.
  final PdfTimestampClient? timestampClient;

  /// When true and no [createKeylessIdentity] is wired, shows a note that
  /// keyless email signing is available in the desktop/mobile app - set on the
  /// web, where the OAuth broker's loopback/CORS constraints preclude it.
  final bool keylessUnavailable;

  /// A **silent** keyless creator run when the dialog opens to pre-select the
  /// identity: it reuses a cached/refreshable Sigstore login and returns null
  /// (selecting nothing) when a token could only be obtained by opening the
  /// browser - so drawing a box never launches sign-in as a side effect.
  final KeylessIdentityCreator? autoCreateKeylessIdentity;

  /// When set, the signature is drawn into this page/rectangle (the
  /// signature-box tool placed it) and the dialog shows an Appearance section
  /// for a hand-drawn mark and a logo backdrop. Null = invisible signature.
  final SignaturePlacement? placement;

  /// Supplies the logo backdrop image; only used when [placement] is set.
  final SignatureLogoPicker? logoPicker;

  /// Total pages in the document, bounding the "Apply to pages" range.
  final int pageCount;

  /// Remembers the drawn mark and logo on the device between signatures.
  /// Only used when [placement] is set. Null disables persistence.
  final SignatureAppearanceStore? appearanceStore;

  @override
  State<DigitalSignatureDialog> createState() => _DigitalSignatureDialogState();
}

class _DigitalSignatureDialogState extends State<DigitalSignatureDialog> {
  final _fieldName = TextEditingController();
  final _reason = TextEditingController(text: 'Approved');
  final _location = TextEditingController();
  final _contact = TextEditingController();

  Uint8List? _privateKey;
  List<Uint8List> _certificates = const [];
  String? _privateKeyName;
  List<String> _certificateNames = const [];
  PdfDigitalSignatureIdentity? _identity;
  PdfSigningIdentity? _selfSigned;
  PdfSigningIdentity? _keyless;
  bool _keylessBusy = false;
  bool _submitting = false;
  String? _error;

  /// A keyless cert with less than this left is re-minted at Sign time, so a
  /// signature never goes out on an about-to-expire short-lived certificate.
  static const _keylessRemintMargin = Duration(minutes: 2);

  // Visible-box appearance (only when widget.placement is set).
  Uint8List? _signaturePng; // rasterized hand-drawn mark
  Uint8List? _logoBytes; // logo backdrop (PNG/JPEG)
  String? _appearanceError;
  // The 0-based inclusive page span the box is shown on; null = this page
  // only. The signature stays a single cryptographic signature either way.
  ({int start, int end})? _applyRange;

  @override
  void initState() {
    super.initState();
    _loadRememberedIdentity();
    if (widget.placement != null) _loadRememberedAppearance();
    // Pre-select a keyless identity on open only when it can be obtained
    // silently (a cached or refreshable login). The creator returns null
    // rather than opening the browser, so drawing a box never triggers
    // sign-in - the user does that explicitly with the button.
    final autoCreate = widget.autoCreateKeylessIdentity;
    if (autoCreate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runKeylessCreator(autoCreate, silent: true);
      });
    }
  }

  /// Pre-fills the drawn mark and logo from the device so a placed signature
  /// reuses the last one. Any storage error just leaves them unset.
  Future<void> _loadRememberedAppearance() async {
    final store = widget.appearanceStore;
    if (store == null) return;
    try {
      final config = await store.load();
      if (!mounted || config.isEmpty) return;
      setState(() {
        _signaturePng ??= config.signaturePng;
        _logoBytes ??= config.logoBytes;
      });
    } catch (_) {
      // no storage here - the pickers still work
    }
  }

  /// Saves the current drawn mark + logo to the device.
  void _persistAppearance() {
    final store = widget.appearanceStore;
    if (store == null || widget.placement == null) return;
    unawaited(store.save(SignatureAppearanceConfig(
      signaturePng: _signaturePng,
      logoBytes: _logoBytes,
    )));
  }

  /// Surfaces a previously created self-signed identity from the keychain, so
  /// signing is genuinely one-tap on the second use. Any storage error (e.g.
  /// no secure storage in a test) just leaves no remembered identity.
  Future<void> _loadRememberedIdentity() async {
    try {
      final ids = await widget.identityStore.ids();
      if (ids.isEmpty) return;
      final identity = await widget.identityStore.load(ids.first);
      if (identity != null && mounted && _identity == null) {
        setState(() => _selfSigned = identity);
      }
    } catch (_) {
      // no secure storage here - the "Create" button still works
    }
  }

  @override
  void dispose() {
    _fieldName.dispose();
    _reason.dispose();
    _location.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _createSelfSignedIdentity() async {
    final identity =
        await widget.createSelfSignedIdentity(context, widget.identityStore);
    if (identity == null || !mounted) return;
    setState(() {
      _selfSigned = identity;
      // A self-signed identity supersedes any file selection.
      _privateKey = null;
      _certificates = const [];
      _privateKeyName = null;
      _certificateNames = const [];
      _identity = null;
      _keyless = null;
      _error = null;
    });
  }

  /// The keyless button: runs the interactive creator (browser allowed).
  Future<void> _createKeylessIdentity() async {
    final creator = widget.createKeylessIdentity;
    if (creator == null) return;
    await _runKeylessCreator(creator);
  }

  Future<void> _runKeylessCreator(KeylessIdentityCreator creator,
      {bool silent = false}) async {
    if (_keylessBusy || _keyless != null) return;
    setState(() {
      _keylessBusy = true;
      _error = null;
    });
    PdfSigningIdentity? identity;
    Object? failure;
    try {
      identity = await creator(context);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() {
      _keylessBusy = false;
      if (failure != null) {
        // A pre-select attempt on open fails quietly; the user can retry with
        // the button (which surfaces the error).
        if (!silent) {
          _error = appL10n(context).appSigKeylessSignInFailed('$failure');
        }
        return;
      }
      if (identity == null) return; // cancelled
      _keyless = identity;
      // A keyless identity supersedes every other selection.
      _privateKey = null;
      _certificates = const [];
      _privateKeyName = null;
      _certificateNames = const [];
      _identity = null;
      _selfSigned = null;
      _error = null;
    });
  }

  Future<void> _selectPrivateKey() async {
    final file = await widget.privateKeyPicker();
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _privateKey = bytes;
        _privateKeyName = file.name;
        _rebuildIdentity();
      });
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = appL10n(context).appSigCouldNotReadKey('$error'));
      }
    }
  }

  Future<void> _selectCertificates() async {
    final files = await widget.certificatePicker();
    if (files.isEmpty) return;
    try {
      final bytes =
          await Future.wait([for (final file in files) file.readAsBytes()]);
      if (!mounted) return;
      setState(() {
        _certificates = bytes;
        _certificateNames = [for (final file in files) file.name];
        _rebuildIdentity();
      });
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = appL10n(context).appSigCouldNotReadCertificate('$error'));
      }
    }
  }

  void _rebuildIdentity() {
    _identity = null;
    _error = null;
    // an explicit file selection supersedes self-signed / keyless
    _selfSigned = null;
    _keyless = null;
    final key = _privateKey;
    if (key == null || _certificates.isEmpty) return;
    try {
      _identity = PdfDigitalSignatureIdentity.fromFiles(
        privateKey: key,
        certificates: _certificates,
      );
    } on PdfSignatureIdentityException catch (error) {
      _error = _localizeSignatureIdentityError(context, error);
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = appL10n(context).appSigKeyOrCertUnreadable;
    }
  }

  /// Maps a [PdfSignatureIdentityException] code (English `message` aside) to a
  /// localized message. The engine model stays English-only; the translation
  /// happens here, at the display site.
  String _localizeSignatureIdentityError(
    BuildContext context,
    PdfSignatureIdentityException error,
  ) {
    final l10n = appL10n(context);
    return switch (error.code) {
      PdfSignatureIdentityError.noCertificateSelected =>
        l10n.appSigErrorNoCertificateSelected,
      PdfSignatureIdentityError.invalidCertificate =>
        l10n.appSigErrorInvalidCertificate(error.certificateIndex ?? 0),
      PdfSignatureIdentityError.keyCertificateMismatch =>
        l10n.appSigErrorKeyCertificateMismatch,
      PdfSignatureIdentityError.encryptedKeyUnsupported =>
        l10n.appSigErrorEncryptedKeyUnsupported,
      PdfSignatureIdentityError.keyNotRsa => l10n.appSigErrorKeyNotRsa,
      PdfSignatureIdentityError.noCertificateFound =>
        l10n.appSigErrorNoCertificateFound,
    };
  }

  String? _value(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _drawSignature() async {
    final signature = await showPdfSignatureDialog(context);
    if (signature == null || !mounted) return;
    final png = await rasterizeInkSignature(signature);
    if (!mounted) return;
    setState(() {
      _signaturePng = png;
      _appearanceError =
          png == null ? appL10n(context).appSigCouldNotCaptureSignature : null;
    });
    _persistAppearance();
  }

  Future<void> _pickLogo() async {
    final picker = widget.logoPicker;
    if (picker == null) return;
    final bytes = await picker();
    if (bytes == null || !mounted) return;
    // fail early on a format the embedder can't take, rather than at sign time
    try {
      PdfEmbeddableImage.decode(bytes);
    } catch (_) {
      setState(
          () => _appearanceError = appL10n(context).appSigChoosePngOrJpeg);
      return;
    }
    setState(() {
      _logoBytes = bytes;
      _appearanceError = null;
    });
    _persistAppearance();
  }

  Future<void> _chooseApplyPages() async {
    final placement = widget.placement;
    if (placement == null) return;
    final range = await showPdfPageRangeDialog(
      context,
      pageCount: widget.pageCount,
      initialStart: _applyRange?.start ?? placement.page,
      initialEnd: _applyRange?.end ?? placement.page,
      title: appL10n(context).appSigShowSignatureOnPages,
      confirmLabel: appL10n(context).apply,
    );
    if (range == null || !mounted) return;
    setState(() => _applyRange = range);
  }

  /// The 0-based pages, besides the placed page, the box is also shown on.
  List<int> _repeatPages() {
    final range = _applyRange;
    final placement = widget.placement;
    if (range == null || placement == null) return const [];
    return [
      for (var p = range.start; p <= range.end; p++)
        if (p != placement.page) p,
    ];
  }

  String _applyPagesLabel() {
    final range = _applyRange;
    if (range == null || (range.start == range.end)) {
      return appL10n(context).appSigThisPageOnly;
    }
    if (range.start == 0 && range.end == widget.pageCount - 1) {
      return appL10n(context).appSigAllPages(widget.pageCount);
    }
    return appL10n(context).appSigPagesRange(range.start + 1, range.end + 1);
  }

  /// The visible-box appearance for the placed rectangle, or null when there
  /// is no placement (an invisible signature).
  PdfSignatureAppearance? _buildAppearance() {
    final placement = widget.placement;
    if (placement == null) return null;
    return PdfSignatureAppearance(
      page: placement.page,
      rect: placement.rect,
      graphic:
          _signaturePng != null ? PdfEmbeddableImage.png(_signaturePng!) : null,
      backgroundImage:
          _logoBytes != null ? PdfEmbeddableImage.decode(_logoBytes!) : null,
      backgroundImageOpacity: _signatureLogoOpacity,
      repeatPages: _repeatPages(),
    );
  }

  /// Keyless certs live only minutes. If the selected one is at (or near) its
  /// expiry, re-mint from the cached login for a fresh cert before signing;
  /// returns null (and shows an error, dropping the selection) if that fails.
  /// A comfortably-valid cert is returned unchanged.
  Future<PdfSigningIdentity?> _freshKeylessIfStale(
      PdfSigningIdentity current) async {
    final creator = widget.createKeylessIdentity;
    if (creator == null) return current;
    DateTime? notAfter;
    try {
      notAfter = X509Certificate.parse(current.certificate).notAfter.toUtc();
    } catch (_) {
      notAfter = null; // unreadable -> treat as stale, re-mint
    }
    final now = DateTime.now().toUtc();
    if (notAfter != null && notAfter.isAfter(now.add(_keylessRemintMargin))) {
      return current; // still comfortably valid
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    PdfSigningIdentity? fresh;
    Object? failure;
    try {
      fresh = await creator(context);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return null;
    setState(() {
      _submitting = false;
      if (fresh == null) {
        _keyless = null; // force a re-tap of "Sign in with your email"
        _error = failure == null
            ? appL10n(context).appSigKeylessSignInExpired
            : appL10n(context).appSigKeylessSignInFailed('$failure');
      }
    });
    return fresh;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final appearance = _buildAppearance();
    final keyless = _keyless;
    if (keyless != null) {
      final fresh = await _freshKeylessIfStale(keyless);
      if (fresh == null || !mounted) return; // re-mint failed; stay open
      Navigator.of(context).pop(DigitalSignatureOptions(
        keylessIdentity: fresh,
        timestampClient: widget.timestampClient,
        fieldName: _value(_fieldName),
        reason: _value(_reason),
        location: _value(_location),
        contactInfo: _value(_contact),
        appearance: appearance,
      ));
      return;
    }
    final selfSigned = _selfSigned;
    if (selfSigned != null) {
      Navigator.of(context).pop(DigitalSignatureOptions(
        selfSignedIdentity: selfSigned,
        fieldName: _value(_fieldName),
        reason: _value(_reason),
        location: _value(_location),
        contactInfo: _value(_contact),
        appearance: appearance,
      ));
      return;
    }
    final identity = _identity;
    if (identity == null) return;
    Navigator.of(context).pop(DigitalSignatureOptions(
      identity: identity,
      fieldName: _value(_fieldName),
      reason: _value(_reason),
      location: _value(_location),
      contactInfo: _value(_contact),
      appearance: appearance,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    final selfSigned = _selfSigned;
    final keyless = _keyless;
    final canSign = identity != null || selfSigned != null || keyless != null;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.verified_user_outlined),
        const SizedBox(width: 10),
        Text(appL10n(context).appSigDigitallySign),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                appL10n(context).appSigIntro,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              // Easiest options first.
              if (widget.createKeylessIdentity != null) ...[
                FilledButton.tonalIcon(
                  key: const ValueKey('digital-signature-keyless'),
                  onPressed: _keylessBusy ? null : _createKeylessIdentity,
                  icon: _keylessBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mail_lock_outlined),
                  label: Text(_keylessBusy
                      ? appL10n(context).appSigSigningYouIn
                      : appL10n(context).appSigSignInWithEmail),
                ),
                const SizedBox(height: 6),
                Text(
                  appL10n(context).appSigKeylessDescription,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ] else if (widget.keylessUnavailable) ...[
                Text(
                  appL10n(context).appSigKeylessWebNote,
                  key: const ValueKey('digital-signature-keyless-web-note'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                key: const ValueKey('digital-signature-create-identity'),
                onPressed: _createSelfSignedIdentity,
                icon: const Icon(Icons.badge_outlined),
                label: Text(appL10n(context).appSigCreateOnDevice),
              ),
              const SizedBox(height: 6),
              Text(
                appL10n(context).appSigSelfSignedDescription,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              // The technical option, tucked away for those who need it.
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: const ValueKey('digital-signature-advanced'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(appL10n(context).appSigUseOwnCertificate,
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                      appL10n(context).appSigUseOwnCertificateSubtitle,
                      style: theme.textTheme.bodySmall),
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        appL10n(context).appSigChooseKeyDescription,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey('digital-signature-private-key'),
                      onPressed: _selectPrivateKey,
                      icon: const Icon(Icons.key_outlined),
                      label: Text(_privateKeyName ??
                          appL10n(context).appSigChoosePrivateKey),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('digital-signature-certificates'),
                      onPressed: _selectCertificates,
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: Text(_certificateNames.isEmpty
                          ? appL10n(context).appSigChooseCertificate
                          : _certificateNames.join(', ')),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('digital-signature-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              if (identity != null) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const ValueKey('digital-signature-identity'),
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(
                        identity.signerName ?? appL10n(context).appSigX509Signer),
                    subtitle: Text(
                      appL10n(context).appSigIdentitySubtitle(
                        identity.certificateCount,
                        MaterialLocalizations.of(context)
                            .formatMediumDate(identity.validFrom.toLocal()),
                        MaterialLocalizations.of(context)
                            .formatMediumDate(identity.validUntil.toLocal()),
                      ),
                    ),
                  ),
                ),
              ] else if (selfSigned != null) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const ValueKey('digital-signature-self-signed'),
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(selfSigned.name ??
                        appL10n(context).appSigSelfSignedIdentity),
                    subtitle: Text(appL10n(context).appSigSelfSignedSubtitle),
                  ),
                ),
              ] else if (keyless != null) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const ValueKey('digital-signature-keyless-identity'),
                    leading: const Icon(Icons.mail_lock_outlined),
                    title: Text(
                        keyless.name ?? appL10n(context).appSigKeylessIdentity),
                    subtitle: Text(appL10n(context).appSigKeylessSubtitle),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('digital-signature-field'),
                controller: _fieldName,
                decoration: InputDecoration(
                  labelText: appL10n(context).appSigFieldLabel,
                  helperText: appL10n(context).appSigFieldHelper,
                ),
              ),
              TextField(
                key: const ValueKey('digital-signature-reason'),
                controller: _reason,
                decoration:
                    InputDecoration(labelText: appL10n(context).appSigReason),
              ),
              TextField(
                key: const ValueKey('digital-signature-location'),
                controller: _location,
                decoration:
                    InputDecoration(labelText: appL10n(context).appSigLocation),
              ),
              TextField(
                key: const ValueKey('digital-signature-contact'),
                controller: _contact,
                decoration: InputDecoration(
                    labelText: appL10n(context).appSigContactInfo),
              ),
              if (widget.placement != null) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(appL10n(context).appSigAppearance,
                        style: theme.textTheme.labelMedium),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 6),
                Text(
                  appL10n(context).appSigAppearanceDescription,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('digital-signature-draw'),
                      onPressed: _drawSignature,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(_signaturePng == null
                          ? appL10n(context).appSigDrawSignature
                          : appL10n(context).appSigSignatureAdded),
                    ),
                  ),
                  if (widget.logoPicker != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('digital-signature-logo'),
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(_logoBytes == null
                            ? appL10n(context).appSigAddLogo
                            : appL10n(context).appSigLogoAdded),
                      ),
                    ),
                  ],
                ]),
                if (widget.pageCount > 1) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                          appL10n(context).appSigApplyTo(_applyPagesLabel()),
                          style: theme.textTheme.bodyMedium),
                    ),
                    TextButton.icon(
                      key: const ValueKey('digital-signature-apply-pages'),
                      onPressed: _chooseApplyPages,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: Text(appL10n(context).appSigApplyToPages),
                    ),
                  ]),
                ],
                const SizedBox(height: 10),
                _AppearancePreview(
                  signaturePng: _signaturePng,
                  logoBytes: _logoBytes,
                  signerName: identity?.signerName ??
                      selfSigned?.name ??
                      keyless?.name,
                  reason: _value(_reason),
                  aspectRatio: widget.placement == null
                      ? 2.0
                      : widget.placement!.rect.width /
                          widget.placement!.rect.height,
                  onClearSignature: _signaturePng == null
                      ? null
                      : () {
                          setState(() => _signaturePng = null);
                          _persistAppearance();
                        },
                  onClearLogo: _logoBytes == null
                      ? null
                      : () {
                          setState(() => _logoBytes = null);
                          _persistAppearance();
                        },
                ),
                if (_appearanceError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _appearanceError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appL10n(context).cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('digital-signature-sign'),
          onPressed: (canSign && !_submitting) ? () => unawaited(_submit()) : null,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.draw_outlined),
          label: Text(_submitting
              ? appL10n(context).appSigRefreshingSignIn
              : appL10n(context).appSigSign),
        ),
      ],
    );
  }
}

/// A rough live preview of the visible signature box: the logo backdrop (if
/// any), the hand-drawn mark or the signer name on the left, and the signing
/// details on the right - mirroring the two-column box the signer renders.
class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({
    required this.signaturePng,
    required this.logoBytes,
    required this.signerName,
    required this.reason,
    required this.aspectRatio,
    required this.onClearSignature,
    required this.onClearLogo,
  });

  final Uint8List? signaturePng;
  final Uint8List? logoBytes;
  final String? signerName;
  final String? reason;

  /// The drawn box's width / height, so the preview matches its shape.
  final double aspectRatio;
  final VoidCallback? onClearSignature;
  final VoidCallback? onClearLogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      if (signerName != null && signerName!.isNotEmpty)
        appL10n(context).appSigSignedBy(signerName!),
      appL10n(context).appSigDate(_acrobatSignDate(DateTime.now())),
      if (reason != null && reason!.isNotEmpty)
        appL10n(context).appSigReasonLine(reason!),
    ];
    // Wraps [child] to the panel width, then scales the whole block down to
    // fit the panel height - mirroring the renderer, which wraps the text and
    // shrinks the font so nothing overflows or is clipped (never an ellipsis).
    Widget fitText(Widget child, Alignment alignment) => Padding(
          padding: const EdgeInsets.all(5),
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: SizedBox(width: constraints.maxWidth, child: child),
            ),
          ),
        );

    final box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF2E5E86)),
        borderRadius: BorderRadius.circular(4),
        image: logoBytes == null
            ? null
            : DecorationImage(
                image: MemoryImage(logoBytes!),
                fit: BoxFit.contain,
                opacity: _signatureLogoOpacity),
      ),
      child: Row(children: [
        Expanded(
          child: signaturePng != null
              ? Padding(
                  padding: const EdgeInsets.all(5),
                  child: Image.memory(signaturePng!, fit: BoxFit.contain),
                )
              // the signer name, centred and shrunk/wrapped to fit
              : fitText(
                  Text(
                    signerName ?? appL10n(context).appSigSigner,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  Alignment.center,
                ),
        ),
        Expanded(
          // the signing details, top-anchored, wrapped and shrunk to fit
          child: fitText(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in details)
                  Text(line,
                      style: const TextStyle(
                          fontSize: 9,
                          height: 1.3,
                          color: Color(0xFF1A1A1A))),
              ],
            ),
            Alignment.centerLeft,
          ),
        ),
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Match the preview to the box the user drew on the page.
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 150),
            child: AspectRatio(
              aspectRatio: aspectRatio.clamp(0.2, 8.0),
              child: box,
            ),
          ),
        ),
        Row(children: [
          if (onClearSignature != null)
            TextButton(
                onPressed: onClearSignature,
                child: Text(appL10n(context).appSigRemoveSignature)),
          if (onClearLogo != null)
            TextButton(
                onPressed: onClearLogo,
                child: Text(appL10n(context).appSigRemoveLogo)),
        ]),
        Text(appL10n(context).appSigPreviewNote,
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}
