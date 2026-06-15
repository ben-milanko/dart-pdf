import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfLineEnding, PdfStandardFont;
import 'package:shared_preferences/shared_preferences.dart';

import '../viewport.dart';
import 'editing_color_picker.dart' show PdfColorFormat;
import 'line_style.dart';
import 'editing_measure.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';

/// Editing-UI preferences, persisted on the local device.
///
/// Every [PdfEditingController] creates one by default, so tool styles
/// (color, stroke width, opacity, font size) and the stylus mode come
/// back the way the user left them, in this session and the next.
/// Panel visibility ([showThumbnailSidebar], [showAnnotationSidebar])
/// lives here too for the host's chrome — pass one instance to both the
/// controller and the surrounding scaffold:
///
/// ```dart
/// final prefs = PdfEditingPreferences();
/// // later, per document:
/// final editing = PdfEditingController(bytes, preferences: prefs);
/// ```
///
/// Values load asynchronously ([ready]); each change is written back
/// immediately. Where no local storage exists — plain widget tests, for
/// example — loading fails silently and the defaults stand.
class PdfEditingPreferences extends ChangeNotifier {
  PdfEditingPreferences() {
    _ready = _load();
  }

  static const _prefix = 'dart_pdf_editor.editing.';

  SharedPreferences? _store;
  late final Future<void> _ready;
  bool _modified = false;

  /// Completes once stored values have been applied — or storage turned
  /// out to be unavailable and the defaults stand.
  Future<void> get ready => _ready;

  Color _color = const Color(0xFFE53935);
  double _strokeWidth = 2;
  double _eraserRadius = 8;
  double _fontSize = 14;
  PdfStandardFont _fontFamily = PdfStandardFont.helvetica;
  double _opacity = 1;
  PdfLineStyle _lineStyle = PdfLineStyle.solid;
  PdfLineEnding _lineStartEnding = PdfLineEnding.none;
  PdfLineEnding _lineEndEnding = PdfLineEnding.none;
  bool _fingerDrawsInk = true;
  bool _showThumbnailSidebar = true;
  bool _hasShowThumbnailSidebarPreference = false;
  bool _showAnnotationSidebar = false;
  String? _author;
  PdfInkSignature? _signature;
  List<PdfCustomStamp> _customStamps = const [];
  ThemeMode _themeMode = ThemeMode.system;
  PdfColorFormat _colorPickerFormat = PdfColorFormat.hex;
  Color _pageColor = const Color(0xFFFFFFFF);
  bool _showAnnotations = true;
  bool _highlightFormFields = true;
  bool _showReflowView = false;
  bool _showPropertiesPanel = false;
  bool _showSearchResultsPanel = false;
  bool _searchMatchCase = false;
  bool _searchWholeWord = false;
  bool _searchRegex = false;
  double? _thumbnailSidebarWidth;
  double? _annotationSidebarWidth;
  double? _propertiesPanelWidth;
  double? _searchPanelWidth;
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
      return; // no local storage here (e.g. widget tests) — defaults stand
    }
    // a value set while the disk read was in flight wins over the stored one
    if (!_modified) {
      final color = store.getInt('${_prefix}color');
      if (color != null) _color = Color(color);
      _strokeWidth = store.getDouble('${_prefix}strokeWidth') ?? _strokeWidth;
      _eraserRadius =
          store.getDouble('${_prefix}eraserRadius') ?? _eraserRadius;
      _fontSize = store.getDouble('${_prefix}fontSize') ?? _fontSize;
      final fontFamily = store.getString('${_prefix}fontFamily');
      if (fontFamily != null) {
        _fontFamily =
            PdfStandardFont.values.asNameMap()[fontFamily] ?? _fontFamily;
      }
      _opacity = store.getDouble('${_prefix}opacity') ?? _opacity;
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
      _showAnnotationSidebar =
          store.getBool('${_prefix}showAnnotationSidebar') ??
              _showAnnotationSidebar;
      _author = store.getString('${_prefix}author') ?? _author;
      final signature = store.getString('${_prefix}signature');
      if (signature != null) _signature = PdfInkSignature.decode(signature);
      final themeMode = store.getString('${_prefix}themeMode');
      if (themeMode != null) {
        _themeMode = ThemeMode.values.asNameMap()[themeMode] ?? _themeMode;
      }
      final colorPickerFormat = store.getString('${_prefix}colorPickerFormat');
      if (colorPickerFormat != null) {
        _colorPickerFormat =
            PdfColorFormat.values.asNameMap()[colorPickerFormat] ??
                _colorPickerFormat;
      }
      final pageColor = store.getInt('${_prefix}pageColor');
      if (pageColor != null) _pageColor = Color(pageColor);
      _showAnnotations =
          store.getBool('${_prefix}showAnnotations') ?? _showAnnotations;
      _highlightFormFields = store.getBool('${_prefix}highlightFormFields') ??
          _highlightFormFields;
      _showReflowView =
          store.getBool('${_prefix}showReflowView') ?? _showReflowView;
      _thumbnailSidebarWidth =
          store.getDouble('${_prefix}thumbnailSidebarWidth') ??
              _thumbnailSidebarWidth;
      _annotationSidebarWidth =
          store.getDouble('${_prefix}annotationSidebarWidth') ??
              _annotationSidebarWidth;
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
      _propertiesPanelWidth =
          store.getDouble('${_prefix}propertiesPanelWidth') ??
              _propertiesPanelWidth;
      _searchPanelWidth =
          store.getDouble('${_prefix}searchPanelWidth') ?? _searchPanelWidth;
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
    }
    // viewports are a write-mostly store, not user-set UI state, so they
    // load regardless of _modified and merge by key — any saved before the
    // disk read (a fast scroll) keeps its place
    for (final entry in _decodeViewports(store.getString(_viewportsKey))) {
      _viewports.putIfAbsent(entry.$1, () => entry.$2);
    }
    _store = store;
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
        final viewport =
            PdfViewport.fromJson(Map<String, Object?>.from(value));
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
  /// `pdfDocumentKey`), or null when none has been stored — what a host
  /// passes to `PdfViewer.initialViewport` so reopening a document lands
  /// where the user left it.
  PdfViewport? viewportFor(String documentKey) => _viewports[documentKey];

  /// Remembers [viewport] as the position for the document keyed by
  /// [documentKey], evicting the least-recently-touched document past the
  /// cap. Passing null forgets it. Persisted but deliberately silent — it
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
      // corrupt blob — drop it, the defaults stand
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
  /// scope — so each annotation tool keeps its own colour, stroke and so on
  /// across sessions. A null [scope] (select mode, or restyling a
  /// selection) writes only the shared defaults.
  void beginStyleScope(String? scope, Set<String> fields) {
    if (scope == _styleScope && setEquals(fields, _styleScopeFields)) return;
    _styleScope = scope;
    _styleScopeFields = fields;
    if (scope != null) _restoreScope(scope);
  }

  void _restoreScope(String scope) {
    final slot = _toolStyles[scope];
    if (slot == null || slot.isEmpty) return;
    // drive the public setters (they update the live value and the shared
    // default), guarding the re-record so this load doesn't rewrite the slot
    _restoringScope = true;
    try {
      if (slot['color'] case final int v) color = Color(v);
      if (slot['strokeWidth'] case final num v) strokeWidth = v.toDouble();
      if (slot['eraserRadius'] case final num v) eraserRadius = v.toDouble();
      if (slot['opacity'] case final num v) opacity = v.toDouble();
      if (slot['fontSize'] case final num v) fontSize = v.toDouble();
      if (slot['fontFamily'] case final String v) {
        final font = PdfStandardFont.values.asNameMap()[v];
        if (font != null) fontFamily = font;
      }
      if (slot['lineStyle'] case final String v) {
        final style = PdfLineStyle.values.asNameMap()[v];
        if (style != null) lineStyle = style;
      }
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

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    _write((s) => s.setInt('${_prefix}color', value.toARGB32()));
    _recordScoped('color', value.toARGB32());
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

  /// Font size for free-text annotations, in PDF points.
  double get fontSize => _fontSize;

  set fontSize(double value) {
    if (value == _fontSize) return;
    _fontSize = value;
    _write((s) => s.setDouble('${_prefix}fontSize', value));
    _recordScoped('fontSize', value);
    notifyListeners();
  }

  /// Font family for free-text annotations — one of the standard PDF
  /// text fonts (sans-serif, serif, monospace).
  PdfStandardFont get fontFamily => _fontFamily;

  set fontFamily(PdfStandardFont value) {
    if (value == _fontFamily) return;
    _fontFamily = value;
    _write((s) => s.setString('${_prefix}fontFamily', value.name));
    _recordScoped('fontFamily', value.name);
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

  /// The saved hand-drawn signature the signature tool stamps, or null
  /// when none has been drawn yet.
  PdfInkSignature? get signature => _signature;

  set signature(PdfInkSignature? value) {
    if (value == _signature) return;
    _signature = value;
    _write((s) => value == null
        ? s.remove('${_prefix}signature')
        : s.setString('${_prefix}signature', value.encode()));
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

  /// The value format the color picker last showed (hex, RGB, HSL, or
  /// CMYK) — the picker reopens in it.
  PdfColorFormat get colorPickerFormat => _colorPickerFormat;

  set colorPickerFormat(PdfColorFormat value) {
    if (value == _colorPickerFormat) return;
    _colorPickerFormat = value;
    _write((s) => s.setString('${_prefix}colorPickerFormat', value.name));
    notifyListeners();
  }

  /// The paper color pages are displayed on (see [PdfViewer.pageColor]).
  /// White — the PDF convention — by default; a display setting only,
  /// the document is untouched.
  Color get pageColor => _pageColor;

  set pageColor(Color value) {
    if (value == _pageColor) return;
    _pageColor = value;
    _write((s) => s.setInt('${_prefix}pageColor', value.toARGB32()));
    notifyListeners();
  }

  /// Whether pages are displayed with their annotations (see
  /// [PdfViewer.showAnnotations]). A display setting only — hiding
  /// changes nothing in the document.
  bool get showAnnotations => _showAnnotations;

  set showAnnotations(bool value) {
    if (value == _showAnnotations) return;
    _showAnnotations = value;
    _write((s) => s.setBool('${_prefix}showAnnotations', value));
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

  /// Whether document search matches case (see `PdfSearchOptions.matchCase`).
  /// Persisted so the search toggles survive reopening the app.
  bool get searchMatchCase => _searchMatchCase;

  set searchMatchCase(bool value) {
    if (value == _searchMatchCase) return;
    _searchMatchCase = value;
    _write((s) => s.setBool('${_prefix}searchMatchCase', value));
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
}
