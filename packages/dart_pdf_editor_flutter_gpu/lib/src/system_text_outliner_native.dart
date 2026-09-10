import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show
        PdfBundledSubstitute,
        pdfBundledSubstituteFor,
        pdfUsesAdventorSubstitute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf_graphics/pdf_graphics.dart';

import 'text_outliner.dart';

/// Best-effort exact outlines for the fonts `CanvasPdfDevice` substitutes into
/// unembedded text: the metric-compatible TeX Gyre faces from the optional
/// `dart_pdf_editor_assets` package where they are bundled, and the platform's
/// own standard families where they are not.
///
/// This adapter is opt-in because platform font locations are not a Flutter
/// API. It returns null unless it can read every face needed by a run; the GPU
/// backend then retains its ordinary whole-scene Canvas fallback. A host with
/// bundled/custom fonts should construct [FlutterGpuTrueTypeTextOutliner]
/// directly from those exact bytes instead.
class FlutterGpuSystemTextOutliner implements FlutterGpuTextOutliner {
  FlutterGpuSystemTextOutliner._(this._catalogue)
      : _delegate = FlutterGpuTrueTypeTextOutliner(_catalogue.resolve);

  /// Prepares a lazy resolver for the faces `CanvasPdfDevice` substitutes.
  ///
  /// Returns null on unsupported platforms. Reading the bundled substitute
  /// faces out of the asset bundle starts here, because it is the one moment
  /// this adapter can do asynchronous work - a run resolves synchronously,
  /// mid-record. Font programs are parsed only when a run first requests that
  /// face; a missing family or style rejects only that run and stays memoized
  /// as unavailable.
  static FlutterGpuSystemTextOutliner? tryCreate() {
    final catalogue = _SystemFontCatalogue.load();
    if (catalogue == null) return null;
    return FlutterGpuSystemTextOutliner._(catalogue..prefetchBundled());
  }

  final _SystemFontCatalogue _catalogue;
  final FlutterGpuTrueTypeTextOutliner _delegate;

  /// Completes once the bundled substitute faces have been read (or found
  /// absent). Until then a run that would draw in one of them declines rather
  /// than outlining a face Canvas would not draw, so a host that must not spend
  /// its first paint on the Canvas fallback can await this.
  Future<void> get ready => _catalogue.bundledReady;

  @override
  PdfTextRun? outline(PdfTextRun run) => _delegate.outline(run);
}

enum _Family {
  sans,
  serif,
  mono,
  symbol,
  dingbats,
  cjkSong,
  cjkHeiti,
  cjkJapaneseSans,
  cjkJapaneseSerif,
}

enum _Style { regular, bold, italic, boldItalic }

class _SystemFontCatalogue {
  _SystemFontCatalogue(this.specs);

  final Map<(_Family, _Style), _FontSpec> specs;
  final Map<String, Uint8List> _byteCache = {};
  final Map<(_Family, _Style), FlutterGpuFontFace> _faces = {};
  final Set<(_Family, _Style)> _attempted = {};

  /// Program bytes of the bundled metric-compatible faces, read once up front
  /// (see [prefetchBundled]); a key absent from both maps once [bundledReady]
  /// has completed means the optional assets package isn't installed.
  final Map<(PdfBundledSubstitute, _Style), Uint8List> _bundledBytes = {};
  final Map<(PdfBundledSubstitute, _Style), FlutterGpuFontFace> _bundledFaces =
      {};
  Future<void>? _bundledPrefetch;

  /// Completes when [prefetchBundled] has settled every bundled face.
  Future<void> get bundledReady => _bundledPrefetch ?? Future.value();

  /// Reads every bundled substitute face out of the asset bundle, once.
  ///
  /// Eager rather than per-face-on-demand because [resolve] is synchronous: a
  /// face still in flight has to decline its run, and doing that lazily would
  /// spend a Canvas fallback on the first page that uses each weight. Bytes
  /// only - parsing stays lazy, so a face nothing draws is never parsed.
  bool _prefetchDone = false;

  Future<void> prefetchBundled() => _bundledPrefetch ??= Future.wait([
        for (final substitute in PdfBundledSubstitute.values)
          for (final style in _Style.values)
            if (substitute.hasItalicFaces || !_isItalic(style))
              _readBundled((substitute, style)),
      ]).whenComplete(() => _prefetchDone = true);

  Future<void> _readBundled((PdfBundledSubstitute, _Style) key) async {
    final (substitute, style) = key;
    final asset = 'packages/dart_pdf_editor_assets/assets/fonts/'
        '${substitute.assetFile(bold: _isBold(style), italic: _isItalic(style))}';
    try {
      final data = await rootBundle.load(asset);
      _bundledBytes[key] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } on Object {
      // No optional assets package: the platform catalogue below is then the
      // right answer, because it is what Canvas falls back to as well.
    }
  }

  static _SystemFontCatalogue? load() {
    final specs = Platform.isMacOS
        ? _macFonts
        : Platform.isIOS
            ? _iosFonts
            : Platform.isWindows
                ? _windowsFonts
                : Platform.isAndroid
                    ? _androidFonts
                    : Platform.isLinux
                        ? _linuxFonts
                        : const <(_Family, _Style), _FontSpec>{};
    return specs.isEmpty ? null : _SystemFontCatalogue(specs);
  }

  FlutterGpuFontFace? resolve(PdfTextRun run) {
    final name = run.fontName ?? '';
    final cjkFamily = _cjkFamily(name);
    if (cjkFamily != null) return _face((cjkFamily, _Style.regular));
    if (_isCjkName(name)) return null;
    final symbolic = name.contains('ZapfDingbats') || name.contains('Symbol');
    final family = name.contains('ZapfDingbats')
        ? _Family.dingbats
        : name.contains('Symbol')
            ? _Family.symbol
            : name.contains('Courier') || name.contains('Mono')
                ? _Family.mono
                : name.contains('Times') || name.contains('Serif')
                    ? _Family.serif
                    : _Family.sans;
    final bold = name.contains('Bold');
    final italic = name.contains('Italic') || name.contains('Oblique');
    final style = bold && italic
        ? _Style.boldItalic
        : bold
            ? _Style.bold
            : italic
                ? _Style.italic
                : _Style.regular;
    if (!symbolic) {
      // Canvas draws this run in a bundled metric-compatible face wherever the
      // optional assets package supplies one, so outlining anything else would
      // put the accelerated backend's glyphs somewhere Canvas would not.
      final bundled = _bundledFace(pdfBundledSubstituteFor(name), style);
      if (bundled.face != null) return bundled.face;
      // Still loading, or an oblique this family ships no file for (the engine
      // slants it and we cannot): decline, leaving the scene on the exact
      // Canvas fallback.
      if (bundled.pending) return null;
      // Only the geometric-sans clone has no platform equivalent a system path
      // could prove it matches.
      if (pdfUsesAdventorSubstitute(name)) return null;
    }
    // Symbol faces generally expose one regular program; Flutter's weight
    // flags do not select a synthetic face for the PDF Symbol/Zapf families.
    return _face((family, style)) ??
        (family == _Family.symbol || family == _Family.dingbats
            ? _face((family, _Style.regular))
            : null);
  }

  /// The bundled face for [substitute] in [style], or null with `pending` set
  /// when this adapter must not answer at all: while [prefetchBundled] is still
  /// in flight, and for a slant the family ships no file for - Canvas has the
  /// engine oblique the upright face, which no outline here can reproduce.
  ({FlutterGpuFontFace? face, bool pending}) _bundledFace(
    PdfBundledSubstitute substitute,
    _Style style,
  ) {
    if (_isItalic(style) && !substitute.hasItalicFaces) {
      return (face: null, pending: true);
    }
    final key = (substitute, style);
    final face = _bundledFaces[key];
    if (face != null) return (face: face, pending: false);
    final bytes = _bundledBytes[key];
    if (bytes != null) {
      try {
        return (face: _bundledFaces[key] = _parseFace(bytes), pending: false);
      } on Object {
        _bundledBytes.remove(key); // unparseable: the platform face it is
        return (face: null, pending: false);
      }
    }
    // Settled and absent means no optional assets package; still settling means
    // hold off one paint rather than draw the wrong metrics.
    return (face: null, pending: _bundledPrefetch != null && !_prefetchDone);
  }

  FlutterGpuFontFace? _face((_Family, _Style) key) {
    if (!_attempted.add(key)) return _faces[key];
    final spec = specs[key];
    if (spec == null) return null;
    for (final path in spec.paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final bytes = _byteCache.putIfAbsent(path, file.readAsBytesSync);
        return _faces[key] = _parseFace(
          bytes,
          collectionIndex: spec.collectionIndex,
        );
      } on Object {
        // Try the next known location. Failure keeps this face unavailable.
      }
    }
    return null;
  }
}

bool _isBold(_Style style) =>
    style == _Style.bold || style == _Style.boldItalic;

bool _isItalic(_Style style) =>
    style == _Style.italic || style == _Style.boldItalic;

/// Parses [bytes] as whichever outline flavour the face carries.
FlutterGpuFontFace _parseFace(Uint8List bytes, {int collectionIndex = 0}) {
  try {
    return FlutterGpuTrueTypeFontFace(bytes, collectionIndex: collectionIndex);
  } on FormatException {
    return FlutterGpuOpenTypeCffFontFace(bytes,
        collectionIndex: collectionIndex);
  }
}

class _FontSpec {
  const _FontSpec(this.paths, {this.collectionIndex = 0});

  final List<String> paths;
  final int collectionIndex;
}

_Family? _cjkFamily(String name) {
  if (name.contains('ºÚÌå')) return _Family.cjkHeiti; // 黑体
  if (name.contains('ËÎÌå') ||
      name.contains('·ÂËÎ') ||
      name.contains('Ð¡±êËÎ')) {
    return _Family.cjkSong; // 宋体 / 仿宋 / 小标宋
  }
  if (name.contains('Mincho') ||
      name.contains('HeiseiMin') ||
      name.contains('Ryumin') ||
      name.contains('KozMin')) {
    return _Family.cjkJapaneseSerif;
  }
  if (name.contains('HeiseiKakuGo') ||
      name.contains('GothicBBB') ||
      name.contains('KozGo') ||
      name.contains('Kaku') ||
      name.contains('MS-Gothic')) {
    return _Family.cjkJapaneseSans;
  }
  return null;
}

bool _isCjkName(String name) =>
    name.contains('ºÚÌå') ||
    name.contains('ËÎÌå') ||
    name.contains('·ÂËÎ') ||
    name.contains('Ð¡±êËÎ') ||
    name.contains('Mincho') ||
    name.contains('HeiseiMin') ||
    name.contains('Ryumin') ||
    name.contains('KozMin') ||
    name.contains('HeiseiKakuGo') ||
    name.contains('GothicBBB') ||
    name.contains('KozGo') ||
    name.contains('Kaku') ||
    name.contains('MS-Gothic');

const _macFonts = <(_Family, _Style), _FontSpec>{
  (_Family.sans, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Helvetica.ttc'],
  ),
  (_Family.sans, _Style.bold): _FontSpec(
    ['/System/Library/Fonts/Helvetica.ttc'],
    collectionIndex: 1,
  ),
  (_Family.sans, _Style.italic): _FontSpec(
    ['/System/Library/Fonts/Helvetica.ttc'],
    collectionIndex: 2,
  ),
  (_Family.sans, _Style.boldItalic): _FontSpec(
    ['/System/Library/Fonts/Helvetica.ttc'],
    collectionIndex: 3,
  ),
  (_Family.serif, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Times New Roman.ttf'],
  ),
  (_Family.serif, _Style.bold): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf'],
  ),
  (_Family.serif, _Style.italic): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf'],
  ),
  (_Family.serif, _Style.boldItalic): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Times New Roman Bold Italic.ttf'],
  ),
  (_Family.mono, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Courier New.ttf'],
  ),
  (_Family.mono, _Style.bold): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Courier New Bold.ttf'],
  ),
  (_Family.mono, _Style.italic): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Courier New Italic.ttf'],
  ),
  (_Family.mono, _Style.boldItalic): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Courier New Bold Italic.ttf'],
  ),
  (_Family.symbol, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Symbol.ttf'],
  ),
  (_Family.dingbats, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/ZapfDingbats.ttf'],
  ),
  // These are the exact faces selected by CanvasPdfDevice's CJK family
  // mapping. Keeping the TTC indices explicit avoids silently outlining with
  // a neighbouring weight or Traditional-Chinese face.
  (_Family.cjkSong, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Supplemental/Songti.ttc'],
    collectionIndex: 4,
  ),
  (_Family.cjkHeiti, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/STHeiti Medium.ttc'],
    collectionIndex: 1,
  ),
  (_Family.cjkJapaneseSans, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc'],
  ),
  (_Family.cjkJapaneseSerif, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/ヒラギノ明朝 ProN.ttc'],
  ),
};

const _iosFonts = <(_Family, _Style), _FontSpec>{
  (_Family.sans, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Core/Helvetica.ttc'],
  ),
  (_Family.sans, _Style.bold): _FontSpec(
    ['/System/Library/Fonts/Core/Helvetica.ttc'],
    collectionIndex: 1,
  ),
  (_Family.sans, _Style.italic): _FontSpec(
    ['/System/Library/Fonts/Core/Helvetica.ttc'],
    collectionIndex: 2,
  ),
  (_Family.sans, _Style.boldItalic): _FontSpec(
    ['/System/Library/Fonts/Core/Helvetica.ttc'],
    collectionIndex: 3,
  ),
  (_Family.serif, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Core/Times.ttc'],
  ),
  (_Family.mono, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Core/Courier.ttc'],
  ),
  (_Family.symbol, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Core/Symbol.ttf'],
  ),
  (_Family.dingbats, _Style.regular): _FontSpec(
    ['/System/Library/Fonts/Core/ZapfDingbats.ttf'],
  ),
};

String get _windowsFontDirectory =>
    '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts';

Map<(_Family, _Style), _FontSpec> get _windowsFonts => {
      (_Family.sans, _Style.regular):
          _FontSpec(['$_windowsFontDirectory\\arial.ttf']),
      (_Family.sans, _Style.bold):
          _FontSpec(['$_windowsFontDirectory\\arialbd.ttf']),
      (_Family.sans, _Style.italic):
          _FontSpec(['$_windowsFontDirectory\\ariali.ttf']),
      (_Family.sans, _Style.boldItalic):
          _FontSpec(['$_windowsFontDirectory\\arialbi.ttf']),
      (_Family.serif, _Style.regular):
          _FontSpec(['$_windowsFontDirectory\\times.ttf']),
      (_Family.serif, _Style.bold):
          _FontSpec(['$_windowsFontDirectory\\timesbd.ttf']),
      (_Family.serif, _Style.italic):
          _FontSpec(['$_windowsFontDirectory\\timesi.ttf']),
      (_Family.serif, _Style.boldItalic):
          _FontSpec(['$_windowsFontDirectory\\timesbi.ttf']),
      (_Family.mono, _Style.regular):
          _FontSpec(['$_windowsFontDirectory\\cour.ttf']),
      (_Family.mono, _Style.bold):
          _FontSpec(['$_windowsFontDirectory\\courbd.ttf']),
      (_Family.mono, _Style.italic):
          _FontSpec(['$_windowsFontDirectory\\couri.ttf']),
      (_Family.mono, _Style.boldItalic):
          _FontSpec(['$_windowsFontDirectory\\courbi.ttf']),
      (_Family.symbol, _Style.regular):
          _FontSpec(['$_windowsFontDirectory\\symbol.ttf']),
    };

const _androidFonts = <(_Family, _Style), _FontSpec>{
  (_Family.sans, _Style.regular):
      _FontSpec(['/system/fonts/Roboto-Regular.ttf']),
  (_Family.sans, _Style.bold): _FontSpec(['/system/fonts/Roboto-Bold.ttf']),
  (_Family.sans, _Style.italic): _FontSpec(['/system/fonts/Roboto-Italic.ttf']),
  (_Family.sans, _Style.boldItalic):
      _FontSpec(['/system/fonts/Roboto-BoldItalic.ttf']),
  (_Family.serif, _Style.regular): _FontSpec(
    [
      '/system/fonts/NotoSerif-Regular.ttf',
      '/system/fonts/DroidSerif-Regular.ttf'
    ],
  ),
  (_Family.serif, _Style.bold): _FontSpec(
    ['/system/fonts/NotoSerif-Bold.ttf', '/system/fonts/DroidSerif-Bold.ttf'],
  ),
  (_Family.serif, _Style.italic): _FontSpec(
    [
      '/system/fonts/NotoSerif-Italic.ttf',
      '/system/fonts/DroidSerif-Italic.ttf'
    ],
  ),
  (_Family.serif, _Style.boldItalic): _FontSpec(
    [
      '/system/fonts/NotoSerif-BoldItalic.ttf',
      '/system/fonts/DroidSerif-BoldItalic.ttf'
    ],
  ),
  (_Family.mono, _Style.regular): _FontSpec(
    ['/system/fonts/RobotoMono-Regular.ttf', '/system/fonts/DroidSansMono.ttf'],
  ),
  (_Family.symbol, _Style.regular): _FontSpec(
    ['/system/fonts/NotoSansSymbols-Regular-Subsetted.ttf'],
  ),
};

const _linuxFonts = <(_Family, _Style), _FontSpec>{
  (_Family.sans, _Style.regular): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ]),
  (_Family.sans, _Style.bold): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  ]),
  (_Family.sans, _Style.italic): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Italic.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf',
  ]),
  (_Family.sans, _Style.boldItalic): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationSans-BoldItalic.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf',
  ]),
  (_Family.serif, _Style.regular): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationSerif-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf',
  ]),
  (_Family.mono, _Style.regular): _FontSpec([
    '/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
  ]),
};
