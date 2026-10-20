import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

/// Resolves the example app's localizations for [context], falling back to
/// English when no [AppLocalizations.delegate] is registered.
AppLocalizations appL10n(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsEn();
