import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file in this package (a Flutter test convention).
///
/// Many editor tests build a [PdfEditingController], which loads
/// [PdfEditingPreferences] from `shared_preferences` asynchronously. With no
/// mock registered the plugin call fails with `MissingPluginException`, and
/// because it can land after a synchronous test body has already finished it
/// surfaces as a flaky "failed after test completion". Registering a default
/// empty mock store here gives every test an in-memory backing so that never
/// happens; individual tests may still call [SharedPreferences.setMockInitialValues]
/// to seed their own values.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
