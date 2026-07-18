import 'package:http/http.dart' as http;

/// Web fallback: the interactive loopback OAuth flow needs a local HTTP server
/// to catch the redirect, which a browser tab can't provide, so keyless
/// sign-in is unavailable on the web. Returns null.
Future<String?> runSigstoreSignIn({
  http.Client? client,
  Future<bool> Function(Uri url)? launch,
}) async =>
    null;
