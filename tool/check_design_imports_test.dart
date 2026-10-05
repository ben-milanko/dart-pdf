// Tests for tool/check_design_imports.dart. CI runs it next to the check.
//
// Usage (from the repo root): dart tool/check_design_imports_test.dart

import 'dart:io';

import 'check_design_imports.dart';

void main() {
  _directives();
  _comments();
  _closureAndCounters();
  _ratchet();
  print('Design import check tests passed.');
}

void _expect(Object? actual, Object? expected, String what) {
  if ('$actual' != '$expected') {
    throw StateError('$what\nExpected: $expected\nActual:   $actual');
  }
}

void _directives() {
  final found = directives('''
library;
// import 'package:flutter/material.dart';
/* export 'commented.dart'; */
import 'package:flutter/widgets.dart' show BuildContext, IconData;
import 'a.dart'
    if (dart.library.js_interop) 'a_web.dart'
    if (dart.library.io) 'a_io.dart';
export 'b.dart' hide Hidden;
part 'c.dart';
part of 'd.dart';
''');
  _expect(
      found.map((d) => d.uri).toList(),
      [
        'package:flutter/widgets.dart',
        'a.dart',
        'a_web.dart',
        'a_io.dart',
        'b.dart',
        'c.dart',
      ],
      'directive URIs');
  _expect(found.first.show, {'BuildContext', 'IconData'}, 'show names');
  _expect(found[4].show, null, 'hide is not show');
}

void _comments() {
  _expect(stripComments("a // x\nb /* y */ c 'not // a comment' d").trim(),
      "a \nb   c 'not // a comment' d", 'comment stripping');
  _expect(stripComments(r"x = r'\'; // gone").trim(), r"x = r'\';",
      'raw string ending in a backslash');
}

void _closureAndCounters() {
  final root = Directory.systemTemp.createTempSync('design_imports_test');
  try {
    void write(String path, String body) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    const lib = 'packages/dart_pdf_editor/lib';
    write('$lib/src/editing/editing_controller.dart', '''
import 'package:dart_pdf_editor/src/editing/editing_preferences.dart';
import '../l10n/pdf_l10n.dart';
import 'model.dart';
''');
    // material_ui counts as Material too
    write('$lib/src/editing/editing_preferences.dart', '''
import 'package:material_ui/material_ui.dart' show ThemeMode;
''');
    write('$lib/src/l10n/pdf_l10n.dart', '''
import '../../l10n/generated.dart';
''');
    write('$lib/l10n/generated.dart', '''
import 'package:flutter_localizations/flutter_localizations.dart';
''');
    write('$lib/src/editing/model.dart', '''
import 'package:flutter/widgets.dart';
import 'leaky.dart';
''');
    write('$lib/src/editing/leaky.dart', '''
import 'package:flutter/cupertino.dart';
void f() {
  // showMenu( in a comment does not count
  showMenu(context: c);
  showModalBottomSheet<void>(context: c);
  ScaffoldMessenger.of(c);
  DropdownButtonHideUnderline(child: DropdownButtonFormField());
  TextField(key: k, decoration: d(')'));
  TextField(contextMenuBuilder: (c, s) => Adaptive(c, s));
  TextFormField(contextMenuBuilder: pdfTextContextMenu, onChanged: (v) {});
  SelectableText('x', contextMenuBuilder: (c, s) =>
      pdfStockTextContextMenu(c, s, systemMenu: false));
  TextFieldTapRegion(child: x);
}
''');
    write('$lib/src/design/menu.dart', '''
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
void g() => showMenu(context: c);
''');
    // the bridge may use the legacy libraries
    write('$lib/src/legacy/bridge.dart', '''
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_localizations/flutter_localizations.dart';
''');
    // the printing package's lib/ is counted too (no design/ exemption)
    write('packages/dart_pdf_printing/lib/src/preview.dart', '''
void h() => DropdownButton(items: []);
''');
    write('$lib/src/pdf_page_view.dart', '''
import 'package:flutter_localizations/flutter_localizations.dart';
''');

    final resolver = PackageResolver({
      'dart_pdf_editor': Uri.directory('${root.path}/$lib'),
    });
    final result = scan(root.path, resolver);

    _expect(
        result.baseline.materialImporters,
        {
          '$lib/src/design/menu.dart',
          '$lib/src/editing/editing_preferences.dart',
          '$lib/src/editing/leaky.dart',
          '$lib/src/legacy/bridge.dart',
        },
        'design-library importers (legacy and material_ui)');
    final problems = result.problems;
    bool has(String text) => problems.any((p) => p.contains(text));
    _expect(problems.length, 6, 'problem count: $problems');
    _expect(
        has('editing_controller.dart -> $lib/src/editing/model.dart -> '
            '$lib/src/editing/leaky.dart imports package:flutter/cupertino.dart'),
        true,
        'closure reports the chain to the Material importer: $problems');
    _expect(
        has('editing_controller.dart -> '
            '$lib/src/editing/editing_preferences.dart imports '
            'package:material_ui/material_ui.dart show ThemeMode'),
        true,
        'a material_ui import breaks a headless closure: $problems');
    _expect(
        has('pdf_page_view.dart imports '
            'package:flutter_localizations/flutter_localizations.dart (only'),
        true,
        'flutter_localizations is allowed only from lib/l10n/: $problems');
    _expect(
        has('$lib/src/editing/leaky.dart imports '
            'package:flutter/cupertino.dart: only'),
        true,
        'legacy imports outside lib/src/legacy/ fail: $problems');
    _expect(
        has('$lib/src/design/menu.dart imports '
            'package:flutter_localizations/flutter_localizations.dart: its'),
        true,
        'flutter_localizations outside lib/l10n/ fails: $problems');
    _expect(
        has('$lib/src/pdf_page_view.dart imports '
            'package:flutter_localizations/flutter_localizations.dart: its'),
        true,
        'flutter_localizations outside lib/l10n/ fails: $problems');
    _expect(has('legacy/bridge.dart'), false,
        'the bridge may import the legacy libraries: $problems');
    _expect(
        result.baseline.counters,
        {
          'showMenu': {'$lib/src/editing/leaky.dart': 1},
          'showModalBottomSheet': {'$lib/src/editing/leaky.dart': 1},
          'ScaffoldMessenger': {'$lib/src/editing/leaky.dart': 1},
          'DropdownButton': {
            '$lib/src/editing/leaky.dart': 1,
            'packages/dart_pdf_printing/lib/src/preview.dart': 1,
          },
          'TextFieldWithoutMenu': {'$lib/src/editing/leaky.dart': 2},
        },
        'counters skip comments and lib/src/design/, and scan printing');
  } finally {
    root.deleteSync(recursive: true);
  }
}

void _ratchet() {
  final baseline = DesignBaseline({
    'a.dart',
    'b.dart'
  }, {
    'showMenu': {'a.dart': 2, 'b.dart': 1},
  });
  final current = DesignBaseline({
    'a.dart',
    'c.dart'
  }, {
    'showMenu': {'a.dart': 3},
  });
  final r = compare(baseline, current);
  _expect(r.growth.length, 2, 'growth: new importer + more uses');
  _expect(r.growth.any((g) => g.startsWith('c.dart imports')), true,
      'new importer reported');
  _expect(r.growth.any((g) => g.startsWith('a.dart: 3 raw showMenu')), true,
      'counter growth reported');
  _expect(r.stale.length, 2, 'stale: dropped importer + fewer uses');
  _expect(
      compare(
          baseline,
          DesignBaseline.fromJson({
            'materialImporters': ['a.dart', 'b.dart'],
            'counters': {
              'showMenu': {'a.dart': 2, 'b.dart': 1}
            }
          })).growth,
      <String>[],
      'round trip is clean');
  final encoded = baseline.encode();
  _expect(encoded.endsWith('\n'), true, 'baseline ends with a newline');
}
