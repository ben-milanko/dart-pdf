// A desktop path-open of a file on fast local storage skips the read-only
// progressive preview: the first-paint open's reads come back local-fast, so
// the rest of the file is read straight after it and the tab becomes an edit
// session directly - one worker generation and one page-0 render, where the
// preview-and-swap path pays for a throwaway second set. A slow source (a
// cloud provider fetching on demand) still mounts the preview at once, with no
// wait; so does storage that answers small reads fast but streams slowly (a
// network share, a USB stick), a few milliseconds into the whole read. Every
// path reads the file exactly once.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/incoming_file.dart';
import 'package:dart_pdf_editor_app/session_store.dart';

import 'test_finders.dart';

/// A [pages]-page PDF with an unreferenced [padding]-byte stream after each
/// page, so a ranged first-paint open needs a read per page leaf and none of
/// its reads happens to span the whole file.
Uint8List _paddedPdf({int pages = 4, int padding = 96 * 1024}) {
  const content = 'BT /F1 24 Tf 72 720 Td (Padded page) Tj ET';
  final kids = [for (var i = 0; i < pages; i++) '${4 + 3 * i} 0 R'];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${kids.join(' ')}] /Count $pages >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    for (var i = 0; i < pages; i++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents ${5 + 3 * i} 0 R /Resources << /Font << /F1 3 0 R >> >> >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      '<< /Length $padding >>\nstream\n${'0' * padding}\nendstream',
    ],
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// What the fake native file-access channel was asked for.
class _Reads {
  int ranges = 0;
  int wholeRanges = 0;
  int wholeFiles = 0;

  /// Every ranged read of at least 256 KB, as `(offset, end)`: the whole-file
  /// read's chunks, where the first-paint open's reads are all far smaller.
  final big = <(int, int)>[];
}

/// Whether [ranges] cover `[0, length)` exactly once, in order.
bool _tileOnce(List<(int, int)> ranges, int length) {
  var pos = 0;
  for (final (start, end) in ranges) {
    if (start != pos || end <= start) return false;
    pos = end;
  }
  return pos == length;
}

void main() {
  const fileAccess = MethodChannel('dev.milanko.dartpdf/file_access');
  late PdfEditingPreferences prefs;
  late Directory tempDir;
  late List<String> perf;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    tempDir = Directory.systemTemp.createTempSync('dartpdf_direct_open_test');
    AppDevTools.instance.clearLog();
    perf = <String>[];
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = perf.add;
  });

  tearDown(() {
    PdfPerfLog.sink = null;
    PdfPerfLog.enabled = false;
    debugDirectOpenMaxMeanReadMs = null;
    debugDirectOpenWaitMs = null;
    prefs.dispose();
    tempDir.deleteSync(recursive: true);
  });

  // The platform override has to be cleared before the test body ends, or the
  // binding's invariant check fails the test.
  Future<void> onPlatform(
      TargetPlatform platform, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  // Serves a bookmarked macOS file from [bytes] through the native
  // file-access channel, as the runner does: every ranged read takes
  // [readDelay], plus [perMegabyte] for each MB it returns, and a read of the
  // whole file first waits for [holdWhole]. [wholeBytes], if given, is what
  // the whole-file read's chunks (and a plain whole read) get instead.
  _Reads serveBookmarkedFile(WidgetTester tester, Uint8List bytes,
      {Duration readDelay = Duration.zero,
      Duration perMegabyte = Duration.zero,
      Future<void>? holdWhole,
      Uint8List? wholeBytes}) {
    final reads = _Reads();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileAccess,
      (call) async {
        final args = (call.arguments as Map).cast<Object?, Object?>();
        switch (call.method) {
          case 'fileLength':
            return bytes.length;
          case 'readFileRange':
            final offset = args['offset'] as int;
            final length = args['length'] as int;
            reads.ranges++;
            if (offset >= bytes.length) return Uint8List(0);
            final end = (offset + length).clamp(0, bytes.length);
            final whole = offset == 0 && length >= bytes.length;
            final big = end - offset >= 256 * 1024;
            if (whole) {
              reads.wholeRanges++;
              await holdWhole;
            }
            if (big) reads.big.add((offset, end));
            await Future<void>.delayed(
                readDelay + perMegabyte * ((end - offset) / (1 << 20)));
            final served =
                (whole || big) && wholeBytes != null ? wholeBytes : bytes;
            return Uint8List.sublistView(served, offset, end);
          case 'readFile':
            reads.wholeFiles++;
            return wholeBytes ?? bytes;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(fileAccess, null));
    return reads;
  }

  String seedFile(String name, Uint8List bytes) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: findMiddleEllipsisText(name),
      );

  String devLog() => AppDevTools.instance.log.map((e) => e.message).join('\n');

  int perfCount(String needle) => perf.where((l) => l.contains(needle)).length;

  // The work an open cost, read from the deterministic PdfPerfLog lines:
  // main-isolate parses (the sparse first-paint one is paid either way),
  // render-worker generations, and page-0 renders.
  ({int sparse, int whole, int generations, int page0}) counts() => (
        sparse: perfCount('cos open bytes=') - perfCount('whole-file'),
        whole: perfCount('whole-file'),
        generations: perfCount('performance mode='),
        page0: perfCount('interpret page=0 '),
      );

  // Whether the newest worker generation - the edit session's - has painted
  // page 0.
  bool editablePainted() {
    if (find.byType(PdfEditorView).evaluate().isEmpty) return false;
    if (!devLog().contains('fast-path direct') &&
        !devLog().contains('full read complete')) {
      return false;
    }
    final generation =
        perf.lastIndexWhere((l) => l.contains('performance mode='));
    return generation != -1 &&
        perf.skip(generation).any((l) => l.contains('page-ready page=0'));
  }

  // Real frames: the open does file I/O and spawns render workers, which only
  // progress under runAsync. Pumps until [done] (or a generous cap), then lets
  // trailing work land.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 400 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
  }

  // Lets whatever an open still has in flight land (real frames, as above).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
  }

  // Mounts the editor, then hands it [args] the way the OS hands over a file.
  Future<void> deliverFile(
      WidgetTester tester, Map<String, Object?> args) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      perf.clear();
      const codec = StandardMethodCodec();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        IncomingFileService.channelName,
        codec.encodeMethodCall(MethodCall('openFile', args)),
        (_) {},
      );
    });
  }

  testWidgets('a fast local file opens straight into an edit session',
      (tester) async {
    await onPlatform(TargetPlatform.linux, () async {
      // Take the direct read however this machine's reads timed: the
      // threshold itself is exercised by the slow-source test below.
      debugDirectOpenMaxMeanReadMs = double.infinity;
      final path = seedFile('local.pdf', Uint8List.fromList(buildClassicPdf()));

      await deliverFile(tester, {'name': 'local.pdf', 'path': path});
      await pumpUntil(tester, editablePainted);

      expect(tabTitle('local.pdf'), findsOneWidget);
      expect(find.byType(PdfEditorView), findsOneWidget);
      final log = devLog();
      expect(log, contains('open-trace: fast-path direct'));
      // No read-only preview was ever mounted, so nothing was swapped.
      expect(log, isNot(contains('first paint')));
      expect(log, isNot(contains('full read complete')));
      expect(counts(), (sparse: 1, whole: 1, generations: 1, page0: 1));
      // The recent is recorded, as a preview's first paint records it.
      final stored = (await SharedPreferences.getInstance())
          .getString('dart_pdf_editor_app.recents');
      final recents = jsonDecode(stored!) as List;
      expect(recents.map((r) => (r as Map)['p']), [path]);
    });
  });

  testWidgets('the preview-and-swap path it replaces renders page 0 twice',
      (tester) async {
    final releaseWhole = Completer<void>();
    addTearDown(() {
      if (!releaseWhole.isCompleted) releaseWhole.complete();
    });
    final reads = serveBookmarkedFile(tester, _paddedPdf(),
        holdWhole: releaseWhole.future);
    await onPlatform(TargetPlatform.macOS, () async {
      debugDirectOpenMaxMeanReadMs = -1;

      await deliverFile(tester, {
        'name': 'doc.pdf',
        'path': '/docs/doc.pdf',
        'bookmark': 'doc-bookmark',
      });
      // Hold the whole read until the preview has painted, as a file big
      // enough to be worth a preview would.
      await pumpUntil(tester, () => perfCount('page-ready page=0') > 0);
      releaseWhole.complete();
      await pumpUntil(tester, editablePainted);

      expect(find.byType(PdfEditorView), findsOneWidget);
      final log = devLog();
      expect(log, isNot(contains('fast-path')));
      expect(log, contains('progressive open: "doc.pdf" first paint'));
      expect(log, contains('full read complete'));
      // The preview's reader re-parses the sparse buffer, and its viewer
      // spins up a worker generation and renders page 0, all thrown away by
      // the swap.
      expect(counts(), (sparse: 2, whole: 1, generations: 2, page0: 2));
      expect(reads.wholeRanges, 1);
    });
  });

  testWidgets('a direct read that misses its wait hands over to the preview',
      (tester) async {
    final releaseWhole = Completer<void>();
    addTearDown(() {
      if (!releaseWhole.isCompleted) releaseWhole.complete();
    });
    final reads = serveBookmarkedFile(tester, _paddedPdf(),
        holdWhole: releaseWhole.future);
    await onPlatform(TargetPlatform.macOS, () async {
      debugDirectOpenMaxMeanReadMs = double.infinity;

      await deliverFile(tester, {
        'name': 'doc.pdf',
        'path': '/docs/doc.pdf',
        'bookmark': 'doc-bookmark',
      });
      // The whole read is stuck, so the bounded wait gives up and the
      // preview goes up with that same read still in flight...
      await pumpUntil(tester, () => perfCount('page-ready page=0') > 0);
      expect(devLog(), contains('open-trace: fast-path missed'));
      expect(devLog(), contains('reason=deadline'));
      expect(devLog(), contains('progressive open: "doc.pdf" first paint'));
      releaseWhole.complete();
      await pumpUntil(tester, editablePainted);

      // ...which completes the swap without a second read of the file.
      expect(find.byType(PdfEditorView), findsOneWidget);
      expect(devLog(), contains('full read complete'));
      expect(reads.wholeRanges, 1);
      expect(reads.wholeFiles, 0);
    });
  });

  testWidgets('a slow source mounts the preview at once and reads once',
      (tester) async {
    // Answering every read 20 ms late is a cloud provider fetching on demand.
    final reads = serveBookmarkedFile(tester, _paddedPdf(),
        readDelay: const Duration(milliseconds: 20));
    await onPlatform(TargetPlatform.macOS, () async {
      await deliverFile(tester, {
        'name': 'cloud.pdf',
        'path': '/cloud/cloud.pdf',
        'bookmark': 'cloud-bookmark',
      });
      await pumpUntil(tester, editablePainted);

      expect(find.byType(PdfEditorView), findsOneWidget);
      final log = devLog();
      // The reads came back slow, so the gate stayed shut: no bounded wait,
      // the preview went up as soon as the first-paint open finished...
      expect(log, isNot(contains('fast-path')));
      expect(log, contains('progressive open: "cloud.pdf" first paint'));
      expect(log, contains('full read complete'));
      // ...and the file was read whole exactly once, behind it.
      expect(reads.ranges, greaterThan(2));
      expect(reads.wholeRanges, 1);
      expect(reads.wholeFiles, 0);
    });
  });

  testWidgets('a restored local tab opens straight into an edit session',
      (tester) async {
    await onPlatform(TargetPlatform.linux, () async {
      debugDirectOpenMaxMeanReadMs = double.infinity;
      final path =
          seedFile('restored.pdf', Uint8List.fromList(buildClassicPdf()));
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session': jsonEncode([
          {'t': 'restored.pdf', 'p': path}
        ]),
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });
      await pumpUntil(tester, editablePainted);

      // The deferred placeholder was replaced in place by the edit session.
      expect(tabTitle('restored.pdf'), findsOneWidget);
      expect(find.byType(PdfEditorView), findsOneWidget);
      expect(find.byTooltip('Close tab'), findsOneWidget);
      final log = devLog();
      expect(log, contains('open-trace: fast-path direct'));
      expect(log, isNot(contains('first paint')));
      expect(counts(), (sparse: 1, whole: 1, generations: 1, page0: 1));
      // Still recorded for the next launch.
      final persisted = await SessionStore().load();
      expect(persisted.map((d) => d.path), [path]);
    });
  });
  testWidgets(
      'storage quick to answer but slow to stream hands over to the preview '
      'without waiting out the budget', (tester) async {
    // A network share or a USB stick: small reads come back at once, but
    // every megabyte takes 300 ms to arrive. The first-paint open's reads
    // pass the latency check (forced open here, so a loaded test machine
    // can't shut it), and the whole read, nearly 4 MB at that rate, can't
    // land in any budget the open allows. (Its chunks run 1, 2, then the
    // last 0.75 MB, each big enough to tell from the open's own reads.)
    final bytes = _paddedPdf(padding: 960 * 1024);
    expect(bytes.length, inInclusiveRange(3.5 * (1 << 20), 4 << 20));
    final reads = serveBookmarkedFile(tester, bytes,
        perMegabyte: const Duration(milliseconds: 300));
    await onPlatform(TargetPlatform.macOS, () async {
      debugDirectOpenMaxMeanReadMs = double.infinity;

      await deliverFile(tester, {
        'name': 'share.pdf',
        'path': '/share/share.pdf',
        'bookmark': 'share-bookmark',
      });
      await pumpUntil(tester, () => perfCount('page-ready page=0') > 0);
      final log = devLog();
      // It fell behind before its first 1 MB chunk was in, so the preview went
      // up then - no wait for the budget to run out.
      expect(log, contains('open-trace: fast-path skipped'));
      expect(log, contains('behindAtBytes=0 '));
      expect(log, isNot(contains('fast-path missed')));
      expect(log, contains('progressive open: "share.pdf" first paint'));

      await pumpUntil(tester, editablePainted);
      expect(find.byType(PdfEditorView), findsOneWidget);
      expect(devLog(), contains('full read complete'));
      // That same read finished the swap: the file was read whole once.
      expect(reads.big.first, (0, 1 << 20));
      expect(_tileOnce(reads.big, bytes.length), isTrue,
          reason: '${reads.big}');
      expect(reads.wholeFiles, 0);
    });
  });

  testWidgets('a tab closed while its direct read is in flight builds nothing',
      (tester) async {
    final releaseWhole = Completer<void>();
    addTearDown(() {
      if (!releaseWhole.isCompleted) releaseWhole.complete();
    });
    final reads = serveBookmarkedFile(tester, _paddedPdf(),
        holdWhole: releaseWhole.future);
    await onPlatform(TargetPlatform.macOS, () async {
      debugDirectOpenMaxMeanReadMs = double.infinity;
      // A budget the held read can't run out of, so it lands as a direct
      // read after the tab is gone.
      debugDirectOpenWaitMs = 60000;

      await deliverFile(tester, {
        'name': 'doc.pdf',
        'path': '/docs/doc.pdf',
        'bookmark': 'doc-bookmark',
      });
      await pumpUntil(tester, () => reads.wholeRanges == 1);
      expect(tabTitle('doc.pdf'), findsOneWidget);
      await tester.tap(find.byTooltip('Close tab'));
      await tester.pump();
      expect(tabTitle('doc.pdf'), findsNothing);
      releaseWhole.complete();
      await pumpUntil(
          tester, () => devLog().contains('open-trace: fast-path direct'));
      await settle(tester);

      expect(devLog(), contains('open-trace: fast-path direct'));
      // No edit session was parsed for the closed tab, no preview mounted in
      // its place, and no render workers spun up.
      expect(perfCount('whole-file'), 0);
      expect(perfCount('performance mode='), 0);
      expect(devLog(), isNot(contains('first paint')));
      expect(tabTitle('doc.pdf'), findsNothing);
    });
  });

  testWidgets(
      'a direct read whose document fails to parse leaves an error tab, '
      'as the preview swap did', (tester) async {
    // The first-paint open reads the real file, but the whole read gets
    // bytes that aren't a PDF. The read itself worked, so this is not a
    // gone origin: the restore's onOpenFailed (close quietly) must not run.
    final bytes = _paddedPdf();
    serveBookmarkedFile(tester, bytes, wholeBytes: Uint8List(bytes.length));
    await onPlatform(TargetPlatform.macOS, () async {
      debugDirectOpenMaxMeanReadMs = double.infinity;
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor_app.session': jsonEncode([
          {'t': 'broken.pdf', 'p': '/docs/broken.pdf', 'b': 'broken-bookmark'}
        ]),
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      });
      await pumpUntil(
          tester, () => devLog().contains('open-trace: fast-path direct'));
      await settle(tester);

      expect(devLog(), contains('open-trace: fast-path direct'));
      expect(find.byType(PdfEditorView), findsNothing);
      // The tab is still there, showing why it didn't open.
      expect(tabTitle('broken.pdf'), findsOneWidget);
      expect(find.byTooltip('Close tab'), findsOneWidget);
    });
  });
}
