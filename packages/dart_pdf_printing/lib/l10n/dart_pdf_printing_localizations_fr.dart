// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class DartPdfPrintingLocalizationsFr extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get cancel => 'Annuler';

  @override
  String get printDlgPreparing => 'Préparation…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendu de la page $rendered sur $total…';
  }

  @override
  String get printDlgTitle => 'Impression';

  @override
  String get printPreviewAll => 'Toutes';

  @override
  String get printPreviewCurrent => 'Actuelle';

  @override
  String get printPreviewNextPage => 'Page suivante';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Page $page sur $total';
  }

  @override
  String get printPreviewPreviousPage => 'Page précédente';

  @override
  String get printPreviewPrint => 'Imprimer';

  @override
  String get printPreviewRange => 'Plage';

  @override
  String printPreviewRangeError(int total) {
    return 'Saisissez une plage de pages comprise entre 1 et $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Pages à imprimer : $count';
  }

  @override
  String get printPreviewTitle => 'Aperçu avant impression';

  @override
  String get printPreviewUnavailable => 'Aperçu indisponible';

  @override
  String get printOptionsPrinter => 'Imprimante';

  @override
  String get printOptionsNativePrinter =>
      'Choisissez l’imprimante, le bac à papier, la couleur, le recto verso et les propriétés du périphérique dans la boîte de dialogue d’impression du système qui s’ouvrira ensuite. Conservez une échelle de 100 % et une seule copie pour utiliser la mise en page affichée ici.';

  @override
  String get printOptionsPages => 'Pages';

  @override
  String get printOptionsSelected => 'Sélectionnées';

  @override
  String get printOptionsPageRange => 'Pages (par exemple, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Ajouter des fichiers…';

  @override
  String get printOptionsAddFailed =>
      'Impossible d’ajouter les fichiers sélectionnés.';

  @override
  String get printOptionsGetWindow => 'Définir la zone';

  @override
  String get printOptionsClearWindow => 'Effacer la zone';

  @override
  String get printOptionsWindowHint =>
      'Tracez un rectangle sur cette page d’origine pour choisir la zone à imprimer.';

  @override
  String get printOptionsPaper => 'Papier';

  @override
  String get printOptionsPaperSize => 'Format du papier';

  @override
  String get printOptionsPageSize => 'Utiliser le format de page du document';

  @override
  String get printOptionsOrientation => 'Orientation';

  @override
  String get printOptionsAuto => 'Automatique';

  @override
  String get printOptionsPortrait => 'Portrait';

  @override
  String get printOptionsLandscape => 'Paysage';

  @override
  String get printOptionsCopies => 'Copies';

  @override
  String get printOptionsCollate => 'Assembler';

  @override
  String get printOptionsReverse => 'Inverser l’ordre des pages';

  @override
  String get printOptionsLayout => 'Mise en page';

  @override
  String get printOptionsScaling => 'Mise à l’échelle';

  @override
  String get printOptionsScaleNone => 'Aucune (taille réelle)';

  @override
  String get printOptionsFitPaper => 'Ajuster au papier';

  @override
  String get printOptionsReducePaper => 'Réduire au format du papier';

  @override
  String get printOptionsFitMargins => 'Ajuster aux marges';

  @override
  String get printOptionsReduceMargins => 'Réduire aux marges';

  @override
  String get printOptionsCustomScale => 'Échelle personnalisée';

  @override
  String get printOptionsMultiple => 'Plusieurs pages par feuille';

  @override
  String get printOptionsScalePercent => 'Échelle (%)';

  @override
  String get printOptionsMargin => 'Marges (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Pages par feuille';

  @override
  String get printOptionsPageOrder => 'Ordre des pages';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal inversé';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical inversé';

  @override
  String get printOptionsBorder => 'Imprimer les bordures de page';

  @override
  String get printOptionsRotation => 'Rotation (sens horaire)';

  @override
  String get printOptionsNoRotation => 'Aucune';

  @override
  String get printOptionsCenter => 'Centrer sur le papier';

  @override
  String get printOptionsOffsetX => 'Décalage vers la droite (pt)';

  @override
  String get printOptionsOffsetY => 'Décalage vers le bas (pt)';

  @override
  String get printOptionsContents => 'Contenu à imprimer';

  @override
  String get printOptionsDocumentAndMarkups => 'Document et annotations';

  @override
  String get printOptionsDocumentOnly => 'Document uniquement';

  @override
  String get printOptionsMarkupsOnly => 'Annotations uniquement';

  @override
  String get printOptionsDimPage => 'Atténuer le contenu de la page';

  @override
  String get printOptionsDimMarkups => 'Atténuer les annotations';

  @override
  String get printOptionsHyperlinks => 'Imprimer les hyperliens visibles';

  @override
  String get printOptionsDefaults => 'Valeurs par défaut';

  @override
  String get printOptionsInvalidNumber =>
      'Saisissez des nombres valides avant d’imprimer.';

  @override
  String get printOptionsInvalidValue => 'Valeur non valide';

  @override
  String get printOptionsMarginGuide =>
      'Les lignes rouges indiquent les marges et ne sont pas imprimées.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Zone : $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Original : $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Feuille : $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Feuille $sheet sur $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Impossible de préparer cette mise en page. Vérifiez le format du papier, les marges et l’échelle.';

  @override
  String get printOptionsChoosePrinter => 'Choisir une imprimante';

  @override
  String get printOptionsNoPrinters =>
      'Aucune imprimante n’est installée. Ajoutez une imprimante dans les Paramètres Windows, puis réessayez.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'L’imprimante enregistrée « $printer » n’est pas disponible. Choisissez une imprimante pour continuer.';
  }

  @override
  String get printOptionsPrinterError =>
      'Impossible de charger les paramètres de l’imprimante. Vérifiez la connexion de l’imprimante et réessayez.';

  @override
  String get printOptionsRetry => 'Réessayer';

  @override
  String get printOptionsColor => 'Couleur';

  @override
  String get printOptionsGrayscale => 'Noir et blanc';

  @override
  String get printOptionsDuplex => 'Impression recto verso';

  @override
  String get printOptionsSimplex => 'Recto uniquement';

  @override
  String get printOptionsLongEdge => 'Retourner sur le bord long';

  @override
  String get printOptionsShortEdge => 'Retourner sur le bord court';

  @override
  String get printOptionsTray => 'Bac à papier';

  @override
  String get printOptionsDefaultTray => 'Valeur par défaut de l’imprimante';

  @override
  String get printOptionsProperties => 'Propriétés de l’imprimante…';

  @override
  String get printOptionsDirectPrinter =>
      'Imprimer envoie ce travail directement à l’imprimante sélectionnée.';

  @override
  String get printOptionsPropertiesError =>
      'Impossible d’ouvrir les propriétés de l’imprimante.';

  @override
  String get printOptionsLoadingPrinters => 'Chargement des imprimantes…';
}
