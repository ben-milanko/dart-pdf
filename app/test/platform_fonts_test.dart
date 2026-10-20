import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/platform_fonts.dart';

void main() {
  test('installed-font discovery returns one sorted entry per family',
      () async {
    // The real scan over this host's font directories, run on its helper
    // isolate (the app skips it under widget tests). An empty list is a valid
    // answer on a font-less CI image.
    final fonts = await loadPlatformFonts();

    expect(fonts.length, lessThanOrEqualTo(300));
    final keys = [for (final font in fonts) font.label.toLowerCase()];
    expect(keys, orderedEquals([...keys]..sort()));
    expect({for (final font in fonts) font.family}, hasLength(fonts.length));
    for (final font in fonts) {
      expect(font.family, isNotEmpty);
      expect(font.label, font.family);
    }
    // The bytes still load lazily, on this isolate, from the scanned path.
    if (fonts.isNotEmpty) expect(await fonts.first.loadBytes(), isNotNull);
  });
}
