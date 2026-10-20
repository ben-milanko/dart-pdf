/// Form field scripts without a JavaScript engine (§12.6.3, §12.7.5.3).
///
/// Real-world AcroForm scripts are overwhelmingly calls to the built-in
/// `AF*` helpers from Acrobat's AForm library: `AFNumber_Format(2, 0, 0, 0,
/// "$", true);`, `AFSimple_Calculate("SUM", new Array("A", "B"));` and so on.
/// This library recognises those calls by parsing the script text of a
/// field's /AA keystroke (/K), format (/F), validate (/V) and calculate (/C)
/// actions, and runs a Dart port of each helper. Anything else - arbitrary
/// JavaScript - is reported as [PdfUnsupportedFieldScript] and never runs.
///
/// Semantics follow the AForm helpers as viewers implement them: /V keeps
/// the raw value, format actions only change what the appearance shows,
/// keystroke actions accept or reject what the user types (normalising a
/// committed value where the helper does), validate actions reject
/// out-of-range values, and calculations run in the /AcroForm /CO order.
library;

import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'form.dart';

/// The field-level /AA triggers that carry form scripts (§12.6.3, table
/// 199), with their /AA key.
enum PdfFieldScriptTrigger {
  /// /K - runs as the user types and when the value is committed.
  keystroke('K'),

  /// /F - turns the stored value into the displayed text.
  format('F'),

  /// /V - accepts or rejects a committed value.
  validate('V'),

  /// /C - recomputes the field from other fields.
  calculate('C');

  const PdfFieldScriptTrigger(this.aaKey);

  /// The key under the field's /AA dictionary.
  final String aaKey;
}

/// One /AA script of a form field: either a recognised `AF*` helper call
/// (the concrete subclasses) or [PdfUnsupportedFieldScript].
sealed class PdfFieldScript {
  const PdfFieldScript(this.source);

  /// The script text as the file stores it.
  final String source;

  /// The trigger this script belongs to. A recognised helper found under a
  /// different trigger (a format helper in /K, say) is reported as
  /// unsupported instead.
  PdfFieldScriptTrigger get trigger;

  /// Whether this is a recognised helper that runs.
  bool get isSupported => true;
}

/// A script that is not a recognised built-in helper call. It is exposed so
/// hosts can see what was skipped, and never runs.
final class PdfUnsupportedFieldScript extends PdfFieldScript {
  const PdfUnsupportedFieldScript(super.source, this.trigger, this.reason);

  @override
  final PdfFieldScriptTrigger trigger;

  /// Why the script was not recognised (for diagnostics, English).
  final String reason;

  @override
  bool get isSupported => false;
}

/// A format (/F) script: turns the stored value into display text.
sealed class PdfFormatScript extends PdfFieldScript {
  const PdfFormatScript(super.source);

  @override
  PdfFieldScriptTrigger get trigger => PdfFieldScriptTrigger.format;

  /// The text the appearance shows for [value]. [now] supplies the date
  /// for date formats that omit the year (tests pin it).
  PdfFieldDisplay format(String value, {DateTime? now});
}

/// A keystroke (/K) script: checks text as it is typed and when committed.
sealed class PdfKeystrokeScript extends PdfFieldScript {
  const PdfKeystrokeScript(super.source);

  @override
  PdfFieldScriptTrigger get trigger => PdfFieldScriptTrigger.keystroke;

  /// Whether [text] is an acceptable in-progress entry - what an input
  /// filter consults on every keystroke. The empty string is always fine.
  bool acceptsPartial(String text);

  /// Checks a committed [text], returning the value to store (normalised
  /// where the helper normalises) or a failure. [fieldName] only feeds
  /// the message.
  PdfFieldInputResult commit(String text,
      {String fieldName = '', DateTime? now});
}

/// A validate (/V) script: accepts or rejects a committed value.
sealed class PdfValidateScript extends PdfFieldScript {
  const PdfValidateScript(super.source);

  @override
  PdfFieldScriptTrigger get trigger => PdfFieldScriptTrigger.validate;

  /// Null when [value] passes, otherwise the failure.
  PdfFieldInputResult? validate(String value);
}

/// A calculate (/C) script: derives the field's value from other fields.
sealed class PdfCalculateScript extends PdfFieldScript {
  const PdfCalculateScript(super.source);

  @override
  PdfFieldScriptTrigger get trigger => PdfFieldScriptTrigger.calculate;

  /// The names of the fields this calculation reads.
  List<String> get inputs;

  /// The new value. [lookup] returns the raw values of the named field -
  /// several when the name is a parent of more than one terminal field,
  /// none when no such field exists.
  String calculate(List<String?> Function(String name) lookup);
}

/// Display text produced by a format script, plus the text colour a
/// negative-number style asks for (0xRRGGBB), or null to keep the /DA
/// colour.
class PdfFieldDisplay {
  const PdfFieldDisplay(this.text, {this.textColor});

  final String text;
  final int? textColor;

  @override
  bool operator ==(Object other) =>
      other is PdfFieldDisplay &&
      other.text == text &&
      other.textColor == textColor;

  @override
  int get hashCode => Object.hash(text, textColor);

  @override
  String toString() => textColor == null
      ? 'PdfFieldDisplay($text)'
      : 'PdfFieldDisplay($text, #${textColor!.toRadixString(16)})';
}

/// Why a keystroke or validate script refused a value.
enum PdfFieldInputFailure {
  /// Not a number / does not match the special mask.
  format,

  /// Not a date the field's date format can read.
  date,

  /// Outside an AFRange_Validate bound.
  range,
}

/// The outcome of checking a committed field value against its keystroke
/// and validate scripts.
class PdfFieldInputResult {
  /// Accepted; [value] is what to store (possibly normalised).
  const PdfFieldInputResult.valid(this.value)
      : failure = null,
        message = null;

  /// Refused; [message] is a sentence the UI can show.
  const PdfFieldInputResult.invalid(
      this.value, PdfFieldInputFailure this.failure, String this.message);

  /// The value to store when valid; the entered text when not.
  final String value;

  /// Null when valid.
  final PdfFieldInputFailure? failure;

  /// Null when valid; an English sentence otherwise.
  final String? message;

  bool get isValid => failure == null;

  @override
  String toString() => isValid
      ? 'PdfFieldInputResult.valid($value)'
      : 'PdfFieldInputResult.invalid($value, $failure: $message)';
}

/// Thrown by [PdfFormFieldScripts]-aware fill APIs when a field's keystroke
/// or validate script refuses the entered value. An [ArgumentError], so
/// callers that already treat bad fill arguments as a refusal keep working.
class PdfFieldInputException extends ArgumentError {
  PdfFieldInputException(this.fieldName, this.result)
      : super(result.message, fieldName);

  final String fieldName;
  final PdfFieldInputResult result;

  @override
  String toString() => 'PdfFieldInputException: ${result.message}';
}

/// The scripts of one field, by trigger.
class PdfFieldScripts {
  const PdfFieldScripts({
    this.keystroke,
    this.format,
    this.validate,
    this.calculate,
  });

  static const none = PdfFieldScripts();

  final PdfFieldScript? keystroke;
  final PdfFieldScript? format;
  final PdfFieldScript? validate;
  final PdfFieldScript? calculate;

  /// Every script present, keyed by trigger.
  Map<PdfFieldScriptTrigger, PdfFieldScript> get all => {
        if (keystroke != null) PdfFieldScriptTrigger.keystroke: keystroke!,
        if (format != null) PdfFieldScriptTrigger.format: format!,
        if (validate != null) PdfFieldScriptTrigger.validate: validate!,
        if (calculate != null) PdfFieldScriptTrigger.calculate: calculate!,
      };

  /// The scripts that run.
  List<PdfFieldScript> get recognized => [
        for (final s in all.values)
          if (s.isSupported) s
      ];

  /// The scripts that were skipped because they are not recognised helper
  /// calls.
  List<PdfUnsupportedFieldScript> get unsupported => [
        for (final s in all.values)
          if (s is PdfUnsupportedFieldScript) s
      ];

  bool get isEmpty => all.isEmpty;
  bool get hasUnsupported => unsupported.isNotEmpty;

  PdfKeystrokeScript? get _keystroke =>
      keystroke is PdfKeystrokeScript ? keystroke as PdfKeystrokeScript : null;
  PdfFormatScript? get _format =>
      format is PdfFormatScript ? format as PdfFormatScript : null;
  PdfValidateScript? get _validate =>
      validate is PdfValidateScript ? validate as PdfValidateScript : null;

  /// Display text for [value] after the format script (or [value]
  /// unchanged without one).
  PdfFieldDisplay display(String value, {DateTime? now}) =>
      _format?.format(value, now: now) ?? PdfFieldDisplay(value);

  /// Whether the keystroke script accepts [text] mid-entry.
  bool acceptsPartial(String text) => _keystroke?.acceptsPartial(text) ?? true;

  /// Runs the keystroke commit then the validate script on [text].
  PdfFieldInputResult check(String text,
      {String fieldName = '', DateTime? now}) {
    final k = _keystroke?.commit(text, fieldName: fieldName, now: now) ??
        PdfFieldInputResult.valid(text);
    if (!k.isValid) return k;
    return _validate?.validate(k.value) ?? k;
  }
}

final Expando<PdfFieldScripts> _scriptCache = Expando('PdfFieldScripts');

/// Script access on a form field. A field's scripts are parsed once per
/// [PdfFormField] instance.
extension PdfFormFieldScripts on PdfFormField {
  /// The field's /AA keystroke, format, validate and calculate scripts:
  /// recognised `AF*` helpers plus [PdfUnsupportedFieldScript]s for what
  /// was skipped. Read from the field dictionary, falling back to a widget
  /// that carries them (some producers put field triggers on the kid).
  PdfFieldScripts get scripts => _scriptCache[this] ??= _readScripts(this);

  /// Display text for [raw] after this field's format script.
  PdfFieldDisplay displayFor(String raw, {DateTime? now}) =>
      scripts.display(raw, now: now);

  /// The current value as the appearance shows it (format applied), or null
  /// when the field is empty.
  String? get formattedValue {
    final v = value;
    return v == null ? null : scripts.display(v).text;
  }

  /// Checks a user-entered [text] against the keystroke (commit) and
  /// validate scripts: the value to store, or why it was refused.
  PdfFieldInputResult checkInput(String text, {DateTime? now}) =>
      scripts.check(text, fieldName: name, now: now);

  /// Whether the keystroke script accepts [text] mid-entry - an input
  /// filter for the text editor.
  bool acceptsPartialInput(String text) => scripts.acceptsPartial(text);
}

PdfFieldScripts _readScripts(PdfFormField field) {
  final cos = field.form.document.cos;
  final sources = <PdfFieldScriptTrigger, String>{};
  void readFrom(CosDictionary dict) {
    final aa = cos.resolve(dict['AA']);
    if (aa is! CosDictionary) return;
    for (final trigger in PdfFieldScriptTrigger.values) {
      if (sources.containsKey(trigger) || !aa.containsKey(trigger.aaKey)) {
        continue;
      }
      final action = PdfAction.parse(field.form.document, aa[trigger.aaKey]);
      sources[trigger] = action is PdfJavaScriptAction ? action.script : '';
    }
  }

  readFrom(field.dict);
  for (final widget in field.widgets) {
    if (!identical(widget, field.dict)) readFrom(widget);
  }
  if (sources.isEmpty) return PdfFieldScripts.none;
  PdfFieldScript? of(PdfFieldScriptTrigger t) {
    final s = sources[t];
    return s == null ? null : parsePdfFieldScript(s, t);
  }

  return PdfFieldScripts(
    keystroke: of(PdfFieldScriptTrigger.keystroke),
    format: of(PdfFieldScriptTrigger.format),
    validate: of(PdfFieldScriptTrigger.validate),
    calculate: of(PdfFieldScriptTrigger.calculate),
  );
}

// ---------------------------------------------------------------------------
// script recognition

/// Recognises [source] as one built-in helper call for [trigger], or
/// returns a [PdfUnsupportedFieldScript] saying why not.
///
/// Accepted shapes: a single `AFName(args);` call (comments and whitespace
/// ignored; arguments are numbers, strings, booleans, and `new Array(...)`
/// / `[...]` string lists), and simplified field notation calculations
/// (`/*** BVCALC A * B EVCALC ***/ ...`).
PdfFieldScript parsePdfFieldScript(
    String source, PdfFieldScriptTrigger trigger) {
  PdfFieldScript unsupported(String reason) =>
      PdfUnsupportedFieldScript(source, trigger, reason);
  if (source.trim().isEmpty) return unsupported('not a JavaScript action');

  final sfn = _sfnRe.firstMatch(source);
  if (sfn != null) {
    if (trigger != PdfFieldScriptTrigger.calculate) {
      return unsupported('simplified field notation outside a calculation');
    }
    final expr = _SfnParser(sfn.group(1)!).parse();
    return expr == null
        ? unsupported('unreadable simplified field notation')
        : PdfSimplifiedCalculateScript._(source, sfn.group(1)!.trim(), expr);
  }

  final call = _parseCall(source);
  if (call == null) return unsupported('not a single built-in helper call');
  final (name, args) = call;
  final script = _recognise(source, name, args);
  if (script == null) return unsupported('$name is not a recognised helper');
  if (script.trigger != trigger) {
    return unsupported('$name belongs to the ${script.trigger.name} trigger');
  }
  return script;
}

final _sfnRe = RegExp(r'BVCALC([\s\S]*?)EVCALC');

/// AFDate_Format / AFDate_Keystroke legacy format indices.
const _legacyDateFormats = [
  'm/d',
  'm/d/yy',
  'mm/dd/yy',
  'mm/yy',
  'd-mmm',
  'd-mmm-yy',
  'dd-mmm-yy',
  'yy-mm-dd',
  'mmm-yy',
  'mmmm-yy',
  'mmm d, yyyy',
  'mmmm d, yyyy',
  'm/d/yy h:MM tt',
  'm/d/yy HH:MM',
];

/// AFTime_Format / AFTime_Keystroke legacy format indices.
const _legacyTimeFormats = ['HH:MM', 'h:MM tt', 'HH:MM:ss', 'h:MM:ss tt'];

PdfFieldScript? _recognise(String source, String name, List<Object?> args) {
  double? num(int i) => i < args.length ? _argNumber(args[i]) : null;
  int int_(int i, int fallback) => num(i)?.truncate() ?? fallback;
  bool bool_(int i, bool fallback) {
    if (i >= args.length) return fallback;
    final a = args[i];
    if (a is bool) return a;
    if (a is double) return a != 0;
    if (a is String) return a == 'true' || (double.tryParse(a) ?? 0) != 0;
    return fallback;
  }

  String str(int i, String fallback) {
    if (i >= args.length) return fallback;
    final a = args[i];
    if (a is String) return a;
    if (a is double) return _jsNumber(a);
    return fallback;
  }

  PdfNumberStyle numberStyle() => PdfNumberStyle(
        decimals: int_(0, 2).clamp(0, 20),
        sepStyle: int_(1, 0).clamp(0, 4),
        negStyle: int_(2, 0).clamp(0, 3),
        currency: str(4, ''),
        currencyPrepend: bool_(5, true),
      );

  String? legacy(List<String> table) {
    final i = num(0)?.truncate();
    return i == null || i < 0 || i >= table.length ? null : table[i];
  }

  switch (name) {
    case 'AFNumber_Format':
      if (args.isEmpty) return null;
      return PdfNumberFormatScript._(source, numberStyle());
    case 'AFNumber_Keystroke':
      if (args.isEmpty) return null;
      return PdfNumberKeystrokeScript._(source, numberStyle());
    case 'AFPercent_Format':
      if (args.isEmpty) return null;
      return PdfPercentFormatScript._(
          source, int_(0, 2).clamp(0, 20), int_(1, 0).clamp(0, 4),
          percentPrepend: bool_(2, false));
    case 'AFPercent_Keystroke':
      if (args.isEmpty) return null;
      return PdfPercentKeystrokeScript._(
          source, int_(0, 2).clamp(0, 20), int_(1, 0).clamp(0, 4));
    case 'AFDate_FormatEx' || 'AFTime_FormatEx':
      final f = str(0, '');
      return f.isEmpty ? null : PdfDateFormatScript._(source, f);
    case 'AFDate_KeystrokeEx' || 'AFTime_KeystrokeEx':
      final f = str(0, '');
      return f.isEmpty ? null : PdfDateKeystrokeScript._(source, f);
    case 'AFDate_Format':
      final f = legacy(_legacyDateFormats);
      return f == null ? null : PdfDateFormatScript._(source, f);
    case 'AFDate_Keystroke':
      final f = legacy(_legacyDateFormats);
      return f == null ? null : PdfDateKeystrokeScript._(source, f);
    case 'AFTime_Format':
      final f = legacy(_legacyTimeFormats);
      return f == null ? null : PdfDateFormatScript._(source, f);
    case 'AFTime_Keystroke':
      final f = legacy(_legacyTimeFormats);
      return f == null ? null : PdfDateKeystrokeScript._(source, f);
    case 'AFSpecial_Format':
      final psf = num(0)?.truncate();
      return psf == null || psf < 0 || psf > 3
          ? null
          : PdfSpecialFormatScript._(source, psf);
    case 'AFSpecial_Keystroke':
      final psf = num(0)?.truncate();
      return psf == null || psf < 0 || psf > 3
          ? null
          : PdfSpecialKeystrokeScript._(source, psf: psf);
    case 'AFSpecial_KeystrokeEx':
      final mask = str(0, '');
      return mask.isEmpty
          ? null
          : PdfSpecialKeystrokeScript._(source, mask: mask);
    case 'AFRange_Validate':
      if (args.length < 4) return null;
      return PdfRangeValidateScript._(
        source,
        min: bool_(0, false) ? num(1) : null,
        max: bool_(2, false) ? num(3) : null,
      );
    case 'AFSimple_Calculate':
      if (args.length < 2) return null;
      final op = switch (str(0, '').toUpperCase()) {
        'SUM' => PdfSimpleCalculation.sum,
        'AVG' => PdfSimpleCalculation.average,
        'PRD' => PdfSimpleCalculation.product,
        'MIN' => PdfSimpleCalculation.minimum,
        'MAX' => PdfSimpleCalculation.maximum,
        _ => null,
      };
      if (op == null) return null;
      final raw = args[1];
      final fields = <String>[
        if (raw is List)
          for (final f in raw)
            if (f is String) f.trim(),
        // AFMakeArrayFromList: a comma-separated string works too
        if (raw is String) ...raw.split(',').map((s) => s.trim()),
      ]..removeWhere((f) => f.isEmpty);
      return PdfSimpleCalculateScript._(source, op, fields);
  }
  return null;
}

double? _argNumber(Object? a) => switch (a) {
      double() => a,
      bool() => a ? 1 : 0,
      String() => double.tryParse(a.trim()),
      _ => null,
    };

/// A minimal tokenizer for `Name(args);` scripts. Returns null for anything
/// that is not exactly one call.
(String, List<Object?>)? _parseCall(String source) {
  final t = _JsTokens(source);
  final name = t.identifier();
  if (name == null || !t.take('(')) return null;
  final args = <Object?>[];
  if (!t.take(')')) {
    while (true) {
      final value = t.value();
      if (value == _JsTokens.invalid) return null;
      args.add(value);
      if (t.take(')')) break;
      if (!t.take(',')) return null;
    }
  }
  t.take(';');
  return t.atEnd ? (name, args) : null;
}

class _JsTokens {
  _JsTokens(this.s);

  static const invalid = Object();
  final String s;
  int i = 0;

  void _skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0) {
        i++;
      } else if (s.startsWith('//', i)) {
        while (i < s.length && s[i] != '\n' && s[i] != '\r') {
          i++;
        }
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        i = end < 0 ? s.length : end + 2;
      } else {
        return;
      }
    }
  }

  bool get atEnd {
    _skip();
    return i >= s.length;
  }

  bool take(String punct) {
    _skip();
    if (s.startsWith(punct, i)) {
      i += punct.length;
      return true;
    }
    return false;
  }

  static final _identRe = RegExp(r'[A-Za-z_$][A-Za-z0-9_$.]*');
  static final _numberRe = RegExp(r'[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?');

  String? identifier() {
    _skip();
    final m = _identRe.matchAsPrefix(s, i);
    if (m == null) return null;
    i = m.end;
    return m.group(0);
  }

  /// A literal argument: number, string, boolean, or string array.
  Object? value() {
    _skip();
    if (i >= s.length) return invalid;
    final c = s[i];
    if (c == '"' || c == "'") return _string(c);
    if (c == '[') {
      i++;
      return _list(']');
    }
    final n = _numberRe.matchAsPrefix(s, i);
    if (n != null) {
      i = n.end;
      return double.parse(n.group(0)!);
    }
    final ident = identifier();
    switch (ident) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null' || 'undefined':
        return null;
      case 'new':
        if (identifier() != 'Array' || !take('(')) return invalid;
        return _list(')');
      case 'Array':
        if (!take('(')) return invalid;
        return _list(')');
    }
    return invalid;
  }

  Object? _list(String close) {
    final out = <Object?>[];
    if (take(close)) return out;
    while (true) {
      final v = value();
      if (v == invalid) return invalid;
      out.add(v);
      if (take(close)) return out;
      if (!take(',')) return invalid;
    }
  }

  Object? _string(String quote) {
    i++;
    final b = StringBuffer();
    while (i < s.length) {
      final c = s[i++];
      if (c == quote) return b.toString();
      if (c == r'\' && i < s.length) {
        final e = s[i++];
        switch (e) {
          case 'n':
            b.write('\n');
          case 't':
            b.write('\t');
          case 'r':
            b.write('\r');
          case 'u' when i + 4 <= s.length:
            final code = int.tryParse(s.substring(i, i + 4), radix: 16);
            if (code == null) return invalid;
            b.writeCharCode(code);
            i += 4;
          default:
            b.write(e);
        }
      } else {
        b.write(c);
      }
    }
    return invalid;
  }
}

// ---------------------------------------------------------------------------
// numbers

/// AFMakeNumber: the number a field value holds, or null. Accepts an
/// optional sign, digits, and a '.' or ',' decimal separator; a value that
/// uses ',' only as thousands grouping alongside a '.' decimal also reads.
double? pdfAfMakeNumber(String? value) {
  if (value == null) return null;
  var s = value.trim();
  if (s.isEmpty) return null;
  if (s.contains('.') && s.contains(',')) s = s.replaceAll(',', '');
  s = s.replaceFirst(',', '.');
  if (!_makeNumberRe.hasMatch(s)) return null;
  final n = double.tryParse(s);
  return n == null || !n.isFinite ? null : n;
}

final _makeNumberRe = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

/// A JavaScript number's string form: integers without a fraction.
String _jsNumber(double v) {
  if (!v.isFinite) return '';
  if (v == v.truncateToDouble() && v.abs() < 1e21) {
    return v.toInt().toString();
  }
  return v.toString();
}

/// Rounds binary noise away (0.1 * 3 → 0.3) the way a 15-significant-digit
/// print does.
double _clean(double v) =>
    v.isFinite ? double.parse(v.toStringAsPrecision(15)) : v;

/// The separator pair for AFNumber's sepStyle 0-4.
(String group, String decimal) _separators(int sepStyle) => switch (sepStyle) {
      0 => (',', '.'),
      1 => ('', '.'),
      2 => ('.', ','),
      3 => ('', ','),
      _ => ("'", '.'),
    };

/// util.printf's `%,<sepStyle>.<decimals>f` on a non-negative magnitude.
String pdfFormatDecimal(double magnitude, int decimals, int sepStyle) {
  final fixed = magnitude.abs().toStringAsFixed(decimals.clamp(0, 20));
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot + 1);
  final (group, decimal) = _separators(sepStyle);
  final grouped = StringBuffer();
  for (var k = 0; k < whole.length; k++) {
    if (k > 0 && group.isNotEmpty && (whole.length - k) % 3 == 0) {
      grouped.write(group);
    }
    grouped.write(whole[k]);
  }
  return frac.isEmpty ? grouped.toString() : '$grouped$decimal$frac';
}

/// AFNumber_Format / AFNumber_Keystroke parameters.
class PdfNumberStyle {
  const PdfNumberStyle({
    this.decimals = 2,
    this.sepStyle = 0,
    this.negStyle = 0,
    this.currency = '',
    this.currencyPrepend = true,
  });

  /// nDec: digits after the decimal separator.
  final int decimals;

  /// 0 `1,234.56`, 1 `1234.56`, 2 `1.234,56`, 3 `1234,56`, 4 `1'234.56`.
  final int sepStyle;

  /// 0 minus sign, 1 red, 2 parentheses, 3 red parentheses.
  final int negStyle;

  /// strCurrency, written verbatim (include any space it wants).
  final String currency;

  /// bCurrencyPrepend: currency before (true) or after the number.
  final bool currencyPrepend;

  /// The red AFNumber paints negative values in styles 1 and 3.
  static const negativeRed = 0xFF0000;

  PdfFieldDisplay format(String value) {
    final v = pdfAfMakeNumber(value);
    if (v == null) return const PdfFieldDisplay('');
    final body = pdfFormatDecimal(v, decimals, sepStyle);
    // a value that rounds to zero shows no sign
    final negative = v < 0 && body.contains(RegExp('[1-9]'));
    final parens = negative && (negStyle == 2 || negStyle == 3);
    final b = StringBuffer();
    if (negative && negStyle == 0) b.write('-');
    if (parens) b.write('(');
    if (currencyPrepend) b.write(currency);
    b.write(body);
    if (!currencyPrepend) b.write(currency);
    if (parens) b.write(')');
    return PdfFieldDisplay(
      b.toString(),
      textColor:
          negative && (negStyle == 1 || negStyle == 3) ? negativeRed : null,
    );
  }

  bool get _commaDecimal => sepStyle == 2 || sepStyle == 3;

  bool acceptsPartial(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return (_commaDecimal ? _partialComma : _partialDot).hasMatch(t);
  }

  static final _partialDot = RegExp(r'^[+-]?\d*\.?\d*$');
  static final _partialComma = RegExp(r'^[+-]?\d*,?\d*$');
  static final _commitDot = RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)$');
  static final _commitComma = RegExp(r'^[+-]?(\d+(,\d*)?|,\d+)$');

  /// The keystroke commit: strict number syntax for the separator style,
  /// after forgiving what the formatted display itself would contain
  /// (currency, well-formed thousands grouping, parentheses for negative).
  /// A comma decimal is stored with '.', like the AForm helper.
  PdfFieldInputResult commit(String text, String fieldName) {
    var t = text.trim();
    if (t.isEmpty) return const PdfFieldInputResult.valid('');
    if (currency.trim().isNotEmpty) t = t.replaceAll(currency.trim(), '');
    t = t.replaceAll(RegExp(r'\s'), '');
    var negative = false;
    if (t.startsWith('(') && t.endsWith(')') && t.length > 2) {
      negative = true;
      t = t.substring(1, t.length - 1);
    }
    final (group, decimal) = _separators(sepStyle);
    if (group.isNotEmpty) {
      final grouped = RegExp('^[+-]?\\d{1,3}(${RegExp.escape(group)}\\d{3})+'
          '(${RegExp.escape(decimal)}\\d*)?\$');
      if (grouped.hasMatch(t)) t = t.replaceAll(group, '');
    }
    if (!(_commaDecimal ? _commitComma : _commitDot).hasMatch(t)) {
      return PdfFieldInputResult.invalid(
          text,
          PdfFieldInputFailure.format,
          'The value entered does not match the format of the field'
          '${fieldName.isEmpty ? '' : ' "$fieldName"'}.');
    }
    if (_commaDecimal) t = t.replaceFirst(',', '.');
    if (t.startsWith('+')) t = t.substring(1);
    if (negative) t = t.startsWith('-') ? t.substring(1) : '-$t';
    return PdfFieldInputResult.valid(t);
  }
}

/// `AFNumber_Format(nDec, sepStyle, negStyle, currStyle, strCurrency,
/// bCurrencyPrepend)`.
final class PdfNumberFormatScript extends PdfFormatScript {
  const PdfNumberFormatScript._(super.source, this.style);

  final PdfNumberStyle style;

  @override
  PdfFieldDisplay format(String value, {DateTime? now}) => style.format(value);
}

/// `AFNumber_Keystroke(...)`: digits, one sign, one decimal separator.
final class PdfNumberKeystrokeScript extends PdfKeystrokeScript {
  const PdfNumberKeystrokeScript._(super.source, this.style);

  final PdfNumberStyle style;

  @override
  bool acceptsPartial(String text) => style.acceptsPartial(text);

  @override
  PdfFieldInputResult commit(String text,
          {String fieldName = '', DateTime? now}) =>
      style.commit(text, fieldName);
}

/// `AFPercent_Format(nDec, sepStyle, bPercentPrepend)`: the value is a
/// fraction, shown times 100 with a percent sign.
final class PdfPercentFormatScript extends PdfFormatScript {
  const PdfPercentFormatScript._(super.source, this.decimals, this.sepStyle,
      {this.percentPrepend = false});

  final int decimals;
  final int sepStyle;
  final bool percentPrepend;

  @override
  PdfFieldDisplay format(String value, {DateTime? now}) {
    final v = pdfAfMakeNumber(value);
    if (v == null) return const PdfFieldDisplay('');
    final body = pdfFormatDecimal(v * 100, decimals, sepStyle);
    final sign = v < 0 && body.contains(RegExp('[1-9]')) ? '-' : '';
    return PdfFieldDisplay(percentPrepend ? '%$sign$body' : '$sign$body%');
  }
}

/// `AFPercent_Keystroke(nDec, sepStyle)`: a number; a committed value typed
/// with a trailing '%' is divided by 100 so "15%" stores 0.15.
final class PdfPercentKeystrokeScript extends PdfKeystrokeScript {
  const PdfPercentKeystrokeScript._(super.source, this.decimals, this.sepStyle);

  final int decimals;
  final int sepStyle;

  PdfNumberStyle get _style =>
      PdfNumberStyle(decimals: decimals, sepStyle: sepStyle);

  @override
  bool acceptsPartial(String text) {
    final t = text.trim();
    return _style
        .acceptsPartial(t.endsWith('%') ? t.substring(0, t.length - 1) : t);
  }

  @override
  PdfFieldInputResult commit(String text,
      {String fieldName = '', DateTime? now}) {
    final t = text.trim();
    if (t.endsWith('%')) {
      final r = _style.commit(t.substring(0, t.length - 1), fieldName);
      if (!r.isValid) {
        return PdfFieldInputResult.invalid(text, r.failure!, r.message!);
      }
      final n = pdfAfMakeNumber(r.value);
      return PdfFieldInputResult.valid(
          n == null ? '' : _jsNumber(_clean(n / 100)));
    }
    final r = _style.commit(t, fieldName);
    return r.isValid
        ? r
        : PdfFieldInputResult.invalid(text, r.failure!, r.message!);
  }
}

// ---------------------------------------------------------------------------
// dates

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// util.printd format tokens, longest first.
const _dateTokens = [
  'yyyy', 'yy', //
  'mmmm', 'mmm', 'mm', 'm',
  'dddd', 'ddd', 'dd', 'd',
  'HH', 'H', 'hh', 'h',
  'MM', 'M', 'ss', 's', 'tt', 't',
];

/// A format split into tokens: printd tokens as themselves, literal text as
/// `(false, text)`.
List<(bool token, String text)> _tokenizeDateFormat(String format) {
  final out = <(bool, String)>[];
  var i = 0;
  outer:
  while (i < format.length) {
    if (format[i] == r'\' && i + 1 < format.length) {
      out.add((false, format[i + 1]));
      i += 2;
      continue;
    }
    for (final token in _dateTokens) {
      if (format.startsWith(token, i)) {
        out.add((true, token));
        i += token.length;
        continue outer;
      }
    }
    out.add((false, format[i]));
    i++;
  }
  return out;
}

String _pad2(int v) => v.toString().padLeft(2, '0');

/// util.printd: [date] rendered with [format]'s tokens.
String pdfPrintDate(String format, DateTime date) {
  final b = StringBuffer();
  for (final (token, text) in _tokenizeDateFormat(format)) {
    if (!token) {
      b.write(text);
      continue;
    }
    final h12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    b.write(switch (text) {
      'yyyy' => date.year.toString().padLeft(4, '0'),
      'yy' => _pad2(date.year % 100),
      'mmmm' => _monthNames[date.month - 1],
      'mmm' => _monthNames[date.month - 1].substring(0, 3),
      'mm' => _pad2(date.month),
      'm' => '${date.month}',
      'dddd' => _dayNames[date.weekday - 1],
      'ddd' => _dayNames[date.weekday - 1].substring(0, 3),
      'dd' => _pad2(date.day),
      'd' => '${date.day}',
      'HH' => _pad2(date.hour),
      'H' => '${date.hour}',
      'hh' => _pad2(h12),
      'h' => '$h12',
      'MM' => _pad2(date.minute),
      'M' => '${date.minute}',
      'ss' => _pad2(date.second),
      's' => '${date.second}',
      'tt' => date.hour < 12 ? 'am' : 'pm',
      't' => date.hour < 12 ? 'a' : 'p',
      _ => text,
    });
  }
  return b.toString();
}

int? _monthFromWord(String word) {
  final w = word.toLowerCase();
  if (w.length < 3) return null;
  for (var m = 0; m < 12; m++) {
    final name = _monthNames[m].toLowerCase();
    if (name.startsWith(w) || (w.length > 3 && w.startsWith(name))) {
      return m + 1;
    }
  }
  // "Sept"
  return w == 'sept' ? 9 : null;
}

bool? _meridiem(String word) => switch (word.toLowerCase()) {
      'a' || 'am' || 'a.m.' => false,
      'p' || 'pm' || 'p.m.' => true,
      _ => null,
    };

class _DateFields {
  int? year, month, day, hour, minute, second;
  bool yearShort = false;
  bool? pm;

  DateTime? build(DateTime now) {
    // a bare time (nothing of the date given) is today
    final today = year == null && month == null && day == null;
    var y = year ?? now.year;
    if (year != null && yearShort) y += y < 50 ? 2000 : 1900;
    final m = month ?? (today ? now.month : 1);
    final d = day ?? (today ? now.day : 1);
    var h = hour ?? 0;
    if (pm != null) {
      if (h < 1 || h > 12) return null;
      if (pm! && h < 12) h += 12;
      if (!pm! && h == 12) h = 0;
    }
    final mi = minute ?? 0, s = second ?? 0;
    if (m < 1 || m > 12 || d < 1 || d > DateTime.utc(y, m + 1, 0).day) {
      return null;
    }
    if (h < 0 || h > 23 || mi < 0 || mi > 59 || s < 0 || s > 59) return null;
    return DateTime(y, m, d, h, mi, s);
  }
}

/// AFParseDateEx: reads [value] as a date/time written in [format]. Tries
/// an exact read of the format first, then the lenient read the helper
/// does - numbers taken in the order the format lists its date fields
/// (year dropped when too few are typed), month names anywhere, then time
/// numbers and am/pm. Missing fields default to the current year, January,
/// the 1st, and midnight. Null when nothing sensible can be read.
DateTime? pdfParseDate(String value, String format, {DateTime? now}) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final clock = now ?? DateTime.now();
  final tokens = _tokenizeDateFormat(format);
  return _strictDate(v, tokens)?.build(clock) ??
      _lenientDate(v, tokens)?.build(clock);
}

_DateFields? _strictDate(String v, List<(bool, String)> tokens) {
  final f = _DateFields();
  var i = 0;
  int? digits(int max) {
    final start = i;
    while (i < v.length && i - start < max && _isDigit(v.codeUnitAt(i))) {
      i++;
    }
    return i == start ? null : int.parse(v.substring(start, i));
  }

  String letters() {
    final start = i;
    while (i < v.length && _isLetter(v.codeUnitAt(i))) {
      i++;
    }
    return v.substring(start, i);
  }

  for (final (token, text) in tokens) {
    if (!token) {
      if (text.trim().isEmpty) {
        while (i < v.length && v[i].trim().isEmpty) {
          i++;
        }
        continue;
      }
      if (i >= v.length || v[i].toLowerCase() != text.toLowerCase()) {
        return null;
      }
      i++;
      continue;
    }
    switch (text) {
      case 'yyyy':
        final start = i;
        f.year = digits(4);
        if (f.year == null) return null;
        f.yearShort = i - start <= 2;
      case 'yy':
        f.year = digits(2);
        if (f.year == null) return null;
        f.yearShort = true;
      case 'mmmm' || 'mmm':
        final m = _monthFromWord(letters());
        if (m == null) return null;
        f.month = m;
      case 'mm' || 'm':
        f.month = digits(2);
        if (f.month == null) return null;
      case 'dddd' || 'ddd':
        if (letters().isEmpty) return null;
      case 'dd' || 'd':
        f.day = digits(2);
        if (f.day == null) return null;
      case 'HH' || 'H':
        f.hour = digits(2);
        if (f.hour == null) return null;
      case 'hh' || 'h':
        f.hour = digits(2);
        if (f.hour == null) return null;
        f.pm ??= false;
      case 'MM' || 'M':
        f.minute = digits(2);
        if (f.minute == null) return null;
      case 'ss' || 's':
        f.second = digits(2);
        if (f.second == null) return null;
      case 'tt' || 't':
        final start = i;
        while (i < v.length && (_isLetter(v.codeUnitAt(i)) || v[i] == '.')) {
          i++;
        }
        final m = _meridiem(v.substring(start, i));
        if (m == null) return null;
        f.pm = m;
    }
  }
  return v.substring(i).trim().isEmpty ? f : null;
}

_DateFields? _lenientDate(String v, List<(bool, String)> tokens) {
  final numbers = <(int value, int length)>[];
  final f = _DateFields();
  for (final m in RegExp(r'\d+|[A-Za-z]+(\.[mM]\.)?').allMatches(v)) {
    final word = m.group(0)!;
    if (_isDigit(word.codeUnitAt(0))) {
      numbers.add((int.parse(word), word.length));
      continue;
    }
    final meridiem = _meridiem(word);
    if (meridiem != null) {
      f.pm = meridiem;
      continue;
    }
    final month = _monthFromWord(word);
    if (month != null) {
      f.month = month;
      continue;
    }
    if (_dayNames.any((d) => d.toLowerCase().startsWith(word.toLowerCase())) &&
        word.length >= 3) {
      continue; // a weekday name carries nothing we need
    }
    return null;
  }
  if (numbers.isEmpty && f.month == null) return null;

  // the order the format lists its fields
  final dateOrder = <String>[];
  final timeOrder = <String>[];
  for (final (token, text) in tokens) {
    if (!token) continue;
    final kind = switch (text[0]) {
      'y' => 'y',
      'm' => text.length >= 3 ? 'mw' : 'm',
      'd' => text.length >= 3 ? null : 'd',
      'H' || 'h' => 'H',
      'M' => 'M',
      's' => 's',
      _ => null,
    };
    if (kind == null) continue;
    if (kind == 'mw') {
      // a month written as a word in the format may still be typed as a
      // number
      if (f.month == null && !dateOrder.contains('m')) dateOrder.add('m');
    } else if (kind == 'H' || kind == 'M' || kind == 's') {
      if (!timeOrder.contains(kind)) timeOrder.add(kind);
    } else if (!(kind == 'm' && f.month != null) && !dateOrder.contains(kind)) {
      dateOrder.add(kind);
    }
  }
  if (numbers.length < dateOrder.length) dateOrder.remove('y');
  // a four-digit number is the year wherever it sits; leading the input it
  // also means ISO order (2024-03-05) whatever the field's format
  if (dateOrder.contains('y')) {
    final at = numbers.indexWhere((n) => n.$2 >= 3);
    if (at >= 0) {
      final (value, _) = numbers.removeAt(at);
      f.year = value;
      dateOrder.remove('y');
      if (at == 0 && dateOrder.length == 2 && f.month == null) {
        dateOrder
          ..clear()
          ..addAll(['m', 'd']);
      }
    }
  }
  var n = 0;
  for (final kind in [...dateOrder, ...timeOrder]) {
    if (n >= numbers.length) break;
    final (value, length) = numbers[n++];
    switch (kind) {
      case 'y':
        f.year = value;
        f.yearShort = length <= 2;
      case 'm':
        f.month = value;
      case 'd':
        f.day = value;
      case 'H':
        f.hour = value;
      case 'M':
        f.minute = value;
      case 's':
        f.second = value;
    }
  }
  if (n < numbers.length) return null; // more numbers than fields
  return f;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c > 0x7F;

/// `AFDate_FormatEx(cFormat)` (and `AFDate_Format(n)`, `AFTime_Format(n)`,
/// `AFTime_FormatEx(cFormat)`): the value re-printed in [dateFormat]; a
/// value that does not read as a date is shown unchanged.
final class PdfDateFormatScript extends PdfFormatScript {
  const PdfDateFormatScript._(super.source, this.dateFormat);

  /// The util.printd format (`mm/dd/yyyy`, `h:MM tt`, ...).
  final String dateFormat;

  @override
  PdfFieldDisplay format(String value, {DateTime? now}) {
    if (value.trim().isEmpty) return PdfFieldDisplay(value);
    final date = pdfParseDate(value, dateFormat, now: now);
    return PdfFieldDisplay(
        date == null ? value : pdfPrintDate(dateFormat, date));
  }
}

/// `AFDate_KeystrokeEx(cFormat)` (and the legacy/time variants): any typing
/// is allowed; a committed value must read as a date in [dateFormat]. The
/// stored value stays as typed.
final class PdfDateKeystrokeScript extends PdfKeystrokeScript {
  const PdfDateKeystrokeScript._(super.source, this.dateFormat);

  final String dateFormat;

  @override
  bool acceptsPartial(String text) => true;

  @override
  PdfFieldInputResult commit(String text,
      {String fieldName = '', DateTime? now}) {
    final t = text.trim();
    if (t.isEmpty || pdfParseDate(t, dateFormat, now: now) != null) {
      return PdfFieldInputResult.valid(t);
    }
    return PdfFieldInputResult.invalid(
        text,
        PdfFieldInputFailure.date,
        'Invalid date/time: please ensure that the date/time exists. Field'
        '${fieldName.isEmpty ? '' : ' "$fieldName"'} should match format '
        '$dateFormat.');
  }
}

// ---------------------------------------------------------------------------
// special formats

/// The AFSpecial psf masks: 0 zip, 1 zip+4, 2 phone, 3 SSN.
const pdfSpecialMasks = [
  '99999',
  '99999-9999',
  '(999) 999-9999',
  '999-99-9999',
];

/// util.printx: [mask] filled from [source]. `9` takes the next digit, `A`
/// the next letter, `X` the next letter or digit, `?` the next character,
/// `*` the rest; `>`/`<`/`=` switch to upper/lower/unchanged case, `\`
/// escapes; anything else is literal. Stops when the source runs out.
String pdfPrintMask(String mask, String source) {
  final b = StringBuffer();
  var i = 0;
  var caseMode = 0; // 0 keep, 1 upper, 2 lower
  String cased(String c) => switch (caseMode) {
        1 => c.toUpperCase(),
        2 => c.toLowerCase(),
        _ => c,
      };
  bool isAlpha(String c) => _isAsciiLetter(c.codeUnitAt(0));
  bool isDigit(String c) => _isDigit(c.codeUnitAt(0));
  var escaped = false;
  for (final m in mask.split('')) {
    if (escaped) {
      b.write(m);
      escaped = false;
      continue;
    }
    if (i >= source.length) break;
    switch (m) {
      case '?':
        b.write(cased(source[i++]));
      case 'X' || 'A' || '9':
        while (i < source.length) {
          final c = source[i++];
          final ok = switch (m) {
            'X' => isAlpha(c) || isDigit(c),
            'A' => isAlpha(c),
            _ => isDigit(c),
          };
          if (ok) {
            b.write(cased(c));
            break;
          }
        }
      case '*':
        while (i < source.length) {
          b.write(cased(source[i++]));
        }
      case r'\':
        escaped = true;
      case '>':
        caseMode = 1;
      case '<':
        caseMode = 2;
      case '=':
        caseMode = 0;
      default:
        b.write(m);
    }
  }
  return b.toString();
}

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// `AFSpecial_Format(psf)`: zip, zip+4, phone or SSN printed from the
/// value's digits.
final class PdfSpecialFormatScript extends PdfFormatScript {
  const PdfSpecialFormatScript._(super.source, this.psf);

  /// 0 zip, 1 zip+4, 2 phone, 3 SSN.
  final int psf;

  @override
  PdfFieldDisplay format(String value, {DateTime? now}) {
    if (value.isEmpty) return PdfFieldDisplay(value);
    var mask = pdfSpecialMasks[psf];
    if (psf == 2 && pdfPrintMask('9999999999', value).length < 10) {
      mask = '999-9999';
    }
    return PdfFieldDisplay(pdfPrintMask(mask, value));
  }
}

/// `AFSpecial_Keystroke(psf)` / `AFSpecial_KeystrokeEx(cMask)`: the typed
/// text must follow the mask - either with its literal characters or as
/// the bare placeholder characters ("123456789" for an SSN). `9` digit,
/// `A` letter, `O` letter or digit, `X` any character. The stored value
/// stays as typed.
final class PdfSpecialKeystrokeScript extends PdfKeystrokeScript {
  const PdfSpecialKeystrokeScript._(super.source, {this.psf, this.mask});

  /// The psf of an AFSpecial_Keystroke call, or null for KeystrokeEx.
  final int? psf;

  /// The explicit mask of an AFSpecial_KeystrokeEx call.
  final String? mask;

  /// The mask applying to [text] (phone picks the 7 or 10 digit form).
  String maskFor(String text) {
    if (mask != null) return mask!;
    if (psf == 2) {
      return text.startsWith('(') ||
              (text.length > 7 && RegExp(r'^\d+$').hasMatch(text))
          ? '(999) 999-9999'
          : '999-9999';
    }
    return pdfSpecialMasks[psf!];
  }

  static bool _fits(String value, String mask, {required bool commit}) {
    if (value.isEmpty) return true;
    if (value.length > mask.length) return false;
    if (commit && value.length < mask.length) return false;
    for (var i = 0; i < value.length; i++) {
      final m = mask[i];
      final c = value.codeUnitAt(i);
      final ok = switch (m) {
        '9' => _isDigit(c),
        'A' => _isAsciiLetter(c),
        'O' => _isAsciiLetter(c) || _isDigit(c),
        'X' => true,
        _ => m == value[i],
      };
      if (!ok) return false;
    }
    return true;
  }

  bool _check(String text, {required bool commit}) {
    final m = maskFor(text);
    return _fits(text, m.replaceAll(RegExp('[^9AOX]'), ''), commit: commit) ||
        _fits(text, m, commit: commit);
  }

  @override
  bool acceptsPartial(String text) => _check(text, commit: false);

  @override
  PdfFieldInputResult commit(String text,
      {String fieldName = '', DateTime? now}) {
    final t = text.trim();
    if (_check(t, commit: true)) return PdfFieldInputResult.valid(t);
    return PdfFieldInputResult.invalid(
        text,
        PdfFieldInputFailure.format,
        'The value entered does not match the format of the field'
        '${fieldName.isEmpty ? '' : ' "$fieldName"'} (${maskFor(t)}).');
  }
}

// ---------------------------------------------------------------------------
// validation

/// `AFRange_Validate(bGreaterThan, nGreaterThan, bLessThan, nLessThan)`:
/// numeric values must lie within the inclusive bounds. Empty and
/// non-numeric values pass, as in the helper.
final class PdfRangeValidateScript extends PdfValidateScript {
  const PdfRangeValidateScript._(super.source, {this.min, this.max});

  /// The inclusive lower bound, or null when unchecked.
  final double? min;

  /// The inclusive upper bound, or null when unchecked.
  final double? max;

  @override
  PdfFieldInputResult? validate(String value) {
    final v = pdfAfMakeNumber(value);
    if (v == null) return null;
    final lo = min, hi = max;
    final String? message;
    if (lo != null && hi != null) {
      message = v < lo || v > hi
          ? 'Invalid value: must be greater than or equal to ${_jsNumber(lo)} '
              'and less than or equal to ${_jsNumber(hi)}.'
          : null;
    } else if (lo != null) {
      message = v < lo
          ? 'Invalid value: must be greater than or equal to '
              '${_jsNumber(lo)}.'
          : null;
    } else if (hi != null) {
      message = v > hi
          ? 'Invalid value: must be less than or equal to ${_jsNumber(hi)}.'
          : null;
    } else {
      message = null;
    }
    return message == null
        ? null
        : PdfFieldInputResult.invalid(
            value, PdfFieldInputFailure.range, message);
  }
}

// ---------------------------------------------------------------------------
// calculations

/// AFSimple_Calculate's cFunction.
enum PdfSimpleCalculation { sum, average, product, minimum, maximum }

/// `AFSimple_Calculate(cFunction, cFields)`: SUM/AVG/PRD/MIN/MAX over the
/// named fields (a parent name contributes every terminal field under it;
/// non-numeric values count as 0), rounded to six decimal places.
final class PdfSimpleCalculateScript extends PdfCalculateScript {
  const PdfSimpleCalculateScript._(super.source, this.operation, this.fields);

  final PdfSimpleCalculation operation;
  final List<String> fields;

  @override
  List<String> get inputs => fields;

  @override
  String calculate(List<String?> Function(String name) lookup) {
    final values = <double>[
      for (final name in fields)
        for (final v in lookup(name)) pdfAfMakeNumber(v) ?? 0,
    ];
    if (values.isEmpty) return '0';
    final r = switch (operation) {
      PdfSimpleCalculation.sum => values.fold<double>(0, (a, b) => a + b),
      PdfSimpleCalculation.average =>
        values.fold<double>(0, (a, b) => a + b) / values.length,
      PdfSimpleCalculation.product => values.fold<double>(1, (a, b) => a * b),
      PdfSimpleCalculation.minimum => values.reduce((a, b) => a < b ? a : b),
      PdfSimpleCalculation.maximum => values.reduce((a, b) => a > b ? a : b),
    };
    return _jsNumber((r * 1e6).roundToDouble() / 1e6);
  }
}

/// A simplified field notation calculation (`BVCALC Qty * Price EVCALC`):
/// + - * / and parentheses over field names and numbers. Empty or
/// non-numeric fields count as 0; a non-finite result (division by zero)
/// stores an empty value.
final class PdfSimplifiedCalculateScript extends PdfCalculateScript {
  PdfSimplifiedCalculateScript._(super.source, this.expression, this._root);

  /// The notation as written between BVCALC and EVCALC.
  final String expression;
  final _SfnNode _root;

  @override
  List<String> get inputs => _root.fields.toList();

  @override
  String calculate(List<String?> Function(String name) lookup) {
    final r = _root.eval((name) {
      final values = lookup(name);
      return values.isEmpty ? 0 : pdfAfMakeNumber(values.first) ?? 0;
    });
    return _jsNumber(_clean(r));
  }
}

sealed class _SfnNode {
  double eval(double Function(String name) field);
  Iterable<String> get fields;
}

class _SfnNumber extends _SfnNode {
  _SfnNumber(this.value);
  final double value;
  @override
  double eval(double Function(String) field) => value;
  @override
  Iterable<String> get fields => const [];
}

class _SfnField extends _SfnNode {
  _SfnField(this.name);
  final String name;
  @override
  double eval(double Function(String) field) => field(name);
  @override
  Iterable<String> get fields => [name];
}

class _SfnUnary extends _SfnNode {
  _SfnUnary(this.operand);
  final _SfnNode operand;
  @override
  double eval(double Function(String) field) => -operand.eval(field);
  @override
  Iterable<String> get fields => operand.fields;
}

class _SfnBinary extends _SfnNode {
  _SfnBinary(this.op, this.left, this.right);
  final String op;
  final _SfnNode left, right;
  @override
  double eval(double Function(String) field) {
    final a = left.eval(field), b = right.eval(field);
    return switch (op) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      _ => a / b,
    };
  }

  @override
  Iterable<String> get fields => [...left.fields, ...right.fields];
}

/// Recursive-descent parser for simplified field notation. Field names run
/// until whitespace, an operator or a parenthesis; a backslash escapes the
/// next character (`Line\ 1`, `A\-B`).
class _SfnParser {
  _SfnParser(this.s);
  final String s;
  int i = 0;

  _SfnNode? parse() {
    final e = _expr();
    _ws();
    return e != null && i >= s.length ? e : null;
  }

  void _ws() {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
  }

  _SfnNode? _expr() {
    var left = _term();
    while (left != null) {
      _ws();
      if (i < s.length && (s[i] == '+' || s[i] == '-')) {
        final op = s[i++];
        final right = _term();
        if (right == null) return null;
        left = _SfnBinary(op, left, right);
      } else {
        break;
      }
    }
    return left;
  }

  _SfnNode? _term() {
    var left = _factor();
    while (left != null) {
      _ws();
      if (i < s.length && (s[i] == '*' || s[i] == '/')) {
        final op = s[i++];
        final right = _factor();
        if (right == null) return null;
        left = _SfnBinary(op, left, right);
      } else {
        break;
      }
    }
    return left;
  }

  _SfnNode? _factor() {
    _ws();
    if (i >= s.length) return null;
    final c = s[i];
    if (c == '-' || c == '+') {
      i++;
      final f = _factor();
      if (f == null) return null;
      return c == '-' ? _SfnUnary(f) : f;
    }
    if (c == '(') {
      i++;
      final e = _expr();
      _ws();
      if (e == null || i >= s.length || s[i] != ')') return null;
      i++;
      return e;
    }
    final b = StringBuffer();
    var escaped = false;
    while (i < s.length) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length) {
        b.write(s[i + 1]);
        i += 2;
        escaped = true;
        continue;
      }
      if (ch.trim().isEmpty || '+-*/()'.contains(ch)) break;
      b.write(ch);
      i++;
    }
    final word = b.toString();
    if (word.isEmpty) return null;
    if (!escaped && _makeNumberRe.hasMatch(word)) {
      return _SfnNumber(double.parse(word));
    }
    return _SfnField(word);
  }
}

// ---------------------------------------------------------------------------
// calculation order

/// One field value a calculation pass changed.
class PdfCalculatedValue {
  const PdfCalculatedValue(this.field, this.value);

  final PdfFormField field;

  /// The new raw value (/V).
  final String value;

  @override
  String toString() => 'PdfCalculatedValue(${field.name} = $value)';
}

/// Resolved once per form instance, like [PdfAcroForm.fields]: every fill
/// consults it, and a batch fill must not re-walk the field tree each time.
final Expando<List<PdfFormField>> _calculationOrderCache =
    Expando('PdfAcroForm.calculationOrder');

/// Calculation-order access on a form.
extension PdfAcroFormCalculations on PdfAcroForm {
  /// The text fields (never password fields) that carry a calculate script,
  /// in the order they run:
  /// the /CO array first (§12.7.3, "calculation order"), then - leniently,
  /// for producers that omit /CO - any other calculated field in field
  /// order. Includes fields whose calculate script is unsupported.
  List<PdfFormField> get calculationOrder =>
      _calculationOrderCache[this] ??= _calculationOrder();

  List<PdfFormField> _calculationOrder() {
    final byDict = <CosDictionary, PdfFormField>{};
    for (final field in fields) {
      byDict[field.dict] = field;
      for (final w in field.widgets) {
        byDict.putIfAbsent(w, () => field);
      }
    }
    final out = <PdfFormField>[];
    final seen = <PdfFormField>{};
    final co = document.cos.resolve(dict['CO']);
    if (co is CosArray) {
      for (final item in co.items) {
        final node = document.cos.resolve(item);
        final field = node is CosDictionary ? byDict[node] : null;
        if (field != null &&
            field.scripts.calculate != null &&
            seen.add(field)) {
          out.add(field);
        }
      }
    }
    for (final field in fields) {
      if (field.scripts.calculate != null && seen.add(field)) out.add(field);
    }
    // password fields are never calculation targets: their appearance is a
    // mask and their value is not the form's to derive
    return [
      for (final f in out)
        if (f.type == PdfFieldType.text && !f.isPassword) f,
    ];
  }

  /// Runs every supported calculate script once, in [calculationOrder],
  /// each seeing the values computed before it. Returns the values that
  /// changed; nothing is written. [skip] names a field not to recompute
  /// (the one the user just entered, so their value stands).
  /// [overrides] supplies values not yet written to the document.
  List<PdfCalculatedValue> calculate({
    String? skip,
    Map<String, String?> overrides = const {},
  }) {
    final order = calculationOrder;
    if (order.isEmpty) return const [];
    // a password field reads as empty: a total over it must not carry its
    // value into a field that shows it (withheld passwords have no /V
    // anyway, but a stored one does)
    final values = <String, String?>{
      for (final f in fields) f.name: f.isPassword ? null : f.value,
      ...overrides,
    };
    List<String?> lookup(String name) {
      if (values.containsKey(name)) return [values[name]];
      final prefix = '$name.';
      return [
        for (final e in values.entries)
          if (e.key.startsWith(prefix)) e.value,
      ];
    }

    final changed = <PdfCalculatedValue>[];
    for (final field in order) {
      if (field.name == skip) continue;
      final script = field.scripts.calculate;
      if (script is! PdfCalculateScript) continue;
      final next = script.calculate(lookup);
      if (next == (values[field.name] ?? '')) continue;
      values[field.name] = next;
      changed.removeWhere((c) => c.field == field);
      changed.add(PdfCalculatedValue(field, next));
    }
    return changed;
  }
}
