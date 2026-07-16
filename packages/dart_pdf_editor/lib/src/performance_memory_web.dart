import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Device RAM in GB from `navigator.deviceMemory`, or null where the browser
/// will not say.
///
/// Two traps this reads defensively around, both verified in Chrome 141:
///
/// - The property only exists in a **secure context** (and only in Chromium -
///   Firefox and Safari have not shipped the Device Memory API at all), so a
///   page served over plain http sees `undefined`. `package:web` types it as a
///   non-nullable `double`, which would hand back a bogus value rather than
///   null, so this probes for the property before reading it.
/// - The spec says the value is clamped to a power of two in [0.25, 8], but
///   Chrome now reports the real figure - a 16 GB host measures 16. Callers
///   must not read 8 as "the maximum".
double? get detectedPdfDeviceMemoryGb {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has('deviceMemory')) return null;
  final value = navigator.getProperty<JSAny?>('deviceMemory'.toJS);
  if (value == null || !value.isA<JSNumber>()) return null;
  final gb = (value as JSNumber).toDartDouble;
  return gb.isFinite && gb > 0 ? gb : null;
}
