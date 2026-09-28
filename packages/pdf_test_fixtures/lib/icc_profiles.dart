/// Browser-safe ICC profile fixtures.
///
/// Import this focused library from tests that also run under dart2js
/// instead of the package umbrella, which also exports intentionally VM-only
/// 64-bit fixture generators.
library;

export 'src/icc_profiles.dart';
