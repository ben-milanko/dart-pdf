import 'dart:io';

import 'package:flutter/services.dart';

import 'memory_snapshot.dart';

const _memoryChannel = MethodChannel('dev.milanko.dartpdf/memory');

Future<AppMemorySnapshot?> readAppMemorySnapshot() async {
  try {
    final raw =
        await _memoryChannel.invokeMapMethod<String, Object?>('snapshot');
    return AppMemorySnapshot(
      physicalBytes: _positiveInt(raw?['physicalBytes']),
      availableBytes: _positiveInt(raw?['availableBytes']),
      processRssBytes: ProcessInfo.currentRss,
      processLimitBytes: _positiveInt(raw?['processLimitBytes']),
      lowMemory: raw?['lowMemory'] == true,
    );
  } on MissingPluginException {
    return AppMemorySnapshot(processRssBytes: ProcessInfo.currentRss);
  } on PlatformException {
    return AppMemorySnapshot(processRssBytes: ProcessInfo.currentRss);
  }
}

int? _positiveInt(Object? value) {
  final number = value is int
      ? value
      : value is num
          ? value.toInt()
          : null;
  return number != null && number > 0 ? number : null;
}
