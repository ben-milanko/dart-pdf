import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfLineEnding, PdfStandardFont, PdfTextAlign;
import 'package:shared_preferences/shared_preferences.dart';

import '../viewport.dart';
import 'editing_color_picker.dart' show PdfColorFormat;
import 'editing_panel.dart' show PdfDockablePanel, PdfPanelDock;
import 'line_style.dart';
import 'editing_measure.dart';
import 'saved_annotation.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';

/// Editing-UI preferences, persisted on the local device.
///
/// Every [PdfEditingController] creates one by default, so tool styles
/// (color, stroke width, opacity, font size) and the stylus mode come
/// back the way the user left them, in this session and the next.
/// Panel visibility ([showThumbnailSidebar], [showBookmarkSidebar],
/// [showAnnotationSidebar]) lives here too for the host's chrome - pass
/// one instance to both the
/// controller and the surrounding scaffold:
///
/// ```dart
/// final prefs = PdfEditingPreferences();
/// // later, per document:
/// final editing = PdfEditingController(bytes, preferences: prefs);
/// ```
///
/// Values load asynchronously ([ready]); each change is written back
/// immediately. Where no local storage exists - plain widget tests, for
/// example - loading fails silently and the defaults stand.
class PdfEditingPreferences extends ChangeNotifier {
  PdfEditingPreferences() {
    _ready = _load();
  }

  static const _prefix = 'dart_pdf_editor.editing.';

  SharedPreferences? _store;
  late final Future<void> _ready;
  bool _modified = false;

  /// Completes once stored values have been applied - or storage turned
  /// out to be unavailable and the defaults stand.
  Future<void> get ready => _ready;

  Color _color = const Color(0xFFE53935);
  double _strokeWidth = 2;
  double _cornerRadius = 0;
  double _eraserRadius = 8;
  bool _showVerticalCursorGuide = false;
  bool _showHorizontalCursorGuide = false;
  bool _showSnapGrid = false;
  bool _snapToGrid = false;
  double _gridSpacing = 10;
  double _fontSize = 14;
  PdfStandardFont _fontFamily = PdfStandardFont.helvetica;
  PdfTextAlign? _textAlign;
  double _opacity = 1;
  PdfLineStyle _lineStyle = PdfLineStyle.solid;
  double _lineScale = 1;
  PdfLineEnding _lineStartEnding = PdfLineEnding.none;
  PdfLineEnding _lineEndEnding = PdfLineEnding.none;
  bool _fingerDrawsInk = true;
  bool _showThumbnailSidebar = true;
  bool _hasShowThumbnailSidebarPreference = false;
  bool _showBookmarkSidebar = false;
  bool _showAnnotationSidebar = false;
  bool _showAnnotationLibraryPanel = false;
  String? _author;
  List<PdfSavedSignature> _savedSignatures = const [];
  String? _activeSignatureId;
  List<PdfSavedAnnotation> _savedAnnotations = const [];
  List<PdfCustomStamp> _customStamps = const [];
  PdfStampDateFormat _stampDateFormat = PdfStampDateFormat.iso;
  PdfStampTimeFormat _stampTimeFormat = PdfStampTimeFormat.twentyFourHour;
  ThemeMode _themeMode = ThemeMode.system;
  Locale? _locale;
  PdfColorFormat _colorPickerFormat = PdfColorFormat.hex;
  List<Color> _recentColors = const [];
  List<String> _recentFonts = const [];
  Color _pageColor = const Color(0xFFFFFFFF);
  bool _showAnnotations = true;
  bool _showScrollbarChapters = false;
  bool _highlightFormFields = true;
  bool _showReflowView = false;
  bool _showThumbnailView = false;
  double? _thumbnailViewTileWidth;
  bool _showPropertiesPanel = false;
  bool _showSearchResultsPanel = false;
  bool _searchMatchCase = false;
  bool _searchWholeWord = false;
  bool _searchRegex = false;
  bool _searchAnnotations = true;
  bool _searchReplaceExpanded = false;
  double? _thumbnailSidebarWidth;
  double? _bookmarkSidebarWidth;
  double? _annotationSidebarWidth;
  double? _annotationLibraryPanelWidth;
  double? _propertiesPanelWidth;
  double? _searchPanelWidth;
  // Which edge each dockable panel is attached to. Defaults reproduce the
  // built-in layout (thumbnails/search/bookmarks left, annotations/
  // properties right); the user drags a panel's move handle to redock it.
  PdfPanelDock _thumbnailSidebarDock = PdfPanelDock.left;
  PdfPanelDock _searchPanelDock = PdfPanelDock.left;
  PdfPanelDock _bookmarkSidebarDock = PdfPanelDock.left;
  PdfPanelDock _annotationSidebarDock = PdfPanelDock.right;
  PdfPanelDock _propertiesPanelDock = PdfPanelDock.right;
  PdfPanelDock _annotationLibraryPanelDock = PdfPanelDock.right;
  PdfPanelDock _toolbarDock = PdfPanelDock.bottom;
  // Tab-group membership: panels sharing the same dock AND the same group id
  // render as one tabbed panel; a panel alone in its group is a standalone
  // side-by-side panel. The default id is each panel's own enum index, so
  // every panel starts standalone (the built-in side-by-side layout).
  final Map<PdfDockablePanel, int> _panelGroups = {
    for (final p in PdfDockablePanel.values) p: p.index,
  };
  // The dragged extent of a dock's tab group (its width for left/right, its
  // height for top/bottom), null until the group is first resized.
  final Map<PdfPanelDock, double> _panelGroupWidths = {};
  Color? _textFillColor;
  Color? _textBorderColor;
  Color? _shapeFillColor;
  PdfMeasurementScale? _measurementScale;

  /// Per-tool style memory (see [beginStyleScope]). Keyed by an opaque
  /// scope string (the controller uses tool names plus `'markup'`); each
  /// slot holds the subset of style fields that tool remembers, JSON-
  /// encoded (colors as ARGB ints, enums by name).
  final Map<String, Map<String, Object?>> _toolStyles = {};

  /// The active style scope, or null when style changes go only to the
  /// shared defaults (select mode, restyling a selection). Set through
  /// [beginStyleScope].
  String? _styleScope;
  Set<String> _styleScopeFields = const {};

  /// While restoring a scope's stored style we drive the public setters,
  /// so this suppresses the re-record back into the same slot.
  bool _restoringScope = false;

  static const _toolStylesKey = '${_prefix}toolStyles';

  /// Saved viewports per document (see [viewportFor]). Insertion order is
  /// least- to most-recently-touched, for LRU eviction past
  /// [_maxViewports].
  final Map<String, PdfViewport> _viewports = {};
  bool _viewportsDirty = false;

  /// How many documents' viewports to remember before evicting the
  /// oldest.
  static const _maxViewports = 64;

  static const _viewportsKey = '${_prefix}documentViewports';

  Future<void> _load() async {
    final SharedPreferences store;
    try {
      store = await SharedPreferences.getInstance();
    } catch (_) {
      return; // no local storage here (e.g. widget tests) - defaults stand
    }
    var migratedLegacySignature = false;
    // a value set while the disk read was in flight wins over the stored one
    if (!_modified) {
      final color = store.getInt('${_prefix}color');
      if (color != null) _color = Color(color);
      _strokeWidth = store.getDouble('${_prefix}strokeWidth') ?? _strokeWidth;
      _cornerRadius =
          store.getDouble('${_prefix}cornerRadius') ?? _cornerRadius;
      _eraserRadius =
          store.getDouble('${_prefix}eraserRadius') ?? _eraserRadius;
      _showVerticalCursorGuide =
          store.getBool('${_prefix}showVerticalCursorGuide') ??
              _showVerticalCursorGuide;
      _showHorizontalCursorGuide =
          store.getBool('${_prefix}showHorizontalCursorGuide') ??
              _showHorizontalCursorGuide;
      _showSnapGrid = store.getBool('${_prefix}showSnapGrid') ?? _showSnapGrid;
      _snapToGrid = store.getBool('${_prefix}snapToGrid') ?? _snapToGrid;
      final gridSpacing = store.getDouble('${_prefix}gridSpacing');
      if (gridSpacing != null && gridSpacing.isFinite && gridSpacing > 0) {
        _gridSpacing = gridSpacing;
      }
      _fontSize = store.getDouble('${_prefix}fontSize') ?? _fontSize;
      final fontFamily = store.getString('${_prefix}fontFamily');
      if (fontFamily != null) {
        _fontFamily =
            PdfStandardFont.values.asNameMap()[fontFamily] ?? _fontFamily;
      }
      final textAlign = store.getString('${_prefix}textAlign');
      if (textAlign != null) {
        _textAlign = PdfTextAlign.values.asNameMap()[textAlign] ?? _textAlign;
      }
      _opacity = store.getDouble('${_prefix}opacity') ?? _opacity;
      _lineScale = store.getDouble('${_prefix}lineScale') ?? _lineScale;
      final lineStyle = store.getString('${_prefix}lineStyle');
      if (lineStyle != null) {
        _lineStyle = PdfLineStyle.values.asNameMap()[lineStyle] ?? _lineStyle;
      } else if (store.getBool('${_prefix}dashedStroke') ?? false) {
        // migrate the old boolean dashed-stroke preference
        _lineStyle = PdfLineStyle.dashed;
      }
      final lineStart = store.getString('${_prefix}lineStartEnding');
      if (lineStart != null) {
        _lineStartEnding =
            PdfLineEnding.values.asNameMap()[lineStart] ?? _lineStartEnding;
      }
      final lineEnd = store.getString('${_prefix}lineEndEnding');
      if (lineEnd != null) {
        _lineEndEnding =
            PdfLineEnding.values.asNameMap()[lineEnd] ?? _lineEndEnding;
      }
      _fingerDrawsInk =
          store.getBool('${_prefix}fingerDrawsInk') ?? _fingerDrawsInk;
      const thumbnailSidebarKey = '${_prefix}showThumbnailSidebar';
      _hasShowThumbnailSidebarPreference =
          store.containsKey(thumbnailSidebarKey);
      if (_hasShowThumbnailSidebarPreference) {
        _showThumbnailSidebar =
            store.getBool(thumbnailSidebarKey) ?? _showThumbnailSidebar;
      }
      _showBookmarkSidebar = store.getBool('${_prefix}showBookmarkSidebar') ??
          _showBookmarkSidebar;
      _showAnnotationSidebar =
          store.getBool('${_prefix}showAnnotationSidebar') ??
              _showAnnotationSidebar;
      _showAnnotationLibraryPanel =
          store.getBool('${_prefix}showAnnotationLibraryPanel') ??
              _showAnnotationLibraryPanel;
      _author = store.getString('${_prefix}author') ?? _author;
      final signatures = store.getStringList('${_prefix}signatures');
      if (signatures != null) {
        _savedSignatures = List.unmodifiable([
          for (final signature in signatures)
            if (PdfSavedSignature.decode(signature) case final decoded?)
              decoded,
        ]);
      } else {
        // Migrate the pre-library singleton without losing it. Keep the old
        // key mirrored on future writes so an older app build can still use
        // whichever signature is active.
        final legacy = store.getString('${_prefix}signature');
        final decoded = legacy == null ? null : PdfInkSignature.decode(legacy);
        if (decoded != null) {
          final entry = PdfSavedSignature(
            id: 'legacy-signature',
            name: 'Signature 1',
            signature: decoded,
          );
          _savedSignatures = List.unmodifiable([entry]);
          _activeSignatureId = entry.id;
          migratedLegacySignature = true;
        }
      }
      _activeSignatureId =
          store.getString('${_prefix}activeSignatureId') ?? _activeSignatureId;
      if (!_savedSignatures.any((entry) => entry.id == _activeSignatureId)) {
        _activeSignatureId =
            _savedSignatures.isEmpty ? null : _savedSignatures.first.id;
      }
      final annotations = store.getStringList('${_prefix}savedAnnotations');
      if (annotations != null) {
        _savedAnnotations = List.unmodifiable([
          for (final annotation in annotations)
            if (PdfSavedAnnotation.decode(annotation) case final decoded?)
              decoded,
        ]);
      }
      final themeMode = store.getString('${_prefix}themeMode');
      if (themeMode != null) {
        _themeMode = ThemeMode.values.asNameMap()[themeMode] ?? _themeMode;
      }
      final locale = store.getString('${_prefix}locale');
      if (locale != null && locale.isNotEmpty) {
        _locale = _parseLocaleTag(locale);
      }
      final colorPickerFormat = store.getString('${_prefix}colorPickerFormat');
      if (colorPickerFormat != null) {
        _colorPickerFormat =
            PdfColorFormat.values.asNameMap()[colorPickerFormat] ??
                _colorPickerFormat;
      }
      final recentColors = store.getStringList('${_prefix}recentColors');
      if (recentColors != null) {
        _recentColors = List.unmodifiable([
          for (final entry in recentColors)
            if (int.tryParse(entry) case final rgb?) Color(0xFF000000 | rgb),
        ]);
      }
      final recentFonts = store.getStringList('${_prefix}recentFonts');
      if (recentFonts != null) {
        _recentFonts = List.unmodifiable(recentFonts);
      }
      final pageColor = store.getInt('${_prefix}pageColor');
      if (pageColor != null) _pageColor = Color(pageColor);
      _showAnnotations =
          store.getBool('${_prefix}showAnnotations') ?? _showAnnotations;
      _showScrollbarChapters =
          store.getBool('${_prefix}showScrollbarChapters') ??
              _showScrollbarChapters;
      _highlightFormFields = store.getBool('${_prefix}highlightFormFields') ??
          _highlightFormFields;
      _showReflowView =
          store.getBool('${_prefix}showReflowView') ?? _showReflowView;
      _showThumbnailView =
          store.getBool('${_prefix}showThumbnailView') ?? _showThumbnailView;
      _thumbnailViewTileWidth =
          store.getDouble('${_prefix}thumbnailViewTileWidth') ??
              _thumbnailViewTileWidth;
      _thumbnailSidebarWidth =
          store.getDouble('${_prefix}thumbnailSidebarWidth') ??
              _thumbnailSidebarWidth;
      _bookmarkSidebarWidth =
          store.getDouble('${_prefix}bookmarkSidebarWidth') ??
              _bookmarkSidebarWidth;
      _annotationSidebarWidth =
          store.getDouble('${_prefix}annotationSidebarWidth') ??
              _annotationSidebarWidth;
      _annotationLibraryPanelWidth =
          store.getDouble('${_prefix}annotationLibraryPanelWidth') ??
              _annotationLibraryPanelWidth;
      _showPropertiesPanel = store.getBool('${_prefix}showPropertiesPanel') ??
          _showPropertiesPanel;
      _showSearchResultsPanel =
          store.getBool('${_prefix}showSearchResultsPanel') ??
              _showSearchResultsPanel;
      _searchMatchCase =
          store.getBool('${_prefix}searchMatchCase') ?? _searchMatchCase;
      _searchWholeWord =
          store.getBool('${_prefix}searchWholeWord') ?? _searchWholeWord;
      _searchRegex = store.getBool('${_prefix}searchRegex') ?? _searchRegex;
      _searchAnnotations =
          store.getBool('${_prefix}searchAnnotations') ?? _searchAnnotations;
      _searchReplaceExpanded =
          store.getBool('${_prefix}searchReplaceExpanded') ??
              _searchReplaceExpanded;
      _propertiesPanelWidth =
          store.getDouble('${_prefix}propertiesPanelWidth') ??
              _propertiesPanelWidth;
      _searchPanelWidth =
          store.getDouble('${_prefix}searchPanelWidth') ?? _searchPanelWidth;
      _thumbnailSidebarDock =
          _readDock(store, 'thumbnailSidebarDock', _thumbnailSidebarDock);
      _searchPanelDock = _readDock(store, 'searchPanelDock', _searchPanelDock);
      _bookmarkSidebarDock =
          _readDock(store, 'bookmarkSidebarDock', _bookmarkSidebarDock);
      _annotationSidebarDock =
          _readDock(store, 'annotationSidebarDock', _annotationSidebarDock);
      _annotationLibraryPanelDock = _readDock(
          store, 'annotationLibraryPanelDock', _annotationLibraryPanelDock);
      _propertiesPanelDock =
          _readDock(store, 'propertiesPanelDock', _propertiesPanelDock);
      _toolbarDock = _readDock(store, 'toolbarDock', _toolbarDock);
      for (final p in PdfDockablePanel.values) {
        _panelGroups[p] =
            store.getInt('${_prefix}panelGroup.${p.name}') ?? _panelGroups[p]!;
      }
      for (final d in PdfPanelDock.values) {
        final w = store.getDouble('${_prefix}panelGroupWidth.${d.name}');
        if (w != null) _panelGroupWidths[d] = w;
      }
      final textFill = store.getInt('${_prefix}textFillColor');
      if (textFill != null) _textFillColor = Color(textFill);
      final textBorder = store.getInt('${_prefix}textBorderColor');
      if (textBorder != null) _textBorderColor = Color(textBorder);
      final shapeFill = store.getInt('${_prefix}shapeFillColor');
      if (shapeFill != null) _shapeFillColor = Color(shapeFill);
      final scale = store.getString('${_prefix}measurementScale');
      if (scale != null) _measurementScale = PdfMeasurementScale.decode(scale);
      _loadToolStyles(store.getString(_toolStylesKey));
      final stamps = store.getStringList('${_prefix}customStamps');
      if (stamps != null) {
        _customStamps = List.unmodifiable([
          for (final stamp in stamps)
            if (PdfCustomStamp.decode(stamp) case final decoded?) decoded
        ]);
      }
      final stampDateFormat = store.getString('${_prefix}stampDateFormat');
      if (stampDateFormat != null) {
        _stampDateFormat =
            PdfStampDateFormat.values.asNameMap()[stampDateFormat] ??
                _stampDateFormat;
      }
      final stampTimeFormat = store.getString('${_prefix}stampTimeFormat');
      if (stampTimeFormat != null) {
        _stampTimeFormat =
            PdfStampTimeFormat.values.asNameMap()[stampTimeFormat] ??
                _stampTimeFormat;
      }
    }
    // viewports are a write-mostly store, not user-set UI state, so they
    // load regardless of _modified and merge by key - any saved before the
    // disk read (a fast scroll) keeps its place
    for (final entry in _decodeViewports(store.getString(_viewportsKey))) {
      _viewports.putIfAbsent(entry.$1, () => entry.$2);
    }
    _store = store;
    if (migratedLegacySignature) _writeSignatureLibrary();
    if (_viewportsDirty) _writeViewports();
    notifyListeners();
  }

  static List<(String, PdfViewport)> _decodeViewports(String? source) {
    if (source == null) return const [];
    final result = <(String, PdfViewport)>[];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final key = entry['k'];
        final value = entry['v'];
        if (key is! String || value is! Map) continue;
        final viewport = PdfViewport.fromJson(Map<String, Object?>.from(value));
        if (viewport != null) result.add((key, viewport));
      }
    } catch (_) {
      return const [];
    }
    return result;
  }

  void _writeViewports() {
    final store = _store;
    if (store == null) {
      _viewportsDirty = true; // flush once storage is ready
      return;
    }
    _viewportsDirty = false;
    final list = [
      for (final entry in _viewports.entries)
        {'k': entry.key, 'v': entry.value.toJson()}
    ];
    unawaited(store.setString(_viewportsKey, jsonEncode(list)));
  }

  /// The saved viewport for the document keyed by [documentKey] (see
  /// `pdfDocumentKey`), or null when none has been stored - what a host
  /// passes to `PdfViewer.initialViewport` so reopening a document lands
  /// where the user left it.
  PdfViewport? viewportFor(String documentKey) => _viewports[documentKey];

  /// Remembers [viewport] as the position for the document keyed by
  /// [documentKey], evicting the least-recently-touched document past the
  /// cap. Passing null forgets it. Persisted but deliberately silent - it
  /// is called on every scroll/zoom settle, so it never notifies
  /// listeners.
  void setViewport(String documentKey, PdfViewport? viewport) {
    if (documentKey.isEmpty) return;
    if (viewport == null) {
      if (_viewports.remove(documentKey) == null) return;
    } else {
      if (_viewports[documentKey] == viewport &&
          _viewports.keys.isNotEmpty &&
          _viewports.keys.last == documentKey) {
        return; // unchanged and already most-recent
      }
      // re-insert so it becomes the most-recently-touched entry
      _viewports.remove(documentKey);
      _viewports[documentKey] = viewport;
      while (_viewports.length > _maxViewports) {
        _viewports.remove(_viewports.keys.first);
      }
    }
    _writeViewports();
  }

  void _write(Future<Object?> Function(SharedPreferences store) write) {
    _modified = true;
    final store = _store;
    if (store != null) unawaited(write(store));
  }

  // -------------------------------------------------------------------------
  // per-tool style memory

  void _loadToolStyles(String? source) {
    if (source == null) return;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          _toolStyles[key] = {
            for (final entry in value.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
        }
      });
    } catch (_) {
      // corrupt blob - drop it, the defaults stand
    }
  }

  void _writeToolStyles() =>
      _write((s) => s.setString(_toolStylesKey, jsonEncode(_toolStyles)));

  /// Activates the style scope [scope], remembering only [fields] under it,
  /// and restores that scope's previously-saved style into the live values.
  ///
  /// While a scope is active every style setter ([color], [strokeWidth],
  /// [opacity], [fontSize], [fontFamily], [lineStyle], the line endings,
  /// the fill colors, [eraserRadius]) also records its new value under the
  /// scope - so each annotation tool keeps its own colour, stroke and so on
  /// across sessions. A null [scope] (select mode, or restyling a
  /// selection) writes only the shared defaults.
  void beginStyleScope(String? scope, Set<String> fields,
      {Map<String, Object?> defaults = const {},
      Set<String> lockedFields = const {},
      bool forceRestore = false}) {
    var seeded = false;
    if (scope != null &&
        defaults.isNotEmpty &&
        !_toolStyles.containsKey(scope)) {
      final slot = {
        for (final entry in defaults.entries)
          if (fields.contains(entry.key)) entry.key: entry.value,
      };
      if (slot.isNotEmpty) {
        _toolStyles[scope] = slot;
        _writeToolStyles();
        seeded = true;
      }
    }
    if (scope == _styleScope && setEquals(fields, _styleScopeFields)) {
      if ((seeded || forceRestore) && scope != null) {
        _restoreScope(scope, lockedFields: lockedFields);
      }
      return;
    }
    _styleScope = scope;
    _styleScopeFields = fields;
    if (scope != null) _restoreScope(scope, lockedFields: lockedFields);
  }

  void _restoreScope(String scope, {Set<String> lockedFields = const {}}) {
    final slot = _toolStyles[scope];
    if (slot == null || slot.isEmpty) return;
    // drive the public setters (they update the live value and the shared
    // default), guarding the re-record so this load doesn't rewrite the slot
    _restoringScope = true;
    try {
      if (!lockedFields.contains('color')) {
        if (slot['color'] case final int v) color = Color(v);
      }
      if (slot['strokeWidth'] case final num v) strokeWidth = v.toDouble();
      if (slot['cornerRadius'] case final num v) cornerRadius = v.toDouble();
      if (slot['eraserRadius'] case final num v) eraserRadius = v.toDouble();
      if (slot['opacity'] case final num v) opacity = v.toDouble();
      if (slot['fontSize'] case final num v) fontSize = v.toDouble();
      if (slot['fontFamily'] case final String v) {
        final font = PdfStandardFont.values.asNameMap()[v];
        if (font != null) fontFamily = font;
      }
      if (slot.containsKey('textAlign')) {
        final v = slot['textAlign'];
        textAlign = v is String ? PdfTextAlign.values.asNameMap()[v] : null;
      }
      if (slot['lineStyle'] case final String v) {
        final style = PdfLineStyle.values.asNameMap()[v];
        if (style != null) lineStyle = style;
      }
      if (slot['lineScale'] case final num v) lineScale = v.toDouble();
      if (slot['lineStartEnding'] case final String v) {
        final ending = PdfLineEnding.values.asNameMap()[v];
        if (ending != null) lineStartEnding = ending;
      }
      if (slot['lineEndEnding'] case final String v) {
        final ending = PdfLineEnding.values.asNameMap()[v];
        if (ending != null) lineEndEnding = ending;
      }
      if (slot.containsKey('textFillColor')) {
        textFillColor = _colorOrNull(slot['textFillColor']);
      }
      if (slot.containsKey('textBorderColor')) {
        textBorderColor = _colorOrNull(slot['textBorderColor']);
      }
      if (slot.containsKey('shapeFillColor')) {
        shapeFillColor = _colorOrNull(slot['shapeFillColor']);
      }
    } finally {
      _restoringScope = false;
    }
  }

  static Color? _colorOrNull(Object? value) =>
      value is int ? Color(value) : null;

  /// Saves the current live style values into the active tool scope.
  ///
  /// This is separate from [_recordScoped], which only runs when a setter
  /// changes a value. A tool still needs to remember the style it inherited
  /// on first activation, otherwise switching to another tool with seeded
  /// defaults can leak that other tool's style back into it.
  void snapshotActiveStyleScope({Set<String> lockedFields = const {}}) {
    final scope = _styleScope;
    if (scope == null || _styleScopeFields.isEmpty) return;
    final slot = _toolStyles[scope] ??= <String, Object?>{};
    var changed = false;

    void put(String field, Object? value) {
      if (!_styleScopeFields.contains(field)) return;
      if (lockedFields.contains(field)) return;
      if (slot[field] == value && slot.containsKey(field)) return;
      slot[field] = value;
      changed = true;
    }

    put('color', _color.toARGB32());
    put('strokeWidth', _strokeWidth);
    put('cornerRadius', _cornerRadius);
    put('eraserRadius', _eraserRadius);
    put('opacity', _opacity);
    put('fontSize', _fontSize);
    put('fontFamily', _fontFamily.name);
    put('textAlign', _textAlign?.name);
    put('lineStyle', _lineStyle.name);
    put('lineScale', _lineScale);
    put('lineStartEnding', _lineStartEnding.name);
    put('lineEndEnding', _lineEndEnding.name);
    put('textFillColor', _textFillColor?.toARGB32());
    put('textBorderColor', _textBorderColor?.toARGB32());
    put('shapeFillColor', _shapeFillColor?.toARGB32());

    if (changed) _writeToolStyles();
  }

  /// Writes captured style [values] into the persisted style scope [scope],
  /// keeping only the fields the scope actually remembers ([fields]). When
  /// [scope] is the currently active scope, the values also flow into the
  /// live creation defaults so the change takes effect immediately for the
  /// armed tool. Used by "set as default", which seeds a tool's creation
  /// style from an existing annotation.
  ///
  /// A field whose value is null is honoured for the colours that can be
  /// cleared ([textFillColor]/[textBorderColor]/[shapeFillColor]) - null
  /// there means "no fill" - and skipped otherwise, so a value the
  /// annotation doesn't carry leaves that default untouched.
  void writeScopedStyle(
      String scope, Set<String> fields, Map<String, Object?> values) {
    const nullable = {'textFillColor', 'textBorderColor', 'shapeFillColor'};
    final slot = _toolStyles[scope] ??= <String, Object?>{};
    var changed = false;
    values.forEach((field, value) {
      if (!fields.contains(field)) return;
      if (value == null && !nullable.contains(field)) return;
      if (slot.containsKey(field) && slot[field] == value) return;
      slot[field] = value;
      changed = true;
    });
    if (changed) _writeToolStyles();
    // Reflect into the live values when this is the active scope, driving the
    // public setters (which notify) through the shared restore path.
    if (scope == _styleScope) _restoreScope(scope);
  }

  /// Records [value] for [field] under the active scope when that scope
  /// remembers the field. Called from the style setters.
  void _recordScoped(String field, Object? value) {
    if (_restoringScope || _styleScope == null) return;
    if (!_styleScopeFields.contains(field)) return;
    (_toolStyles[_styleScope!] ??= {})[field] = value;
    _writeToolStyles();
  }

  /// The color new annotations are created with.
  Color get color => _color;

  set color(Color value) => setColor(value);

  void setColor(Color value, {bool recordStyleScope = true}) {
    if (value == _color) return;
    _color = value;
    _write((s) => s.setInt('${_prefix}color', value.toARGB32()));
    if (recordStyleScope) _recordScoped('color', value.toARGB32());
    notifyListeners();
  }

  /// Stroke width for ink and shape annotations, in PDF points.
  double get strokeWidth => _strokeWidth;

  set strokeWidth(double value) {
    if (value == _strokeWidth) return;
    _strokeWidth = value;
    _write((s) => s.setDouble('${_prefix}strokeWidth', value));
    _recordScoped('strokeWidth', value);
    notifyListeners();
  }

  /// Corner radius for new rectangle shapes, in PDF points; 0 (the default)
  /// gives square corners.
  double get cornerRadius => _cornerRadius;

  set cornerRadius(double value) {
    if (value == _cornerRadius) return;
    _cornerRadius = value;
    _write((s) => s.setDouble('${_prefix}cornerRadius', value));
    _recordScoped('cornerRadius', value);
    notifyListeners();
  }

  /// The circle eraser's radius, in PDF points (see
  /// [PdfEditingController.eraserRadius]).
  double get eraserRadius => _eraserRadius;

  set eraserRadius(double value) {
    if (value == _eraserRadius) return;
    _eraserRadius = value;
    _write((s) => s.setDouble('${_prefix}eraserRadius', value));
    _recordScoped('eraserRadius', value);
    notifyListeners();
  }

  /// Whether a page-height guide follows the mouse pointer's horizontal
  /// position. The guide is display-only and is not written into the PDF.
  bool get showVerticalCursorGuide => _showVerticalCursorGuide;

  set showVerticalCursorGuide(bool value) {
    if (value == _showVerticalCursorGuide) return;
    _showVerticalCursorGuide = value;
    _write((s) => s.setBool('${_prefix}showVerticalCursorGuide', value));
    notifyListeners();
  }

  /// Whether a page-width guide follows the mouse pointer's vertical
  /// position. The guide is display-only and is not written into the PDF.
  bool get showHorizontalCursorGuide => _showHorizontalCursorGuide;

  set showHorizontalCursorGuide(bool value) {
    if (value == _showHorizontalCursorGuide) return;
    _showHorizontalCursorGuide = value;
    _write((s) => s.setBool('${_prefix}showHorizontalCursorGuide', value));
    notifyListeners();
  }

  /// Whether the page-space snap grid is drawn over the page. This is a
  /// display-only preference and is independent of [snapToGrid].
  bool get showSnapGrid => _showSnapGrid;

  set showSnapGrid(bool value) {
    if (value == _showSnapGrid) return;
    _showSnapGrid = value;
    _write((s) => s.setBool('${_prefix}showSnapGrid', value));
    notifyListeners();
  }

  /// Whether annotation placement, movement, resizing, and line vertices
  /// snap to a page-space grid. Hold Alt during a gesture to bypass it.
  bool get snapToGrid => _snapToGrid;

  set snapToGrid(bool value) {
    if (value == _snapToGrid) return;
    _snapToGrid = value;
    _write((s) => s.setBool('${_prefix}snapToGrid', value));
    notifyListeners();
  }

  /// The grid interval in PDF points. Grid coordinates are measured from
  /// the visible crop box's lower-left corner and stay stable across zoom.
  double get gridSpacing => _gridSpacing;

  set gridSpacing(double value) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, 'gridSpacing', 'must be positive');
    }
    if (value == _gridSpacing) return;
    _gridSpacing = value;
    _write((s) => s.setDouble('${_prefix}gridSpacing', value));
    notifyListeners();
  }

  /// Font size for free-text annotations, in PDF points.
  double get fontSize => _fontSize;

  set fontSize(double value) {
    if (value == _fontSize) return;
    _fontSize = value;
    _write((s) => s.setDouble('${_prefix}fontSize', value));
    _recordScoped('fontSize', value);
    notifyListeners();
  }

  /// Font family for free-text annotations - one of the standard PDF
  /// text fonts (sans-serif, serif, monospace).
  PdfStandardFont get fontFamily => _fontFamily;

  set fontFamily(PdfStandardFont value) {
    if (value == _fontFamily) return;
    _fontFamily = value;
    _write((s) => s.setString('${_prefix}fontFamily', value.name));
    _recordScoped('fontFamily', value.name);
    notifyListeners();
  }

  /// Horizontal alignment (left/center/right) new free-text boxes are
  /// created with - the box's /Q quadding. Null (the default) follows the
  /// text direction: left for LTR, right for RTL. Persisted.
  PdfTextAlign? get textAlign => _textAlign;

  set textAlign(PdfTextAlign? value) {
    if (value == _textAlign) return;
    _textAlign = value;
    _write((s) => value == null
        ? s.remove('${_prefix}textAlign')
        : s.setString('${_prefix}textAlign', value.name));
    _recordScoped('textAlign', value?.name);
    notifyListeners();
  }

  /// Opacity (0–1] new ink, shape, markup, and stamp annotations are
  /// created with.
  double get opacity => _opacity;

  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    _write((s) => s.setDouble('${_prefix}opacity', value));
    _recordScoped('opacity', value);
    notifyListeners();
  }

  /// The border line style (solid / dashed / dotted / dash-dot) new shape
  /// and line annotations are created with. Persisted by enum name.
  PdfLineStyle get lineStyle => _lineStyle;

  set lineStyle(PdfLineStyle value) {
    if (value == _lineStyle) return;
    _lineStyle = value;
    _write((s) => s.setString('${_prefix}lineStyle', value.name));
    _recordScoped('lineStyle', value.name);
    notifyListeners();
  }

  /// The pattern scale new shape and line annotations are created with - a
  /// multiplier (1 = default) driving the size of dash patterns and cloudy
  /// scallops *independently* of [strokeWidth], so the line thickness and
  /// the pattern size change separately. Persisted.
  double get lineScale => _lineScale;

  set lineScale(double value) {
    if (value == _lineScale) return;
    _lineScale = value;
    _write((s) => s.setDouble('${_prefix}lineScale', value));
    _recordScoped('lineScale', value);
    notifyListeners();
  }

  /// The line ending drawn at the *start* of new /Line and /PolyLine
  /// annotations (§12.5.6.7). Defaults to [PdfLineEnding.none].
  PdfLineEnding get lineStartEnding => _lineStartEnding;

  set lineStartEnding(PdfLineEnding value) {
    if (value == _lineStartEnding) return;
    _lineStartEnding = value;
    _write((s) => s.setString('${_prefix}lineStartEnding', value.name));
    _recordScoped('lineStartEnding', value.name);
    notifyListeners();
  }

  /// The line ending drawn at the *end* of new /Line and /PolyLine
  /// annotations (§12.5.6.7). Defaults to [PdfLineEnding.none].
  PdfLineEnding get lineEndEnding => _lineEndEnding;

  set lineEndEnding(PdfLineEnding value) {
    if (value == _lineEndEnding) return;
    _lineEndEnding = value;
    _write((s) => s.setString('${_prefix}lineEndEnding', value.name));
    _recordScoped('lineEndEnding', value.name);
    notifyListeners();
  }

  /// Whether touch pointers draw with the ink tool (see
  /// [PdfEditingController.fingerDrawsInk]). Persisted so a stylus
  /// user's palm rejection survives reopening the app.
  bool get fingerDrawsInk => _fingerDrawsInk;

  set fingerDrawsInk(bool value) {
    if (value == _fingerDrawsInk) return;
    _fingerDrawsInk = value;
    _write((s) => s.setBool('${_prefix}fingerDrawsInk', value));
    notifyListeners();
  }

  /// Whether the host shows the page thumbnail sidebar.
  bool get showThumbnailSidebar => _showThumbnailSidebar;

  set showThumbnailSidebar(bool value) {
    if (value == _showThumbnailSidebar && _hasShowThumbnailSidebarPreference) {
      return;
    }
    _showThumbnailSidebar = value;
    _hasShowThumbnailSidebarPreference = true;
    _write((s) => s.setBool('${_prefix}showThumbnailSidebar', value));
    notifyListeners();
  }

  /// Whether [showThumbnailSidebar] came from storage or a user change,
  /// rather than the built-in desktop-oriented default.
  bool get hasShowThumbnailSidebarPreference =>
      _hasShowThumbnailSidebarPreference;

  /// The active hand-drawn signature the signature tool stamps, or null when
  /// the library is empty.
  ///
  /// This singleton-shaped property is retained for source and storage
  /// compatibility. New code can use [savedSignatures] and
  /// [activeSavedSignature] to manage the whole library.
  PdfInkSignature? get signature => activeSavedSignature?.signature;

  set signature(PdfInkSignature? value) {
    if (value == null) {
      if (_savedSignatures.isEmpty) return;
      _savedSignatures = const [];
      _activeSignatureId = null;
      _writeSignatureLibrary();
      notifyListeners();
      return;
    }
    final active = activeSavedSignature;
    if (active == null) {
      final entry = PdfSavedSignature.create(
        name: 'Signature 1',
        signature: value,
      );
      _savedSignatures = List.unmodifiable([entry]);
      _activeSignatureId = entry.id;
    } else {
      _savedSignatures = List.unmodifiable([
        for (final entry in _savedSignatures)
          if (entry.id == active.id)
            entry.copyWith(signature: value)
          else
            entry,
      ]);
    }
    _writeSignatureLibrary();
    notifyListeners();
  }

  /// The user's saved signatures, oldest first.
  List<PdfSavedSignature> get savedSignatures => _savedSignatures;

  set savedSignatures(List<PdfSavedSignature> value) {
    final next = List<PdfSavedSignature>.unmodifiable(value);
    if (_encodedListsEqual(next.map((entry) => entry.encode()),
        _savedSignatures.map((entry) => entry.encode()))) {
      return;
    }
    _savedSignatures = next;
    if (!next.any((entry) => entry.id == _activeSignatureId)) {
      _activeSignatureId = next.isEmpty ? null : next.first.id;
    }
    _writeSignatureLibrary();
    notifyListeners();
  }

  /// The signature currently chosen for placement.
  PdfSavedSignature? get activeSavedSignature {
    for (final entry in _savedSignatures) {
      if (entry.id == _activeSignatureId) return entry;
    }
    return _savedSignatures.isEmpty ? null : _savedSignatures.first;
  }

  set activeSavedSignature(PdfSavedSignature? value) {
    final id = value?.id ??
        (_savedSignatures.isEmpty ? null : _savedSignatures.first.id);
    if (id == _activeSignatureId ||
        (id != null && !_savedSignatures.any((entry) => entry.id == id))) {
      return;
    }
    _activeSignatureId = id;
    _writeSignatureLibrary();
    notifyListeners();
  }

  void _writeSignatureLibrary() {
    final active = activeSavedSignature;
    // Invoke every setter before yielding. Successive library mutations can
    // arrive faster than the platform store completes a write; awaiting each
    // key here would let an older call resume between a newer call's writes
    // and leave the active id or legacy mirror stale.
    _write((store) => Future.wait<Object?>([
          store.setStringList('${_prefix}signatures', [
            for (final entry in _savedSignatures) entry.encode(),
          ]),
          if (active == null) ...[
            store.remove('${_prefix}activeSignatureId'),
            store.remove('${_prefix}signature'),
          ] else ...[
            store.setString('${_prefix}activeSignatureId', active.id),
            store.setString('${_prefix}signature', active.signature.encode()),
          ],
        ]));
  }

  /// Named reusable annotation snapshots saved on this device.
  List<PdfSavedAnnotation> get savedAnnotations => _savedAnnotations;

  set savedAnnotations(List<PdfSavedAnnotation> value) {
    final next = List<PdfSavedAnnotation>.unmodifiable(value);
    if (_encodedListsEqual(next.map((entry) => entry.encode()),
        _savedAnnotations.map((entry) => entry.encode()))) {
      return;
    }
    _savedAnnotations = next;
    _write((store) => store.setStringList('${_prefix}savedAnnotations', [
          for (final entry in next) entry.encode(),
        ]));
    notifyListeners();
  }

  /// The user's saved custom rubber stamps, oldest first.
  List<PdfCustomStamp> get customStamps => _customStamps;

  set customStamps(List<PdfCustomStamp> value) {
    if (listEquals(value, _customStamps)) return;
    _customStamps = List.unmodifiable(value);
    _write((s) => s.setStringList(
        '${_prefix}customStamps', [for (final stamp in value) stamp.encode()]));
    notifyListeners();
  }

  /// User-selected format for built-in stamp `{{date}}` fields.
  PdfStampDateFormat get stampDateFormat => _stampDateFormat;

  set stampDateFormat(PdfStampDateFormat value) {
    if (value == _stampDateFormat) return;
    _stampDateFormat = value;
    _write((s) => s.setString('${_prefix}stampDateFormat', value.name));
    notifyListeners();
  }

  /// User-selected format for built-in stamp `{{time}}` fields.
  PdfStampTimeFormat get stampTimeFormat => _stampTimeFormat;

  set stampTimeFormat(PdfStampTimeFormat value) {
    if (value == _stampTimeFormat) return;
    _stampTimeFormat = value;
    _write((s) => s.setString('${_prefix}stampTimeFormat', value.name));
    notifyListeners();
  }

  /// The author name new annotations carry (/T), shown in the
  /// annotation sidebar. Null leaves them unsigned.
  String? get author => _author;

  set author(String? value) {
    if (value == _author) return;
    _author = value;
    _write((s) => value == null
        ? s.remove('${_prefix}author')
        : s.setString('${_prefix}author', value));
    notifyListeners();
  }

  /// The app theme the host runs the viewer UI in. The viewer and the
  /// stock chrome all follow the ambient [Theme]; this just remembers
  /// the user's choice for the host's `MaterialApp.themeMode`.
  ThemeMode get themeMode => _themeMode;

  set themeMode(ThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    _write((s) => s.setString('${_prefix}themeMode', value.name));
    notifyListeners();
  }

  /// The UI language the user picked in Settings, or null (the default) to
  /// follow the platform locale. A host feeds this to its `MaterialApp`
  /// locale resolution; null means "System default" and defers to Flutter's
  /// own preferred-locale algorithm. Persisted by BCP-47 language tag.
  Locale? get locale => _locale;

  set locale(Locale? value) {
    if (value == _locale) return;
    _locale = value;
    _write((s) => value == null
        ? s.remove('${_prefix}locale')
        : s.setString('${_prefix}locale', value.toLanguageTag()));
    notifyListeners();
  }

  /// Parses a persisted BCP-47 language tag (e.g. `es`, `pt-BR`, `zh-Hans`)
  /// back into a [Locale], reading a 4-letter subtag as the script and a
  /// 2-letter / 3-digit subtag as the region. Returns null for an empty or
  /// malformed tag so a corrupt value quietly falls back to the system
  /// locale.
  static Locale? _parseLocaleTag(String tag) {
    final parts = tag.split(RegExp('[-_]'));
    if (parts.isEmpty || parts.first.isEmpty) return null;
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && script == null) {
        script = part[0].toUpperCase() + part.substring(1).toLowerCase();
      } else if (country == null &&
          (part.length == 2 ||
              (part.length == 3 && int.tryParse(part) != null))) {
        country = part.toUpperCase();
      }
    }
    return Locale.fromSubtags(
      languageCode: parts.first.toLowerCase(),
      scriptCode: script,
      countryCode: country,
    );
  }

  /// The value format the color picker last showed (hex, RGB, HSL, or
  /// CMYK) - the picker reopens in it.
  PdfColorFormat get colorPickerFormat => _colorPickerFormat;

  set colorPickerFormat(PdfColorFormat value) {
    if (value == _colorPickerFormat) return;
    _colorPickerFormat = value;
    _write((s) => s.setString('${_prefix}colorPickerFormat', value.name));
    notifyListeners();
  }

  /// How many recently-picked colours to remember (see [recentColors]).
  static const _maxRecentColors = 18;

  /// The colours most recently chosen in the full colour picker, newest
  /// first - the picker's "Recent" quick-pick grid. Opaque (alpha
  /// dropped); deduplicated by RGB. Persisted on the device.
  List<Color> get recentColors => _recentColors;

  /// Records [color] as the most-recently-used colour, moving it to the
  /// front (deduplicated by RGB) and dropping the oldest past
  /// [_maxRecentColors]. Alpha is ignored - the picker deals in opaque
  /// colours. A no-op when [color] is already the newest entry.
  void noteRecentColor(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    final opaque = Color(0xFF000000 | rgb);
    if (_recentColors.isNotEmpty &&
        (_recentColors.first.toARGB32() & 0xFFFFFF) == rgb) {
      return;
    }
    final next = [
      opaque,
      for (final existing in _recentColors)
        if ((existing.toARGB32() & 0xFFFFFF) != rgb) existing,
    ];
    if (next.length > _maxRecentColors) {
      next.removeRange(_maxRecentColors, next.length);
    }
    _recentColors = List.unmodifiable(next);
    _write((s) => s.setStringList('${_prefix}recentColors',
        [for (final c in _recentColors) '${c.toARGB32() & 0xFFFFFF}']));
    notifyListeners();
  }

  /// How many recently-picked fonts to remember (see [recentFonts]).
  static const _maxRecentFonts = 6;

  /// Opaque keys of the fonts most recently chosen in the font menu, newest
  /// first - the menu's "Recently used" group. Each key identifies a menu
  /// entry (a standard family, a bundled/platform font, or a document font)
  /// rather than carrying font bytes, so the menu resolves it back to a live
  /// choice; keys no longer present (e.g. a document font from a closed file)
  /// are simply skipped. Persisted on the device.
  List<String> get recentFonts => _recentFonts;

  /// Records [key] as the most-recently-used font, moving it to the front
  /// (deduplicated) and dropping the oldest past [_maxRecentFonts]. A no-op
  /// when [key] is empty or already the newest entry.
  void noteRecentFont(String key) {
    if (key.isEmpty) return;
    if (_recentFonts.isNotEmpty && _recentFonts.first == key) return;
    final next = [
      key,
      for (final existing in _recentFonts)
        if (existing != key) existing,
    ];
    if (next.length > _maxRecentFonts) {
      next.removeRange(_maxRecentFonts, next.length);
    }
    _recentFonts = List.unmodifiable(next);
    _write((s) => s.setStringList('${_prefix}recentFonts', _recentFonts));
    notifyListeners();
  }

  /// The paper color pages are displayed on (see [PdfViewer.pageColor]).
  /// White - the PDF convention - by default; a display setting only,
  /// the document is untouched.
  Color get pageColor => _pageColor;

  set pageColor(Color value) {
    if (value == _pageColor) return;
    _pageColor = value;
    _write((s) => s.setInt('${_prefix}pageColor', value.toARGB32()));
    notifyListeners();
  }

  /// Whether pages are displayed with their annotations (see
  /// [PdfViewer.showAnnotations]). A display setting only - hiding
  /// changes nothing in the document.
  bool get showAnnotations => _showAnnotations;

  set showAnnotations(bool value) {
    if (value == _showAnnotations) return;
    _showAnnotations = value;
    _write((s) => s.setBool('${_prefix}showAnnotations', value));
    notifyListeners();
  }

  /// Whether document outline entries appear as chapter markers on the
  /// viewer's main scrollbar. A display setting only, off by default.
  bool get showScrollbarChapters => _showScrollbarChapters;

  set showScrollbarChapters(bool value) {
    if (value == _showScrollbarChapters) return;
    _showScrollbarChapters = value;
    _write((s) => s.setBool('${_prefix}showScrollbarChapters', value));
    notifyListeners();
  }

  /// Whether form-field widgets are washed with the visibility tint
  /// (see [PdfViewer.highlightFormFields]). A display setting only.
  bool get highlightFormFields => _highlightFormFields;

  set highlightFormFields(bool value) {
    if (value == _highlightFormFields) return;
    _highlightFormFields = value;
    _write((s) => s.setBool('${_prefix}highlightFormFields', value));
    notifyListeners();
  }

  /// Whether reader chrome shows the inferred text reflow view instead
  /// of fixed-layout PDF pages. Display-only.
  bool get showReflowView => _showReflowView;

  set showReflowView(bool value) {
    if (value == _showReflowView) return;
    _showReflowView = value;
    _write((s) => s.setBool('${_prefix}showReflowView', value));
    notifyListeners();
  }

  /// Whether the host shows the dedicated full-area page thumbnail grid
  /// (`PdfThumbnailView`) in place of the page viewer. A view mode, not a
  /// docked panel - distinct from [showThumbnailSidebar].
  bool get showThumbnailView => _showThumbnailView;

  set showThumbnailView(bool value) {
    if (value == _showThumbnailView) return;
    _showThumbnailView = value;
    _write((s) => s.setBool('${_prefix}showThumbnailView', value));
    notifyListeners();
  }

  /// The page thumbnail grid's tile width, in logical pixels - the size
  /// control in `PdfThumbnailView` drives it. Null until first changed,
  /// where the widget's own default applies.
  double? get thumbnailViewTileWidth => _thumbnailViewTileWidth;

  set thumbnailViewTileWidth(double? value) {
    if (value == _thumbnailViewTileWidth) return;
    _thumbnailViewTileWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}thumbnailViewTileWidth')
        : s.setDouble('${_prefix}thumbnailViewTileWidth', value));
    notifyListeners();
  }

  /// The thumbnail sidebar's user-dragged width, or null while it has
  /// never been resized (the widget's own default width applies).
  double? get thumbnailSidebarWidth => _thumbnailSidebarWidth;

  set thumbnailSidebarWidth(double? value) {
    if (value == _thumbnailSidebarWidth) return;
    _thumbnailSidebarWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}thumbnailSidebarWidth')
        : s.setDouble('${_prefix}thumbnailSidebarWidth', value));
    notifyListeners();
  }

  /// The annotation sidebar's user-dragged width, or null while it has
  /// never been resized.
  double? get annotationSidebarWidth => _annotationSidebarWidth;

  set annotationSidebarWidth(double? value) {
    if (value == _annotationSidebarWidth) return;
    _annotationSidebarWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}annotationSidebarWidth')
        : s.setDouble('${_prefix}annotationSidebarWidth', value));
    notifyListeners();
  }

  /// The background fill new free-text boxes are created with, or null
  /// (the default) for no fill.
  Color? get textFillColor => _textFillColor;

  set textFillColor(Color? value) {
    if (value == _textFillColor) return;
    _textFillColor = value;
    _write((s) => value == null
        ? s.remove('${_prefix}textFillColor')
        : s.setInt('${_prefix}textFillColor', value.toARGB32()));
    _recordScoped('textFillColor', value?.toARGB32());
    notifyListeners();
  }

  /// The border color new free-text boxes are created with, or null
  /// (the default) for no border. The border width follows [strokeWidth].
  Color? get textBorderColor => _textBorderColor;

  set textBorderColor(Color? value) {
    if (value == _textBorderColor) return;
    _textBorderColor = value;
    _write((s) => value == null
        ? s.remove('${_prefix}textBorderColor')
        : s.setInt('${_prefix}textBorderColor', value.toARGB32()));
    _recordScoped('textBorderColor', value?.toARGB32());
    notifyListeners();
  }

  /// The interior fill new shapes (rectangle/ellipse) are created with, or
  /// null (the default) for an unfilled outline. Persisted.
  Color? get shapeFillColor => _shapeFillColor;

  set shapeFillColor(Color? value) {
    if (value == _shapeFillColor) return;
    _shapeFillColor = value;
    _write((s) => value == null
        ? s.remove('${_prefix}shapeFillColor')
        : s.setInt('${_prefix}shapeFillColor', value.toARGB32()));
    _recordScoped('shapeFillColor', value?.toARGB32());
    notifyListeners();
  }

  /// The active measurement calibration the measure tools stamp onto new
  /// annotations, or null until a scale is set. Persisted so a drawing's
  /// scale survives reopening the file.
  PdfMeasurementScale? get measurementScale => _measurementScale;

  set measurementScale(PdfMeasurementScale? value) {
    if (value == _measurementScale) return;
    _measurementScale = value;
    _write((s) => value == null
        ? s.remove('${_prefix}measurementScale')
        : s.setString('${_prefix}measurementScale', value.encode()));
    notifyListeners();
  }

  /// Whether the host shows the annotation list sidebar.
  bool get showAnnotationSidebar => _showAnnotationSidebar;

  set showAnnotationSidebar(bool value) {
    if (value == _showAnnotationSidebar) return;
    _showAnnotationSidebar = value;
    _write((s) => s.setBool('${_prefix}showAnnotationSidebar', value));
    notifyListeners();
  }

  /// Whether the host shows the reusable annotation-library panel.
  bool get showAnnotationLibraryPanel => _showAnnotationLibraryPanel;

  set showAnnotationLibraryPanel(bool value) {
    if (value == _showAnnotationLibraryPanel) return;
    _showAnnotationLibraryPanel = value;
    _write((s) => s.setBool('${_prefix}showAnnotationLibraryPanel', value));
    notifyListeners();
  }

  /// The annotation-library panel's user-dragged width, or null until it has
  /// been resized.
  double? get annotationLibraryPanelWidth => _annotationLibraryPanelWidth;

  set annotationLibraryPanelWidth(double? value) {
    if (value == _annotationLibraryPanelWidth) return;
    _annotationLibraryPanelWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}annotationLibraryPanelWidth')
        : s.setDouble('${_prefix}annotationLibraryPanelWidth', value));
    notifyListeners();
  }

  /// Whether the host shows the document bookmarks/outline panel.
  bool get showBookmarkSidebar => _showBookmarkSidebar;

  set showBookmarkSidebar(bool value) {
    if (value == _showBookmarkSidebar) return;
    _showBookmarkSidebar = value;
    _write((s) => s.setBool('${_prefix}showBookmarkSidebar', value));
    notifyListeners();
  }

  /// The bookmarks panel's user-dragged width, or null while it has
  /// never been resized.
  double? get bookmarkSidebarWidth => _bookmarkSidebarWidth;

  set bookmarkSidebarWidth(double? value) {
    if (value == _bookmarkSidebarWidth) return;
    _bookmarkSidebarWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}bookmarkSidebarWidth')
        : s.setDouble('${_prefix}bookmarkSidebarWidth', value));
    notifyListeners();
  }

  /// Whether the host shows the annotation properties panel.
  bool get showPropertiesPanel => _showPropertiesPanel;

  set showPropertiesPanel(bool value) {
    if (value == _showPropertiesPanel) return;
    _showPropertiesPanel = value;
    _write((s) => s.setBool('${_prefix}showPropertiesPanel', value));
    notifyListeners();
  }

  /// The properties panel's user-dragged width, or null while it has
  /// never been resized.
  double? get propertiesPanelWidth => _propertiesPanelWidth;

  set propertiesPanelWidth(double? value) {
    if (value == _propertiesPanelWidth) return;
    _propertiesPanelWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}propertiesPanelWidth')
        : s.setDouble('${_prefix}propertiesPanelWidth', value));
    notifyListeners();
  }

  /// Whether the host shows the search results panel.
  bool get showSearchResultsPanel => _showSearchResultsPanel;

  set showSearchResultsPanel(bool value) {
    if (value == _showSearchResultsPanel) return;
    _showSearchResultsPanel = value;
    _write((s) => s.setBool('${_prefix}showSearchResultsPanel', value));
    notifyListeners();
  }

  /// The search results panel's user-dragged width, or null while it
  /// has never been resized.
  double? get searchPanelWidth => _searchPanelWidth;

  set searchPanelWidth(double? value) {
    if (value == _searchPanelWidth) return;
    _searchPanelWidth = value;
    _write((s) => value == null
        ? s.remove('${_prefix}searchPanelWidth')
        : s.setDouble('${_prefix}searchPanelWidth', value));
    notifyListeners();
  }

  PdfPanelDock _readDock(
          SharedPreferences store, String key, PdfPanelDock fallback) =>
      PdfPanelDock.values.asNameMap()[store.getString('$_prefix$key')] ??
      fallback;

  void _setDock(String key, PdfPanelDock value) {
    _write((s) => s.setString('$_prefix$key', value.name));
    notifyListeners();
  }

  /// Which edge the page-thumbnail panel is docked on. Persisted so a
  /// dragged layout survives reopening the app.
  PdfPanelDock get thumbnailSidebarDock => _thumbnailSidebarDock;

  set thumbnailSidebarDock(PdfPanelDock value) {
    if (value == _thumbnailSidebarDock) return;
    _thumbnailSidebarDock = value;
    _setDock('thumbnailSidebarDock', value);
  }

  /// Which edge the search-results panel is docked on. Persisted.
  PdfPanelDock get searchPanelDock => _searchPanelDock;

  set searchPanelDock(PdfPanelDock value) {
    if (value == _searchPanelDock) return;
    _searchPanelDock = value;
    _setDock('searchPanelDock', value);
  }

  /// Which edge the bookmarks/outline panel is docked on. Persisted.
  PdfPanelDock get bookmarkSidebarDock => _bookmarkSidebarDock;

  set bookmarkSidebarDock(PdfPanelDock value) {
    if (value == _bookmarkSidebarDock) return;
    _bookmarkSidebarDock = value;
    _setDock('bookmarkSidebarDock', value);
  }

  /// Which edge the annotation-list panel is docked on. Persisted.
  PdfPanelDock get annotationSidebarDock => _annotationSidebarDock;

  set annotationSidebarDock(PdfPanelDock value) {
    if (value == _annotationSidebarDock) return;
    _annotationSidebarDock = value;
    _setDock('annotationSidebarDock', value);
  }

  /// Which edge the annotation-properties panel is docked on. Persisted.
  PdfPanelDock get propertiesPanelDock => _propertiesPanelDock;

  set propertiesPanelDock(PdfPanelDock value) {
    if (value == _propertiesPanelDock) return;
    _propertiesPanelDock = value;
    _setDock('propertiesPanelDock', value);
  }

  /// Which edge the reusable annotation-library panel is docked on.
  PdfPanelDock get annotationLibraryPanelDock => _annotationLibraryPanelDock;

  set annotationLibraryPanelDock(PdfPanelDock value) {
    if (value == _annotationLibraryPanelDock) return;
    _annotationLibraryPanelDock = value;
    _setDock('annotationLibraryPanelDock', value);
  }

  /// Which edge the floating editing toolbar is attached to. Persisted so a
  /// dragged toolbar returns to the same edge in later sessions. Compact
  /// layouts still use their fixed bottom bar regardless of this preference.
  PdfPanelDock get toolbarDock => _toolbarDock;

  set toolbarDock(PdfPanelDock value) {
    if (value == _toolbarDock) return;
    _toolbarDock = value;
    _setDock('toolbarDock', value);
  }

  /// The dock a specific [panel] is attached to, keyed by identity - the
  /// generic form of the per-panel dock getters above.
  PdfPanelDock panelDock(PdfDockablePanel panel) => switch (panel) {
        PdfDockablePanel.thumbnails => _thumbnailSidebarDock,
        PdfDockablePanel.search => _searchPanelDock,
        PdfDockablePanel.bookmarks => _bookmarkSidebarDock,
        PdfDockablePanel.annotations => _annotationSidebarDock,
        PdfDockablePanel.properties => _propertiesPanelDock,
        PdfDockablePanel.annotationLibrary => _annotationLibraryPanelDock,
      };

  /// Sets [panel]'s dock, keyed by identity.
  void setPanelDock(PdfDockablePanel panel, PdfPanelDock dock) {
    switch (panel) {
      case PdfDockablePanel.thumbnails:
        thumbnailSidebarDock = dock;
      case PdfDockablePanel.search:
        searchPanelDock = dock;
      case PdfDockablePanel.bookmarks:
        bookmarkSidebarDock = dock;
      case PdfDockablePanel.annotations:
        annotationSidebarDock = dock;
      case PdfDockablePanel.properties:
        propertiesPanelDock = dock;
      case PdfDockablePanel.annotationLibrary:
        annotationLibraryPanelDock = dock;
    }
  }

  /// The tab-group id [panel] belongs to. Panels that share both a dock and
  /// a group id render as one tabbed panel; a panel alone in its group is a
  /// standalone side-by-side panel. Defaults to the panel's own enum index
  /// (every panel standalone).
  int panelGroup(PdfDockablePanel panel) => _panelGroups[panel]!;

  /// Its own enum index - the value [panelGroup] returns when the panel is
  /// standalone (in no shared tab group).
  int standalonePanelGroup(PdfDockablePanel panel) => panel.index;

  /// Sets [panel]'s tab-group id. Pass [standalonePanelGroup] to split it out
  /// of any tab group.
  void setPanelGroup(PdfDockablePanel panel, int group) {
    if (_panelGroups[panel] == group) return;
    _panelGroups[panel] = group;
    _write((s) => s.setInt('${_prefix}panelGroup.${panel.name}', group));
    notifyListeners();
  }

  /// The dragged extent of the tab group docked on [dock] (its width for
  /// left/right, its height for top/bottom), or null before it is resized.
  double? panelGroupWidth(PdfPanelDock dock) => _panelGroupWidths[dock];

  /// Persists the dragged extent of the tab group docked on [dock].
  void setPanelGroupWidth(PdfPanelDock dock, double width) {
    if (_panelGroupWidths[dock] == width) return;
    _panelGroupWidths[dock] = width;
    _write((s) => s.setDouble('${_prefix}panelGroupWidth.${dock.name}', width));
    notifyListeners();
  }

  /// Whether document search matches case (see `PdfSearchOptions.matchCase`).
  /// Persisted so the search toggles survive reopening the app.
  bool get searchMatchCase => _searchMatchCase;

  set searchMatchCase(bool value) {
    if (value == _searchMatchCase) return;
    _searchMatchCase = value;
    _write((s) => s.setBool('${_prefix}searchMatchCase', value));
    notifyListeners();
  }

  /// Whether the search panel's replace controls are expanded. They are
  /// collapsed by default - find is the common case and the replacement field
  /// plus its two buttons are a lot of vertical space to spend on a panel
  /// whose job is listing hits. Persisted, so a user who works in replace
  /// keeps it open across sessions.
  bool get searchReplaceExpanded => _searchReplaceExpanded;

  set searchReplaceExpanded(bool value) {
    if (value == _searchReplaceExpanded) return;
    _searchReplaceExpanded = value;
    _write((s) => s.setBool('${_prefix}searchReplaceExpanded', value));
    notifyListeners();
  }

  /// Whether document search matches whole words only (see
  /// `PdfSearchOptions.wholeWord`). Persisted.
  bool get searchWholeWord => _searchWholeWord;

  set searchWholeWord(bool value) {
    if (value == _searchWholeWord) return;
    _searchWholeWord = value;
    _write((s) => s.setBool('${_prefix}searchWholeWord', value));
    notifyListeners();
  }

  /// Whether document search treats the query as a regular expression (see
  /// `PdfSearchOptions.regex`). Persisted.
  bool get searchRegex => _searchRegex;

  set searchRegex(bool value) {
    if (value == _searchRegex) return;
    _searchRegex = value;
    _write((s) => s.setBool('${_prefix}searchRegex', value));
    notifyListeners();
  }

  /// Whether document search also scans annotation /Contents (see
  /// `PdfSearchOptions.searchAnnotations`). On by default. Persisted.
  bool get searchAnnotations => _searchAnnotations;

  set searchAnnotations(bool value) {
    if (value == _searchAnnotations) return;
    _searchAnnotations = value;
    _write((s) => s.setBool('${_prefix}searchAnnotations', value));
    notifyListeners();
  }
}

bool _encodedListsEqual(Iterable<String> a, Iterable<String> b) {
  final left = a.iterator;
  final right = b.iterator;
  while (true) {
    final hasLeft = left.moveNext();
    final hasRight = right.moveNext();
    if (hasLeft != hasRight) return false;
    if (!hasLeft) return true;
    if (left.current != right.current) return false;
  }
}
