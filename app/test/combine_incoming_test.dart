// Several PDFs the OS opens together - a multi-file "Open with" - ask whether
// to open them in their own tabs or combine them into one new document.
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';

import 'test_finders.dart';

void main() {
  group('EditorScreen', () {
    late PdfEditingPreferences prefs;
    late Directory tempDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs = PdfEditingPreferences();
      tempDir = Directory.systemTemp.createTempSync('dartpdf_combine_test');
    });

    tearDown(() {
      prefs.dispose();
      tempDir.deleteSync(recursive: true);
    });

    String seedFile(String name,
        {PdfPageSize size = PdfPageSize.letter, int pages = 1}) {
      final path = '${tempDir.path}/$name';
      File(path).writeAsBytesSync(
          PdfBlankDocument.create(pageSize: size, pageCount: pages));
      return path;
    }

    Finder tabTitle(String name) => find.descendant(
          of: find.byKey(const ValueKey('tab-strip')),
          matching: findMiddleEllipsisText(name),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
    }

    // One OS request carrying [paths] - a multi-file "Open with".
    Future<void> openFromOs(WidgetTester tester, List<String> paths,
        {bool combine = false}) async {
      const codec = StandardMethodCodec();
      await tester.runAsync(() async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          IncomingFileService.channelName,
          codec.encodeMethodCall(MethodCall('openFiles', [
            for (final path in paths)
              {
                'name': path.split('/').last,
                'path': path,
                if (combine) 'combine': true,
              },
          ])),
          (_) {},
        );
      });
      await settle(tester);
    }

    Future<void> runOnLinux(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('combines several OS-opened PDFs into one new document',
        (tester) async {
      await runOnLinux(() async {
        // Delivered out of order: the dialog lists them by name.
        final second = seedFile('b-second.pdf', pages: 2);
        final first = seedFile('a-first.pdf', size: PdfPageSize.a4);
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await settle(tester);

        await openFromOs(tester, [second, first]);
        expect(find.byKey(const ValueKey('incoming-files-dialog')),
            findsOneWidget);
        final names = tester
            .widgetList<ListTile>(find.descendant(
                of: find.byKey(const ValueKey('incoming-files-order')),
                matching: find.byType(ListTile)))
            .map((tile) => (tile.title! as Text).data)
            .toList();
        expect(names, ['a-first.pdf', 'b-second.pdf']);

        await tester.tap(find.byKey(const ValueKey('incoming-files-combine')));
        await settle(tester);

        expect(tabTitle('Combined.pdf'), findsOneWidget);
        expect(tabTitle('a-first.pdf'), findsNothing);
        expect(tabTitle('b-second.pdf'), findsNothing);
        final controller = tester
            .widget<PdfEditorView>(find.byType(PdfEditorView))
            .controller!;
        final document = controller.document;
        expect(document.pageCount, 3);
        expect(document.page(0).mediaBox.width,
            closeTo(PdfPageSize.a4.width, 0.5));
        expect(document.page(1).mediaBox.width,
            closeTo(PdfPageSize.letter.width, 0.5));
      });
    });

    testWidgets('can still open OS-opened PDFs in their own tabs',
        (tester) async {
      await runOnLinux(() async {
        final a = seedFile('a.pdf');
        final b = seedFile('b.pdf');
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await settle(tester);

        await openFromOs(tester, [a, b]);
        await tester.tap(find.byKey(const ValueKey('incoming-files-separate')));
        await settle(tester);

        expect(tabTitle('a.pdf'), findsOneWidget);
        expect(tabTitle('b.pdf'), findsOneWidget);
        expect(tabTitle('Combined.pdf'), findsNothing);
      });
    });

    testWidgets('the OS "Combine with DartPDF" entry only asks for the order',
        (tester) async {
      await runOnLinux(() async {
        final a = seedFile('a.pdf', size: PdfPageSize.a4);
        final b = seedFile('b.pdf', pages: 2);
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await settle(tester);

        await openFromOs(tester, [b, a], combine: true);
        expect(find.text('Combine 2 PDFs'), findsOneWidget);
        expect(find.byKey(const ValueKey('incoming-files-separate')),
            findsNothing);

        await tester.tap(find.byKey(const ValueKey('incoming-files-combine')));
        await settle(tester);

        expect(tabTitle('Combined.pdf'), findsOneWidget);
        final controller = tester
            .widget<PdfEditorView>(find.byType(PdfEditorView))
            .controller!;
        expect(controller.document.pageCount, 3);
        expect(controller.document.page(0).mediaBox.width,
            closeTo(PdfPageSize.a4.width, 0.5));
      });
    });

    testWidgets('a cold start with several launch files asks what to do',
        (tester) async {
      await runOnLinux(() async {
        final a = seedFile('a.pdf');
        final b = seedFile('b.pdf');
        await tester.pumpWidget(
            MaterialApp(home: EditorScreen(prefs: prefs, launchArgs: [a, b])));
        await settle(tester);

        expect(find.text('Open 2 PDFs'), findsOneWidget);
        expect(find.byKey(const ValueKey('incoming-files-separate')),
            findsOneWidget);
      });
    });

    testWidgets('a cold start with --combine combines the launch files',
        (tester) async {
      await runOnLinux(() async {
        final a = seedFile('a.pdf');
        final b = seedFile('b.pdf');
        await tester.pumpWidget(MaterialApp(
            home: EditorScreen(prefs: prefs, launchArgs: ['--combine', a, b])));
        await settle(tester);

        expect(find.text('Combine 2 PDFs'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('incoming-files-combine')));
        await settle(tester);
        expect(tabTitle('Combined.pdf'), findsOneWidget);
        expect(tabTitle('a.pdf'), findsNothing);
      });
    });

    testWidgets('a single OS-opened PDF opens without asking', (tester) async {
      await runOnLinux(() async {
        final a = seedFile('solo.pdf');
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await settle(tester);

        await openFromOs(tester, [a]);
        expect(
            find.byKey(const ValueKey('incoming-files-dialog')), findsNothing);
        expect(tabTitle('solo.pdf'), findsOneWidget);
      });
    });
  });
}
