import 'package:crypto/crypto.dart' as crypto;

import 'sha512_js.dart';

/// [hash]'s digest of [data]: SHA-384/512 on 32-bit halves, anything else
/// through package:crypto (see `sha2_digest.dart`).
List<int> sha2Digest(crypto.Hash hash, List<int> data) {
  if (identical(hash, crypto.sha512)) return sha512Js(data);
  if (identical(hash, crypto.sha384)) return sha384Js(data);
  return hash.convert(data).bytes;
}
