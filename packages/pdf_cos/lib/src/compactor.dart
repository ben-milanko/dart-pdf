import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'builder.dart';
import 'document.dart';
import 'objects.dart';

/// The outcome of a [CosCompactor] run: the rewritten bytes plus a small
/// before/after accounting so hosts can report "saved N%".
class CosCompactionResult {
  const CosCompactionResult({
    required this.bytes,
    required this.bytesBefore,
    required this.objectsBefore,
    required this.objectsAfter,
    required this.streamsDeflated,
  });

  /// The compacted file.
  final Uint8List bytes;

  /// Length of the source document's bytes.
  final int bytesBefore;

  /// Number of object slots the source cross-reference declared.
  final int objectsBefore;

  /// Number of live objects written to the compacted file (excludes the
  /// object streams and cross-reference stream the writer synthesises).
  final int objectsAfter;

  /// Number of previously uncompressed streams re-deflated by this pass.
  final int streamsDeflated;

  int get bytesAfter => bytes.length;

  /// Fraction of the original size removed, in `[0, 1)`; 0 when the source
  /// was empty.
  double get ratio =>
      bytesBefore == 0 ? 0 : (bytesBefore - bytesAfter) / bytesBefore;
}

/// Rewrites a [CosDocument] into a fresh, compacted PDF - the lossless
/// structural pass of the file-size optimiser (#368).
///
/// The pass is lossless for rendered output: only objects reachable from the
/// catalog (and `/Info`) survive, so the dead copies that incremental updates
/// accumulate across revisions are dropped; the non-stream objects are packed
/// into compressed object streams and addressed by a PDF 1.5 xref stream; and
/// streams that were stored with no compression filter are re-deflated (kept
/// only when that actually shrinks them). Every stream's decoded content is
/// preserved bit-for-bit - already-encoded payloads pass through verbatim.
///
/// The output is a from-scratch file with no `/Prev` chain, so it does **not**
/// preserve prior-revision history and it invalidates any existing digital
/// signature - that is inherent to rewriting a file smaller, and is why this
/// is an explicit action rather than part of a normal save.
///
/// Encrypted documents are refused: a faithful rewrite would have to either
/// re-encrypt (out of scope here) or silently drop the encryption, so the
/// caller is told to decrypt first.
class CosCompactor {
  CosCompactor(this.document, {this.deflateLevel = 9});

  final CosDocument document;

  /// zlib level (0-9) for the object streams, xref stream, and re-deflated
  /// payloads. 9 favours size over speed, which suits an explicit "reduce
  /// file size" action.
  final int deflateLevel;

  CosCompactionResult run() {
    if (document.isEncrypted) {
      throw ArgumentError(
          'cannot compact an encrypted document; decrypt it first');
    }
    final rootRef = document.trailer['Root'];
    if (rootRef is! CosReference) {
      throw StateError('document has no indirect /Root catalog to compact');
    }

    final builder = CosDocumentBuilder();
    final copier = _GraphCopier(document, builder, deflateLevel);

    final rootDest = copier.copyValue(rootRef) as CosReference;
    CosReference? infoDest;
    final infoRef = document.trailer['Info'];
    if (infoRef is CosReference && document.resolve(infoRef) is CosDictionary) {
      infoDest = copier.copyValue(infoRef) as CosReference;
    }

    final bytes = builder.build(
      root: rootDest,
      info: infoDest,
      version: '1.7',
      objectStreams: true,
      deflateLevel: deflateLevel,
    );

    return CosCompactionResult(
      bytes: bytes,
      bytesBefore: document.bytes.length,
      objectsBefore: document.objectNumbers.length,
      objectsAfter: copier.objectsWritten,
      streamsDeflated: copier.streamsDeflated,
    );
  }
}

/// Deep-copies the whole reachable object graph of a document into a
/// [CosDocumentBuilder], remapping references and breaking cycles by
/// registering each destination object before its contents are filled in.
///
/// Unlike page extraction there is no copy boundary - every reference is
/// followed - so a dead object simply never gets visited and is dropped.
class _GraphCopier {
  _GraphCopier(this.document, this._builder, this._deflateLevel);

  final CosDocument document;
  final CosDocumentBuilder _builder;
  final int _deflateLevel;
  final Map<CosReference, CosObject> _mapped = {};

  int objectsWritten = 0;
  int streamsDeflated = 0;

  /// Copies any value. Direct containers copy structurally; references
  /// allocate (once) in the destination and remap.
  CosObject copyValue(CosObject value) {
    switch (value) {
      case CosReference ref:
        return _mapped[ref] ??= _copyTarget(ref);
      case CosStream stream: // direct streams are illegal, but tolerate
        return _copyStream(null, stream);
      case CosDictionary dict:
        final out = CosDictionary();
        dict.entries.forEach((key, item) => out[key] = copyValue(item));
        return out;
      case CosArray array:
        return CosArray([for (final item in array.items) copyValue(item)]);
      case CosString string:
        return CosString(Uint8List.fromList(string.bytes), isHex: string.isHex);
      default:
        return value; // names, numbers, booleans, null are immutable
    }
  }

  CosObject _copyTarget(CosReference ref) {
    final target = document.resolve(ref);
    switch (target) {
      case CosStream stream:
        return _copyStream(ref, stream);
      case CosDictionary dict:
        final out = CosDictionary();
        final outRef = _builder.add(out);
        _mapped[ref] = outRef;
        objectsWritten++;
        dict.entries.forEach((key, item) => out[key] = copyValue(item));
        return outRef;
      case CosNull():
        return CosNull.instance;
      default:
        // an indirectly referenced scalar - inline it at the use site
        return copyValue(target);
    }
  }

  /// Copies a stream. An already-encoded payload passes through verbatim; a
  /// stream stored with no compression filter is re-deflated when that
  /// shrinks it (kept lossless - `FlateDecode` of the result reproduces the
  /// stored bytes exactly).
  CosObject _copyStream(CosReference? ref, CosStream stream) {
    final srcDict = stream.dictionary;
    var payload = stream.rawBytes;
    var addFlate = false;
    if (_isUnfiltered(srcDict)) {
      final deflated = Uint8List.fromList(
          const ZLibEncoder().encodeBytes(payload, level: _deflateLevel));
      if (deflated.length < payload.length) {
        payload = deflated;
        addFlate = true;
        streamsDeflated++;
      }
    }

    final out = CosStream(CosDictionary(), payload);
    final outRef = ref != null ? (_mapped[ref] = _builder.add(out)) : null;
    if (ref != null) objectsWritten++;
    srcDict.entries.forEach((key, item) {
      if (key == 'Length') return; // recomputed below
      out.dictionary[key] = copyValue(item);
    });
    if (addFlate) out.dictionary['Filter'] = const CosName('FlateDecode');
    out.dictionary['Length'] = CosInteger(payload.length);
    return outRef ?? out;
  }

  /// A stream is unfiltered when it declares no `/Filter` (or an empty array).
  bool _isUnfiltered(CosDictionary dict) {
    final filter = document.resolve(dict['Filter']);
    return switch (filter) {
      CosName() => false,
      CosArray(:final items) => items.isEmpty,
      _ => true,
    };
  }
}
