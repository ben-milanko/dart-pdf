import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Password-field values kept in a [PdfFormSecretStore] instead of /V
/// (#931, ISO 32000 §12.7.4.3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The AcroForm fixture with its `name` field turned into a password
  /// field (still carrying its legacy `/V (prefilled)`), optionally with a
  /// trailer /ID so two "different documents" can be told apart.
  Uint8List passwordForm({Uint8List? id}) {
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final field = editor.acroForm!.fieldNamed('name')!;
    field.dict['Ff'] = const CosInteger(PdfFormField.passwordFlag);
    if (id != null) {
      // withholding writes the /ID when the file has none
      editor.setPasswordValue(field, 'seed', documentId: id);
    }
    editor.setTextValue(field, 'prefilled');
    return editor.save();
  }

  /// A flat [buildMultiPagePdf] with no trailer /ID, given an empty
  /// /AcroForm (and [linksPerPage] indirect /Link annotations on every page)
  /// by an incremental update - the shape where the no-/ID open has to look
  /// at the form to decide whether to hash.
  Uint8List noIdFormPdf(int pageCount, {int linksPerPage = 0}) {
    final doc = PdfDocument.open(buildMultiPagePdf(pageCount));
    final updater = CosIncrementalUpdater(doc.cos);
    if (linksPerPage > 0) {
      for (final page in doc.pages) {
        page.dict['Annots'] = CosArray([
          for (var i = 0; i < linksPerPage; i++)
            updater.addObject(CosDictionary({
              'Type': const CosName('Annot'),
              'Subtype': const CosName('Link'),
              'Rect': CosArray([
                const CosInteger(72),
                CosInteger(700 - i * 20),
                const CosInteger(300),
                CosInteger(712 - i * 20),
              ]),
            })),
        ]);
        updater.markChanged(page.dict);
      }
    }
    doc.catalog['AcroForm'] = CosDictionary({'Fields': CosArray([])});
    updater.markChanged(doc.catalog);
    return updater.save();
  }

  /// [bytes] with every trailer / xref-stream /ID blanked in place - the
  /// same length, so no offset moves - for a builder file that has to open
  /// without one.
  Uint8List withoutId(Uint8List bytes) {
    final out = Uint8List.fromList(bytes);
    final id = RegExp(r'/ID\s*\[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]');
    for (final m in id.allMatches(latin1.decode(bytes))) {
      out.fillRange(m.start, m.end, 0x20);
    }
    return out;
  }

  /// A two-page form without /ID: a cover page showing no widget, then
  /// [fields] combo boxes on page 1, each listing [options] inline /Opt
  /// [export, display] pairs - the country-dropdown shape, where resolving
  /// one field parses its whole option list. With [objectStreams] the objects
  /// pack 128 to a compressed object stream, so the fields spread over about
  /// fields / 128 of them. [withheld] adds a withheld password field `secret`
  /// after the dropdowns.
  Uint8List dropdownNoIdForm(int fields,
      {int options = 40, bool objectStreams = false, bool withheld = false}) {
    final b = CosDocumentBuilder();
    final catalog = CosDictionary({'Type': const CosName('Catalog')});
    final catalogRef = b.add(catalog);
    final pages = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = b.add(pages);
    CosDictionary page() => CosDictionary({
          'Type': const CosName('Page'),
          'Parent': pagesRef,
          'MediaBox': CosArray(const [
            CosInteger(0),
            CosInteger(0),
            CosInteger(612),
            CosInteger(792),
          ]),
        });
    final coverRef = b.add(page());
    final formPage = page();
    final formPageRef = b.add(formPage);
    pages['Kids'] = CosArray([coverRef, formPageRef]);
    pages['Count'] = const CosInteger(2);
    CosDictionary widget(String name, int i) => CosDictionary({
          'Type': const CosName('Annot'),
          'Subtype': const CosName('Widget'),
          'T': CosString.fromText(name),
          'P': formPageRef,
          'Rect': CosArray([
            const CosInteger(72),
            CosInteger(i % 30 * 24),
            const CosInteger(300),
            CosInteger(i % 30 * 24 + 20),
          ]),
        });
    final roots = <CosObject>[
      for (var i = 0; i < fields; i++)
        b.add(widget('country$i', i)
          ..['FT'] = const CosName('Ch')
          ..['Ff'] = const CosInteger(PdfFormField.comboFlag)
          ..['Opt'] = CosArray([
            for (var o = 0; o < options; o++)
              CosArray([
                CosString.fromText('C$o'),
                CosString.fromText('Country number $o'),
              ]),
          ])),
      if (withheld)
        b.add(widget('secret', fields)
          ..['FT'] = const CosName('Tx')
          ..['Ff'] = const CosInteger(PdfFormField.passwordFlag)
          ..[PdfFormFilling.passwordWithheldKey] = const CosBoolean(true)),
    ];
    formPage['Annots'] = CosArray(roots);
    catalog['Pages'] = pagesRef;
    catalog['AcroForm'] = CosDictionary({'Fields': CosArray(roots)});
    final bytes =
        withoutId(b.build(root: catalogRef, objectStreams: objectStreams));
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);
    return bytes;
  }

  /// A two-page form without /ID: a cover page, then [leaves] text-field
  /// widgets on page 1, all kids of the bottom node of a chain of [depth]
  /// named field nodes (`r.n.n...`) linked by /Parent. /FT sits on the root
  /// only, and so does /Ff - as an indirect integer object ([flags]) that
  /// only an inherited-flag lookup ever loads. Every leaf carries a /V except
  /// the last when [withheld]: that one has the withheld marker instead, and
  /// is a password field only through the root's [flags]. Returns the bytes
  /// and the last leaf's fully qualified name.
  (Uint8List, String) deepNoIdForm(int depth, int leaves,
      {int flags = 0, bool withheld = false}) {
    final b = CosDocumentBuilder();
    final catalog = CosDictionary({'Type': const CosName('Catalog')});
    final catalogRef = b.add(catalog);
    final pages = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = b.add(pages);
    CosDictionary page() => CosDictionary({
          'Type': const CosName('Page'),
          'Parent': pagesRef,
          'MediaBox': CosArray(const [
            CosInteger(0),
            CosInteger(0),
            CosInteger(612),
            CosInteger(792),
          ]),
        });
    final coverRef = b.add(page());
    final formPage = page();
    final formPageRef = b.add(formPage);
    pages['Kids'] = CosArray([coverRef, formPageRef]);
    pages['Count'] = const CosInteger(2);
    final root = CosDictionary({
      'T': CosString.fromText('r'),
      'FT': const CosName('Tx'),
      'Ff': b.add(CosInteger(flags)),
    });
    final rootRef = b.add(root);
    var parent = root;
    var parentRef = rootRef;
    for (var i = 0; i < depth; i++) {
      final node = CosDictionary({
        'T': CosString.fromText('n'),
        'Parent': parentRef,
      });
      final ref = b.add(node);
      parent['Kids'] = CosArray([ref]);
      parent = node;
      parentRef = ref;
    }
    final kids = <CosObject>[
      for (var i = 0; i < leaves; i++)
        b.add(CosDictionary({
          'Type': const CosName('Annot'),
          'Subtype': const CosName('Widget'),
          'T': CosString.fromText('l$i'),
          'Parent': parentRef,
          'P': formPageRef,
          'Rect': CosArray([
            const CosInteger(72),
            CosInteger(i % 30 * 24),
            const CosInteger(300),
            CosInteger(i % 30 * 24 + 20),
          ]),
          if (withheld && i == leaves - 1)
            PdfFormFilling.passwordWithheldKey: const CosBoolean(true)
          else
            'V': CosString.fromText('v$i'),
        })),
    ];
    parent['Kids'] = CosArray(kids);
    formPage['Annots'] = CosArray(kids);
    catalog['Pages'] = pagesRef;
    catalog['AcroForm'] = CosDictionary({
      'Fields': CosArray([rootRef]),
    });
    final bytes = withoutId(b.build(root: catalogRef));
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);
    return (
      bytes,
      ['r', for (var i = 0; i < depth; i++) 'n', 'l${leaves - 1}'].join('.')
    );
  }

  bool fileContains(Uint8List bytes, String text) =>
      latin1.decode(bytes).contains(text);

  Future<PdfEditingController> open(
      Uint8List bytes, PdfFormSecretStore? store) async {
    final controller = PdfEditingController(bytes, formSecretStore: store);
    addTearDown(controller.dispose);
    await controller.formSecretsLoaded;
    return controller;
  }

  test('without a store, a password field still fills /V', () async {
    final c = await open(passwordForm(), null);
    expect(c.setFormFieldText('name', 'hunter2'), isTrue);
    expect(c.acroForm!.fieldNamed('name')!.value, 'hunter2');
    expect(c.formSecretDocumentId, isNull);
  });

  test('with a store the value goes to the store, never the file', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    expect(c.setFormFieldText('name', 'hunter2'), isTrue);
    await c.formSecretsSettled;

    final field = c.acroForm!.fieldNamed('name')!;
    expect(field.value, isNull, reason: 'the legacy /V is removed');
    expect(c.formFieldTextValue(field), 'hunter2');
    expect(fileContains(c.bytes, 'hunter2'), isFalse);
    expect(c.isModified, isTrue);
    expect(await store.read(c.formSecretDocumentId!, 'name'), 'hunter2');

    // flattening burns only the mask
    expect(c.flattenFormFields(), isTrue);
    expect(fileContains(c.bytes, 'hunter2'), isFalse);
  });

  test('reopening the saved file restores the value without dirtying it',
      () async {
    final store = InMemoryFormSecretStore();
    final first = await open(passwordForm(), store);
    first.setFormFieldText('name', 'hunter2');
    await first.formSecretsSettled;
    final saved = first.bytes;

    final again = await open(saved, store);
    expect(again.formSecretDocumentId, first.formSecretDocumentId,
        reason: 'the fallback identity was written as the file /ID');
    expect(again.formFieldTextValue(again.acroForm!.fieldNamed('name')!),
        'hunter2');
    expect(again.isModified, isFalse);
    expect(again.revisionCount, 1);
  });

  test('a different document never sees the value', () async {
    final store = InMemoryFormSecretStore();
    final a = await open(passwordForm(id: Uint8List(16)), store);
    a.setFormFieldText('name', 'hunter2');
    await a.formSecretsSettled;

    final otherId = Uint8List.fromList(List.filled(16, 7));
    final b = await open(passwordForm(id: otherId), store);
    expect(b.formSecretDocumentId, isNot(a.formSecretDocumentId));
    // b shows its own legacy /V, not a's stored value
    expect(b.formFieldTextValue(b.acroForm!.fieldNamed('name')!), 'prefilled');
    expect(await store.readAll(b.formSecretDocumentId!), isEmpty);
  });

  test('a stale entry for a field the file no longer withholds is ignored',
      () async {
    final store = InMemoryFormSecretStore();
    final bytes = passwordForm(id: Uint8List(16)); // /V (prefilled)
    await store.write(pdfFormSecretDocumentId(Uint8List(16)), 'name', 'old');
    final c = await open(bytes, store);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), 'prefilled');
  });

  test('undo and redo carry the stored value with the revision', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    final id = c.formSecretDocumentId!;
    String? shown() => c.formFieldTextValue(c.acroForm!.fieldNamed('name')!);

    c.setFormFieldText('name', 'first');
    c.setFormFieldText('name', 'second');
    await c.formSecretsSettled;
    expect(await store.read(id, 'name'), 'second');

    c.undo();
    await c.formSecretsSettled;
    expect(shown(), 'first');
    expect(await store.read(id, 'name'), 'first');

    c.undo(); // back to the file as opened: its legacy /V, nothing stored
    await c.formSecretsSettled;
    expect(shown(), 'prefilled');
    expect(await store.read(id, 'name'), isNull);

    c.redo();
    await c.formSecretsSettled;
    expect(shown(), 'first');
    expect(await store.read(id, 'name'), 'first');
  });

  test('clearing the field removes the stored value', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    c.setFormFieldText('name', 'hunter2');
    expect(c.setFormFieldText('name', ''), isTrue);
    await c.formSecretsSettled;
    expect(await store.readAll(c.formSecretDocumentId!), isEmpty);
  });

  test('forgetFormSecrets clears the document from the store', () async {
    final store = InMemoryFormSecretStore();
    final c = await open(passwordForm(), store);
    c.setFormFieldText('name', 'hunter2');
    await c.forgetFormSecrets();
    expect(await store.readAll(c.formSecretDocumentId!), isEmpty);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), isNull);
  });

  // A file without a trailer /ID answers to the SHA-256 of its bytes - an
  // O(file) hash on the UI isolate. Opening must not pay it (nor the store
  // read) unless a field could actually take a stored value.
  test('a file with no withheld field opens without the hash or a store read',
      () async {
    for (final bytes in [buildMultiPagePdf(2), passwordForm()]) {
      final store = _CountingStore();
      final c = await open(bytes, store);
      expect(pdfTrailerPermanentId(c.document), isNull);
      expect(store.readAlls, 0);
      expect(c.debugFormSecretIdResolved, isFalse,
          reason: 'the fallback identity is hashed on first need only');
      // ...and is then the key the eager open used to compute
      expect(
          c.formSecretDocumentId,
          pdfFormSecretDocumentId(
              pdfPermanentDocumentId(PdfDocument.open(bytes))));
      expect(c.debugFormSecretIdResolved, isTrue);
    }
  });

  // Without /ID the open reads no field at all: the decision waits for the
  // first read of the form's fields (the form layer's, once a page showing a
  // widget attaches), which is also where the orphan-widget reconcile maps
  // the pages - work the hash this replaces never cost the open.
  test('a no-/ID form opens without walking the page tree', () async {
    const pageCount = 3000;
    final bytes = noIdFormPdf(pageCount);
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);

    addTearDown(() {
      PdfPerf.enabled = false;
      PdfPerf.reset();
    });
    PdfPerf.enabled = true;
    PdfPerf.reset();
    final store = _CountingStore();
    final c = PdfEditingController(bytes, formSecretStore: store);
    addTearDown(c.dispose);
    final opened = PdfPerf.snapshot();
    expect(c.acroForm, isNotNull);
    expect(store.readAlls, 0);
    expect(c.debugFormSecretIdResolved, isFalse);
    expect(opened.phaseCalls[PdfPerfPhase.pageTreeWalk.index], 0,
        reason: 'the open reads no field, let alone the pages');

    expect(c.document.pages, hasLength(pageCount));
    expect(PdfPerf.snapshot().phaseCalls[PdfPerfPhase.pageTreeWalk.index], 1,
        reason: "the viewer's document.pages is the only walk");
    await c.formSecretsLoaded; // reads the (empty) fields: nothing withheld
    expect(store.readAlls, 0);
    expect(c.debugFormSecretIdResolved, isFalse);
  });

  // Through PdfAcroForm.fields a no-/ID file with an empty /AcroForm and dense
  // link annotations (a TOC, an index) parsed all of them in the constructor
  // - 0.8 s at 40k links.
  test('a no-/ID form open loads no more objects for more annotations',
      () async {
    addTearDown(() {
      PdfPerf.enabled = false;
      PdfPerf.reset();
    });
    int constructorLoads(Uint8List bytes) {
      PdfPerf.enabled = true;
      PdfPerf.reset();
      final store = _CountingStore();
      final c = PdfEditingController(bytes, formSecretStore: store);
      final loads = PdfPerf.snapshot().counts[PdfPerfCount.objectsLoaded.index];
      PdfPerf.enabled = false;
      c.dispose();
      expect(store.readAlls, 0);
      return loads;
    }

    final bare = constructorLoads(noIdFormPdf(200));
    final linked = constructorLoads(noIdFormPdf(200, linksPerPage: 20));
    expect(linked, bare,
        reason: '4000 link annotations must cost the open nothing');
    expect(bare, lessThan(20), reason: 'nor may the 200 pages');
  });

  // A field can cost far more to resolve than the hash of the bytes it
  // occupies: a dropdown parses its whole /Opt list, and on the web every
  // compressed object stream a field sits in is a pure-Dart inflate. An open
  // that walked the field tree regressed exactly these forms whenever the
  // first page shows no widget (the form layer then reads no field at attach).
  // The open must cost the same whatever the form holds.
  group('a no-/ID form behind a cover page', () {
    tearDown(() {
      PdfPerf.enabled = false;
      PdfPerf.reset();
    });

    /// Objects and object streams loaded from the constructor through the
    /// viewer attaching the cover page, plus the controller.
    (int, int, PdfEditingController) openToCover(
        Uint8List bytes, PdfFormSecretStore store) {
      PdfPerf.enabled = true;
      PdfPerf.reset();
      final c = PdfEditingController(bytes, formSecretStore: store);
      addTearDown(c.dispose);
      c.document.pages.length;
      expect(c.formWidgetsOn(0), isEmpty, reason: 'the cover has no widget');
      final counts = PdfPerf.snapshot().counts;
      PdfPerf.enabled = false;
      return (
        counts[PdfPerfCount.objectsLoaded.index],
        counts[PdfPerfCount.objectStreamsLoaded.index],
        c,
      );
    }

    for (final objectStreams in [false, true]) {
      final shape = objectStreams ? 'spread over object streams' : 'flat';
      test('reads no dropdown at open ($shape)', () async {
        final small = _CountingStore(), large = _CountingStore();
        final (smallLoads, smallStreams, _) = openToCover(
            dropdownNoIdForm(20, objectStreams: objectStreams), small);
        final (loads, streams, c) = openToCover(
            dropdownNoIdForm(1000, objectStreams: objectStreams), large);
        expect(loads, smallLoads,
            reason: '1000 dropdowns cost the open what 20 do: no field read');
        expect(streams, smallStreams,
            reason: 'nor is an object stream holding a field inflated');
        expect(loads, lessThan(8));
        expect(streams, lessThanOrEqualTo(1));
        expect(large.readAlls, 0);
        expect(c.debugFormSecretIdResolved, isFalse);

        // the page with the dropdowns reads the fields - and settles the
        // decision off them: nothing withheld, so no hash and no store read
        expect(c.formWidgetsOn(1), hasLength(1000));
        await c.formSecretsLoaded;
        expect(large.readAlls, 0);
        expect(c.debugFormSecretIdResolved, isFalse);
      });
    }

    test('reads the store once the form layer reads the fields', () async {
      final bytes = dropdownNoIdForm(200, objectStreams: true, withheld: true);
      final store = _CountingStore();
      await store.write(pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)),
          'secret', 'pw');
      final (_, _, c) = openToCover(bytes, store);
      expect(store.readAlls, 0, reason: 'nothing has read a field yet');
      expect(c.debugFormSecretIdResolved, isFalse);

      expect(c.formWidgetsOn(1), hasLength(201));
      expect(store.readAlls, 1, reason: 'a withheld field: read the store');
      await c.formSecretsLoaded;
      expect(c.formFieldTextValue(c.acroForm!.fieldNamed('secret')!), 'pw');
    });

    test('an edit before the first read of the fields falls back to the load',
        () async {
      // the fields at a later revision may have lost one the opened file
      // withheld, so they cannot rule the store out - the eager open's load
      // (hash + store read) decides instead, paid then rather than at open
      final bytes = dropdownNoIdForm(20, withheld: true);
      final store = _CountingStore();
      final opened = pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes));
      await store.write(opened, 'secret', 'pw');
      final (_, _, c) = openToCover(bytes, store);
      c.addRectangle(0, const PdfRect(100, 100, 200, 200));
      expect(store.readAlls, 0);

      expect(c.formWidgetsOn(1), hasLength(21));
      expect(store.readAlls, 1);
      expect(c.formSecretDocumentId, opened);
      await c.formSecretsLoaded;
      expect(c.formFieldTextValue(c.acroForm!.fieldNamed('secret')!), 'pw');
      c.undo();
      expect(c.formFieldTextValue(c.acroForm!.fieldNamed('secret')!), 'pw');
    });

    test('a later revision that lost the field still reads the store',
        () async {
      // flattening from the cover (the toolbar's Flatten, before any page
      // with a widget showed) removes every field: the fields read at that
      // revision show nothing withheld, yet an undo brings the field back -
      // so a first read after an edit must not rule the store out
      final bytes = dropdownNoIdForm(20, withheld: true);
      final store = _CountingStore();
      await store.write(pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)),
          'secret', 'pw');
      final (_, _, c) = openToCover(bytes, store);
      expect(c.flattenFormFields(), isTrue);
      expect(store.readAlls, 0);
      expect(c.acroForm!.fields, isEmpty);
      expect(store.readAlls, 1);
      await c.formSecretsLoaded;
      c.undo();
      expect(c.formFieldTextValue(c.acroForm!.fieldNamed('secret')!), 'pw');
    });

    test('a prefill of a field from another PdfAcroForm reads the store',
        () async {
      final bytes = dropdownNoIdForm(20, withheld: true);
      final store = _CountingStore();
      await store.write(pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)),
          'secret', 'pw');
      final (_, _, c) = openToCover(bytes, store);
      final field = PdfAcroForm.of(c.document)!.fieldNamed('secret')!;
      expect(store.readAlls, 0, reason: "not the controller's form");
      c.formFieldTextValue(field);
      expect(store.readAlls, 1);
      await c.formSecretsLoaded;
      expect(c.formFieldTextValue(field), 'pw');
    });

    test('a redaction burn before any field read still restores the value',
        () async {
      final bytes = dropdownNoIdForm(20, withheld: true);
      final store = _CountingStore();
      await store.write(pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)),
          'secret', 'pw');
      final (_, _, c) = openToCover(bytes, store);
      c.addRedaction(0, const PdfRect(100, 100, 200, 200));
      expect(c.applyRedactions(), isTrue);
      // the burned file is the whole history now: its fields decide
      expect(c.formWidgetsOn(0), isEmpty);
      expect(store.readAlls, 0);
      expect(c.formWidgetsOn(1), hasLength(21));
      expect(store.readAlls, 1);
      await c.formSecretsLoaded;
      expect(c.formSecretDocumentId,
          pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)));
      expect(c.formFieldTextValue(c.acroForm!.fieldNamed('secret')!), 'pw');
    });

    test('forgetFormSecrets settles the decision without a read', () async {
      final bytes = dropdownNoIdForm(20, withheld: true);
      final store = _CountingStore();
      final (_, _, c) = openToCover(bytes, store);
      await c.forgetFormSecrets();
      c.formWidgetsOn(1);
      await c.formSecretsLoaded;
      expect(store.readAlls, 0);
    });
  });

  test('a withheld field nested under /Kids in a no-/ID file is found',
      () async {
    // a parent node holding the password field
    final doc = PdfDocument.open(buildAcroFormPdf());
    final updater = CosIncrementalUpdater(doc.cos);
    final form = doc.cos.resolve(doc.catalog['AcroForm']) as CosDictionary;
    final roots = (doc.cos.resolve(form['Fields']) as CosArray).items;
    final nameRef = roots.first;
    final name = doc.cos.resolve(nameRef) as CosDictionary;
    expect(doc.cos.resolve(name['T']), CosString.fromText('name'));
    name['Ff'] = const CosInteger(PdfFormField.passwordFlag);
    name.entries.remove('V');
    name[PdfFormFilling.passwordWithheldKey] = const CosBoolean(true);
    final group = updater.addObject(CosDictionary({
      'T': CosString.fromText('group'),
      'Kids': CosArray([nameRef]),
    }));
    name['Parent'] = group;
    form['Fields'] = CosArray([group, ...roots.skip(1)]);
    updater
      ..markChanged(name)
      ..markChanged(doc.catalog);
    final bytes = updater.save();
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);

    final store = _CountingStore();
    await store.write(pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)),
        'group.name', 'nested');
    final c = await open(bytes, store);
    expect(store.readAlls, 1);
    expect(
        c.formFieldTextValue(c.acroForm!.fieldNamed('group.name')!), 'nested');
  });

  // The decision runs over every field of the form. /FT, /Ff and /V are
  // inheritable, so asking a leaf isPassword (or its value) climbs /Parent to
  // the root: over a deep hierarchy that was O(fields x depth), more than the
  // whole-file hash the decision replaced. The withheld marker lives on the
  // field's own dictionary, so it is asked first and only a marked field
  // climbs. The probe: the root's /Ff is an indirect object nothing but an
  // inherited-flag lookup loads.
  group('a deep no-/ID field hierarchy', () {
    const depth = 300, leaves = 1000;

    tearDown(() {
      PdfPerf.enabled = false;
      PdfPerf.reset();
    });

    int loadsOf(void Function() read) {
      PdfPerf.enabled = true;
      PdfPerf.reset();
      read();
      final loads = PdfPerf.snapshot().counts[PdfPerfCount.objectsLoaded.index];
      PdfPerf.enabled = false;
      return loads;
    }

    test('is decided without climbing /Parent for an unmarked field', () async {
      final (bytes, _) = deepNoIdForm(depth, leaves);
      final store = _CountingStore();
      final c = PdfEditingController(bytes, formSecretStore: store);
      addTearDown(c.dispose);
      expect(c.formWidgetsOn(0), isEmpty, reason: 'the cover has no widget');

      // the first read of the fields: the whole hierarchy loads, and the
      // decision runs over all of it
      late List<PdfFormField> fields;
      expect(loadsOf(() => fields = c.acroForm!.fields),
          greaterThan(depth + leaves));
      expect(fields, hasLength(leaves));
      await c.formSecretsLoaded;
      expect(store.readAlls, 0);
      expect(c.debugFormSecretIdResolved, isFalse);

      // ...yet the root's /Ff is still unloaded: no field asked for a flag
      expect(loadsOf(() => expect(fields.first.isPassword, isFalse)), 1,
          reason: 'the decision climbed /Parent for an unmarked field');
    });

    test('still finds a marked leaf that inherits its password flag', () async {
      final (bytes, name) = deepNoIdForm(depth, leaves,
          flags: PdfFormField.passwordFlag, withheld: true);
      final store = _CountingStore();
      await store.write(
          pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)), name, 'pw');
      final c = PdfEditingController(bytes, formSecretStore: store);
      addTearDown(c.dispose);
      expect(store.readAlls, 0);
      expect(c.formWidgetsOn(1), hasLength(leaves));
      expect(store.readAlls, 1, reason: 'the marked leaf is withheld');
      await c.formSecretsLoaded;
      final field = c.acroForm!.fieldNamed(name)!;
      expect(field.isPassword, isTrue, reason: 'inherited from the root');
      expect(c.formFieldTextValue(field), 'pw');
      // every other leaf is a password field too, but shows its /V
      expect(c.formFieldTextValue(c.acroForm!.fields.first), 'v0');
    });
  });

  test('an orphan withheld widget in a no-/ID file gets its value back',
      () async {
    // the password field's merged widget stays on the page but is missing
    // from /Fields - PdfAcroForm.fields reconciles it back, and the decision
    // reads the same fields the load filters on
    final doc = PdfDocument.open(buildAcroFormPdf());
    final updater = CosIncrementalUpdater(doc.cos);
    final form = doc.cos.resolve(doc.catalog['AcroForm']) as CosDictionary;
    final roots = (doc.cos.resolve(form['Fields']) as CosArray).items;
    final name = doc.cos.resolve(roots.first) as CosDictionary;
    expect(doc.cos.resolve(name['T']), CosString.fromText('name'));
    name['Ff'] = const CosInteger(PdfFormField.passwordFlag);
    name.entries.remove('V');
    name[PdfFormFilling.passwordWithheldKey] = const CosBoolean(true);
    form['Fields'] = CosArray(roots.skip(1).toList());
    updater
      ..markChanged(name)
      ..markChanged(doc.catalog);
    final bytes = updater.save();
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);

    final store = _CountingStore();
    await store.write(
        pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)), 'name', 'pw');
    final c = await open(bytes, store);
    expect(store.readAlls, 1);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), 'pw');
  });

  test('a file with a trailer /ID but no form skips the store read', () async {
    final store = _CountingStore();
    final bytes = buildEncryptedPdf(revision: 4);
    final c = await open(bytes, store);
    expect(store.readAlls, 0);
    expect(c.debugFormSecretIdResolved, isTrue, reason: '/ID[0] is free');
    expect(c.formSecretDocumentId,
        pdfFormSecretDocumentId(pdfTrailerPermanentId(c.document)!));
  });

  test('a withheld field in a file without /ID still gets its value back',
      () async {
    // a withheld fill writes /ID, so this takes a file whose /ID was lost
    // after the fill - the one case where the open still has to hash
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final field = editor.acroForm!.fieldNamed('name')!;
    field.dict['Ff'] = const CosInteger(PdfFormField.passwordFlag);
    editor.setTextValue(field, 'marked');
    field.dict.entries.remove('V');
    field.dict[PdfFormFilling.passwordWithheldKey] = const CosBoolean(true);
    final bytes = editor.save();
    expect(pdfTrailerPermanentId(PdfDocument.open(bytes)), isNull);

    final store = _CountingStore();
    await store.write(
        pdfFormSecretDocumentId(pdfFallbackDocumentId(bytes)), 'name', 'pw');
    final c = await open(bytes, store);
    expect(store.readAlls, 1);
    expect(c.formFieldTextValue(c.acroForm!.fieldNamed('name')!), 'pw');
  });

  test('a first withheld fill after another edit files under the opened hash',
      () async {
    // The fallback identity is the hash of the bytes as OPENED: hashing the
    // current revision instead would file the value under a key that no
    // longer matches the /ID the fill writes, and lose it on reopen.
    final store = InMemoryFormSecretStore();
    final original = passwordForm();
    final c = await open(original, store);
    c.addRectangle(0, const PdfRect(100, 100, 200, 200));
    expect(c.revisionCount, 2);
    expect(c.debugFormSecretIdResolved, isFalse);

    expect(c.setFormFieldText('name', 'hunter2'), isTrue);
    await c.formSecretsSettled;
    final opened = pdfFallbackDocumentId(original);
    expect(c.formSecretDocumentId, pdfFormSecretDocumentId(opened));
    expect(pdfTrailerPermanentId(c.document), opened,
        reason: 'the fill writes the same identity as the file /ID');
    expect(
        await store.read(pdfFormSecretDocumentId(opened), 'name'), 'hunter2');

    final again = await open(c.bytes, store);
    expect(again.formSecretDocumentId, c.formSecretDocumentId);
    expect(again.formFieldTextValue(again.acroForm!.fieldNamed('name')!),
        'hunter2');
  });

  // A redaction burn replaces the whole buffer (_resetTo): revision 0 is no
  // longer the opened bytes, so the lazy fallback identity has to be taken
  // before the swap or later fills would file under the hash of the burned
  // file instead.
  test('a no-/ID file keeps its opened identity across a redaction burn',
      () async {
    final store = InMemoryFormSecretStore();
    final original = passwordForm();
    final c = await open(original, store);
    expect(c.debugFormSecretIdResolved, isFalse);
    c.addRedaction(0, const PdfRect(400, 100, 500, 150));
    expect(c.applyRedactions(), isTrue);
    expect(c.revisionCount, 1, reason: 'the burn starts a fresh history');

    expect(c.setFormFieldText('name', 'v'), isTrue);
    await c.formSecretsSettled;
    final key = pdfFormSecretDocumentId(pdfFallbackDocumentId(original));
    expect(c.formSecretDocumentId, key);
    expect(await store.read(key, 'name'), 'v');
  });

  test('SecureFormSecretStore round-trips through flutter_secure_storage',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureFormSecretStore();
    await store.write('doc-a', 'pin', '1234');
    await store.write('doc-a', 'pw', 'hunter2');
    await store.write('doc-b', 'pw', 'other');
    expect(await store.readAll('doc-a'), {'pin': '1234', 'pw': 'hunter2'});
    await store.remove('doc-a', 'pin');
    expect(await store.read('doc-a', 'pin'), isNull);
    await store.clearDocument('doc-a');
    expect(await store.readAll('doc-a'), isEmpty);
    expect(await store.read('doc-b', 'pw'), 'other');
    await store.clearAll();
    expect(await store.readAll('doc-b'), isEmpty);
  });
}

/// Counts [readAll] - the keychain round trip an open makes only when the
/// file could hold a withheld value.
class _CountingStore extends InMemoryFormSecretStore {
  int readAlls = 0;

  @override
  Future<Map<String, String>> readAll(String documentId) {
    readAlls++;
    return super.readAll(documentId);
  }
}
