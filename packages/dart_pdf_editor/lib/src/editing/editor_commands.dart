import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../design/editor_presenter.dart';
import '../l10n/pdf_l10n.dart';
import '../pdf_editor_view.dart' show PdfEditorFeatures;
import '../pdf_viewer.dart';
import 'editing_color_pick.dart';
import 'editing_controller.dart';
import 'editing_measure.dart';
import 'editing_preferences.dart';
import 'editing_signature.dart';
import 'editing_tool_catalog.dart';
import 'models/panel_dock.dart';
import 'tool_shortcuts.dart';

/// An armable tool choice: an editing [tool], or a text-[markup] kind. Both
/// null is Hand (plain reader) mode.
typedef PdfToolChoice = ({PdfEditTool? tool, PdfMarkupKind? markup});

/// Which part of the editor a [PdfCommand] belongs to - what a command
/// palette shows as its source and what a host filters on.
enum PdfCommandCategory {
  /// Arms an editing tool or a text-markup kind.
  tool,

  /// Shows or hides a dockable panel.
  panel,

  /// A view option or view mode.
  view,

  /// A document action - save, save as.
  document,

  /// Anything a host adds.
  custom,
}

/// One thing the editor can do, described as data: what to call it, how to
/// draw it, whether it applies right now and how to run it.
///
/// [PdfEditorCommands.catalog] lists the editor's own; a host builds its own
/// to put in a tool group ([PdfToolEntry.command]) or next to the stock ones
/// in a command palette or menu. [label], [icon] and [invoke] are the only
/// required parts.
@immutable
class PdfCommand {
  const PdfCommand({
    required this.id,
    required this.icon,
    required this.label,
    required this.invoke,
    this.tooltip,
    this.shortcut,
    this.shortcutLabel,
    this.enabled = PdfCommand.alwaysEnabled,
    this.selected = PdfCommand.neverSelected,
    this.category = PdfCommandCategory.custom,
    this.toolGroup,
  });

  /// A stable identity, e.g. `tool-rectangle`, `panel-search` or `save`.
  final String id;

  final IconData icon;

  /// The localized name.
  final String Function(BuildContext context) label;

  /// A fuller hover hint; null falls back to [label].
  final String Function(BuildContext context)? tooltip;

  /// The key that runs this command where the editor binds it, if any.
  final ShortcutActivator? shortcut;

  /// A display form of [shortcut] (`R`, `⇧L`), when there is one.
  final String? shortcutLabel;

  /// Whether the command can run now.
  final ValueListenable<bool> enabled;

  /// Whether the command's state is on: an armed tool, a visible panel, the
  /// current view mode.
  final ValueListenable<bool> selected;

  final PdfCommandCategory category;

  /// The dock group a [PdfCommandCategory.tool] command comes from.
  final PdfToolGroup? toolGroup;

  /// Runs the command. [context] is where any prompt it needs opens (the
  /// measuring scale, a signature) - any context under the app's
  /// [Navigator] and localizations.
  final Future<void> Function(BuildContext context) invoke;

  /// [tooltip], or [label] when there is none.
  String tooltipOf(BuildContext context) => (tooltip ?? label).call(context);

  /// A listenable that is always true - the default [enabled].
  static const ValueListenable<bool> alwaysEnabled = _ConstantFlag(true);

  /// A listenable that is always false - the default [selected].
  static const ValueListenable<bool> neverSelected = _ConstantFlag(false);

  @override
  String toString() => 'PdfCommand($id)';
}

class _ConstantFlag implements ValueListenable<bool> {
  const _ConstantFlag(this.value);

  @override
  final bool value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// A [ValueListenable] read off another [Listenable]: [value] is recomputed
/// on every read and listeners ride on [source].
class _DerivedFlag implements ValueListenable<bool> {
  _DerivedFlag(this.source, this.read);

  final Listenable source;
  final bool Function() read;

  @override
  bool get value => read();

  @override
  void addListener(VoidCallback listener) => source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);
}

class _RecentTools extends ChangeNotifier
    implements ValueListenable<List<PdfToolChoice>> {
  List<PdfToolChoice> _value = const [];

  @override
  List<PdfToolChoice> get value => _value;

  void set(List<PdfToolChoice> next, {bool notify = true}) {
    _value = List.unmodifiable(next);
    if (notify) notifyListeners();
  }

  void announce() => notifyListeners();
}

/// The editor's intents as one object: arm a tool (asking for whatever it
/// needs first), open a tool group, apply text markup or a colour, flatten,
/// and the recently used tools - what the stock [PdfEditingToolbar] runs and
/// what a host's own toolbar, menu, command palette or keyboard handler can
/// run too, with the same results.
///
/// [PdfEditorView] owns one and provides it to everything beneath it (pass
/// [PdfEditorView.commands] to own it yourself, e.g. to reach it from a
/// command palette above the editor). A standalone [PdfEditingToolbar]
/// shares the commands above it when they drive the same controller, and
/// otherwise owns its own. Find them with [PdfEditorCommands.of].
///
/// The prompts some commands need first - the measuring scale for a measure
/// tool, a drawn signature for the signature tool - open as the stock
/// Material dialogs for now, so they need a Material host.
class PdfEditorCommands extends ChangeNotifier {
  PdfEditorCommands({
    required PdfEditingController controller,
    required this.viewerController,
    List<PdfToolGroup> toolGroups = pdfToolGroups,
    this.preferences,
    this.viewMode,
    this.features,
    this.tools,
    this.toolShortcuts = pdfEditToolShortcuts,
    this.onSave,
    this.onSaveAs,
    this.saveEnabled,
  })  : _controller = controller,
        _toolGroups = toolGroups,
        _openGroupId = _restingGroupIdIn(toolGroups) {
    _resetRecentTools();
    controller.addListener(_trackRecentTool);
  }

  /// The commands provided above [context], or null.
  static PdfEditorCommands? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PdfEditorCommandsScope>()
      ?.commands;

  /// The commands provided above [context]: by [PdfEditorView], by a
  /// [PdfEditingToolbar] for its own subtree, or by a
  /// [PdfEditorCommandsScope] a host places itself.
  static PdfEditorCommands of(BuildContext context) {
    final commands = maybeOf(context);
    assert(
        commands != null,
        'No PdfEditorCommands above this context. They are provided by '
        'PdfEditorView, by PdfEditingToolbar for its subtree, or by a '
        'PdfEditorCommandsScope.');
    return commands!;
  }

  // ---- what the commands drive ------------------------------------------

  PdfEditingController _controller;
  List<PdfToolGroup> _toolGroups;
  bool _disposed = false;

  /// The edit session the commands drive.
  ///
  /// Swapping it (a new document) starts the recently used tools afresh but
  /// keeps the open tool group, as the stock toolbar always has.
  PdfEditingController get controller => _controller;
  set controller(PdfEditingController value) {
    if (identical(value, _controller)) return;
    _controller.removeListener(_trackRecentTool);
    _controller = value;
    _resetRecentTools(notify: false);
    value.addListener(_trackRecentTool);
    // A swap usually lands while a parent is building; tell listeners once
    // that build is over rather than from inside it.
    scheduleMicrotask(() {
      if (!_disposed) _recent.announce();
    });
  }

  /// The viewer whose text selection markup reads and whose selection tool
  /// changes clear.
  PdfViewerController viewerController;

  /// The tool groups, in dock order - the same list the toolbar shows.
  List<PdfToolGroup> get toolGroups => _toolGroups;
  set toolGroups(List<PdfToolGroup> value) {
    if (identical(value, _toolGroups)) return;
    final wasResting = _openGroupId == _restingGroupIdIn(_toolGroups);
    _toolGroups = value;
    if (wasResting) _openGroupId = _restingGroupIdIn(value);
  }

  /// The preferences the panel and view commands toggle. Null uses the
  /// session's own [PdfEditingController.preferences].
  PdfEditingPreferences? preferences;

  /// The live view mode the reflow and page-grid commands switch. Null
  /// leaves them out of [catalog].
  PdfViewModeHolder? viewMode;

  /// The editor surfaces that exist, which decides which panel and view
  /// commands [catalog] lists. Null - a toolbar without the stock shell -
  /// lists the tools only.
  PdfEditorFeatures? features;

  /// The editing tools [catalog] offers, null meaning all of them.
  Set<PdfEditTool>? tools;

  /// The tool key bindings [catalog] reports as each tool's shortcut.
  Map<PdfEditTool, PdfToolShortcut> toolShortcuts;

  /// Saves the document; [catalog] lists a Save command when set.
  VoidCallback? onSave;

  /// Saves the document elsewhere; [catalog] lists Save as when set.
  VoidCallback? onSaveAs;

  /// Whether Save can run now. Null means whenever the document has
  /// unsaved edits.
  bool Function()? saveEnabled;

  PdfEditingPreferences get _prefs => preferences ?? _controller.preferences;

  // ---- tool groups ------------------------------------------------------

  static String? _restingGroupIdIn(List<PdfToolGroup> groups) {
    for (final group in groups) {
      if (group.kind == PdfEditToolGroup.select) return group.id;
    }
    return 'select';
  }

  String? _openGroupId;

  /// Which group's strip is open when no group tool is armed (Select,
  /// Markup, Measure and Edit can be open with nothing armed). When a tool
  /// *is* armed, its group wins - see [currentGroupId].
  String? get openGroupId => _openGroupId;
  set openGroupId(String? value) {
    if (value == _openGroupId) return;
    _openGroupId = value;
    notifyListeners();
  }

  /// The group of the armed tool or markup kind, else the explicitly opened
  /// group.
  String? get currentGroupId => armedGroup?.id ?? _openGroupId;

  /// The group the armed tool or markup kind belongs to.
  PdfToolGroup? get armedGroup {
    final markup = _controller.markupTool;
    if (markup != null) return groupForMarkup(markup);
    return groupForTool(_controller.tool);
  }

  /// The group [tool] sits in, or null.
  PdfToolGroup? groupForTool(PdfEditTool? tool) {
    if (tool == null) return null;
    for (final group in _toolGroups) {
      for (final entry in group.tools) {
        if (entry.tool == tool) return group;
      }
    }
    return null;
  }

  /// The group [markup] sits in, or null.
  PdfToolGroup? groupForMarkup(PdfMarkupKind markup) {
    for (final group in _toolGroups) {
      for (final entry in group.tools) {
        if (entry.markup == markup) return group;
      }
    }
    return null;
  }

  /// Opens [group] and, when arming is side-effect-free, arms its
  /// [PdfToolGroup.defaultTool] so its settings are live immediately.
  /// Opening the open group again collapses back to Select; opening Select
  /// while Select is armed drops to plain-reader mode.
  void openGroup(PdfToolGroup group) {
    final navigation = group.kind == PdfEditToolGroup.select;
    if (currentGroupId == group.id && !navigation) {
      openGroupId = _restingGroupIdIn(_toolGroups);
      _controller.tool = PdfEditTool.select;
      return;
    }
    if (navigation && _controller.tool == PdfEditTool.select) {
      openGroupId = null;
      _controller.tool = null;
      return;
    }
    openGroupId = group.id;
    if (groupForTool(_controller.tool)?.id == group.id) return;
    _controller.tool = group.defaultTool;
    if (_controller.tool != null) viewerController.clearSelection();
    // markup arms no tool, so its style scope is set explicitly (after the
    // tool reset above, which would otherwise clear it) - this is what lets
    // the highlighter keep its own colour from the other tools'
    if (group.kind == PdfEditToolGroup.markup) {
      _controller.useMarkupStyleScope();
    }
  }

  /// Hand mode: no tool, pages pan.
  void activateHandMode() {
    if (_controller.isHandMode) return;
    openGroupId = null;
    _controller.activateHandMode();
    viewerController.clearSelection();
  }

  /// Select mode: pick, move and resize what is on the page.
  void activateSelectMode() {
    if (_controller.tool == PdfEditTool.select) return;
    openGroupId = _restingGroupIdIn(_toolGroups);
    _controller.tool = PdfEditTool.select;
    viewerController.clearSelection();
  }

  /// Disarms whatever tool or markup kind is armed, to plain-reader mode.
  void clearTool() {
    if (_controller.tool == null && _controller.markupTool == null) return;
    openGroupId = null;
    _controller.tool = null;
    viewerController.clearSelection();
  }

  // ---- tools ------------------------------------------------------------

  /// Arms [tool], first running what it needs: a measuring scale for the
  /// measure tools, a drawn signature for the signature tool. Already armed
  /// is a no-op. Returns whether [tool] is armed afterwards - false when a
  /// prompt was dismissed.
  Future<bool> armTool(BuildContext context, PdfEditTool tool) async {
    if (_controller.tool == tool) return true;
    await toggleTool(context, tool);
    return _controller.tool == tool;
  }

  /// The toolbar's tap: arms [tool] (with [armTool]'s prerequisites), or,
  /// when it is already armed, drops back to Select. Returns whether [tool]
  /// is armed afterwards.
  Future<bool> toggleTool(BuildContext context, PdfEditTool tool) async {
    switch (tool) {
      case PdfEditTool.measureDistance:
      case PdfEditTool.measurePerimeter:
      case PdfEditTool.measureArea:
      case PdfEditTool.measureVolume:
      case PdfEditTool.measureSlope:
      case PdfEditTool.measureAngle:
      case PdfEditTool.measureArc:
        await _toggleMeasureTool(context, tool);
      case PdfEditTool.signature:
        await _toggleSignatureTool(context);
      default:
        toggleToolNow(tool);
    }
    return _controller.tool == tool;
  }

  /// Toggles [tool] with no prerequisites: arms it, or drops back to Select
  /// when it is already armed - never to no tool at all, so tapping the
  /// active tool off leaves things selectable. Clears the text selection.
  void toggleToolNow(PdfEditTool tool) {
    _controller.tool = _controller.tool == tool ? PdfEditTool.select : tool;
    viewerController.clearSelection();
  }

  /// Arms the stamp tool for its picker menu (no toggle).
  void armStampTool() {
    if (_controller.tool == PdfEditTool.stamp) return;
    _controller.tool = PdfEditTool.stamp;
    viewerController.clearSelection();
  }

  Future<void> _toggleMeasureTool(
      BuildContext context, PdfEditTool tool) async {
    if (_controller.tool == tool) {
      _controller.tool = PdfEditTool.select;
      return;
    }
    if (!_controller.hasMeasurementScale) {
      await setMeasurementScale(context);
      if (!_controller.hasMeasurementScale) return;
    }
    toggleToolNow(tool);
  }

  Future<void> _toggleSignatureTool(BuildContext context) async {
    if (_controller.tool == PdfEditTool.signature) {
      _controller.tool = PdfEditTool.select;
      return;
    }
    final drawn = _controller.activeSavedSignature == null;
    if (drawn && !await drawSignature(context)) return;
    toggleToolNow(PdfEditTool.signature);
    // Arming the tool restores the signature style scope over whatever
    // drawSignature just seeded, so seed it again now the scope is live.
    if (drawn) {
      _seedSignatureStyle(_controller.activeSavedSignature!.signature);
    }
  }

  /// Asks for the measuring scale and stores it in the preferences.
  Future<void> setMeasurementScale(BuildContext context) async {
    final scale = await _promptMeasurementScale(context);
    if (scale != null) _controller.preferences.measurementScale = scale;
  }

  /// Asks for a drawn signature and saves it as the active one, styling the
  /// signature tool after it. Returns false when the pad was dismissed.
  Future<bool> drawSignature(BuildContext context) async {
    final signature = await _promptSignature(context);
    if (signature == null) return false;
    _controller.addSavedSignature(signature);
    _seedSignatureStyle(signature);
    return true;
  }

  /// Points the tool's colour and pen width at what [signature] was drawn
  /// with - the placed ink follows the toolbar, not the record, so this is
  /// what makes the stamp match the pad. Both stay editable afterwards.
  void _seedSignatureStyle(PdfInkSignature signature) {
    _controller.color = Color(0xFF000000 | signature.color);
    _controller.preferences.strokeWidth = signature.strokeWidth;
  }

  // ---- markup, colour, flatten -------------------------------------------

  /// Arms [kind] and, when text is selected in the viewer, marks it up
  /// straight away and clears the selection.
  void applyMarkup(PdfMarkupKind kind) {
    _controller.markupTool = kind;
    if (!viewerController.hasSelection) return;
    markupSelection(kind);
    viewerController.clearSelection();
  }

  /// Marks the viewer's current text selection up as [kind], without arming
  /// anything.
  void markupSelection(PdfMarkupKind kind) {
    // capture before the edit: the document swap clears the selection
    final quadsByPage = {
      for (final page in viewerController.selectionPages)
        page: viewerController.selectionRectsOn(page),
    };
    _controller.addMarkup(kind, quadsByPage);
  }

  /// Sets the creation colour - and recolours the selection in place when
  /// the whole selection restyles (selected text in an open text box, or the
  /// selected annotations).
  void applyColor(Color color) {
    _controller.color = color;
    if (_controller.restyleEditingTextSelection(
        color: color.toARGB32() & 0xFFFFFF)) {
      return;
    }
    if (_controller.canRestyleSelected) {
      _controller.restyleSelected(color: color);
    }
  }

  /// Flattens every annotation into page content, with a notice that offers
  /// Undo.
  void flatten(BuildContext context) {
    final flattened = _controller.flattenDocument();
    showUndoNotice(
      context,
      flattened
          ? pdfL10n(context).tbAnnotationsFlattened
          : pdfL10n(context).tbNoAnnotationsToFlatten,
      undoable: flattened,
    );
  }

  /// Flattens every form field into page content, with a notice that offers
  /// Undo.
  void flattenFormFields(BuildContext context) {
    final flattened = _controller.flattenFormFields();
    showUndoNotice(
      context,
      flattened
          ? pdfL10n(context).tbFormFieldsFlattened
          : pdfL10n(context).tbNoFormFieldsToFlatten,
      undoable: flattened,
    );
  }

  /// Shows [message] as a transient notice, with Undo when [undoable] and
  /// there is something to undo.
  void showUndoNotice(BuildContext context, String message,
      {required bool undoable}) {
    _showNotice(context, message,
        onUndo: undoable && _controller.canUndo ? _controller.undo : null);
  }

  // ---- prompts ----------------------------------------------------------
  //
  // Every prompt and notice the commands raise goes through the nearest
  // [PdfEditorPresenter] (see [PdfEditorScope]).

  Future<PdfMeasurementScale?> _promptMeasurementScale(BuildContext context) {
    final presenter = PdfEditorPresenter.of(context);
    return presenter.measurementScale(
      context,
      PdfMeasurementScaleRequest(
        initial: _controller.preferences.measurementScale,
        onCalibrate: () {
          _controller.tool = PdfEditTool.calibrate;
          if (!context.mounted) return;
          presenter.notice(
            context,
            PdfEditorNotice(
              pdfL10n(context).tbCalibrateScaleHint,
              replaceCurrent: false,
              placement: PdfNoticePlacement.attached,
            ),
          );
        },
      ),
    );
  }

  Future<PdfInkSignature?> _promptSignature(BuildContext context) =>
      PdfEditorPresenter.of(context).signature(
        context,
        PdfSignatureRequest(
          initialColor: _controller.color,
          initialStrokeWidth: _controller.preferences.strokeWidth,
          // the signature dialog is modal over the page, so the picker it
          // opens has no page to sample: no eyedropper there
          pickColor: (context, initial) => pickEditingColor(
              context, _controller,
              initial: initial, fromPage: false),
        ),
      );

  void _showNotice(BuildContext context, String message,
      {VoidCallback? onUndo}) {
    PdfEditorPresenter.of(context).notice(
      context,
      PdfEditorNotice(message, onUndo: onUndo),
    );
  }

  // ---- recently used tools ------------------------------------------------

  final _recent = _RecentTools();
  PdfToolChoice? _lastObservedTool;

  /// The armed tool or markup kind.
  PdfToolChoice get activeTool => _controller.markupTool != null
      ? (tool: null, markup: _controller.markupTool)
      : (tool: _controller.tool, markup: null);

  /// Every tool and markup kind armed this session, most recent first, the
  /// armed one included. Hand mode is never recorded. Swapping [controller]
  /// starts it afresh.
  ValueListenable<List<PdfToolChoice>> get recentTools => _recent;

  void _resetRecentTools({bool notify = true}) {
    final choice = activeTool;
    _lastObservedTool = choice;
    _recent.set([
      if (choice.tool != null || choice.markup != null) choice,
    ], notify: notify);
  }

  void _trackRecentTool() {
    final choice = activeTool;
    if (choice == _lastObservedTool) return;
    _lastObservedTool = choice;
    // Null is Hand/reader mode rather than Select. Temporary null transitions
    // while changing tools must not displace genuine history.
    if (choice.tool == null && choice.markup == null) return;
    _recent.set([
      choice,
      for (final previous in _recent.value)
        if (previous != choice) previous,
    ]);
  }

  // ---- catalog ----------------------------------------------------------

  /// Everything this editor can do, as [PdfCommand]s: its tools and markup
  /// kinds (in [toolGroups] order, filtered by [tools] and [features]), then
  /// - when [features] says the stock shell is around - its panels and view
  /// options, the view modes when [viewMode] is set, and Save / Save as when
  /// [onSave] / [onSaveAs] are.
  ///
  /// Tool commands arm through [armTool], so a measure tool asks for its
  /// scale and the signature tool for a signature exactly as the toolbar
  /// does. Every entry reads live state: build the list when it is needed,
  /// not once.
  List<PdfCommand> catalog(BuildContext context) {
    final features = this.features;
    final controller = _controller;
    final prefs = _prefs;
    final markupOn = features == null ||
        (features.markup &&
            (features.toolGroups?.contains(PdfEditToolGroup.markup) ?? true));
    bool groupOn(PdfToolGroup group) {
      final kind = group.kind;
      return features?.toolGroups == null ||
          kind == null ||
          features!.toolGroups!.contains(kind);
    }

    final commands = <PdfCommand>[];
    for (final group in _toolGroups) {
      if (!groupOn(group)) continue;
      for (final entry in group.tools) {
        final tool = entry.tool;
        final markup = entry.markup;
        final command = entry.command;
        if (command != null) {
          commands.add(command);
        } else if (tool != null) {
          if (!(tools?.contains(tool) ?? true)) continue;
          if (!(features?.tools?.contains(tool) ?? true)) continue;
          final key = toolShortcuts[tool];
          commands.add(PdfCommand(
            id: 'tool-${tool.name}',
            icon: entry.icon,
            label: entry.label,
            tooltip: entry.tooltip,
            shortcut: key?.activator,
            shortcutLabel: key?.label,
            category: PdfCommandCategory.tool,
            toolGroup: group,
            selected: _DerivedFlag(controller, () => controller.tool == tool),
            invoke: (context) => armTool(context, tool),
          ));
        } else if (markup != null && markupOn) {
          commands.add(PdfCommand(
            id: 'markup-${markup.name}',
            icon: entry.icon,
            label: entry.label,
            tooltip: entry.tooltip,
            category: PdfCommandCategory.tool,
            toolGroup: group,
            selected:
                _DerivedFlag(controller, () => controller.markupTool == markup),
            invoke: (context) async => applyMarkup(markup),
          ));
        }
      }
    }
    if (features == null) return commands;

    PdfCommand toggle(
      String id,
      IconData icon,
      String Function(BuildContext) label,
      PdfCommandCategory category,
      bool Function() read,
      void Function(bool) write,
    ) =>
        PdfCommand(
          id: id,
          icon: icon,
          label: label,
          category: category,
          selected: _DerivedFlag(prefs, read),
          invoke: (context) async => write(!read()),
        );

    String panelLabel(BuildContext context, PdfDockablePanel panel) =>
        panel.label(context);
    const panel = PdfCommandCategory.panel;
    if (features.searchResultsPanel) {
      commands.add(toggle(
          'panel-search',
          PdfDockablePanel.search.icon,
          (c) => panelLabel(c, PdfDockablePanel.search),
          panel,
          () => prefs.showSearchResultsPanel,
          (v) => prefs.showSearchResultsPanel = v));
    }
    if (features.thumbnails) {
      commands.add(toggle(
          'panel-pages',
          PdfDockablePanel.thumbnails.icon,
          (c) => panelLabel(c, PdfDockablePanel.thumbnails),
          panel,
          () => prefs.showThumbnailSidebar,
          (v) => prefs.showThumbnailSidebar = v));
    }
    if (features.bookmarks) {
      commands.add(toggle(
          'panel-bookmarks',
          PdfDockablePanel.bookmarks.icon,
          (c) => panelLabel(c, PdfDockablePanel.bookmarks),
          panel,
          () => prefs.showBookmarkSidebar,
          (v) => prefs.showBookmarkSidebar = v));
    }
    if (features.annotationSidebar) {
      commands.add(toggle(
          'panel-annotations',
          PdfDockablePanel.annotations.icon,
          (c) => panelLabel(c, PdfDockablePanel.annotations),
          panel,
          () => prefs.showAnnotationSidebar,
          (v) => prefs.showAnnotationSidebar = v));
    }
    if (features.annotationLibrary) {
      commands.add(toggle(
          'panel-annotation-library',
          PdfDockablePanel.annotationLibrary.icon,
          (c) => panelLabel(c, PdfDockablePanel.annotationLibrary),
          panel,
          () => prefs.showAnnotationLibraryPanel,
          (v) => prefs.showAnnotationLibraryPanel = v));
    }
    if (features.propertiesPanel) {
      commands.add(toggle(
          'panel-properties',
          PdfDockablePanel.properties.icon,
          (c) => panelLabel(c, PdfDockablePanel.properties),
          panel,
          () => prefs.showPropertiesPanel,
          (v) => prefs.showPropertiesPanel = v));
    }

    const view = PdfCommandCategory.view;
    if (features.viewOptions) {
      commands.add(toggle(
          'view-annotations',
          _visibilityOutlined,
          (c) => pdfL10n(c).shellShowAnnotations,
          view,
          () => prefs.showAnnotations,
          (v) => prefs.showAnnotations = v));
    }
    final mode = viewMode;
    if (mode != null) {
      // Reflow and the page grid each replace the page viewer, so they go
      // through the view mode rather than their own flags: turning one on
      // clears the other, and turning one off lands on plain pages.
      PdfCommand modeToggle(String id, IconData icon,
              String Function(BuildContext) label, PdfViewMode target) =>
          PdfCommand(
            id: id,
            icon: icon,
            label: label,
            category: view,
            selected: _DerivedFlag(mode, () => mode.viewMode == target),
            invoke: (context) async => mode.viewMode =
                mode.viewMode == target ? PdfViewMode.pages : target,
          );
      if (features.reflowView) {
        commands.add(modeToggle('view-reflow', _articleOutlined,
            (c) => pdfL10n(c).shellReflowText, PdfViewMode.reflow));
      }
      if (features.thumbnails) {
        commands.add(modeToggle('view-page-grid', _gridViewOutlined,
            (c) => pdfL10n(c).shellPageGrid, PdfViewMode.pageGrid));
      }
    }
    if (features.viewOptions) {
      commands.add(toggle(
          'view-form-fields',
          _ballotOutlined,
          (c) => pdfL10n(c).shellHighlightFormFields,
          view,
          () => prefs.highlightFormFields,
          (v) => prefs.highlightFormFields = v));
      commands.add(toggle(
          'view-scrollbar-chapters',
          _toc,
          (c) => pdfL10n(c).shellShowScrollbarChapters,
          view,
          () => prefs.showScrollbarChapters,
          (v) => prefs.showScrollbarChapters = v));
    }

    final save = onSave;
    if (save != null) {
      final canSave = saveEnabled;
      commands.add(PdfCommand(
        id: 'save',
        icon: _saveAlt,
        label: (c) => pdfL10n(c).save,
        category: PdfCommandCategory.document,
        enabled: _DerivedFlag(
            controller, () => canSave?.call() ?? controller.isModified),
        invoke: (context) async => save(),
      ));
    }
    final saveAs = onSaveAs;
    if (saveAs != null) {
      commands.add(PdfCommand(
        id: 'save-as',
        icon: _saveAsOutlined,
        label: (c) => pdfL10n(c).commandSaveAs,
        category: PdfCommandCategory.document,
        invoke: (context) async => saveAs(),
      ));
    }
    return commands;
  }

  // Material Icons glyphs as plain const IconData (the same values as
  // Icons.visibility_outlined, Icons.article_outlined, Icons.grid_view_outlined,
  // Icons.ballot_outlined, Icons.toc, Icons.save_alt and Icons.save_as_outlined),
  // so this file stays on the widgets layer.
  static const _visibilityOutlined =
      IconData(0xf4a1, fontFamily: 'MaterialIcons');
  static const _articleOutlined = IconData(0xee93, fontFamily: 'MaterialIcons');
  static const _gridViewOutlined =
      IconData(0xf0d7, fontFamily: 'MaterialIcons');
  static const _ballotOutlined = IconData(0xeebb, fontFamily: 'MaterialIcons');
  static const _toc =
      IconData(0xe669, fontFamily: 'MaterialIcons', matchTextDirection: true);
  static const _saveAlt = IconData(0xe551, fontFamily: 'MaterialIcons');
  static const _saveAsOutlined = IconData(0xf065a, fontFamily: 'MaterialIcons');

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_trackRecentTool);
    _recent.dispose();
    super.dispose();
  }
}

/// Provides [commands] to the subtree, for [PdfEditorCommands.of].
///
/// [PdfEditorView] and a standalone [PdfEditingToolbar] place one
/// themselves; a host that builds its own editor layout around a
/// [PdfViewer] can place one above both so the viewer's tool shortcuts and
/// the host's controls share the same commands.
class PdfEditorCommandsScope extends InheritedWidget {
  const PdfEditorCommandsScope({
    super.key,
    required this.commands,
    required super.child,
  });

  final PdfEditorCommands commands;

  @override
  bool updateShouldNotify(PdfEditorCommandsScope oldWidget) =>
      !identical(commands, oldWidget.commands);
}
