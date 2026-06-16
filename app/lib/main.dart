import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart' deferred as app;
import 'app_info.dart' deferred as app_info;

/// On Windows and Linux the OS launches the app with the opened file as a
/// command-line argument; the Flutter runner forwards it here.
Future<void> main(List<String> args) async {
  // PackageInfo (loaded below) needs the binding; ensure it before awaiting.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(_DeferredApp(launchArgs: args));

  // Do not block first paint or the initial loading unit on package metadata.
  // The About box refreshes from this best-effort value after the shell is
  // already on screen.
  unawaited(_loadAppInfo());
}

Future<void> _loadAppInfo() async {
  try {
    await app_info.loadLibrary();
    await app_info.AppInfo.load();
  } catch (_) {
    // Keep the fallback; the About box is non-critical.
  }
}

class _DeferredApp extends StatefulWidget {
  const _DeferredApp({required this.launchArgs});

  final List<String> launchArgs;

  @override
  State<_DeferredApp> createState() => _DeferredAppState();
}

class _DeferredAppState extends State<_DeferredApp> {
  Object? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await app.loadLibrary();
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded) {
      return app.DartPdfEditorApp(launchArgs: widget.launchArgs);
    }
    return MaterialApp(
      title: 'DartPDF',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const _StartupIndicator()
              : _StartupError(error: _error!),
        ),
      ),
    );
  }
}

class _StartupIndicator extends StatelessWidget {
  const _StartupIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.picture_as_pdf_outlined, size: 56, color: colors.primary),
        const SizedBox(height: 24),
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading DartPDF…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.error),
          const SizedBox(height: 16),
          Text(
            'DartPDF failed to load',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '$error',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
