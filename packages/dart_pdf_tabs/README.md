# dart_pdf_tabs

Browser-style document tabs for Flutter, extracted from the DartPDF app. The
widgets know nothing about PDFs: they draw any tab type you give them, so any
multi-document app can use them.

- **`DocumentTabs<T>`** - the tab set: strip order, the active tab, reorder,
  sort by name (natural, numeric-aware), replace-in-place, and disposal of a
  removed tab after the frame that unmounts it. Every change notifies.
- **`DocumentTabStrip<T>`** + **`DocumentTabStripController`** - a
  Chrome-style strip. Tabs share the width equally between a minimum and a
  maximum and scroll past that. Narrow inactive tabs drop their close
  button. While the pointer stays on the strip, a run of closes holds the
  remaining tabs at their width. Tabs drag to reorder (a mouse drags at
  once, touch after a long-press), a secondary click opens a context menu,
  and each title is middle-ellipsized with an unsaved-changes dot. The strip
  can also show a drop slot for a tab dragged in from elsewhere.
- **`DocumentTabsOverview<T>`** + **`DocumentTabTile`** - a searchable grid of
  every open tab that opens scrolled to the active one, with a multi-select
  to share or close several tabs at once. Show it in a bottom sheet on a
  phone or a dialog on desktop.
- **`DocumentTabsButton`** - the compact layout's tabs badge.
- **`MiddleEllipsisText`** - a one-line label that truncates in the middle,
  so a file name keeps its start and its extension.

All strings come from `DocumentTabsLabels` (English defaults), so you can pass
your own localizations.

## Use

```dart
class OpenFile with DocumentTabEntry {
  OpenFile(this.title);

  @override
  final String title;
}

final tabs = DocumentTabs<OpenFile>();
final strip = DocumentTabStripController();

ListenableBuilder(
  listenable: tabs,
  builder: (context, _) => DocumentTabStrip<OpenFile>(
    tabs: tabs.tabs,
    activeIndex: tabs.activeIndex,
    controller: strip,
    titleOf: (file) => file.title,
    onActivate: tabs.activate,
    onClose: (i) {
      strip.holdWidthForClose(); // Chrome-style close streak
      tabs.remove([tabs[i]]);
    },
    onReorder: tabs.reorder,
    onAdd: pickAndOpen,
  ),
);
```

`tabBuilder` wraps each tab's chrome for extras like hover previews or a
cross-window drag source. `externalGapIndex` and `insertionIndex` show a
dragged-in tab's drop slot, and `DocumentTabStripController.insertionIndexAt`
maps a pointer position to that slot.
