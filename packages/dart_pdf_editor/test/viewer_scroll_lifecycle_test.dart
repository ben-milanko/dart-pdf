import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exercise a controller update from inside the page's nested build scope.
// This models the text-session cleanup a page lifecycle callback can publish;
// without deferral it dirties the viewer and the page's listening ancestors.
class _CloseEditingOnUpdate extends StatefulWidget {
  const _CloseEditingOnUpdate(this.editing);
  final PdfEditingController editing;
  @override
  State<_CloseEditingOnUpdate> createState() => _CloseEditingOnUpdateState();
}

class _CloseEditingOnUpdateState extends State<_CloseEditingOnUpdate> {
  @override
  void didUpdateWidget(_CloseEditingOnUpdate oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.editing.setEditingText(false);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('frame notifications coalesce while input stays synchronous',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await editing.preferences.ready;
    final phases = <SchedulerPhase>[];
    editing.addListener(() => phases.add(tester.binding.schedulerPhase));
    editing.setEditingText(true);
    expect(phases, [SchedulerPhase.idle]);
    phases.clear();
    await tester.pumpWidget(Builder(builder: (context) {
      editing.setEditingText(false);
      editing.setEditingText(true);
      expect(editing.isEditingText, isTrue);
      expect(phases, isEmpty);
      return const SizedBox.shrink();
    }));
    expect(phases, [SchedulerPhase.postFrameCallbacks]);
  });

  testWidgets('a pending notification cannot outlive its controller',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    await editing.preferences.ready;
    var notifications = 0;
    editing.addListener(() => notifications++);
    await tester.pumpWidget(Builder(builder: (context) {
      editing.setEditingText(true);
      editing.dispose();
      return const SizedBox.shrink();
    }));
    expect(notifications, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page lifecycle notifications do not dirty a rebuilding viewer',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(57));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfViewer(
      document: editing.document,
      editing: editing,
      controller: viewer,
      pagePreviews: false,
      pageOverlayBuilder: (context, index, geometry) => [
        _CloseEditingOnUpdate(editing),
      ],
    ))));
    await tester.pump();
    editing.setEditingText(true);
    viewer.setZoom(0.22);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(editing.isEditingText, isFalse);
    expect(find.byType(PdfPageView), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('scrolling past a focused inline editor preserves navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(57));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    editing.addFreeText(0, const PdfRect(100, 600, 300, 700), 'Note');
    editing.selectAnnotation(0, 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            document: editing.document,
            editing: editing,
            controller: viewer,
            pagePreviews: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing.requestEditSelectedTextInline();
    await tester.pump();
    expect(editing.isEditingText, isTrue);
    viewer.jumpToPage(44);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(viewer.currentPage, 44);
    // Flutter keeps the focused editor alive off-screen. It must not block
    // touch navigation or corrupt the lazy list while other pages rebuild.
    await tester.drag(find.byType(PdfViewer), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(viewer.currentPage, greaterThan(44));
    expect(find.byType(PdfPageView), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
