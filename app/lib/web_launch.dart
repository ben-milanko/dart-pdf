// Drains PDFs handed to an installed web app through the File Handling API
// (the browser's launch queue). Resolves to a no-op off the web.
export 'web_launch_stub.dart'
    if (dart.library.js_interop) 'web_launch_web.dart';
