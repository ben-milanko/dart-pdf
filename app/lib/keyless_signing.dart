import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// Obtains an OpenID Connect `id_token` (a JWT) proving the signer's email,
/// via whatever OAuth 2.0 flow the deployment configures - a Google, GitHub,
/// or Microsoft sign-in through the browser. Returns null if the user cancels.
///
/// DartPDF ships no default OAuth client (client registration is
/// deployment-specific), so keyless signing is only offered when the host
/// wires one of these in. It is the single seam that turns the keyless option
/// on; every other part of the flow (Fulcio, the timestamp) is implemented
/// here.
typedef OidcTokenProvider = Future<String?> Function(BuildContext context);

/// POSTs a Fulcio v2 `signingCert` request over HTTPS and returns the JSON
/// response body. The default production [PdfFulcioTransport]; [endpoint] and
/// [client] are injectable so tests can stand in an in-process Fulcio.
Future<Uint8List> fulcioHttpTransport(
  Uint8List requestBody, {
  String endpoint = PdfFulcioAuthority.sigstore,
  http.Client? client,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c.post(
      Uri.parse(endpoint),
      headers: const {'Content-Type': 'application/json'},
      body: requestBody,
    );
    if (response.statusCode != 200) {
      throw http.ClientException(
          'Fulcio returned HTTP ${response.statusCode}', Uri.parse(endpoint));
    }
    return response.bodyBytes;
  } finally {
    if (owned) c.close();
  }
}

/// A default RFC 3161 [PdfTimestampClient] backed by a free public TSA
/// (DigiCert by default). Keyless signing requires a timestamp because the
/// Fulcio certificate expires within minutes; this supplies it.
Future<Uint8List> defaultTimestampClient(
  Uint8List request, {
  String endpoint = PdfDefaultTimestampAuthority.digicert,
  http.Client? client,
}) async {
  final owned = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c.post(
      Uri.parse(endpoint),
      headers: const {'Content-Type': 'application/timestamp-query'},
      body: request,
    );
    if (response.statusCode != 200) {
      throw http.ClientException(
          'TSA returned HTTP ${response.statusCode}', Uri.parse(endpoint));
    }
    return timeStampTokenFromResponse(response.bodyBytes);
  } finally {
    if (owned) c.close();
  }
}

/// Mints a keyless [PdfSigningIdentity]: runs [tokenProvider] to get an OIDC
/// token, then exchanges it with Fulcio through [transport] (the production
/// HTTPS transport by default) for a short-lived certificate. Returns null if
/// the user cancels sign-in.
///
/// The resulting identity's certificate is valid for only minutes - sign
/// immediately with a timestamp (the dialog routes it to PAdES B-T).
Future<PdfSigningIdentity?> keylessSigningIdentity(
  BuildContext context, {
  required OidcTokenProvider tokenProvider,
  PdfFulcioTransport? transport,
}) async {
  final token = await tokenProvider(context);
  if (token == null || token.isEmpty) return null;
  return fulcioSigningIdentity(
    oidcToken: token,
    transport: transport ?? fulcioHttpTransport,
  );
}
