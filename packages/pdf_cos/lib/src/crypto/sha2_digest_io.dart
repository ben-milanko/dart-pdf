import 'package:crypto/crypto.dart' as crypto;

/// [hash]'s digest of [data], through package:crypto (see `sha2_digest.dart`).
List<int> sha2Digest(crypto.Hash hash, List<int> data) =>
    hash.convert(data).bytes;
