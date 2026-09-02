import 'dart:io';
import 'dart:typed_data';

/// Builds a deterministic page with overlapping advanced-blend strokes.
///
/// The strokes are geometrically separate but have overlapping conservative
/// bounds. That forces twelve ordered destination-sampling passes and makes
/// advanced-blend performance large enough to distinguish from runner noise.
Uint8List buildAdvancedBlendStressPdf() {
  final content = StringBuffer()
    ..writeln('q')
    ..writeln('0.160 0.350 0.620 rg')
    ..writeln('0 0 612 792 re f')
    ..writeln('/Darken gs')
    ..writeln('2.5 w');
  for (var index = 0; index < 12; index++) {
    final red = 0.12 + index * 0.035;
    final y1 = 105 + index * 9;
    final y2 = 465 + index * 9;
    content
      ..writeln('${red.toStringAsFixed(3)} 0.240 0.720 RG')
      ..writeln('55 $y1 m 557 $y2 l S');
  }
  content.writeln('Q');

  final stream = content.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /ExtGState << '
        '/Darken << /Type /ExtGState /BM /Darken >> >> >> >>',
    '<< /Length ${stream.length} >>\nstream\n$stream' 'endstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
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
  return Uint8List.fromList(buffer.toString().codeUnits);
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: dart advanced_blend_stress_fixture.dart OUTPUT');
    exitCode = 64;
    return;
  }
  File(arguments.single).writeAsBytesSync(buildAdvancedBlendStressPdf());
}
