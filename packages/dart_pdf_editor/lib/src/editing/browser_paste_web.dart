import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

typedef BrowserPaste = ({Uint8List? image, String? text});

/// The viewer's paste action leaves ⌘V/Ctrl+V unconsumed here, so the engine
/// does not preventDefault it and the browser goes on to fire its paste event.
bool get pasteKeyReachesBrowser => true;

/// How long a keyboard paste waits for its paste event before falling back,
/// and how long after the key press one may still start.
const _eventWait = Duration(milliseconds: 300);
const _pressFresh = Duration(seconds: 1);

var _watching = false;

/// Keyboard pastes seen, and when the latest was pressed.
var _presses = 0;
DateTime? _pressedAt;

/// The paste the latest read served (by key press), shared by the reads that
/// follow it.
Future<BrowserPaste?>? _served;
var _servedPress = -1;

/// The read waiting on the paste event, if any. Only a waiting read claims
/// the event, so pastes into text fields and other hosts' handlers are left
/// alone.
Completer<BrowserPaste?>? _awaiting;

void ensureWatching() {
  if (_watching) return;
  _watching = true;
  // HardwareKeyboard handlers run before the focus tree's shortcuts, so the
  // press is counted before the paste action reads.
  HardwareKeyboard.instance.addHandler(_onKey);
  web.document.addEventListener('paste', _onPaste.toJS);
}

bool _onKey(KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyV) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed || keyboard.isControlPressed) {
      _presses++;
      _pressedAt = DateTime.now();
    }
  }
  return false;
}

Future<BrowserPaste?> browserPaste() {
  ensureWatching();
  final served = _served;
  if (served != null && _servedPress == _presses) {
    return served;
  }
  final pressedAt = _pressedAt;
  if (pressedAt == null || DateTime.now().difference(pressedAt) > _pressFresh) {
    return Future.value(null);
  }
  final awaiting = Completer<BrowserPaste?>();
  _awaiting = awaiting;
  final paste = awaiting.future.timeout(_eventWait, onTimeout: () {
    if (identical(_awaiting, awaiting)) _awaiting = null;
    return null;
  });
  _served = paste;
  _servedPress = _presses;
  return paste;
}

void _onPaste(web.ClipboardEvent event) {
  final awaiting = _awaiting;
  final data = event.clipboardData;
  if (awaiting == null || data == null) return;
  _awaiting = null;
  event.preventDefault();
  final text = data.getData('text/plain');
  web.File? image;
  final files = data.files;
  for (var i = 0; i < files.length; i++) {
    final file = files.item(i);
    if (file != null &&
        (file.type == 'image/png' || file.type == 'image/jpeg')) {
      image = file;
      break;
    }
  }
  awaiting.complete(_read(image, text.isEmpty ? null : text));
}

Future<BrowserPaste> _read(web.File? file, String? text) async {
  Uint8List? image;
  if (file != null) {
    try {
      image = (await file.arrayBuffer().toDart).toDart.asUint8List();
    } catch (_) {
      // An unreadable file pastes the text alone.
    }
  }
  return (image: image, text: text);
}
