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
}
