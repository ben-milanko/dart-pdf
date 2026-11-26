/// Browser-style document tabs: the tab-set model, a Chrome-style tab strip,
/// and a searchable tabs overview.
///
/// The widgets are agnostic about what a tab holds - a host keeps its own tab
/// type (implementing [DocumentTabEntry]) in a [DocumentTabs] and hands the
/// strip and overview the strings and callbacks they need.
library;

export 'src/document_tab_drag_start_listener.dart';
export 'src/document_tab_strip.dart';
export 'src/document_tab_tile.dart';
export 'src/document_tabs.dart';
export 'src/document_tabs_button.dart';
export 'src/document_tabs_labels.dart';
export 'src/document_tabs_overview.dart';
export 'src/middle_ellipsis_text.dart';
