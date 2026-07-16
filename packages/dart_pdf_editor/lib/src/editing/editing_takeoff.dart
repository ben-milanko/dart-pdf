import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_controller.dart';

/// A compact takeoff register: the per-tool running totals over the live
/// document, one row per measurement group (bucketed by /Takeoff label),
/// with its kind, item count, and accumulated real-world total.
///
/// Pure read-side: it listens to the [controller] and rebuilds
/// [PdfTakeoffSummary] on every revision (cheap - one annotation walk), so
/// it always mirrors the current document, including after undo/redo. Drop
/// it beside the viewer or in a bottom sheet:
///
/// ```dart
/// PdfTakeoffPanel(controller: editing)
/// ```
class PdfTakeoffPanel extends StatelessWidget {
  const PdfTakeoffPanel({super.key, required this.controller, this.title});

  final PdfEditingController controller;

  /// Optional header text; defaults to "Takeoff".
  final String? title;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final summary = controller.takeoffSummary;
        final groups = summary.groups;
        // format running totals through the active scale so they match the
        // on-page captions (200 ft² not 200.00 ft²).
        final measure = controller.measurementScale?.toMeasure();
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(title ?? 'Takeoff',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (groups.isNotEmpty)
                    Text('${groups.length} groups',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text('No measurements yet.'),
              )
            else
              ListView.separated(
                key: const ValueKey('pdf-takeoff-list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groups.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final g = groups[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(_iconFor(g.kind), size: 20),
                    title: Text(g.label),
                    subtitle: Text(_kindLabel(g.kind)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(g.formattedTotal(measure),
                            style: theme.textTheme.titleSmall),
                        Text('${g.count} item${g.count == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              ),
            if (groups.isNotEmpty) const Divider(height: 1),
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (summary.totalCount > 0)
                      _Chip(label: 'Count', value: '${summary.totalCount}'),
                    if (summary.totalLength > 0)
                      _Chip(
                          label: 'Length',
                          value: summary.totalLength.toStringAsFixed(1)),
                    if (summary.totalArea > 0)
                      _Chip(
                          label: 'Area',
                          value: summary.totalArea.toStringAsFixed(1)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static IconData _iconFor(PdfMeasurementKind kind) => switch (kind) {
        PdfMeasurementKind.count => Icons.tag,
        PdfMeasurementKind.distance => Icons.straighten,
        PdfMeasurementKind.perimeter => Icons.timeline,
        PdfMeasurementKind.area => Icons.crop_square,
        PdfMeasurementKind.areaCutout => Icons.crop_din,
        PdfMeasurementKind.volume => Icons.view_in_ar,
        PdfMeasurementKind.angle => Icons.architecture,
        PdfMeasurementKind.arc => Icons.gesture,
        PdfMeasurementKind.slope => Icons.trending_up,
      };

  static String _kindLabel(PdfMeasurementKind kind) => switch (kind) {
        PdfMeasurementKind.count => 'Count',
        PdfMeasurementKind.distance => 'Length',
        PdfMeasurementKind.perimeter => 'Perimeter',
        PdfMeasurementKind.area => 'Area',
        PdfMeasurementKind.areaCutout => 'Net area',
        PdfMeasurementKind.volume => 'Volume',
        PdfMeasurementKind.angle => 'Angle',
        PdfMeasurementKind.arc => 'Arc',
        PdfMeasurementKind.slope => 'Slope',
      };
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
