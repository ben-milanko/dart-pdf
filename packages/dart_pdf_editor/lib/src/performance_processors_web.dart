import 'package:web/web.dart' as web;

int get detectedPdfLogicalProcessors =>
    web.window.navigator.hardwareConcurrency;
