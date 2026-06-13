import 'package:flutter/material.dart';

import 'app.dart';

/// On Windows and Linux the OS launches the app with the opened file as a
/// command-line argument; the Flutter runner forwards it here.
void main(List<String> args) => runApp(DartPdfEditorApp(launchArgs: args));
