import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/compression_worker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf_document/pdf_document.dart';

import 'file_io.dart';
import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';

/// An injectable worker for the reduce-file-size dialog.
typedef PdfCompressionRunner = Future<PdfCompressionResult> Function(
  Uint8List bytes,
  PdfCompressionOptions options,
);

/// Runs optimisation off the UI thread on native platforms and the web.
Future<PdfCompressionResult> reducePdfBytes(
  Uint8List bytes,
  PdfCompressionOptions options,
) =>
    PdfCompressionTask.start(bytes, options: options).result;

/// Optimizes a fixed revision and offers a separate save dialog for its copy.
/// Closing/cancelling stops the worker. Neither a run
/// nor saving its result replaces the open document or its undo history.
Future<void> showReduceFileSizeDialog(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  required bool hasSignatures,
  required Future<SaveResult> Function(
    BuildContext context,
    Uint8List bytes,
    String suggestedName,
  ) saveCopy,
  PdfCompressionRunner? runner,
}) =>
    showPdfDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReduceFileSizeDialog(
        bytes: bytes,
        title: title,
        hasSignatures: hasSignatures,
        runner: runner,
        saveCopy: saveCopy,
      ),
    );

String reducedPdfFileName(String title) {
  var stem = title.trim();
  if (stem.toLowerCase().endsWith('.pdf')) {
    stem = stem.substring(0, stem.length - 4).trim();
  }
  return '${stem.isEmpty ? 'document' : stem}-reduced.pdf';
}

class _ReduceFileSizeDialog extends StatefulWidget {
  const _ReduceFileSizeDialog({
    required this.bytes,
    required this.title,
    required this.hasSignatures,
    required this.runner,
    required this.saveCopy,
  });

  final Uint8List bytes;
  final String title;
  final bool hasSignatures;
  final PdfCompressionRunner? runner;
  final Future<SaveResult> Function(BuildContext, Uint8List, String) saveCopy;

  @override
  State<_ReduceFileSizeDialog> createState() => _ReduceFileSizeDialogState();
}

class _ReduceFileSizeDialogState extends State<_ReduceFileSizeDialog> {
  PdfCompressionPreset _preset = PdfCompressionPreset.lossless;
  bool _custom = false;
  bool _recompress = true;
  bool _unused = true;
  bool _deduplicate = true;
  bool _subsetFonts = true;
  double? _dpi;
  int _quality = 85;
  bool _allowInvalidateSignatures = false;
  bool _running = false;
  bool _saving = false;
  PdfCompressionResult? _result;
  String? _error;
  PdfCompressionTask? _task;
  bool _closing = false;

  void _cancelWork() {
    _closing = true;
    _task?.cancel();
  }

  void _close() {
    _cancelWork();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _cancelWork();
    super.dispose();
  }

  void _setPreset(PdfCompressionPreset preset) {
    final options = preset.options;
    setState(() {
      _preset = preset;
      _custom = false;
      _recompress = options.recompressStreams;
      _unused = options.removeUnusedResources;
      _deduplicate = options.deduplicate;
      _subsetFonts = options.subsetFonts;
      _dpi = options.targetDpi;
      _quality = options.jpegQuality;
    });
  }

  Future<void> _run() async {
    final l10n = appL10n(context);
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      // Paint progress before copying the source buffer into its worker.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _closing) return;
      final options = PdfCompressionOptions(
        recompressStreams: _recompress,
        removeUnusedResources: _unused,
        deduplicate: _deduplicate,
        subsetFonts: _subsetFonts,
        targetDpi: _dpi,
        jpegQuality: _quality,
        allowInvalidateSignatures: _allowInvalidateSignatures,
      );
      final runner = widget.runner;
      final Future<PdfCompressionResult> pending;
      if (runner != null) {
        pending = runner(widget.bytes, options);
      } else {
        final task =
            _task = PdfCompressionTask.start(widget.bytes, options: options);
        pending = task.result;
      }
      final result = await pending;
      if (!mounted || _closing) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted || _closing) return;
      setState(() => _error = l10n.reduceSizeFailed(error.toString()));
    } finally {
      _task = null;
      if (mounted && !_closing) setState(() => _running = false);
    }
  }

  Future<void> _saveCopy() async {
    final l10n = appL10n(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.saveCopy(
        context,
        _result!.bytes,
        reducedPdfFileName(widget.title),
      );
      if (!mounted) return;
      if (saved.succeeded) {
        Navigator.of(context).pop();
      } else if (saved.message != null) {
        setState(() => _error = saved.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = l10n.reduceSizeSaveFailed(error.toString()));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    final result = _result;
    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancelWork();
      },
      child: AlertDialog(
        key: const ValueKey('reduce-size-dialog'),
        title: Text(l10n.reduceSizeTitle),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_running) ...[
                const LinearProgressIndicator(
                  key: ValueKey('reduce-size-progress'),
                ),
                const SizedBox(height: 16),
                Semantics(
                    liveRegion: true, child: Text(l10n.reduceSizeRunning)),
              ] else if (result != null)
                _report(l10n, result)
              else
                _settings(l10n),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const ValueKey('reduce-size-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('reduce-size-cancel'),
            onPressed: _saving ? null : _close,
            child: Text(result == null ? l10n.cancel : l10n.close),
          ),
          if (result != null) ...[
            TextButton(
              key: const ValueKey('reduce-size-settings'),
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _result = null;
                        _error = null;
                      }),
              child: Text(l10n.reduceSizeChangeSettings),
            ),
            PdfDialogSubmit(
                child: FilledButton(
              key: const ValueKey('reduce-size-save'),
              onPressed: _saving ? null : _saveCopy,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.reduceSizeSaveCopy),
            )),
          ] else if (!_running)
            PdfDialogSubmit(
                child: FilledButton(
              key: const ValueKey('reduce-size-run'),
              onPressed: widget.hasSignatures && !_allowInvalidateSignatures
                  ? null
                  : _run,
              child: Text(l10n.reduceSizeRun),
            )),
        ],
      ),
    );
  }

  Widget _settings(AppLocalizations l10n) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.reduceSizeDescription),
          const SizedBox(height: 16),
          InputDecorator(
            key: const ValueKey('reduce-size-preset'),
            decoration: InputDecoration(labelText: l10n.reduceSizePreset),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<PdfCompressionPreset>(
                value: _custom ? null : _preset,
                isExpanded: true,
                itemHeight: null,
                hint: Text(l10n.reduceSizeCustom),
                items: [
                  for (final preset in PdfCompressionPreset.values)
                    DropdownMenuItem(
                      value: preset,
                      child: Text(_presetLabel(l10n, preset)),
                    ),
                ],
                onChanged: (preset) {
                  if (preset != null) _setPreset(preset);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_dpi == null
              ? l10n.reduceSizeLosslessHint
              : l10n.reduceSizeLossyHint),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const ValueKey('reduce-size-advanced'),
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.reduceSizeAdvanced),
            children: [
              _toggle('streams', l10n.reduceSizeRecompress, _recompress,
                  (value) => _recompress = value),
              _toggle('resources', l10n.reduceSizeUnusedResources, _unused,
                  (value) => _unused = value),
              _toggle('duplicates', l10n.reduceSizeDeduplicate, _deduplicate,
                  (value) => _deduplicate = value),
              _toggle('fonts', l10n.reduceSizeSubsetFonts, _subsetFonts,
                  (value) => _subsetFonts = value),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                // Preset changes must reset the FormField's cached selection.
                key: ValueKey('reduce-size-dpi-$_dpi'),
                initialValue: _dpi ?? 0,
                isExpanded: true,
                isDense: false,
                decoration: InputDecoration(labelText: l10n.reduceSizeDpi),
                items: [
                  DropdownMenuItem(
                      value: 0, child: Text(l10n.reduceSizeKeepImages)),
                  for (final dpi in [72.0, 96.0, 150.0, 300.0, 600.0])
                    DropdownMenuItem(
                      value: dpi,
                      child: Text(l10n.imgExportDpiValue(dpi.toInt())),
                    ),
                ],
                onChanged: (value) =>
                    _customize(() => _dpi = value == 0 ? null : value),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(l10n.reduceSizeJpegQuality(_quality)),
              ),
              Slider(
                key: const ValueKey('reduce-size-jpeg-quality'),
                min: 10,
                max: 100,
                divisions: 90,
                value: _quality.toDouble(),
                label: '$_quality',
                onChanged: _dpi == null
                    ? null
                    : (value) => _customize(() => _quality = value.round()),
              ),
            ],
          ),
          if (widget.hasSignatures) ...[
            const SizedBox(height: 12),
            Text(l10n.reduceSizeSignaturesNotice),
            CheckboxListTile(
              key: const ValueKey('reduce-size-signature-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.reduceSizeInvalidateSignatures),
              value: _allowInvalidateSignatures,
              onChanged: (value) =>
                  setState(() => _allowInvalidateSignatures = value!),
            ),
          ],
        ],
      );

  Widget _toggle(
          String key, String label, bool value, ValueChanged<bool> update) =>
      CheckboxListTile(
        key: ValueKey('reduce-size-$key'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label),
        value: value,
        onChanged: (next) => _customize(() => update(next!)),
      );

  void _customize(VoidCallback update) => setState(() {
        _custom = true;
        update();
      });

  Widget _report(AppLocalizations l10n, PdfCompressionResult result) {
    final locale = Localizations.localeOf(context).toString();
    final number = NumberFormat.decimalPattern(locale);
    String size(int bytes) {
      if (bytes.abs() < 1024) return '${number.format(bytes)} B';
      final unit = bytes.abs() < 1024 * 1024 ? 'KiB' : 'MiB';
      final divisor = unit == 'KiB' ? 1024 : 1024 * 1024;
      return '${NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 1).format(bytes / divisor)} $unit';
    }

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(flex: 3, child: Text(label)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Text(value, textAlign: TextAlign.end)),
          ]),
        );

    return Column(
      key: const ValueKey('reduce-size-report'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(l10n.reduceSizeBefore, size(result.bytesBefore)),
        row(l10n.reduceSizeAfter, size(result.bytesAfter)),
        row(
          l10n.reduceSizeSavings,
          '${size(result.bytesSaved)} (${NumberFormat.percentPattern(locale).format(result.savingsFraction)})',
        ),
        if (result.bytesSaved == 0) ...[
          const SizedBox(height: 8),
          Text(l10n.reduceSizeNoSavings),
        ],
        if (result.steps.isNotEmpty) ...[
          const Divider(height: 24),
          Text(l10n.reduceSizeReportHint),
          for (final step in result.steps)
            row(_stepLabel(l10n, step.kind), size(step.bytesSaved)),
        ],
        for (final warning in result.warnings) ...[
          const SizedBox(height: 8),
          Text(warning),
        ],
      ],
    );
  }
}

String _presetLabel(AppLocalizations l10n, PdfCompressionPreset preset) =>
    switch (preset) {
      PdfCompressionPreset.lossless => l10n.reduceSizeLossless,
      PdfCompressionPreset.screen => l10n.reduceSizeScreen,
      PdfCompressionPreset.ebook => l10n.reduceSizeEbook,
      PdfCompressionPreset.printer => l10n.reduceSizePrinter,
    };

String _stepLabel(AppLocalizations l10n, PdfCompressionKind kind) =>
    switch (kind) {
      PdfCompressionKind.structure => l10n.reduceSizeStructure,
      PdfCompressionKind.resources => l10n.reduceSizeResources,
      PdfCompressionKind.fonts => l10n.reduceSizeFonts,
      PdfCompressionKind.images => l10n.reduceSizeImages,
      PdfCompressionKind.duplicates => l10n.reduceSizeDuplicates,
    };
