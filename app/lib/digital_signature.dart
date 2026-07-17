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

/// Everything the app needs to add one approval signature. Exactly one of
/// [identity] (a bring-your-own RSA key + chain) or [selfSignedIdentity] (a
/// one-tap self-signed P-256 identity) is set. Either way the private key is
/// only used in memory when signing; a self-signed identity may also be kept
/// in the platform keychain via [SecureIdentityStore].
class DigitalSignatureOptions {
  const DigitalSignatureOptions({
    this.identity,
    this.selfSignedIdentity,
    this.fieldName,
    this.reason,
    this.location,
    this.contactInfo,
  }) : assert((identity == null) != (selfSignedIdentity == null),
            'exactly one identity kind must be provided');

  /// A bring-your-own RSA/X.509 identity from files, or null for a self-signed
  /// signature.
  final PdfDigitalSignatureIdentity? identity;

  /// A one-tap self-signed P-256 identity, or null for a file-based signature.
  final PdfSigningIdentity? selfSignedIdentity;

  final String? fieldName;
  final String? reason;
  final String? location;
  final String? contactInfo;

  /// The signer name to show, regardless of which identity kind is set.
  String? get signerName =>
      identity?.signerName ?? selfSignedIdentity?.name;
}

Future<DigitalSignatureOptions?> showDigitalSigningDialog(
  BuildContext context, {
  DigitalSignaturePrivateKeyPicker? privateKeyPicker,
  DigitalSignatureCertificatePicker? certificatePicker,
  PdfIdentityStore? identityStore,
  SelfSignedIdentityCreator? createSelfSignedIdentity,
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
  });

  final DigitalSignaturePrivateKeyPicker privateKeyPicker;
  final DigitalSignatureCertificatePicker certificatePicker;
  final PdfIdentityStore identityStore;
  final SelfSignedIdentityCreator createSelfSignedIdentity;

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
    _selfSigned = null; // an explicit file selection supersedes self-signed
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
    final canSign = identity != null || selfSigned != null;
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
