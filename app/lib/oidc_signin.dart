import 'package:flutter/widgets.dart';

import 'keyless_signing.dart';
// The loopback flow needs dart:io; the web build gets a stub returning null.
import 'oidc_signin_stub.dart'
    if (dart.library.io) 'oidc_signin_io.dart' as runner;

export 'oidc_pkce.dart' show SigstoreOidc;

/// An [OidcTokenProvider] backed by **Sigstore's public interactive OAuth
/// broker** (`oauth2.sigstore.dev`). It brokers Google / GitHub / Microsoft
/// sign-in and mints an OIDC token Fulcio's production CA accepts, using a
/// public client (`sigstore`) with PKCE and a loopback redirect - exactly how
/// cosign signs - so DartPDF needs no OAuth client registration of its own.
///
/// Wire it into [EditorScreen.oidcTokenProvider] to switch on the "Sign in with
/// your email (keyless)" option. Returns null if the user cancels or on the web
/// (a browser tab can't host the loopback redirect).
Future<String?> sigstoreOidcTokenProvider(BuildContext context) =>
    runner.runSigstoreSignIn();
