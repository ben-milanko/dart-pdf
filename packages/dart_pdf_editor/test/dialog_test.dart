// The regression exercises the same feature gate that Flutter's showDialog
// consults when deciding whether to create a native dialog window.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PDF dialogs remain interactive inside a windowed view',
      (tester) async {
    final original = isWindowingEnabled;
    isWindowingEnabled = true;
    String? result;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('In-view dialog'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'accepted'),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('In-view dialog'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(result, 'accepted');
      expect(find.text('In-view dialog'), findsNothing);
    } finally {
      isWindowingEnabled = original;
    }
  });
}
