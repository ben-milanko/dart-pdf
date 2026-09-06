import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'signing_identity_store.dart';

/// Shows the "Create signing identity" dialog: the user enters a name (and
/// optionally an email and organization), and a self-signed P-256
/// [PdfSigningIdentity] is minted offline via [PdfSigningIdentity.generate].
///
/// When a [store] is given the identity is also persisted under its name (or
/// [storeId] when supplied), so it survives across sessions. Returns the new
/// identity, or null if the user cancels.
Future<PdfSigningIdentity?> showCreateSigningIdentityDialog(
  BuildContext context, {
  PdfIdentityStore? store,
  String? storeId,
}) =>
    showPdfDialog<PdfSigningIdentity>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: CreateSigningIdentityForm(store: store, storeId: storeId),
        ),
      ),
    );

/// The body of the create-identity dialog, exposed on its own so it can be
/// embedded (e.g. in a settings page) and tested without a [Dialog] host.
///
/// On submit it generates the identity, persists it to [store] (if any), and
/// calls [onCreated] - or, when hosted in a dialog, pops with the identity.
class CreateSigningIdentityForm extends StatefulWidget {
  const CreateSigningIdentityForm({
    super.key,
    this.store,
    this.storeId,
    this.onCreated,
  });

  /// Where to persist the new identity; null keeps it in memory only.
  final PdfIdentityStore? store;

  /// The id to store the identity under; defaults to the entered name.
  final String? storeId;

  /// Called with the freshly created identity. When null and the form is
  /// hosted in a dialog, the form pops the navigator with the identity.
  final ValueChanged<PdfSigningIdentity>? onCreated;

  @override
  State<CreateSigningIdentityForm> createState() =>
      _CreateSigningIdentityFormState();
}

class _CreateSigningIdentityFormState extends State<CreateSigningIdentityForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _organization = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _organization.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final identity = PdfSigningIdentity.generate(
        name: _name.text.trim(),
        email: _nonEmpty(_email.text),
        organization: _nonEmpty(_organization.text),
      );
      final store = widget.store;
      if (store != null) {
        await store.save(widget.storeId ?? identity.name!, identity);
      }
      if (!mounted) return;
      if (widget.onCreated != null) {
        widget.onCreated!(identity);
      } else {
        Navigator.of(context).pop(identity);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pdfL10n(context).signIdTitle,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: pdfL10n(context).signIdName,
                hintText: pdfL10n(context).signIdNameHint,
              ),
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? pdfL10n(context).signIdNameRequired
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _email,
              decoration:
                  InputDecoration(labelText: pdfL10n(context).signIdEmail),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _organization,
              decoration: InputDecoration(
                  labelText: pdfL10n(context).signIdOrganization),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pdfL10n(context).signIdSelfSignedInfo,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).maybePop(),
                  child: Text(pdfL10n(context).cancel),
                ),
                const SizedBox(width: 8),
                PdfDialogSubmit(
                    child: FilledButton(
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(pdfL10n(context).signIdCreate),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
