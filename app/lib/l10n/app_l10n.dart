import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_en.dart';

/// Resolves the app's localizations for [context], falling back to English
/// when no [AppLocalizations.delegate] is registered - so widgets work out
/// of the box (and widget tests that pump bare screens keep finding English
/// text) without every test having to register delegates.
AppLocalizations appL10n(BuildContext context) =>
    Localizations.of<AppLocalizations>(context, AppLocalizations) ??
    AppLocalizationsEn();
