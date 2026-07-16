import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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

/// Everything the app needs to add one approval signature. The private key is
/// retained only by [identity] in memory and is never persisted by the app.
class DigitalSignatureOptions {
  const DigitalSignatureOptions({
    required this.identity,
    this.fieldName,
    this.reason,
    this.location,
    this.contactInfo,
  });

  final PdfDigitalSignatureIdentity identity;
  final String? fieldName;
  final String? reason;
  final String? location;
  final String? contactInfo;
}

Future<DigitalSignatureOptions?> showDigitalSigningDialog(
  BuildContext context, {
  DigitalSignaturePrivateKeyPicker? privateKeyPicker,
  DigitalSignatureCertificatePicker? certificatePicker,
}) =>
    showDialog<DigitalSignatureOptions>(
      context: context,
      builder: (context) => DigitalSignatureDialog(
        privateKeyPicker: privateKeyPicker ?? _pickPrivateKey,
        certificatePicker: certificatePicker ?? _pickCertificates,
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
  });

  final DigitalSignaturePrivateKeyPicker privateKeyPicker;
  final DigitalSignatureCertificatePicker certificatePicker;

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
  String? _error;

  @override
  void dispose() {
    _fieldName.dispose();
    _reason.dispose();
    _location.dispose();
    _contact.dispose();
    super.dispose();
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
          onPressed: identity == null ? null : _submit,
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Sign'),
        ),
      ],
    );
  }
}
