import 'package:material_ui/material_ui.dart';

import 'document_tabs_labels.dart';

/// The compact layout's stand-in for a [DocumentTabStrip]: a tab icon badged
/// with the number of open tabs, which a host wires to its tabs overview.
class DocumentTabsButton extends StatelessWidget {
  const DocumentTabsButton({
    super.key,
    required this.count,
    required this.onPressed,
    this.labels = const DocumentTabsLabels(),
  });

  /// How many tabs are open.
  final int count;
  final VoidCallback? onPressed;
  final DocumentTabsLabels labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: const ValueKey('mobile-tabs-button'),
        tooltip: labels.openTabs,
        icon: Badge(
          label: Text('$count', key: const ValueKey('mobile-tabs-count')),
          child: const Icon(Icons.tab_outlined),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
