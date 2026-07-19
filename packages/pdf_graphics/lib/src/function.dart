import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// A PDF function (§7.10), one input except where shadings need more.
///
/// All four types are supported: 0 (sampled, with linear interpolation),
/// 2 (exponential), 3 (stitching), and 4 (PostScript calculator).
abstract class PdfFunction {
  const PdfFunction();

  List<double> evaluate(double x);

  /// Multi-input evaluation, for function-based (type 1) shadings whose
  /// functions map (x, y) and for multi-colorant DeviceN/Separation tint
  /// transforms. Sampled (type 0) and calculator (type 4) functions
  /// genuinely consume more than one input; the others fall back to the
  /// first.
  List<double> evaluateAt(List<double> inputs) =>
      evaluate(inputs.isEmpty ? 0.0 : inputs[0]);

  static PdfFunction? parse(CosDocument cos, CosObject? object) {
    final resolved = cos.resolve(object);
    if (resolved is CosArray) {
      // one single-output function per color component
      final parts = <PdfFunction>[];
      for (final item in resolved.items) {
        final part = parse(cos, item);
        if (part == null) return null;
        parts.add(part);
      }
      return _CombinedFunction(parts);
    }

    final CosDictionary dict;
    if (resolved is CosStream) {
      dict = resolved.dictionary;
    } else if (resolved is CosDictionary) {
      dict = resolved;
    } else {
      return null;
    }

    final domain = _numbers(cos, dict['Domain']);
    final x0 = domain.isNotEmpty ? domain[0] : 0.0;
    final x1 = domain.length > 1 ? domain[1] : 1.0;

    final type = cos.resolve(dict['FunctionType']);
    switch (type is CosInteger ? type.value : -1) {
      case 2:
        final c0 = _numbers(cos, dict['C0']);
        final c1 = _numbers(cos, dict['C1']);
        final n = _number(cos, dict['N'], 1);
        return _ExponentialFunction(
          x0,
          x1,
          c0.isEmpty ? const [0] : c0,
          c1.isEmpty ? const [1] : c1,
          n,
        );
      case 3:
        final functions = cos.resolve(dict['Functions']);
        if (functions is! CosArray) return null;
        final parts = <PdfFunction>[];
        for (final item in functions.items) {
          final part = parse(cos, item);
          if (part == null) return null;
          parts.add(part);
        }
        return _StitchingFunction(
          x0,
          x1,
          parts,
          _numbers(cos, dict['Bounds']),
          _numbers(cos, dict['Encode']),
        );
      case 0:
        if (resolved is! CosStream) return null;
        final size = _numbers(cos, dict['Size']);
        final range = _numbers(cos, dict['Range']);
        final bits = _number(cos, dict['BitsPerSample'], 8).toInt();
        if (size.isEmpty || range.isEmpty) return null;
        final Uint8List data;
        try {
          data = cos.decodeStreamData(resolved);
        } on Exception {
          return null;
        }
        final encode = _numbers(cos, dict['Encode']);
        final decode = _numbers(cos, dict['Decode']);
        return _SampledFunction(
          domain.isNotEmpty ? domain : [x0, x1],
          [for (final s in size) s.toInt()],
          data,
          bits,
          range,
          encode,
          decode,
        );
      case 4:
        if (resolved is! CosStream) return null;
        final range = _numbers(cos, dict['Range']);
        if (range.length < 2) return null;
        final Uint8List source;
        try {
          source = cos.decodeStreamData(resolved);
        } on Exception {
          return null;
        }
        final program = _PostScriptFunction.parseProgram(
            String.fromCharCodes(source));
        if (program == null) return null;
        return _PostScriptFunction(
            x0, x1, program, range, domain.length >= 2 ? domain : [x0, x1]);
      default:
        return null;
    }
  }

  static double _number(CosDocument cos, CosObject? object, double fallback) {
    final v = cos.resolve(object);
    if (v is CosInteger) return v.value.toDouble();
    if (v is CosReal) return v.value;
    return fallback;
  }

  static List<double> _numbers(CosDocument cos, CosObject? object) {
    final v = cos.resolve(object);
    if (v is! CosArray) return const [];
    return [
      for (final item in v.items)
        switch (cos.resolve(item)) {
          CosInteger(:final value) => value.toDouble(),
          CosReal(:final value) => value,
          _ => 0.0,
        },
    ];
  }
}

class _CombinedFunction extends PdfFunction {
  const _CombinedFunction(this.parts);

  final List<PdfFunction> parts;

  @override
  List<double> evaluate(double x) =>
      [for (final part in parts) ...part.evaluate(x)];

  @override
  List<double> evaluateAt(List<double> inputs) =>
      [for (final part in parts) ...part.evaluateAt(inputs)];
}

class _ExponentialFunction extends PdfFunction {
  const _ExponentialFunction(this.x0, this.x1, this.c0, this.c1, this.n);

  final double x0, x1;
  final List<double> c0, c1;
  final double n;

  @override
  List<double> evaluate(double x) {
    final t = (x.clamp(x0, x1) - x0) / (x1 == x0 ? 1 : x1 - x0);
    final tn = math.pow(t, n).toDouble();
    final count = math.max(c0.length, c1.length);
    return [
      for (var i = 0; i < count; i++)
        _at(c0, i) + tn * (_at(c1, i) - _at(c0, i)),
    ];
  }

  static double _at(List<double> list, int i) =>
      i < list.length ? list[i] : 0;
}

class _StitchingFunction extends PdfFunction {
  const _StitchingFunction(
      this.x0, this.x1, this.functions, this.bounds, this.encode);

  final double x0, x1;
  final List<PdfFunction> functions;
  final List<double> bounds;
  final List<double> encode;

  @override
  List<double> evaluate(double x) {
    final clamped = x.clamp(x0, x1);
    var index = 0;
    while (index < bounds.length && clamped >= bounds[index]) {
      index++;
    }
    index = index.clamp(0, functions.length - 1);
    final low = index == 0 ? x0 : bounds[index - 1];
    final high = index < bounds.length ? bounds[index] : x1;
    final e0 = index * 2 < encode.length ? encode[index * 2] : 0.0;
    final e1 = index * 2 + 1 < encode.length ? encode[index * 2 + 1] : 1.0;
    final t = high == low ? e0 : e0 + (clamped - low) / (high - low) * (e1 - e0);
    return functions[index].evaluate(t);
  }
}

/// Type 0: a sampled function (§7.10.2). The sample grid has one axis per
/// input dimension (the first dimension varies fastest in the byte stream);
/// values in between grid points are multilinearly interpolated across the
/// 2^m surrounding samples. DeviceN/Separation tint transforms with more
/// than one colorant land here, so multi-input evaluation is required, not
/// just the single-input shading path.
class _SampledFunction extends PdfFunction {
  const _SampledFunction(this.domain, this.size, this.data, this.bitsPerSample,
      this.range, this.encode, this.decode);

  final List<double> domain;
  final List<int> size;
  final Uint8List data;
  final int bitsPerSample;
  final List<double> range;
  final List<double> encode;
  final List<double> decode;

  int get _inputs => size.length;
  int get _outputs => range.length ~/ 2;

  @override
  List<double> evaluate(double x) => evaluateAt([x]);

  @override
  List<double> evaluateAt(List<double> inputs) {
    final m = _inputs;
    final n = _outputs;
    if (m == 0 || n == 0) return const [0];

    // Encode each input into sample-grid coordinates, split into an integer
    // lower corner and a fractional weight per dimension.
    final lower = List<int>.filled(m, 0);
    final frac = List<double>.filled(m, 0);
    for (var i = 0; i < m; i++) {
      final sizeI = size[i];
      if (sizeI <= 0) return [for (var j = 0; j < n; j++) _decodeValue(0, j)];
      final d0 = i * 2 < domain.length ? domain[i * 2] : 0.0;
      final d1 = i * 2 + 1 < domain.length ? domain[i * 2 + 1] : 1.0;
      final e0 = i * 2 < encode.length ? encode[i * 2] : 0.0;
      final e1 = i * 2 + 1 < encode.length ? encode[i * 2 + 1] : sizeI - 1.0;
      final x = (i < inputs.length ? inputs[i] : d0)
          .clamp(math.min(d0, d1), math.max(d0, d1));
      final t = d1 == d0 ? 0.0 : (x - d0) / (d1 - d0);
      final position = (e0 + t * (e1 - e0)).clamp(0.0, sizeI - 1.0);
      lower[i] = position.floor();
      frac[i] = position - lower[i];
    }

    // Strides into the flat sample array; dimension 0 varies fastest.
    final stride = List<int>.filled(m, 1);
    for (var i = 1; i < m; i++) {
      stride[i] = stride[i - 1] * size[i - 1];
    }

    final max = math.max(1, (1 << bitsPerSample) - 1);
    final accum = List<double>.filled(n, 0);
    final corners = 1 << m;
    for (var corner = 0; corner < corners; corner++) {
      var weight = 1.0;
      var offset = 0;
      for (var i = 0; i < m; i++) {
        final upper = (corner >> i) & 1 == 1;
        weight *= upper ? frac[i] : 1 - frac[i];
        final coord = upper ? math.min(lower[i] + 1, size[i] - 1) : lower[i];
        offset += coord * stride[i];
      }
      if (weight == 0) continue;
      for (var j = 0; j < n; j++) {
        accum[j] += weight * _sampleAt(offset * n + j) / max;
      }
    }

    return [for (var j = 0; j < n; j++) _decodeValue(accum[j], j)];
  }

  double _decodeValue(double normalized, int output) {
    final src = decode.isNotEmpty ? decode : range;
    final d0 = output * 2 < src.length ? src[output * 2] : 0.0;
    final d1 = output * 2 + 1 < src.length ? src[output * 2 + 1] : 1.0;
    final value = d0 + normalized * (d1 - d0);
    final r0 = range[output * 2], r1 = range[output * 2 + 1];
    return value.clamp(math.min(r0, r1), math.max(r0, r1));
  }

  double _sampleAt(int sampleIndex) {
    final bitOffset = sampleIndex * bitsPerSample;
    var value = 0;
    for (var i = 0; i < bitsPerSample; i++) {
      final bit = bitOffset + i;
      final byte = bit >> 3;
      if (byte >= data.length) return 0;
      value = (value << 1) | ((data[byte] >> (7 - (bit & 7))) & 1);
    }
    return value.toDouble();
  }
}

/// Type 4: a PostScript calculator program (§7.10.5). The program is
/// parsed once into a token list; numbers and booleans share one operand
/// stack at evaluation time. Angles for sin/cos/atan are in degrees.
class _PostScriptFunction extends PdfFunction {
  const _PostScriptFunction(
      this.x0, this.x1, this.program, this.range, this.domain);

  final double x0, x1;

  /// Tokens: [double] literals, [String] operator names, and nested
  /// `List<Object>` procedure bodies for if/ifelse.
  final List<Object> program;
  final List<double> range;

  /// The full /Domain, pairs per input - multi-input shading functions
  /// clamp each input against its own pair.
  final List<double> domain;

  /// Parses the outermost `{ ... }` block. Returns null on malformed
  /// programs (unbalanced braces, missing body).
  static List<Object>? parseProgram(String source) {
    // % starts a comment that runs to the end of the line
    final stripped = source.replaceAll(RegExp(r'%[^\r\n]*'), ' ');
    final tokens = RegExp(r'[{}]|[^\s{}]+')
        .allMatches(stripped)
        .map((m) => m.group(0)!)
        .toList();
    var pos = 0;

    List<Object>? parseBlock() {
      if (pos >= tokens.length || tokens[pos] != '{') return null;
      pos++;
      final block = <Object>[];
      while (pos < tokens.length && tokens[pos] != '}') {
        if (tokens[pos] == '{') {
          final inner = parseBlock();
          if (inner == null) return null;
          block.add(inner);
        } else {
          final token = tokens[pos++];
          block.add(double.tryParse(token) ?? token);
        }
      }
      if (pos >= tokens.length) return null;
      pos++; // the closing brace
      return block;
    }

    while (pos < tokens.length && tokens[pos] != '{') {
      pos++;
    }
    return parseBlock();
  }

  @override
  List<double> evaluate(double x) => evaluateAt([x]);

  @override
  List<double> evaluateAt(List<double> inputs) {
    final outputs = range.length ~/ 2;
    final stack = <Object>[
      for (var i = 0; i < inputs.length; i++)
        domain.length >= (i + 1) * 2
            ? inputs[i].clamp(domain[i * 2], domain[i * 2 + 1])
            : inputs[i],
    ];
    try {
      _run(program, stack, 0);
    } catch (_) {
      // stack underflow / unknown operator: paint the bottom of the
      // range, not garbage
      return [for (var i = 0; i < outputs; i++) range[i * 2]];
    }
    final result = <double>[];
    for (var i = 0; i < outputs; i++) {
      final index = stack.length - outputs + i;
      final value = index >= 0 && index < stack.length ? stack[index] : 0.0;
      final number = switch (value) {
        bool b => b ? 1.0 : 0.0,
        num n => n.toDouble(),
        _ => 0.0,
      };
      result.add(number.clamp(range[i * 2], range[i * 2 + 1]));
    }
    return result;
  }

  static void _run(List<Object> block, List<Object> stack, int depth) {
    if (depth > 100) {
      throw const FormatException('calculator recursion too deep');
    }
    double popNum() {
      final v = stack.removeLast();
      if (v is num) return v.toDouble();
      throw const FormatException('expected a number');
    }

    int popInt() => popNum().truncate();

    bool popBool() {
      final v = stack.removeLast();
      if (v is bool) return v;
      throw const FormatException('expected a boolean');
    }

    /// `and or xor not` work on booleans logically and integers bitwise.
    Object popLogical() {
      final v = stack.removeLast();
      if (v is bool || v is num) return v;
      throw const FormatException('expected a boolean or integer');
    }

    for (final token in block) {
      if (token is double) {
        stack.add(token);
        continue;
      }
      if (token is List<Object>) {
        stack.add(token);
        continue;
      }
      switch (token as String) {
        case 'add':
          final b = popNum(), a = popNum();
          stack.add(a + b);
        case 'sub':
          final b = popNum(), a = popNum();
          stack.add(a - b);
        case 'mul':
          final b = popNum(), a = popNum();
          stack.add(a * b);
        case 'div':
          final b = popNum(), a = popNum();
          stack.add(b == 0 ? 0.0 : a / b);
        case 'idiv':
          final b = popInt(), a = popInt();
          stack.add(b == 0 ? 0.0 : (a ~/ b).toDouble());
        case 'mod':
          final b = popInt(), a = popInt();
          stack.add(b == 0 ? 0.0 : (a.remainder(b)).toDouble());
        case 'neg':
          stack.add(-popNum());
        case 'abs':
          stack.add(popNum().abs());
        case 'ceiling':
          stack.add(popNum().ceilToDouble());
        case 'floor':
          stack.add(popNum().floorToDouble());
        case 'round':
          stack.add(popNum().roundToDouble());
        case 'truncate':
          stack.add(popNum().truncateToDouble());
        case 'sqrt':
          stack.add(math.sqrt(math.max(0, popNum())));
        case 'sin':
          stack.add(math.sin(popNum() * math.pi / 180));
        case 'cos':
          stack.add(math.cos(popNum() * math.pi / 180));
        case 'atan':
          final den = popNum(), num = popNum();
          var degrees = math.atan2(num, den) * 180 / math.pi;
          if (degrees < 0) degrees += 360;
          stack.add(degrees);
        case 'exp':
          final exponent = popNum(), base = popNum();
          stack.add(math.pow(base, exponent).toDouble());
        case 'ln':
          stack.add(math.log(math.max(1e-300, popNum())));
        case 'log':
          stack.add(math.log(math.max(1e-300, popNum())) / math.ln10);
        case 'cvi':
          stack.add(popNum().truncateToDouble());
        case 'cvr':
          stack.add(popNum());
        case 'eq':
          final b = stack.removeLast(), a = stack.removeLast();
          stack.add(a == b);
        case 'ne':
          final b = stack.removeLast(), a = stack.removeLast();
          stack.add(a != b);
        case 'gt':
          final b = popNum(), a = popNum();
          stack.add(a > b);
        case 'ge':
          final b = popNum(), a = popNum();
          stack.add(a >= b);
        case 'lt':
          final b = popNum(), a = popNum();
          stack.add(a < b);
        case 'le':
          final b = popNum(), a = popNum();
          stack.add(a <= b);
        case 'and':
          final b = popLogical(), a = popLogical();
          stack.add(a is bool && b is bool
              ? a && b
              : ((a as num).truncate() & (b as num).truncate()).toDouble());
        case 'or':
          final b = popLogical(), a = popLogical();
          stack.add(a is bool && b is bool
              ? a || b
              : ((a as num).truncate() | (b as num).truncate()).toDouble());
        case 'xor':
          final b = popLogical(), a = popLogical();
          stack.add(a is bool && b is bool
              ? a != b
              : ((a as num).truncate() ^ (b as num).truncate()).toDouble());
        case 'not':
          final a = popLogical();
          stack.add(a is bool ? !a : (~(a as num).truncate()).toDouble());
        case 'bitshift':
          final shift = popInt(), value = popInt();
          stack.add((shift >= 0 ? value << shift : value >> -shift)
              .toDouble());
        case 'true':
          stack.add(true);
        case 'false':
          stack.add(false);
        case 'pop':
          stack.removeLast();
        case 'exch':
          final b = stack.removeLast(), a = stack.removeLast();
          stack
            ..add(b)
            ..add(a);
        case 'dup':
          stack.add(stack.last);
        case 'copy':
          final n = popInt();
          if (n < 0 || n > stack.length) {
            throw const FormatException('copy out of range');
          }
          stack.addAll(stack.sublist(stack.length - n));
        case 'index':
          final n = popInt();
          if (n < 0 || n >= stack.length) {
            throw const FormatException('index out of range');
          }
          stack.add(stack[stack.length - 1 - n]);
        case 'roll':
          final j = popInt(), n = popInt();
          if (n < 0 || n > stack.length) {
            throw const FormatException('roll out of range');
          }
          if (n > 0 && j != 0) {
            final window = stack.sublist(stack.length - n);
            stack.removeRange(stack.length - n, stack.length);
            final shift = ((j % n) + n) % n;
            stack
              ..addAll(window.sublist(n - shift))
              ..addAll(window.sublist(0, n - shift));
          }
        case 'if':
          final proc = stack.removeLast();
          final condition = popBool();
          if (proc is! List<Object>) {
            throw const FormatException('if needs a procedure');
          }
          if (condition) _run(proc, stack, depth + 1);
        case 'ifelse':
          final procElse = stack.removeLast();
          final procThen = stack.removeLast();
          final condition = popBool();
          if (procThen is! List<Object> || procElse is! List<Object>) {
            throw const FormatException('ifelse needs two procedures');
          }
          _run(condition ? procThen : procElse, stack, depth + 1);
        default:
          throw FormatException('unknown calculator operator: $token');
      }
    }
  }
}
