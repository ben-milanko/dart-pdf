// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get add => 'Ajouter';

  @override
  String get apply => 'Appliquer';

  @override
  String get cancel => 'Annuler';

  @override
  String get clear => 'Effacer';

  @override
  String get close => 'Fermer';

  @override
  String get copy => 'Copier';

  @override
  String get cut => 'Couper';

  @override
  String get delete => 'Supprimer';

  @override
  String get done => 'Terminé';

  @override
  String get edit => 'Modifier';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript transmis à l\'application : $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Lien : $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Action nommée : $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Type d\'action non pris en charge : $type';
  }

  @override
  String get exAnnotationTextCopied => 'Texte de l\'annotation copié';

  @override
  String get exApiKeyHelper => 'Envoyé sous forme Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Clé API / jeton (facultatif)';

  @override
  String get exAppMenuTooltip => 'Menu DartPDF';

  @override
  String get exClearRecentFiles => 'Effacer les fichiers récents';

  @override
  String get exCloseTab => 'Fermer l\'onglet';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Comparer : $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Comparer avec un autre PDF…';

  @override
  String get exCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get exCopySelectedText => 'Copier le texte sélectionné (⌘C)';

  @override
  String get exCopyText => 'Copier le texte';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Impossible d\'ouvrir $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Impossible d\'ouvrir $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Impossible d\'ouvrir $uri\n$error\n\nSur le web, il s\'agit souvent d\'une restriction CORS : le serveur doit envoyer Access-Control-Allow-Origin et exposer les en-têtes Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Impossible de rouvrir $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Impossible de rouvrir $title - sa copie enregistrée n\'est plus disponible.';
  }

  @override
  String get exDemoNoteHint =>
      'Saisissez ici - cette zone de texte flotte au-dessus de la page';

  @override
  String get exDiagnosticsCopied => 'Diagnostics copiés dans le presse-papiers';

  @override
  String exDownloaded(String name) {
    return '$name téléchargé';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name téléchargé - recollez-le dans le PDF avec Ctrl+V';
  }

  @override
  String get exExport => 'Exporter';

  @override
  String exExportFailed(String error) {
    return 'Échec de l\'exportation : $error';
  }

  @override
  String get exExportPageImageMenu => 'Exporter la page comme image…';

  @override
  String get exExportPageImageTitle => 'Exporter la page comme image';

  @override
  String get exFeatureShowcase => 'Présentation des fonctionnalités';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Masquer';

  @override
  String get exHorizontalLayout => 'Disposition horizontale des pages';

  @override
  String get exHowToSetupOcr => 'Comment configurer un serveur OCR';

  @override
  String get exModelName => 'Nom du modèle';

  @override
  String get exNoMessage => 'Aucun message';

  @override
  String get exNoRecentFiles => 'Aucun fichier récent';

  @override
  String exNotAValidUrl(String url) {
    return 'URL non valide :\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'L\'OCR a ajouté $count zones de texte - le texte de la page est désormais sélectionnable',
      one:
          'L\'OCR a ajouté 1 zone de texte - le texte de la page est désormais sélectionnable',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Ajoute une couche de texte sélectionnable et interrogeable sur les pages numérisées à l\'aide d\'un modèle OCR vision-langage que vous hébergez (dots.ocr sur vLLM, ou tout point de terminaison OCR compatible OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'Échec de l\'OCR : $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Ouvrir';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Ouvrez un document avant de lancer l\'OCR';

  @override
  String get exOpenDocumentFirst => 'Ouvrez d\'abord un document';

  @override
  String get exOpenFromUrl => 'Ouvrir depuis une URL…';

  @override
  String get exOpenFromUrlTitle => 'Ouvrir depuis une URL';

  @override
  String get exOpenInNewTab => 'Ouvrir le PDF dans un nouvel onglet';

  @override
  String get exOpenInteractiveDemo => 'Ouvrir la démo interactive';

  @override
  String get exOpenPdf => 'Ouvrir un PDF…';

  @override
  String get exOpenPdfButton => 'Ouvrir un PDF';

  @override
  String get exOpenRecent => 'Ouvrir un fichier récent';

  @override
  String get exOpenUrlDescription =>
      'Diffuse le PDF via des requêtes HTTP Range à l\'aide de PdfHttpByteSource, en ne récupérant que ce dont l\'analyseur a besoin et en basculant vers un téléchargement complet lorsque le serveur ne prend pas en charge les requêtes Range.';

  @override
  String get exOpeningDocument => 'Ouverture du document';

  @override
  String get exOpeningPdf => 'Ouverture du PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Ouverture de $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL du PDF';

  @override
  String get exPerformanceAuto => 'Performances : Auto';

  @override
  String get exPreparing => 'Préparation…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor sur pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Reconnaissance de la page $current sur $count…';
  }

  @override
  String get exResolution => 'Résolution';

  @override
  String get exRunOcr => 'Lancer l\'OCR';

  @override
  String get exSaveAs => 'Enregistrer sous…';

  @override
  String exSaveFailed(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String exSavedName(String name) {
    return '$name enregistré';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name enregistré - recollez-le dans le PDF avec ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get exScrollIndicatorDemo =>
      'Démo de l\'API d\'indicateur de défilement';

  @override
  String get exServiceEndpoint => 'Point de terminaison du service';

  @override
  String get exShow => 'Afficher';

  @override
  String get exSingleWorker => 'Un seul worker';

  @override
  String get exSupplyFeedback => 'Envoyer un retour…';

  @override
  String get exSwitchToEdit => 'Passer en mode édition';

  @override
  String get exSwitchToReadOnly => 'Passer en lecture seule';

  @override
  String get exThemeDark => 'Thème : sombre - passer au système';

  @override
  String get exThemeLight => 'Thème : clair - passer au sombre';

  @override
  String get exThemeSystem => 'Thème : système - passer au clair';

  @override
  String get exTryDemo => 'Essayer la démo interactive';

  @override
  String get exUntitled => 'Sans titre';

  @override
  String get exVerticalLayout => 'Disposition verticale des pages';

  @override
  String get exViewSource => 'Voir le code source sur GitHub';

  @override
  String get exWorkerAuto => 'Auto';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performances : $count workers',
      one: 'Performances : un seul worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics => 'Joindre ces diagnostics au rapport';

  @override
  String get feedbackClearLog => 'Effacer le journal';

  @override
  String get feedbackCopyDiagnostics => 'Copier les diagnostics';

  @override
  String get feedbackDiagnosticsNotice =>
      'Le formulaire de retour s\'ouvre dans votre navigateur. Les diagnostics ci-dessous sont collectés uniquement sur cet appareil et sont joints pour aider à reproduire le problème. Examinez-les d\'abord - n\'incluez rien que vous préféreriez garder confidentiel.';

  @override
  String get feedbackOpenForm => 'Ouvrir le formulaire de retour';

  @override
  String get feedbackTitle => 'Envoyer un retour';

  @override
  String get none => 'Aucun';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Coller';

  @override
  String get redo => 'Rétablir';

  @override
  String get remove => 'Retirer';

  @override
  String get rename => 'Renommer';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get save => 'Enregistrer';

  @override
  String get scrollDemoNextPage => 'Page suivante';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Page $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Page précédente';

  @override
  String get scrollDemoSwitchHorizontal =>
      'Passer à la disposition horizontale';

  @override
  String get scrollDemoSwitchVertical => 'Passer à la disposition verticale';

  @override
  String get scrollDemoTitle => 'API d\'indicateur de défilement';

  @override
  String get undo => 'Annuler';

  @override
  String get exFileTypePdf => 'Documents PDF';

  @override
  String get exFileTypeImages => 'Images';

  @override
  String get exFileTypeFonts => 'Polices';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - partie $part.pdf';
  }
}
