// The tab-set transitions, without pumping EditorScreen: ordering, focus,
// the restored block, and disposal after the unmounting frame.

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/document_tabs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tab extends DocumentTab {
  _Tab(String title) : super.error(title: title, error: 'x');

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Loading extends DocumentTab {
  _Loading(String title) : super.loading(title: title);
}

void main() {
  late List<VoidCallback> frame;
  late DocumentTabs tabs;
  late int changes;

  setUp(() {
    frame = [];
    tabs = DocumentTabs(afterFrame: frame.add)..addListener(() => changes++);
    changes = 0;
  });

  void endFrame() {
    for (final callback in List.of(frame)) {
      callback();
    }
    frame.clear();
  }

  List<String> titles() => [for (final tab in tabs.tabs) tab.title];

  test('every change notifies', () {
    final a = _Tab('a');
    tabs
      ..add(a)
      ..add(_Tab('b'))
      ..activate(0)
      ..reorder(0, 1)
      ..remove([a]);
    expect(changes, 5);
  });

  test('restored tabs slot in ahead of what the user opened', () {
    tabs.add(_Tab('launched'));
    tabs.add(_Tab('restored 1'), restored: true);
    tabs.add(_Tab('restored 2'), restored: true);
    expect(titles(), ['restored 1', 'restored 2', 'launched']);
    expect(tabs.active!.title, 'launched',
        reason: 'the launched file keeps focus');
    expect(tabs.restoredCount, 2);
  });

  test('a restored tab takes focus only while nothing else is open', () {
    tabs.add(_Tab('restored'), restored: true);
    expect(tabs.active!.title, 'restored');
  });

  test('re-opening a restored placeholder moves it to the end', () {
    final placeholder = _Loading('report');
    tabs
      ..add(placeholder, restored: true)
      ..add(_Tab('other'), restored: true)
      ..add(_Tab('launched'));
    tabs.focusOpened(placeholder);
    expect(titles(), ['other', 'launched', 'report']);
    expect(tabs.active, same(placeholder));
    expect(tabs.restoredCount, 1);
  });

  test('a document on its feet keeps its place when re-opened', () {
    final doc = _Tab('doc');
    tabs
      ..add(doc, restored: true)
      ..add(_Tab('launched'));
    tabs.focusOpened(doc);
    expect(titles(), ['doc', 'launched']);
    expect(tabs.active, same(doc));
  });

  test('replace swaps in place, keeps focus, disposes after the frame', () {
    final loading = _Tab('placeholder');
    final other = _Tab('other');
    tabs
      ..add(loading)
      ..add(other);
    final built = _Tab('document');
    expect(tabs.replace(loading, built), isTrue);
    expect(titles(), ['document', 'other']);
    expect(tabs.active, same(other));
    expect(loading.disposed, isFalse, reason: 'still mounted this frame');
    endFrame();
    expect(loading.disposed, isTrue);
  });

  test('replacing a closed tab disposes the replacement instead', () {
    final gone = _Tab('gone');
    final built = _Tab('built');
    expect(tabs.replace(gone, built), isFalse);
    expect(built.disposed, isTrue);
    expect(changes, 0);
  });

  test('remove keeps the active document, else falls to a neighbour', () {
    final a = _Tab('a'), b = _Tab('b'), c = _Tab('c');
    tabs
      ..add(a)
      ..add(b)
      ..add(c)
      ..activate(1);
    tabs.remove([a]);
    expect(tabs.active, same(b));
    tabs.remove([b]);
    expect(tabs.active, same(c));
    endFrame();
    expect(a.disposed && b.disposed, isTrue);
    expect(c.disposed, isFalse);
  });

  test('removing from the restored block keeps its count honest', () {
    final restored = _Tab('restored');
    tabs
      ..add(restored, restored: true)
      ..add(_Tab('user'));
    tabs.remove([restored]);
    expect(tabs.restoredCount, 0);
    tabs.add(_Tab('late restore'), restored: true);
    expect(titles(), ['late restore', 'user']);
  });

  test('reorder keeps the active document active', () {
    final a = _Tab('a'), b = _Tab('b'), c = _Tab('c');
    tabs
      ..add(a)
      ..add(b)
      ..add(c)
      ..activate(0);
    tabs.reorder(0, 2);
    expect(titles(), ['b', 'c', 'a']);
    expect(tabs.active, same(a));
  });

  test('a handed-over tab is inserted where it was dropped, active', () {
    tabs
      ..add(_Tab('a'))
      ..add(_Tab('b'));
    tabs.insert(1, _Tab('handoff'));
    expect(titles(), ['a', 'handoff', 'b']);
    expect(tabs.active!.title, 'handoff');
    tabs.insert(99, _Tab('end'));
    expect(titles().last, 'end');
  });

  test('documentId keys by the origin, not the title', () {
    final one =
        DocumentTab.loading(title: 'report.pdf', originPath: '/a/report.pdf');
    final two =
        DocumentTab.loading(title: 'report.pdf', originPath: '/b/report.pdf');
    final cached =
        DocumentTab.loading(title: 'report.pdf', cachePath: 'cache/123.pdf');
    final bare = DocumentTab.loading(title: 'report.pdf');
    expect(one.documentId, isNot(two.documentId));
    expect(cached.documentId, 'cache/123.pdf');
    expect(bare.documentId, 'report.pdf');
  });
}
