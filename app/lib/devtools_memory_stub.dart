/// Web build: process RSS is not observable from a browser tab.
int? currentRssBytes() => null;

/// Web build: no high-water mark either.
int? maxRssBytes() => null;

/// Web build: flutter_test implies the VM, so never.
bool inFlutterTest() => false;
