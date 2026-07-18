import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/oidc_token_cache.dart';

/// An unsigned JWT (`header.payload.`) carrying [claims].
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

void main() {
  group('oidcTokenExpiry', () {
    test('reads the exp claim as a UTC time', () {
      final exp = DateTime.utc(2026, 6, 10, 12);
      final token =
          _jwt({'email': 'dev@example.com', 'exp': exp.millisecondsSinceEpoch ~/ 1000});
      expect(oidcTokenExpiry(token), exp);
    });

    test('is null for a non-JWT or a token without exp', () {
      expect(oidcTokenExpiry('not-a-jwt'), isNull);
      expect(oidcTokenExpiry(_jwt({'email': 'x@y.z'})), isNull);
    });
  });
}
