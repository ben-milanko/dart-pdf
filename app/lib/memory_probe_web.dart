import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'memory_snapshot.dart';

Future<AppMemorySnapshot?> readAppMemorySnapshot() async {
  final navigator = web.window.navigator as JSObject;
  final performance = web.window.performance as JSObject;

  final deviceGb = _numberProperty(navigator, 'deviceMemory');
  final memory = performance.getProperty<JSAny?>('memory'.toJS);
  final memoryObject =
      memory != null && memory.isA<JSObject>() ? memory as JSObject : null;
  final heapLimit = _numberProperty(memoryObject, 'jsHeapSizeLimit');
  final heapUsed = _numberProperty(memoryObject, 'usedJSHeapSize');

  final physical = deviceGb == null ? null : (deviceGb * (1 << 30)).round();
  return AppMemorySnapshot(
    physicalBytes: physical,
    processRssBytes: heapUsed?.round(),
    processLimitBytes: heapLimit?.round(),
  );
}

double? _numberProperty(JSObject? object, String name) {
  if (object == null || !object.has(name)) return null;
  final value = object.getProperty<JSAny?>(name.toJS);
  if (value == null || !value.isA<JSNumber>()) return null;
  final number = (value as JSNumber).toDartDouble;
  return number.isFinite && number > 0 ? number : null;
}
