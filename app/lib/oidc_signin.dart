import 'package:flutter/widgets.dart';

import 'oidc_pkce.dart';
import 'oidc_token_cache.dart' show oidcTokenExpiry;
// The loopback flow needs dart:io; the web build gets a stub returning null.
import 'oidc_signin_stub.dart'
    if (dart.library.io) 'oidc_signin_io.dart' as runner;

export 'oidc_pkce.dart' show SigstoreOidc, OidcTokens;

/// Manages a **Sigstore** keyless login (via the public OAuth broker at
/// `oauth2.sigstore.dev`, exactly how cosign signs). It caches the OIDC
/// `id_token` in memory and reuses it while valid; when it expires it silently
/// mints a fresh one from the refresh token (no browser); only with no usable
/// token or refresh token does it launch the interactive browser sign-in.
///
/// The instance is callable, so it drops straight into
/// [EditorScreen.oidcTokenProvider]. [signIn], [refresh] and [now] are
/// injectable for tests.
class SigstoreSignInManager {
  SigstoreSignInManager({
    Future<OidcTokens?> Function()? signIn,
    Future<OidcTokens?> Function(String refreshToken)? refresh,
    Duration leeway = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _signIn = signIn ?? runner.runSigstoreSignIn,
        _refresh = refresh ?? runner.refreshSigstoreTokens,
        _leeway = leeway,
        _now = now ?? DateTime.now;

  final Future<OidcTokens?> Function() _signIn;
  final Future<OidcTokens?> Function(String) _refresh;
  final Duration _leeway;
  final DateTime Function() _now;

  String? _idToken;
  String? _refreshToken;

  /// Whether a token can be produced without an interactive browser sign-in:
  /// the cached id_token is still valid, or a refresh token is held.
  bool get hasValidToken => _idValid() || _refreshToken != null;

  /// Returns a valid `id_token`, reusing/refreshing silently where possible
  /// and signing in interactively otherwise. Null if sign-in was cancelled.
  Future<String?> call([BuildContext? context]) async {
    final silent = await silentToken();
    if (silent != null) return silent;
    _store(await _signIn());
    return _idToken;
  }

  /// A valid `id_token` obtained **without any browser interaction** - the
  /// cached one while it's valid, or a fresh one minted from the refresh
  /// token. Null when getting one would require an interactive sign-in. Used
  /// to pre-select the keyless identity when the dialog opens without ever
  /// popping the browser as a side effect.
  Future<String?> silentToken() async {
    if (_idValid()) return _idToken;
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      final refreshed = await _refresh(refreshToken);
      if (refreshed != null && refreshed.idToken.isNotEmpty) {
        _store(refreshed);
        if (_idValid()) return _idToken;
      }
      _refreshToken = null; // stale refresh token; an interactive sign-in
    }
    return null;
  }

  /// Forgets the cached login (e.g. on explicit sign-out).
  void clear() {
    _idToken = null;
    _refreshToken = null;
  }

  void _store(OidcTokens? tokens) {
    if (tokens == null || tokens.idToken.isEmpty) {
      _idToken = null;
      return;
    }
    _idToken = tokens.idToken;
    if (tokens.refreshToken != null) _refreshToken = tokens.refreshToken;
  }

  bool _idValid() {
    final token = _idToken;
    if (token == null) return false;
    final exp = oidcTokenExpiry(token);
    return exp != null && exp.subtract(_leeway).isAfter(_now().toUtc());
  }
}
