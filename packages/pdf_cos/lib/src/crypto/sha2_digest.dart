/// `sha2Digest(hash, data)`: a one-shot SHA-2 digest that picks the fast
/// implementation for the platform.
///
/// - VM/native: package:crypto for every hash; its SHA-384/512 run on real
///   64-bit integers.
/// - Web (dart2js/dart2wasm): SHA-384 and SHA-512 go through `sha512_js.dart`,
///   which is about 13x faster than package:crypto's 64-bit emulation there
///   (the same `dart.library.js_interop` condition package:crypto uses to pick
///   that emulation). Every other hash stays on package:crypto.
///
/// Callers keep passing package:crypto's own `Hash` objects: code elsewhere
/// (CMS digest OIDs, X.509 signing, the ECDSA nonce HMAC) switches on their
/// identity, so this dispatches on them rather than replacing them.
library;

export 'sha2_digest_io.dart'
    if (dart.library.js_interop) 'sha2_digest_web.dart';
