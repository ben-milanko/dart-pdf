import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  patrolTest(
    'opens the demo, follows PDF links, and keeps overlays interactive',
    ($) async {
      const showAnnotationsKey = 'dart_pdf_editor.editing.showAnnotations';
      final preferences = await SharedPreferences.getInstance();
      final previousShowAnnotations = preferences.getBool(showAnnotationsKey);
      await preferences.setBool(showAnnotationsKey, true);
      addTearDown(() async {
        if (previousShowAnnotations == null) {
          await preferences.remove(showAnnotationsKey);
        } else {
          await preferences.setBool(
            showAnnotationsKey,
            previousShowAnnotations,
          );
        }
      });
      await $.pumpWidget(const ViewerApp());

      // Deferred localizations and the post-frame demo load need several
      // frames. The demo also owns a periodic clock, so pumpAndSettle would
      // never finish.
      for (var i = 0; i < 80 && $(PdfViewer).evaluate().isEmpty; i++) {
        await $.pump(const Duration(milliseconds: 100));
      }
      expect($(PdfViewer), findsOneWidget);
      expect($(const ValueKey('pdf-page-number-field')), findsOneWidget);
      expect($(const ValueKey('pdf-search-field')), findsOneWidget);

      // Exercise Patrol's out-of-process platform bridge as well as its
      // Flutter finder layer. Native automation is not implemented on macOS.
      if ($.isAndroid || $.isIOS) {
        expect(await $.platform.mobile.getOsVersion(), greaterThan(0));
      } else if ($.isWeb) {
        expect(await $.platform.web.getCurrentPageUrl(), isNotEmpty);
      }

      final viewer = $.tester.getRect(find.byType(PdfViewer));
      const pageAspect = 792 / 612;
      final zoom =
          (viewer.height / (viewer.width * pageAspect)).clamp(0.0, 1.0);
      final pageWidth = viewer.width * zoom;
      final page = Rect.fromLTWH(
        viewer.left + (viewer.width - pageWidth) / 2,
        viewer.top,
        pageWidth,
        pageWidth * pageAspect,
      );

      Offset onPage(double x, double y) {
        final scale = page.width / 612;
        return page.topLeft + Offset(x * scale, (792 - y) * scale);
      }

      Finder plainText(String value) => find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == value,
          );
      Finder viewerText(String value) => find.descendant(
            of: find.byType(PdfViewer),
            matching: plainText(value),
          );

      // Compact viewports keep more than one demo overlay alive in the
      // viewer cache, and both can expose the shared counter value.
      expect(viewerText('0'), findsWidgets);
      expect(viewerText('1'), findsNothing);
      await $.tester.tapAt(onPage(176, 618));
      await $.pump(const Duration(milliseconds: 400));
      expect(viewerText('1'), findsWidgets);

      await $.tester.tapAt(onPage(176, 498));
      await $.pump(const Duration(milliseconds: 400));
      // The first pump resolves the competing double-tap recognizer. Give
      // the viewer's destination scroll animation its own bounded pump.
      await $.pump(const Duration(milliseconds: 350));
      expect($(Switch), findsOneWidget);
      expect($.tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await $.tester.tap(find.byType(Switch));
      await $.pump(const Duration(milliseconds: 400));
      expect($.tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      // Dispose the demo's periodic clock before Patrol checks test invariants.
      await $.pumpWidget(const SizedBox());
      await $.pump();
    },
  );
}
