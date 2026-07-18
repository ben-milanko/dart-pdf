import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/oidc_token_cache.dart';

/// An unsigned JWT (`header.payload.`) carrying [claims].
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

String _token(DateTime exp) =>
    _jwt({'email': 'dev@example.com', 'exp': exp.millisecondsSinceEpoch ~/ 1000});

void main() {
  group('oidcTokenExpiry', () {
    test('reads the exp claim as a UTC time', () {
      final exp = DateTime.utc(2026, 6, 10, 12);
      expect(oidcTokenExpiry(_token(exp)), exp);
    });

    test('is null for a non-JWT or a token without exp', () {
      expect(oidcTokenExpiry('not-a-jwt'), isNull);
      expect(oidcTokenExpiry(_jwt({'email': 'x@y.z'})), isNull);
    });
  });

  group('CachingOidcTokenProvider', () {
    Future<BuildContext> context(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
          Builder(builder: (c) => Directionality(
                textDirection: TextDirection.ltr,
                child: Builder(builder: (c) {
                  ctx = c;
                  return const SizedBox();
                }),
              )));
      return ctx;
    }

    testWidgets('reuses a still-valid login without signing in again',
        (tester) async {
      final ctx = await context(tester);
      final now = DateTime.utc(2026, 1, 1, 12);
      var calls = 0;
      final provider = CachingOidcTokenProvider(
        (_) async {
          calls++;
          return _token(now.add(const Duration(minutes: 30)));
        },
        now: () => now,
      );

      expect(await provider.call(ctx), isNotNull);
      expect(calls, 1);
      // second open: the valid token is reused, no browser sign-in
      await provider.call(ctx);
      expect(calls, 1);
      expect(provider.hasValidToken, isTrue);
    });

    testWidgets('signs in again once the cached token has expired',
        (tester) async {
      final ctx = await context(tester);
      final now = DateTime.utc(2026, 1, 1, 12);
      var calls = 0;
      final provider = CachingOidcTokenProvider(
        (_) async {
          calls++;
          // already past its expiry relative to `now`
          return _token(now.subtract(const Duration(minutes: 1)));
        },
        now: () => now,
      );

      await provider.call(ctx);
      expect(calls, 1);
      await provider.call(ctx);
      expect(calls, 2); // expired -> re-prompt
      expect(provider.hasValidToken, isFalse);
    });

    testWidgets('a cancelled sign-in caches nothing', (tester) async {
      final ctx = await context(tester);
      final provider = CachingOidcTokenProvider((_) async => null);
      expect(await provider.call(ctx), isNull);
      expect(provider.hasValidToken, isFalse);
    });

    testWidgets('the leeway forces a refresh just before expiry',
        (tester) async {
      final ctx = await context(tester);
      final now = DateTime.utc(2026, 1, 1, 12);
      var calls = 0;
      final provider = CachingOidcTokenProvider(
        (_) async {
          calls++;
          // expires within the 1-minute default leeway window
          return _token(now.add(const Duration(seconds: 30)));
        },
        now: () => now,
      );
      await provider.call(ctx);
      await provider.call(ctx);
      expect(calls, 2); // treated as (nearly) expired, re-prompted
    });
  });
}
