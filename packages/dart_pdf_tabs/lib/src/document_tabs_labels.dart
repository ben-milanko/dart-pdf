/// The user-facing strings the tab widgets show, so a host can pass its own
/// localizations. The defaults are English.
class DocumentTabsLabels {
  const DocumentTabsLabels({
    this.untitled = 'Untitled',
    this.closeTab = 'Close tab',
    this.openTab = 'Open in new tab',
    this.viewAllTabs = 'View all tabs',
    this.openTabs = 'Open tabs',
    this.tabs = 'Tabs',
    this.selectTabs = 'Select tabs',
    this.searchTabs = 'Search tabs',
    this.clearTabSearch = 'Clear search',
    this.noMatchingTabs = 'No matching tabs',
    this.closeSelectedTabs = 'Close selected tabs',
    this.tabsOpenCount = defaultTabsOpenCount,
  });

  /// Shown in place of an empty title.
  final String untitled;

  /// Tooltip of a tab's close button.
  final String closeTab;

  /// Tooltip of the strip's and the overview's add button.
  final String openTab;

  /// Tooltip of the strip's button that opens the overview.
  final String viewAllTabs;

  /// Tooltip of [DocumentTabsButton], the compact layout's tabs badge.
  final String openTabs;

  /// The overview's heading.
  final String tabs;

  /// Tooltip of the overview's button that starts a multi-select.
  final String selectTabs;

  /// Hint of the overview's search field.
  final String searchTabs;

  /// Tooltip of the button that clears the overview's search.
  final String clearTabSearch;

  /// Shown when the overview's search matches nothing.
  final String noMatchingTabs;

  /// Tooltip of the overview's close action while selecting.
  final String closeSelectedTabs;

  /// The overview's footer, for [count] open tabs.
  final String Function(int count) tabsOpenCount;

  /// The default [tabsOpenCount]: `1 tab open`, `3 tabs open`.
  static String defaultTabsOpenCount(int count) =>
      count == 1 ? '1 tab open' : '$count tabs open';
}
