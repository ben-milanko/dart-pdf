import 'package:flutter/widgets.dart';

/// Pause between pages when the app is no longer visible. A transient loss of
/// focus (inactive) still permits foreground work, such as a desktop dialog.
bool get ocrShouldPause => switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached =>
        true,
      _ => false,
    };
