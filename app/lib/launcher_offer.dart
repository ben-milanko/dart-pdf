import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_l10n.dart';
import 'launcher_registration.dart';

/// Nonmodal startup offer. The child stays mounted while detection/setup runs.
class LauncherOffer extends StatefulWidget {
  const LauncherOffer(
      {super.key,
      required this.child,
      this.enabled = true,
      this.status = launcherRegistrationStatus,
      this.register = registerLauncher,
      this.saveSuppression});
  final Widget child;
  final bool enabled;
  final Future<String> Function() status;
  final Future<void> Function() register;
  final Future<bool> Function()? saveSuppression;
  static const suppressionKey = 'dartpdf.launcherOffer.suppressed';

  @override
  State<LauncherOffer> createState() => _LauncherOfferState();
}

class _LauncherOfferState extends State<LauncherOffer> {
  bool _visible = false;
  bool _busy = false;
  bool _error = false;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _check();
  }

  Future<void> _check() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (_prefs!.getBool(LauncherOffer.suppressionKey) == true) return;
      final status = await widget.status();
      if (mounted && status == 'missing') setState(() => _visible = true);
    } catch (_) {
      // Startup must remain usable when storage or the platform probe fails.
    }
  }

  Future<void> _suppress() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final saved = await (widget.saveSuppression?.call() ??
          _prefs!.setBool(LauncherOffer.suppressionKey, true));
      if (!saved) throw StateError('Preference not saved');
      if (mounted) setState(() => _visible = false);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      await widget.register();
      if (await widget.status() != 'registered') {
        throw StateError('Not registered');
      }
      if (mounted) setState(() => _visible = false);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final l = appL10n(context);
    return Column(children: [
      if (_visible)
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.launcherOfferTitle,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(_error ? l.launcherOfferError : l.launcherOfferBody),
                      Wrap(spacing: 8, children: [
                        TextButton(
                            onPressed: _busy ? null : _register,
                            child: Text(l.launcherOfferRegister)),
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _visible = false),
                            child: Text(l.launcherOfferLater)),
                        TextButton(
                            onPressed: _busy ? null : _suppress,
                            child: Text(l.launcherOfferNever)),
                      ]),
                      if (_busy) const LinearProgressIndicator(),
                    ]),
              )),
        ),
      Expanded(child: widget.child),
    ]);
  }
}
