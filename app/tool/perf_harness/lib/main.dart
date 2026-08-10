// This workspace package deliberately has a minimal dependency/plugin graph.
// The production app has OCR, scanner, file, camera, and desktop plugins that
// are irrelevant to rendering benchmarks.
import 'harness.dart' as harness;

void main() => harness.main();
