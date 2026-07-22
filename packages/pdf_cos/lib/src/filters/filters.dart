import 'dart:typed_data';

import '../exceptions.dart';
import '../objects.dart';
import '../parser.dart';
import '../perf/perf.dart';
import 'ascii.dart';
import 'ccitt.dart';
import 'flate.dart';
import 'lzw.dart';
import 'run_length.dart';

export 'ascii.dart';
export 'ccitt.dart';
export 'flate.dart';
export 'jbig2.dart';
export 'jpx.dart';
export 'lzw.dart';
export 'predictor.dart';
export 'run_length.dart';

/// Decodes one stage of a stream's /Filter chain.
abstract class CosFilter {
  const CosFilter();

  Uint8List decode(Uint8List data, CosDictionary? params);
}

const Map<String, CosFilter> _filters = {
  'FlateDecode': FlateFilter(),
  'Fl': FlateFilter(),
  'ASCIIHexDecode': AsciiHexFilter(),
  'AHx': AsciiHexFilter(),
  'ASCII85Decode': Ascii85Filter(),
  'A85': Ascii85Filter(),
  'LZWDecode': LzwFilter(),
  'LZW': LzwFilter(),
  'RunLengthDecode': RunLengthFilter(),
  'RL': RunLengthFilter(),
  'CCITTFaxDecode': CcittFaxFilter(),
  'CCF': CcittFaxFilter(),
  // JBIG2Decode is not decoded here. DCTDecode/JPXDecode stay encoded;
  // image decoding happens at render time (platform codecs).
};

/// Decodes a stream's payload by applying its /Filter chain in order.
///
/// [resolve] is used to chase indirect references inside /Filter,
/// /DecodeParms, and /Length entries.
///
/// [stopBeforeFilter] stops the chain just before the named filter and
/// returns the partially decoded bytes - used to undo e.g. FlateDecode
/// wrapped around a JPEG while leaving the JPEG for a platform codec.
Uint8List decodeStream(CosStream stream,
    {CosResolver? resolve, String? stopBeforeFilter}) {
  CosObject deref(CosObject? object) {
    var value = object ?? CosNull.instance;
    while (value is CosReference && resolve != null) {
      value = resolve(value);
    }
    return value;
  }

  final filterObject = deref(stream.dictionary['Filter']);
  final paramsObject =
      deref(stream.dictionary['DecodeParms'] ?? stream.dictionary['DP']);

  final names = <String>[];
  if (filterObject is CosName) names.add(filterObject.value);
  if (filterObject is CosArray) {
    for (final f in filterObject.items) {
      final r = deref(f);
      if (r is CosName) names.add(r.value);
    }
  }

  final params = <CosDictionary?>[];
  if (paramsObject is CosDictionary) params.add(paramsObject);
  if (paramsObject is CosArray) {
    for (final p in paramsObject.items) {
      final r = deref(p);
      params.add(r is CosDictionary ? r : null);
    }
  }

  var data = stream.rawBytes;
  for (var i = 0; i < names.length; i++) {
    if (names[i] == stopBeforeFilter) break;
    final filter = _filters[names[i]];
    if (filter == null) throw UnsupportedFilterException(names[i]);
    final t0 = PdfPerf.begin();
    data = filter.decode(data, i < params.length ? params[i] : null);
    if (PdfPerf.enabled) _recordFilterDecode(names[i], t0, data.length);
  }
  if (names.isNotEmpty) PdfPerf.add(PdfPerfCount.streamsDecoded);
  return data;
}

/// Attributes one filter stage's time + decoded bytes; only called while
/// [PdfPerf.enabled], so name mapping never runs on the normal path.
void _recordFilterDecode(String name, int t0, int decodedBytes) {
  final PdfPerfPhase phase;
  final PdfPerfCount bytes;
  switch (name) {
    case 'FlateDecode' || 'Fl':
      phase = PdfPerfPhase.flate;
      bytes = PdfPerfCount.bytesDecodedFlate;
    case 'LZWDecode' || 'LZW':
      phase = PdfPerfPhase.lzw;
      bytes = PdfPerfCount.bytesDecodedOther;
    case 'CCITTFaxDecode' || 'CCF':
      phase = PdfPerfPhase.ccitt;
      bytes = PdfPerfCount.bytesDecodedCcitt;
    case 'RunLengthDecode' || 'RL':
      phase = PdfPerfPhase.runLength;
      bytes = PdfPerfCount.bytesDecodedOther;
    default:
      phase = PdfPerfPhase.asciiFilter;
      bytes = PdfPerfCount.bytesDecodedOther;
  }
  PdfPerf.end(phase, t0);
  PdfPerf.add(bytes, decodedBytes);
}
