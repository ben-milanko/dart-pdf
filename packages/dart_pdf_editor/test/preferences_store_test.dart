// PdfEditingPreferences(store:) keeps the preferences in a host-supplied
// PdfPreferencesStore instead of the device's shared_preferences.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reads from and writes to the injected store only', () async {
    final store = PdfMemoryPreferencesStore({
      'dart_pdf_editor.editing.strokeWidth': 7.5,
    });
    final prefs = PdfEditingPreferences(store: store);
    addTearDown(prefs.dispose);
    await prefs.ready;
    expect(prefs.strokeWidth, 7.5);

    prefs.strokeWidth = 3;
    expect(store.getDouble('dart_pdf_editor.editing.strokeWidth'), 3);
    final device = await SharedPreferences.getInstance();
    expect(device.getKeys(), isEmpty, reason: 'nothing reached the device');

    // a second instance over the same store sees the write
    final again = PdfEditingPreferences(store: store);
    addTearDown(again.dispose);
    await again.ready;
    expect(again.strokeWidth, 3);
  });

  test('without a store the device default is used', () async {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor.editing.strokeWidth': 5.0,
    });
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await prefs.ready;
    expect(prefs.strokeWidth, 5);
  });

  test('PdfMemoryPreferencesStore round-trips every value type', () async {
    final store = PdfMemoryPreferencesStore();
    await store.setBool('b', true);
    await store.setInt('i', 3);
    await store.setDouble('d', 1.5);
    await store.setString('s', 'x');
    await store.setStringList('l', ['a', 'b']);
    expect(store.getBool('b'), isTrue);
    expect(store.getInt('i'), 3);
    expect(store.getDouble('d'), 1.5);
    expect(store.getString('s'), 'x');
    expect(store.getStringList('l'), ['a', 'b']);
    expect(store.getString('i'), isNull, reason: 'wrong type reads as null');
    expect(store.containsKey('s'), isTrue);
    await store.remove('s');
    expect(store.containsKey('s'), isFalse);
  });
}
