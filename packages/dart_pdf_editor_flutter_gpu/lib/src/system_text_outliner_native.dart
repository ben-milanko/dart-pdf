import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';

import 'text_outliner.dart';

/// Best-effort exact outlines for the native fonts selected by
/// `CanvasPdfDevice`'s standard substitution families.
///
/// This adapter is opt-in because platform font locations are not a Flutter
/// API. It returns null unless it can read every face needed by a run; the GPU
/// backend then retains its ordinary whole-scene Canvas fallback. A host with
/// bundled/custom fonts should construct [FlutterGpuTrueTypeTextOutliner]
/// directly from those exact bytes instead.
class FlutterGpuSystemTextOutliner implements FlutterGpuTextOutliner {
  FlutterGpuSystemTextOutliner._(this._delegate);

  /// Prepares a lazy resolver for the current platform's known native faces.
  ///
  /// Returns null on unsupported platforms. Font files are parsed only when a
  /// run first requests that face; a missing family or style rejects only that
  /// run and stays memoized as unavailable.
  static FlutterGpuSystemTextOutliner? tryCreate() {
    final catalogue = _SystemFontCatalogue.load();
    if (catalogue == null) return null;
    return FlutterGpuSystemTextOutliner._(
      FlutterGpuTrueTypeTextOutliner(catalogue.resolve),
    );
  }

  final FlutterGpuTrueTypeTextOutliner _delegate;

  @override
  PdfTextRun? outline(PdfTextRun run) => _delegate.outline(run);
}

enum _Family { sans, serif, mono, symbol, dingbats }

enum _Style { regular, bold, italic, boldItalic }

class _SystemFontCatalogue {
  _SystemFontCatalogue(this.specs);

  final Map<(_Family, _Style), _FontSpec> specs;
  final Map<String, Uint8List> _byteCache = {};
  final Map<(_Family, _Style), FlutterGpuTrueTypeFontFace> _faces = {};
  final Set<(_Family, _Style)> _attempted = {};

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

  FlutterGpuTrueTypeFontFace? resolve(PdfTextRun run) {
    final name = run.fontName ?? '';
    final lower = name.toLowerCase();
    // Canvas uses a separately registered TeX Gyre Adventor asset for these.
    // System paths cannot prove they match it.
    if (_usesAdventor(lower) || _isCjkName(name)) return null;
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
    // Symbol faces generally expose one regular program; Flutter's weight
    // flags do not select a synthetic face for the PDF Symbol/Zapf families.
    return _face((family, style)) ??
        (family == _Family.symbol || family == _Family.dingbats
            ? _face((family, _Style.regular))
            : null);
  }

  FlutterGpuTrueTypeFontFace? _face((_Family, _Style) key) {
    if (!_attempted.add(key)) return _faces[key];
    final spec = specs[key];
    if (spec == null) return null;
    for (final path in spec.paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final bytes = _byteCache.putIfAbsent(path, file.readAsBytesSync);
        return _faces[key] = FlutterGpuTrueTypeFontFace(
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

class _FontSpec {
  const _FontSpec(this.paths, {this.collectionIndex = 0});

  final List<String> paths;
  final int collectionIndex;
}

bool _usesAdventor(String name) =>
    name.contains('centurygothic') ||
    name.contains('century gothic') ||
    name.contains('avantgarde') ||
    name.contains('avant garde') ||
    name.contains('texgyreadventor') ||
    name.contains('tex gyre adventor') ||
    name.contains('urwgothic') ||
    name.contains('urw gothic');

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
