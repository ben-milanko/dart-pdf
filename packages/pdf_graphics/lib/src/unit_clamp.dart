/// Clamps for the per-pixel and per-colour loops (ICC pipelines, image
/// colour conversion). Not exported.
///
/// `num.clamp` is the obvious spelling and the wrong one in a hot loop.
/// dart2js compiles it to three `compareTo` calls, each with its own -0.0/NaN
/// handling, and the VM's `_Double.clamp` does the same work boxed. Its static
/// type is also `num` for int bounds, and dart2js carries that into any typed
/// list the result is stored in, turning every later store into that list
/// into a checked, non-inlined `$indexSet`.
///
/// These plain comparisons return exactly what `clamp` returns for every
/// input, on the VM and on the web: NaN maps to the upper bound (`compareTo`
/// orders NaN above everything) and -0.0 maps to +0.0 (it orders below 0.0).
library;

/// `v.clamp(0.0, 1.0)`.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
double clampUnit(double v) => v <= 0.0 ? 0.0 : (v < 1.0 ? v : 1.0);

/// `v.clamp(0, 255)`, typed `int`.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
int clampByte(int v) => v <= 0 ? 0 : (v < 255 ? v : 255);

/// `v.clamp(lo, hi)` for `lo <= hi`, typed `int`.
///
/// Unlike `clamp` it does not throw when `lo > hi`; it answers [lo]. The only
/// caller that can see that is an ICC CLUT with fewer than one grid point,
/// whose empty table then throws a [RangeError] on the read that follows, so
/// the malformed profile still fails the same way.
@pragma('vm:prefer-inline')
@pragma('dart2js:prefer-inline')
int clampIndex(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
