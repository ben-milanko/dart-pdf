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

  test('feedback links reach the issue form and a version-tagged email', () {
    expect(AppInfo.feedbackIssueUrl,
        'https://github.com/ben-milanko/dart-pdf/issues/new?template=app_feedback.yml');

    final mail = AppInfo.feedbackMailto();
    expect(mail.scheme, 'mailto');
    expect(mail.path, AppInfo.feedbackEmail);
    // Spaces must reach the mail client as %20, not `+`.
    expect(mail.toString(), isNot(contains('+')));
    expect(Uri.decodeComponent(mail.query),
        'subject=${AppInfo.displayName} ${AppInfo.displayVersion} feedback');
  });
}
