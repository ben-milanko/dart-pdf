import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../patrol_test/native_perf_e2e_test.dart';

void main() {
  testWidgets('native tile pressure journey fills once and settles',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(() async {
      await runNativeTilePerfScenario(
        pump: (duration) => tester.pump(duration),
      );
    });
  });
}
