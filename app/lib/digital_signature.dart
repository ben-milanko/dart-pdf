import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

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

  void _submit() {
    final keyless = _keyless;
    if (keyless != null) {
      Navigator.of(context).pop(DigitalSignatureOptions(
        keylessIdentity: keyless,
        timestampClient: widget.timestampClient,
        fieldName: _value(_fieldName),
        reason: _value(_reason),
        location: _value(_location),
        contactInfo: _value(_contact),
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
                'Add a certificate-backed PAdES signature. This is a '
                'cryptographic signature, separate from a drawn signature.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Choose an unencrypted RSA PKCS#1/PKCS#8 key and its X.509 '
                'certificate chain (PEM or DER). The key is used in memory '
                'only and is never saved by DartPDF.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
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
                    ? 'Choose certificate chain…'
                    : _certificateNames.join(', ')),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('or', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('digital-signature-create-identity'),
                onPressed: _createSelfSignedIdentity,
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Create a signing identity…'),
              ),
              const SizedBox(height: 6),
              Text(
                'No files needed. A self-signed identity reads as "signed, '
                'validity unknown" in Acrobat (like its own self-signed IDs); '
                'it is remembered in your device keychain.',
                style: theme.textTheme.bodySmall,
              ),
              if (widget.createKeylessIdentity != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
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
                      : 'Sign in with your email (keyless)…'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Verifies your email through Sigstore and signs with a '
                  'short-lived certificate plus a trusted timestamp. No key to '
                  'manage; the email is real, but (like every free option) it '
                  'reads as "validity unknown" in Acrobat.',
                  style: theme.textTheme.bodySmall,
                ),
              ] else if (widget.keylessUnavailable) ...[
                const SizedBox(height: 12),
                Text(
                  'Keyless email signing (sign in, no files) is available in '
                  'the DartPDF desktop and mobile apps. It can\'t run in a web '
                  'browser: the Sigstore sign-in service blocks cross-origin '
                  'browser requests.',
                  key: const ValueKey('digital-signature-keyless-web-note'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
