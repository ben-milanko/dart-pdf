import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'rect.dart';

/// What kind of input a form field accepts, derived from /FT plus the
/// discriminating /Ff bits (§12.7.4).
enum PdfFieldType {
  text,
  checkBox,
  radioGroup,
  pushButton,
  comboBox,
  listBox,
  signature,
  unknown,
}

/// The document's interactive form (§12.7.2): the catalog's /AcroForm
/// dictionary plus the field tree hanging off /Fields.
class PdfAcroForm {
  PdfAcroForm._(this.document, this.dict);

  /// The document's form, or null if it has none.
  static PdfAcroForm? of(PdfDocument document) {
    final dict = document.cos.resolve(document.catalog['AcroForm']);
    return dict is CosDictionary ? PdfAcroForm._(document, dict) : null;
  }

  final PdfDocument document;

  /// The raw /AcroForm dictionary.
  final CosDictionary dict;

  /// The form-wide /DA default appearance string, if any.
  String? get defaultAppearance {
    final da = document.cos.resolve(dict['DA']);
    return da is CosString ? da.text : null;
  }

  /// The form-wide /DR default resources (fonts the /DA strings name).
  CosDictionary? get defaultResources {
    final dr = document.cos.resolve(dict['DR']);
    return dr is CosDictionary ? dr : null;
  }

  /// Whether the file asks viewers to regenerate appearances themselves.
  bool get needsAppearances {
    final flag = document.cos.resolve(dict['NeedAppearances']);
    return flag is CosBoolean && flag.value;
  }

  List<PdfFormField>? _fields;

  /// All terminal (fillable) fields, depth-first across the field tree.
  List<PdfFormField> get fields => _fields ??= () {
        final out = <PdfFormField>[];
        final roots = document.cos.resolve(dict['Fields']);
        if (roots is CosArray) {
          for (final item in roots.items) {
            final node = document.cos.resolve(item);
            if (node is CosDictionary) {
              _collect(node, '', out, <CosDictionary>{});
            }
          }
        }
        return out;
      }();

  /// Looks up a field by its fully qualified name.
  PdfFormField? fieldNamed(String name) {
    for (final field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }

  /// One [PdfFormFieldInfo] per terminal field: the metadata a form
  /// editor or template pipeline persists (name, type, page, rect)
  /// without touching values. Lenient — malformed widgets yield
  /// pageIndex −1 and a null rect rather than failing the whole list.
  List<PdfFormFieldInfo> describeFields() => [
        for (final field in fields)
          PdfFormFieldInfo(
            name: field.name,
            type: field.type,
            pageIndex: field.widgetPageIndex(0),
            rect: field.widgetRect(0),
          ),
      ];

  List<CosDictionary>? _pageDicts;

  /// Page dictionaries by index, resolved once per form instance.
  List<CosDictionary> get _pages => _pageDicts ??= [
        for (var i = 0; i < document.pageCount; i++) document.page(i).dict,
      ];

  /// The page index of [widget]: its /P entry when present, otherwise
  /// the first page whose /Annots lists it. −1 when no page claims it.
  int _pageIndexOf(CosDictionary widget) {
    final cos = document.cos;
    final p = cos.resolve(widget['P']);
    if (p is CosDictionary) {
      for (var i = 0; i < _pages.length; i++) {
        if (identical(_pages[i], p)) return i;
      }
    }
    for (var i = 0; i < _pages.length; i++) {
      final annots = cos.resolve(_pages[i]['Annots']);
      if (annots is! CosArray) continue;
      for (final item in annots.items) {
        if (identical(cos.resolve(item), widget)) return i;
      }
    }
    return -1;
  }

  /// A node with /T-carrying kids is an internal node; a node whose kids
  /// are all widgets (no /T) is a terminal field (§12.7.4.2).
  void _collect(CosDictionary node, String prefix, List<PdfFormField> out,
      Set<CosDictionary> visited) {
    if (!visited.add(node)) return;
    final cos = document.cos;
    final t = cos.resolve(node['T']);
    final partial = t is CosString ? t.text : null;
    final name = switch ((prefix.isEmpty, partial)) {
      (_, null) => prefix,
      (true, _) => partial!,
      (false, _) => '$prefix.$partial',
    };

    final kids = cos.resolve(node['Kids']);
    var hasChildFields = false;
    if (kids is CosArray) {
      for (final item in kids.items) {
        final kid = cos.resolve(item);
        if (kid is CosDictionary && cos.resolve(kid['T']) is CosString) {
          hasChildFields = true;
          _collect(kid, name, out, visited);
        }
      }
    }
    if (!hasChildFields) {
      out.add(PdfFormField._(this, node, name));
    }
  }
}

/// Persistable metadata for one terminal field — what a template editor
/// stores about a form without reading values (see
/// [PdfAcroForm.describeFields]).
class PdfFormFieldInfo {
  const PdfFormFieldInfo({
    required this.name,
    required this.type,
    required this.pageIndex,
    required this.rect,
  });

  /// Fully qualified field name.
  final String name;

  final PdfFieldType type;

  /// The page showing the field's first widget, or −1 when no page
  /// claims it (malformed or orphaned widgets).
  final int pageIndex;

  /// The first widget's rectangle in page space (bottom-left origin,
  /// point units), or null when the widget has no parseable /Rect.
  final PdfRect? rect;
}

/// One terminal field of the form: a value plus the widget annotations
/// that display it on pages.
class PdfFormField {
  PdfFormField._(this.form, this.dict, this.name);

  final PdfAcroForm form;

  /// The raw field dictionary (also the widget dictionary when merged).
  final CosDictionary dict;

  /// Fully qualified name: partial /T names joined with dots.
  final String name;

  CosDocument get _cos => form.document.cos;

  /// Resolves an inheritable entry up the /Parent chain (§12.7.4.2).
  CosObject? inherited(String key) {
    CosDictionary? node = dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final value = node.containsKey(key) ? _cos.resolve(node[key]) : null;
      if (value != null && value is! CosNull) return value;
      final parent = _cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    return null;
  }

  /// The /FT name without the slash ('Tx', 'Btn', 'Ch', 'Sig'), inherited.
  String? get fieldTypeName {
    final ft = inherited('FT');
    return ft is CosName ? ft.value : null;
  }

  /// The /Ff field-flag word, inherited.
  int get flags {
    final ff = inherited('Ff');
    return ff is CosInteger ? ff.value : 0;
  }

  PdfFieldType get type => switch (fieldTypeName) {
        'Tx' => PdfFieldType.text,
        'Ch' => flags & comboFlag != 0
            ? PdfFieldType.comboBox
            : PdfFieldType.listBox,
        'Btn' => flags & pushButtonFlag != 0
            ? PdfFieldType.pushButton
            : flags & radioFlag != 0
                ? PdfFieldType.radioGroup
                : PdfFieldType.checkBox,
        'Sig' => PdfFieldType.signature,
        _ => PdfFieldType.unknown,
      };

  static const readOnlyFlag = 1; // bit 1
  static const requiredFlag = 2; // bit 2
  static const multilineFlag = 1 << 12; // bit 13
  static const passwordFlag = 1 << 13; // bit 14
  static const radioFlag = 1 << 15; // bit 16
  static const pushButtonFlag = 1 << 16; // bit 17
  static const comboFlag = 1 << 17; // bit 18
  static const editFlag = 1 << 18; // bit 19

  bool get isReadOnly => flags & readOnlyFlag != 0;
  bool get isRequired => flags & requiredFlag != 0;
  bool get isMultiline => flags & multilineFlag != 0;
  bool get isPassword => flags & passwordFlag != 0;

  /// /Q quadding: 0 left (default), 1 centered, 2 right.
  int get quadding {
    final q = inherited('Q');
    return q is CosInteger ? q.value : 0;
  }

  /// The field's /DA string, falling back to the form-wide default.
  String? get defaultAppearance {
    final da = inherited('DA');
    return da is CosString ? da.text : form.defaultAppearance;
  }

  /// The /DA font size in points; 0 means auto-size (the appearance fits
  /// the text to the box). Parsed from the `/Font size Tf` operator.
  double get appearanceFontSize {
    final m = RegExp(r'/[^\s/]+\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(defaultAppearance ?? '');
    return double.tryParse(m?.group(1) ?? '') ?? 0;
  }

  /// The /DA text colour as 0xRRGGBB, or null when the /DA sets none (the
  /// appearance then defaults to black). Reads the last `g` / `rg` / `k`
  /// colour-setting operator and its operands (§12.7.3.3).
  int? get appearanceColor {
    final tokens = (defaultAppearance ?? '')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
    int? rgb;
    final nums = <double>[];
    for (final tok in tokens) {
      final n = double.tryParse(tok);
      if (n != null) {
        nums.add(n);
        continue;
      }
      if (tok == 'g' && nums.isNotEmpty) {
        final v = byte(nums.last);
        rgb = (v << 16) | (v << 8) | v;
      } else if (tok == 'rg' && nums.length >= 3) {
        final c = nums.sublist(nums.length - 3);
        rgb = (byte(c[0]) << 16) | (byte(c[1]) << 8) | byte(c[2]);
      } else if (tok == 'k' && nums.length >= 4) {
        final c = nums.sublist(nums.length - 4);
        double cmyk(int i) => (1 - c[i]) * (1 - c[3]);
        rgb = (byte(cmyk(0)) << 16) | (byte(cmyk(1)) << 8) | byte(cmyk(2));
      }
      nums.clear();
    }
    return rgb;
  }

  /// The current value as text: /V strings come back verbatim, button
  /// state names without the slash, multi-select arrays as their first
  /// string. Null when the field is empty.
  String? get value {
    final v = inherited('V');
    if (v is CosString) return v.text;
    if (v is CosName) return v.value;
    if (v is CosArray && v.length > 0) {
      final first = _cos.resolve(v[0]);
      if (first is CosString) return first.text;
    }
    return null;
  }

  /// Whether a check box or radio group is on (/V set and not /Off).
  bool get isChecked {
    final v = inherited('V');
    return v is CosName && v.value != 'Off';
  }

  /// The widget annotations displaying this field: its /Kids without a
  /// /T of their own, or the field dictionary itself when merged.
  List<CosDictionary> get widgets {
    final kids = _cos.resolve(dict['Kids']);
    if (kids is CosArray) {
      final out = <CosDictionary>[];
      for (final item in kids.items) {
        final kid = _cos.resolve(item);
        if (kid is CosDictionary && _cos.resolve(kid['T']) is! CosString) {
          out.add(kid);
        }
      }
      if (out.isNotEmpty) return out;
    }
    return [dict];
  }

  /// The rectangle of widget [index] in page space, or null when the
  /// widget is malformed.
  PdfRect? widgetRect(int index) {
    final all = widgets;
    if (index < 0 || index >= all.length) return null;
    return pdfRectFrom(_cos, all[index]['Rect']);
  }

  /// The page index displaying widget [index]: the widget's /P entry
  /// when it resolves to a page, otherwise the first page whose /Annots
  /// array lists the widget. −1 when no page claims it.
  int widgetPageIndex(int index) {
    final all = widgets;
    if (index < 0 || index >= all.length) return -1;
    return form._pageIndexOf(all[index]);
  }

  /// The on-state name widget [index] defines: the first key of its
  /// /AP /N state dictionary that isn't 'Off'. For a radio group this is
  /// the state tapping that particular button selects; null for widgets
  /// without state appearances (or an out-of-range [index]).
  String? widgetOnState(int index) {
    final all = widgets;
    if (index < 0 || index >= all.length) return null;
    final ap = _cos.resolve(all[index]['AP']);
    if (ap is! CosDictionary) return null;
    final n = _cos.resolve(ap['N']);
    if (n is! CosDictionary) return null;
    for (final key in n.entries.keys) {
      if (key != 'Off') return key;
    }
    return null;
  }

  /// The on-state names a button's widgets define: the keys of each
  /// /AP /N state dictionary except 'Off'. A plain check box has one
  /// (conventionally 'Yes'); a radio group has one per button.
  List<String> get onStates {
    final out = <String>[];
    for (final widget in widgets) {
      final ap = _cos.resolve(widget['AP']);
      if (ap is! CosDictionary) continue;
      final n = _cos.resolve(ap['N']);
      if (n is! CosDictionary) continue;
      for (final key in n.entries.keys) {
        if (key != 'Off' && !out.contains(key)) out.add(key);
      }
    }
    return out;
  }

  /// Choice options as (exportValue, displayValue) pairs. /Opt entries are
  /// either plain strings or [export display] pairs (§12.7.5.4).
  List<(String, String)> get options {
    final opt = inherited('Opt');
    if (opt is! CosArray) return const [];
    final out = <(String, String)>[];
    for (final item in opt.items) {
      final entry = _cos.resolve(item);
      if (entry is CosString) {
        out.add((entry.text, entry.text));
      } else if (entry is CosArray && entry.length >= 2) {
        final export = _cos.resolve(entry[0]);
        final display = _cos.resolve(entry[1]);
        if (export is CosString && display is CosString) {
          out.add((export.text, display.text));
        }
      }
    }
    return out;
  }
}
