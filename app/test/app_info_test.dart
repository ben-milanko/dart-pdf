import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/app_info.dart';

// `flutter test --dart-define=PDF_BUILD_CHANNEL=nightly` exercises the nightly
// half; a plain run checks the stable identity.
void main() {
  test('the running build names its release channel', () {
    if (AppInfo.isNightly) {
      expect(AppInfo.buildChannel, 'nightly');
      expect(AppInfo.displayName, 'DartPDF Nightly');
      expect(AppInfo.displayVersion, startsWith('${AppInfo.version} nightly'));
    } else {
      expect(AppInfo.buildChannel, 'stable');
      expect(AppInfo.displayName, AppInfo.name);
      expect(AppInfo.displayVersion, AppInfo.version);
    }
  });

  test('a nightly version names its source commit', () {
    String format(bool nightly, String commit) => AppInfo.formatDisplayVersion(
        version: '2.3.0', nightly: nightly, commit: commit);

    expect(format(false, '0123456789abcdef'), '2.3.0');
    expect(format(true, '0123456789abcdef'), '2.3.0 nightly (0123456)');
    expect(format(true, 'abc12'), '2.3.0 nightly (abc12)');
    expect(format(true, 'unknown'), '2.3.0 nightly');
  });
}
