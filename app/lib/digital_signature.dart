import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'signature_raster.dart';

/// How opaque the logo backdrop is drawn - a light watermark so the signer
/// name and details stay readable. Kept in sync between the live preview and
/// the signed box ([PdfSignatureAppearance.backgroundImageOpacity]).
const double _signatureLogoOpacity = 0.2;

const digitalSignatureKeyTypeGroup = XTypeGroup(
  label: 'RSA private keys',
  extensions: ['pem', 'key', 'der'],
  mimeTypes: ['application/x-pem-file', 'application/pkcs8'],
  uniformTypeIdentifiers: ['public.data'],
);

const digitalSignatureCertificateTypeGroup = XTypeGroup(
  label: 'X.509 certificates',
  extensions: ['pem', 'crt', 'cer', 'der'],
  mimeTypes: ['application/pkix-cert', 'application/x-x509-ca-cert'],
  uniformTypeIdentifiers: ['public.x509-certificate', 'public.data'],
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
  SignaturePlacement? placement,
  SignatureLogoPicker? logoPicker,
  int pageCount = 1,
}) =>
    showDialog<DigitalSignatureOptions>(
      context: context,
      builder: (context) => DigitalSignatureDialog(
        privateKeyPicker: privateKeyPicker ?? _pickPrivateKey,
        certificatePicker: certificatePicker ?? _pickCertificates,
        identityStore: identityStore ?? SecureIdentityStore(),
        createSelfSignedIdentity: createSelfSignedIdentity ??
            (context, store) =>
                showCreateSigningIdentityDialog(context, store: store),
        createKeylessIdentity: createKeylessIdentity,
        timestampClient: timestampClient,
        keylessUnavailable: keylessUnavailable,
        placement: placement,
        logoPicker: logoPicker,
        pageCount: pageCount,
      ),
    );

Future<XFile?> _pickPrivateKey() => openFile(
      acceptedTypeGroups: const [digitalSignatureKeyTypeGroup],
    );

Future<List<XFile>> _pickCertificates() => openFiles(
      acceptedTypeGroups: const [digitalSignatureCertificateTypeGroup],
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
    this.placement,
    this.logoPicker,
    this.pageCount = 1,
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

  /// When set, the signature is drawn into this page/rectangle (the
  /// signature-box tool placed it) and the dialog shows an Appearance section
  /// for a hand-drawn mark and a logo backdrop. Null = invisible signature.
  final SignaturePlacement? placement;

  /// Supplies the logo backdrop image; only used when [placement] is set.
  final SignatureLogoPicker? logoPicker;

  /// Total pages in the document, bounding the "Apply to pages" range.
  final int pageCount;

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
  String? _error;

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

  Future<void> _createKeylessIdentity() async {
    final creator = widget.createKeylessIdentity;
    if (creator == null || _keylessBusy) return;
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
        _error = 'Keyless sign-in failed: $failure';
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
      if (mounted) setState(() => _error = 'Could not read the key: $error');
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
        setState(() => _error = 'Could not read the certificate: $error');
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
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'The selected key or certificate could not be read.';
    }
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
      _appearanceError = png == null ? 'Could not capture the signature.' : null;
    });
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
      setState(() => _appearanceError = 'Choose a PNG or JPEG image.');
      return;
    }
    setState(() {
      _logoBytes = bytes;
      _appearanceError = null;
    });
  }

  Future<void> _chooseApplyPages() async {
    final placement = widget.placement;
    if (placement == null) return;
    final range = await showPdfPageRangeDialog(
      context,
      pageCount: widget.pageCount,
      initialStart: _applyRange?.start ?? placement.page,
      initialEnd: _applyRange?.end ?? placement.page,
      title: 'Show the signature on pages',
      confirmLabel: 'Apply',
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
    if (range == null || (range.start == range.end)) return 'This page only';
    if (range.start == 0 && range.end == widget.pageCount - 1) {
      return 'All ${widget.pageCount} pages';
    }
    return 'Pages ${range.start + 1}–${range.end + 1}';
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

  void _submit() {
    final appearance = _buildAppearance();
    final keyless = _keyless;
    if (keyless != null) {
      Navigator.of(context).pop(DigitalSignatureOptions(
        keylessIdentity: keyless,
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
      title: const Row(children: [
        Icon(Icons.verified_user_outlined),
        SizedBox(width: 10),
        Text('Digitally sign'),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A digital signature proves you signed this document and that '
                'it has not been changed since. Pick how you want to sign.',
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
                      ? 'Signing you in…'
                      : 'Sign in with your email'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Easiest. We confirm it\'s you by email and sign for you, '
                  'with a trusted timestamp. Nothing to install or set up.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ] else if (widget.keylessUnavailable) ...[
                Text(
                  'Signing in with your email is the easiest way — it\'s '
                  'available in the DartPDF desktop and mobile apps. For '
                  'security reasons it can\'t run in a web browser.',
                  key: const ValueKey('digital-signature-keyless-web-note'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                key: const ValueKey('digital-signature-create-identity'),
                onPressed: _createSelfSignedIdentity,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Create a signature on this device'),
              ),
              const SizedBox(height: 6),
              Text(
                'No sign-in or files needed. Best for personal use — it\'s '
                'saved on this device for next time. Some PDF readers will '
                'show it as "signed, validity unknown", which is normal for a '
                'signature you make yourself.',
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
                  title: Text('Use your own certificate',
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                      'For a signing certificate from your organisation',
                      style: theme.textTheme.bodySmall),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose your private key (RSA, PEM or DER) and its '
                        'certificate file. The key is only used to sign and is '
                        'never saved.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey('digital-signature-private-key'),
                      onPressed: _selectPrivateKey,
                      icon: const Icon(Icons.key_outlined),
                      label: Text(_privateKeyName ?? 'Choose private key…'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('digital-signature-certificates'),
                      onPressed: _selectCertificates,
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: Text(_certificateNames.isEmpty
                          ? 'Choose certificate file…'
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
                    title: Text(identity.signerName ?? 'X.509 signer'),
                    subtitle: Text(
                      '${identity.certificateCount} certificate'
                      '${identity.certificateCount == 1 ? '' : 's'} · valid '
                      '${MaterialLocalizations.of(context).formatMediumDate(identity.validFrom.toLocal())} '
                      'to ${MaterialLocalizations.of(context).formatMediumDate(identity.validUntil.toLocal())}',
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
                    title: Text(selfSigned.name ?? 'Self-signed identity'),
                    subtitle: const Text('Self-signed · validity unknown'),
                  ),
                ),
              ] else if (keyless != null) ...[
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const ValueKey('digital-signature-keyless-identity'),
                    leading: const Icon(Icons.mail_lock_outlined),
                    title: Text(keyless.name ?? 'Keyless identity'),
                    subtitle:
                        const Text('Keyless · timestamped · validity unknown'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('digital-signature-field'),
                controller: _fieldName,
                decoration: const InputDecoration(
                  labelText: 'Existing signature field (optional)',
                  helperText: 'Leave blank to create a new signature field.',
                ),
              ),
              TextField(
                key: const ValueKey('digital-signature-reason'),
                controller: _reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              TextField(
                key: const ValueKey('digital-signature-location'),
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              TextField(
                key: const ValueKey('digital-signature-contact'),
                controller: _contact,
                decoration: const InputDecoration(labelText: 'Contact info'),
              ),
              if (widget.placement != null) ...[
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Appearance', style: theme.textTheme.labelMedium),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 6),
                Text(
                  'The signature is drawn where you placed it. The signer name '
                  'and details are always shown; you can add a hand-drawn mark '
                  'and a logo backdrop.',
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
                          ? 'Draw signature…'
                          : 'Signature added ✓'),
                    ),
                  ),
                  if (widget.logoPicker != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('digital-signature-logo'),
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                            _logoBytes == null ? 'Add logo…' : 'Logo added ✓'),
                      ),
                    ),
                  ],
                ]),
                if (widget.pageCount > 1) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text('Apply to: ${_applyPagesLabel()}',
                          style: theme.textTheme.bodyMedium),
                    ),
                    TextButton.icon(
                      key: const ValueKey('digital-signature-apply-pages'),
                      onPressed: _chooseApplyPages,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('Apply to pages…'),
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
                  onClearSignature: _signaturePng == null
                      ? null
                      : () => setState(() => _signaturePng = null),
                  onClearLogo: _logoBytes == null
                      ? null
                      : () => setState(() => _logoBytes = null),
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
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('digital-signature-sign'),
          onPressed: canSign ? _submit : null,
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Sign'),
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
    required this.onClearSignature,
    required this.onClearLogo,
  });

  final Uint8List? signaturePng;
  final Uint8List? logoBytes;
  final String? signerName;
  final String? reason;
  final VoidCallback? onClearSignature;
  final VoidCallback? onClearLogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      if (signerName != null && signerName!.isNotEmpty)
        'Digitally signed by $signerName',
      'Date: ${MaterialLocalizations.of(context).formatFullDate(DateTime.now())}',
      if (reason != null && reason!.isNotEmpty) 'Reason: $reason',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF2E5E86)),
            borderRadius: BorderRadius.circular(4),
            image: logoBytes == null
                ? null
                : DecorationImage(
                    image: MemoryImage(logoBytes!),
                    fit: BoxFit.cover,
                    opacity: _signatureLogoOpacity),
          ),
          child: Row(children: [
            Expanded(
              child: Center(
                child: signaturePng != null
                    ? Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.memory(signaturePng!, fit: BoxFit.contain),
                      )
                    : Text(
                        signerName ?? 'Signer',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const VerticalDivider(color: Color(0xFF2E5E86), width: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in details)
                      Text(line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 8, color: Color(0xFF1A1A1A))),
                  ],
                ),
              ),
            ),
          ]),
        ),
        Row(children: [
          if (onClearSignature != null)
            TextButton(
                onPressed: onClearSignature,
                child: const Text('Remove signature')),
          if (onClearLogo != null)
            TextButton(onPressed: onClearLogo, child: const Text('Remove logo')),
        ]),
        Text('Preview - the signed box may differ slightly.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}
