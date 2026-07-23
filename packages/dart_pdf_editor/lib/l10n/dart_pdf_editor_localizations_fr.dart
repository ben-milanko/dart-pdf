// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class DartPdfEditorLocalizationsFr extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get tbCropApply => 'Appliquer le rognage';

  @override
  String get tbCropCancel => 'Annuler le rognage';

  @override
  String get tbCropImage => 'Rogner l\'image';

  @override
  String get tbCropReset => 'Réinitialiser le rognage';

  @override
  String get tbCroppingImage => 'Rognage de l\'image';

  @override
  String get menuLock => 'Verrouiller';

  @override
  String get menuUnlock => 'Déverrouiller';

  @override
  String get sidebarLockAnnotation => 'Verrouiller';

  @override
  String get sidebarUnlockAnnotation => 'Déverrouiller';

  @override
  String get searchAnnotations => 'Rechercher les annotations';

  @override
  String get add => 'Ajouter';

  @override
  String get annotCaret => 'Caret';

  @override
  String get annotCircle => 'Cercle';

  @override
  String get annotFileAttachment => 'Pièce jointe';

  @override
  String get annotFreeText => 'Zone de texte';

  @override
  String get annotHighlight => 'Surlignage';

  @override
  String get annotInk => 'Encre';

  @override
  String get annotLine => 'Ligne';

  @override
  String get annotLink => 'Lien';

  @override
  String get annotPolygon => 'Polygone';

  @override
  String get annotPolyline => 'Ligne brisée';

  @override
  String get annotRedact => 'Caviardage';

  @override
  String get annotSquare => 'Carré';

  @override
  String get annotSquiggly => 'Ondulé';

  @override
  String get annotStamp => 'Tampon';

  @override
  String get annotStrikeOut => 'Barré';

  @override
  String get annotText => 'Note';

  @override
  String get annotUnderline => 'Souligné';

  @override
  String get annotWidget => 'Champ de formulaire';

  @override
  String get apply => 'Appliquer';

  @override
  String get bookmarkAdd => 'Ajouter un signet';

  @override
  String get bookmarkAddChild => 'Ajouter un signet enfant';

  @override
  String get bookmarkCollapse => 'Réduire';

  @override
  String get bookmarkDelete => 'Supprimer le signet';

  @override
  String get bookmarkEdit => 'Modifier le signet';

  @override
  String get bookmarkEmpty => 'Aucun signet';

  @override
  String get bookmarkExpand => 'Développer';

  @override
  String get bookmarkExpandedByDefault => 'Développé par défaut';

  @override
  String get bookmarkNoDestination => 'Aucune destination';

  @override
  String get bookmarkPageFieldLabel => 'Page';

  @override
  String bookmarkPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Signets';

  @override
  String get bookmarkTitleLabel => 'Titre';

  @override
  String get bookmarkUntitled => 'Sans titre';

  @override
  String get cancel => 'Annuler';

  @override
  String get clear => 'Effacer';

  @override
  String get close => 'Fermer';

  @override
  String get colorApplyingChanges =>
      'Application des modifications de couleur…';

  @override
  String get colorColorFormat => 'Format de couleur';

  @override
  String get colorColorTitle => 'Couleur';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count couleurs sélectionnées',
      one: '$count couleur sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Couleurs du document';

  @override
  String get colorFillColors => 'Couleurs de remplissage';

  @override
  String get colorFind => 'Rechercher';

  @override
  String get colorInDocument => 'Dans le document';

  @override
  String get colorNoColorsFound => 'Aucune couleur trouvée pour l\'instant';

  @override
  String get colorNoPageContentColors =>
      'Aucune couleur de contenu de page trouvée';

  @override
  String get colorPalette => 'Palette';

  @override
  String get colorPickColor => 'Sélectionner une couleur';

  @override
  String get colorProcessingTitle => 'Traitement des couleurs';

  @override
  String get colorRecent => 'Récentes';

  @override
  String get colorReplace => 'Remplacer';

  @override
  String get colorReplaceWithTransparent => 'Remplacer par de la transparence';

  @override
  String get colorScanning => 'Analyse…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Analyse $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Pages sélectionnées ($count)';
  }

  @override
  String get colorStrokeColors => 'Couleurs de trait';

  @override
  String get colorTolerance => 'Tolérance';

  @override
  String get colorTransparent => 'Transparent';

  @override
  String get colorWholeDocument => 'Document entier';

  @override
  String get compareAfter => 'Après';

  @override
  String get compareBefore => 'Avant';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications',
      one: '1 modification',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifications',
      one: '1 modification',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(vide)';

  @override
  String get compareNextChange => 'Modification suivante';

  @override
  String get compareNoChanges => 'Aucune modification';

  @override
  String get compareNoDifferences =>
      'Aucune différence entre les deux documents';

  @override
  String get compareOverlay => 'Superposition';

  @override
  String comparePageHeader(int page) {
    return 'Page $page';
  }

  @override
  String get comparePreviousChange => 'Modification précédente';

  @override
  String get compareSideBySide => 'Côte à côte';

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
  String get editorViewAuthorNameTitle => 'Nom de l\'auteur';

  @override
  String get lineStyleDashDot => 'Tiret-point';

  @override
  String get lineStyleDashed => 'Tirets';

  @override
  String get lineStyleDotted => 'Pointillés';

  @override
  String get lineStyleSolid => 'Continu';

  @override
  String get measCalibrate => 'Calibrer';

  @override
  String get measCalibrateScale => 'Calibrer l\'échelle';

  @override
  String get measDepthLabel => 'Profondeur : ';

  @override
  String get measKindAngle => 'Angle';

  @override
  String get measKindArc => 'Arc';

  @override
  String get measKindArea => 'Aire';

  @override
  String get measKindCount => 'Comptage';

  @override
  String get measKindLength => 'Longueur';

  @override
  String get measKindNetArea => 'Aire nette';

  @override
  String get measKindPerimeter => 'Périmètre';

  @override
  String get measKindSlope => 'Pente';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'La ligne que vous avez tracée représente :';

  @override
  String get measMeasure => 'Mesurer';

  @override
  String get measSetScale => 'Définir l\'échelle de mesure';

  @override
  String get measSetScaleButton => 'Définir l\'échelle';

  @override
  String get measVolumeDepth => 'Profondeur du volume';

  @override
  String get menuAddNode => 'Ajouter un nœud';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Appliquer les annotations aux pages',
      one: 'Appliquer l\'annotation aux pages',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Appliquer aux pages…';

  @override
  String get menuBringToFront => 'Mettre au premier plan';

  @override
  String get menuCheck => 'Cocher';

  @override
  String get menuChooseValue => 'Choisir une valeur…';

  @override
  String get menuClearCheck => 'Décocher';

  @override
  String get menuConvertToCheckBox => 'Convertir en case à cocher';

  @override
  String get menuConvertToImageButton => 'Convertir en bouton image';

  @override
  String get menuConvertToTextField => 'Convertir en champ de texte';

  @override
  String get menuDeleteField => 'Supprimer le champ';

  @override
  String get menuEditValue => 'Modifier la valeur…';

  @override
  String get menuFieldName => 'Nom du champ';

  @override
  String get menuFieldValue => 'Valeur du champ';

  @override
  String get menuFlattenForm => 'Aplatir le formulaire';

  @override
  String get menuRecolour => 'Recoloriser…';

  @override
  String get menuRemoveNode => 'Supprimer le nœud';

  @override
  String get menuSetAsDefaultStyle => 'Définir comme style par défaut';

  @override
  String get menuRename => 'Renommer…';

  @override
  String get menuSelectOption => 'Sélectionner l\'option';

  @override
  String get menuSendToBack => 'Mettre à l\'arrière-plan';

  @override
  String get menuSetImage => 'Définir l\'image…';

  @override
  String get menuTextStyle => 'Style de texte…';

  @override
  String get none => 'Aucun';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Couleur';

  @override
  String get overlayEditText => 'Modifier le texte';

  @override
  String get overlayFont => 'Police';

  @override
  String get overlayLarger => 'Plus grand';

  @override
  String get overlayMore => 'Plus';

  @override
  String get overlayNote => 'Note';

  @override
  String get overlaySmaller => 'Plus petit';

  @override
  String get overlayStampText => 'Texte du tampon';

  @override
  String get overlayUnderline => 'Souligner';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Saisissez des pages comprises entre 1 et $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'La dernière page ne doit pas précéder la première.';

  @override
  String get pageRangeFrom => 'De';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'À';

  @override
  String get panelDragToMovePanel => 'Faites glisser pour déplacer le panneau';

  @override
  String get paste => 'Coller';

  @override
  String get propAlign => 'Aligner';

  @override
  String get propAlignCenter => 'Centrer';

  @override
  String get propAlignLeft => 'Aligner à gauche';

  @override
  String get propAlignRight => 'Aligner à droite';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotations',
      one: '$count annotation',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Auteur';

  @override
  String get propAutoSize => 'Taille automatique';

  @override
  String get propBold => 'Gras';

  @override
  String get propBoldLetter => 'G';

  @override
  String get propBundledFont => 'Police intégrée';

  @override
  String get propCallout => 'Légende';

  @override
  String get propCharSpacing => 'Espacement des caractères';

  @override
  String get propColor => 'Couleur';

  @override
  String get propColour => 'Couleur';

  @override
  String get propContents => 'Contenu';

  @override
  String get propEditsApplyToAll =>
      'Les modifications s\'appliquent à toutes les annotations compatibles';

  @override
  String get propFieldName => 'Nom du champ';

  @override
  String get propFieldTypeCheckBox => 'Case à cocher';

  @override
  String get propFieldTypeComboBox => 'Liste déroulante';

  @override
  String get propFieldTypeImageButton => 'Bouton image';

  @override
  String get propFieldTypeListBox => 'Zone de liste';

  @override
  String get propFieldTypeRadioGroup => 'Groupe de boutons radio';

  @override
  String get propFieldTypeSignature => 'Signature';

  @override
  String get propFieldTypeText => 'Champ de texte';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Type de champ : $type';
  }

  @override
  String get propFieldTypeUnknown => 'Champ inconnu';

  @override
  String get propFill => 'Remplissage';

  @override
  String get propFont => 'Police';

  @override
  String get propFontSubsetTooltip =>
      'Cette police est sous-ensemble - seuls les caractères déjà utilisés dans le document peuvent être saisis.';

  @override
  String get propFontWidth => 'Largeur de police';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'L';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Italique';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Caractères limités';

  @override
  String get propLineEnd => 'Fin de ligne';

  @override
  String get propLineEndingButt => 'Plat';

  @override
  String get propLineEndingCircle => 'Cercle';

  @override
  String get propLineEndingClosedArrow => 'Flèche fermée';

  @override
  String get propLineEndingClosedArrowRev => 'Flèche fermée (inv.)';

  @override
  String get propLineEndingDiamond => 'Losange';

  @override
  String get propLineEndingOpenArrow => 'Flèche ouverte';

  @override
  String get propLineEndingOpenArrowRev => 'Flèche ouverte (inv.)';

  @override
  String get propLineEndingSlash => 'Barre oblique';

  @override
  String get propLineEndingSquare => 'Carré';

  @override
  String get propLineSpacing => 'Interligne';

  @override
  String get propLineStart => 'Début de ligne';

  @override
  String get propLineType => 'Type de ligne';

  @override
  String get propLoadFont => 'Charger une police…';

  @override
  String get propLoadFontSubtitle => 'Fichier TTF ou OTF';

  @override
  String get propMoreColors => 'Plus de couleurs…';

  @override
  String get propMultiline => 'Multiligne';

  @override
  String get propNoFill => 'Sans remplissage';

  @override
  String get propNoFontsFound => 'Aucune police trouvée';

  @override
  String get propNoOutline => 'Sans contour';

  @override
  String get propOpacity => 'Opacité';

  @override
  String get propOutline => 'Contour';

  @override
  String get propPageLabel => 'Page';

  @override
  String propPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get propPropertiesTitle => 'Propriétés';

  @override
  String get propRecentlyUsed => 'Récemment utilisées';

  @override
  String get propScale => 'Échelle';

  @override
  String get propSearchFonts => 'Rechercher des polices';

  @override
  String get propSectionAllFonts => 'Toutes les polices';

  @override
  String get propSectionAppearance => 'Apparence';

  @override
  String get propSectionContent => 'Contenu';

  @override
  String get propSectionFormField => 'Champ de formulaire';

  @override
  String get propSectionInThisDocument => 'Dans ce document';

  @override
  String get propSectionPositionSize => 'Position et taille (pt)';

  @override
  String get propSectionSelection => 'Sélection';

  @override
  String get propSectionText => 'Texte';

  @override
  String get propSelectAnnotationPrompt =>
      'Sélectionnez une annotation pour voir ses propriétés';

  @override
  String get propSize => 'Taille';

  @override
  String get propStandardPdfFont => 'Police PDF standard';

  @override
  String get propStroke => 'Trait';

  @override
  String get propStyle => 'Style';

  @override
  String get propSystemFont => 'Police système';

  @override
  String get propType => 'Type';

  @override
  String get propUnderline => 'Souligné';

  @override
  String get propVaries => 'Variable';

  @override
  String get redo => 'Rétablir';

  @override
  String get reflowNoContent => 'Aucun contenu extractible';

  @override
  String reflowPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get reflowSaveOrShare => 'Enregistrer ou partager';

  @override
  String get reflowViewFigure => 'Afficher la figure';

  @override
  String get remove => 'Retirer';

  @override
  String get rename => 'Renommer';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get save => 'Enregistrer';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Page $page';
  }

  @override
  String get sbarCallout => 'Légende';

  @override
  String get sbarFieldButton => 'Champ bouton';

  @override
  String get sbarFieldChoice => 'Champ de choix';

  @override
  String get sbarFieldGeneric => 'Champ de formulaire';

  @override
  String get sbarFieldSignature => 'Champ de signature';

  @override
  String get sbarFieldText => 'Champ de texte';

  @override
  String get sbarStateAccepted => 'Accepté';

  @override
  String get sbarStateCancelled => 'Annulé';

  @override
  String get sbarStateMarked => 'Marqué';

  @override
  String get sbarStateRejected => 'Rejeté';

  @override
  String get sbarStateResolved => 'Résolu';

  @override
  String get sbarStateUnmarked => 'Non marqué';

  @override
  String get searchClearSearch => 'Effacer la recherche';

  @override
  String get searchEmptyHint =>
      'Recherchez dans le document pour lister ici toutes les correspondances';

  @override
  String get searchMatchCase => 'Respecter la casse';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correspondances',
      one: '1 correspondance',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Correspondance suivante';

  @override
  String searchNoMatches(String query) {
    return 'Aucune correspondance pour « $query »';
  }

  @override
  String searchPageHeader(int page) {
    return 'Page $page';
  }

  @override
  String get searchPreviousMatch => 'Correspondance précédente';

  @override
  String get searchRegex => 'Expression régulière';

  @override
  String get searchResultsTitle => 'Résultats de recherche';

  @override
  String get searchWholeWord => 'Mot entier';

  @override
  String get shellControls => 'Commandes';

  @override
  String get shellDefaultAuthor => 'Auteur par défaut…';

  @override
  String get shellHighlightFormFields => 'Surligner les champs de formulaire';

  @override
  String get shellKeyboardShortcutsMenu => 'Raccourcis clavier…';

  @override
  String get shellKeyboardShortcutsTitle => 'Raccourcis clavier';

  @override
  String get shellShortcutsSearchHint => 'Rechercher des raccourcis';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Aucun raccourci ne correspond à « $query »';
  }

  @override
  String get shellShortcutGroupSelect => 'Sélection';

  @override
  String get shellShortcutGroupMarkup => 'Marquage';

  @override
  String get shellShortcutGroupDraw => 'Dessin';

  @override
  String get shellShortcutGroupShapes => 'Formes';

  @override
  String get shellShortcutGroupInsert => 'Insertion';

  @override
  String get shellShortcutGroupMeasure => 'Mesure';

  @override
  String get shellShortcutGroupEdit => 'Édition';

  @override
  String get shellNotSet => 'Non défini';

  @override
  String get shellPageColor => 'Couleur de page…';

  @override
  String get shellPageGrid => 'Grille de pages';

  @override
  String get shellPanelAnnotations => 'Annotations';

  @override
  String get shellPanelBookmarks => 'Signets';

  @override
  String get shellPanelPages => 'Pages';

  @override
  String get shellPanelProperties => 'Propriétés';

  @override
  String get shellPanelSearchResults => 'Résultats de recherche';

  @override
  String get shellPanels => 'Panneaux';

  @override
  String get shellPressAKey => 'Appuyez sur une touche';

  @override
  String get shellPressLetterKeyHint =>
      'Appuyez sur une lettre, ou sur Suppr pour effacer.';

  @override
  String get shellReflow => 'Redistribution';

  @override
  String get shellReflowText => 'Redistribuer le texte';

  @override
  String get shellResetZoom => 'Réinitialiser le zoom';

  @override
  String get shellSectionShell => 'Interface';

  @override
  String get shellSectionView => 'Affichage';

  @override
  String get shellSettings => 'Paramètres';

  @override
  String get shellShowAnnotations => 'Afficher les annotations';

  @override
  String get shellTabHere => 'Onglet ici';

  @override
  String get shellUnbound => 'Non attribué';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'par $author';
  }

  @override
  String get sidebarCancelSelection => 'Annuler la sélection';

  @override
  String get sidebarClearSearch => 'Effacer la recherche';

  @override
  String get sidebarDeleteSelected => 'Supprimer la sélection';

  @override
  String get sidebarDeleteSignature => 'Supprimer la signature';

  @override
  String get sidebarMore => 'Plus';

  @override
  String get sidebarNoAnnotations => 'Aucune annotation';

  @override
  String get sidebarNoMatchingAnnotations => 'Aucune annotation correspondante';

  @override
  String sidebarPageHeader(int number) {
    return 'Page $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Cela supprime la signature numérique du document. Vous pouvez annuler cette action.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Cela supprime du document la signature numérique de « $name ». Vous pouvez annuler cette action.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Supprimer la signature ?';

  @override
  String get sidebarReopen => 'Rouvrir';

  @override
  String get sidebarReply => 'Répondre';

  @override
  String get sidebarResolve => 'Résoudre';

  @override
  String get sidebarSearchHint => 'Rechercher des annotations';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '$count sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Écrire une réponse…';

  @override
  String get sigTitle => 'Signature';

  @override
  String get signIdCreate => 'Créer';

  @override
  String get signIdEmail => 'E-mail (facultatif)';

  @override
  String get signIdName => 'Nom';

  @override
  String get signIdNameHint =>
      'Votre nom, tel qu\'il doit apparaître sur la signature';

  @override
  String get signIdNameRequired => 'Saisissez un nom';

  @override
  String get signIdOrganization => 'Organisation (facultatif)';

  @override
  String get signIdSelfSignedInfo =>
      'Cela crée une identité auto-signée. Les signatures s\'afficheront comme « signé, validité inconnue » dans Adobe Acrobat et d\'autres lecteurs - comme leurs propres identités auto-signées. La coche verte nécessite une autorité de certification payante et publiquement reconnue.';

  @override
  String get signIdTitle => 'Créer une identité de signature';

  @override
  String get stampBox => 'Rectangle';

  @override
  String get stampCircle => 'Cercle';

  @override
  String get stampCustomCaption => 'Tampon personnalisé';

  @override
  String get stampDateFormat => 'Format de date';

  @override
  String get stampDeleteComponent => 'Supprimer le composant sélectionné';

  @override
  String get stampDeleteStamp => 'Supprimer le tampon';

  @override
  String get stampEditStamp => 'Modifier le tampon';

  @override
  String get stampExport => 'Exporter…';

  @override
  String get stampFieldDate => 'Date';

  @override
  String get stampFieldDateTime => 'Date et heure';

  @override
  String get stampFieldTime => 'Heure';

  @override
  String get stampFieldUsername => 'Nom d\'utilisateur';

  @override
  String get stampFont => 'Police';

  @override
  String get stampFontBold => 'Gras';

  @override
  String get stampFontItalic => 'Italique';

  @override
  String get stampHeight => 'Hauteur';

  @override
  String get stampImage => 'Image';

  @override
  String get stampImport => 'Importer…';

  @override
  String get stampInsertField => 'Insérer un champ';

  @override
  String get stampMoreColors => 'Plus de couleurs…';

  @override
  String get stampNewStamp => 'Nouveau tampon…';

  @override
  String get stampNewStampTitle => 'Nouveau tampon';

  @override
  String get stampSelectTextToEdit => 'Sélectionnez du texte à modifier';

  @override
  String get stampSelectedText => 'Texte sélectionné';

  @override
  String get stampSignature => 'Signature';

  @override
  String get stampStamps => 'Tampons';

  @override
  String get stampText => 'Texte';

  @override
  String get stampTime12Hour => '12 h';

  @override
  String get stampTime24Hour => '24 h';

  @override
  String get stampTimeFormat => 'Format d\'heure';

  @override
  String get stampWidth => 'Largeur';

  @override
  String get takeoffArea => 'Aire';

  @override
  String get takeoffCount => 'Comptage';

  @override
  String get takeoffEmpty => 'Aucune mesure pour l\'instant.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groupes',
      one: '$count groupe',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '$count élément',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Longueur';

  @override
  String get takeoffTitle => 'Métré';

  @override
  String get tbAddInkAnnotation => 'Ajouter l\'annotation à l\'encre';

  @override
  String get tbAlign => 'Aligner';

  @override
  String get tbAlignBottom => 'Aligner en bas';

  @override
  String get tbAlignHorizontalCenters => 'Aligner les centres horizontaux';

  @override
  String get tbAlignLeft => 'Aligner à gauche';

  @override
  String get tbAlignRight => 'Aligner à droite';

  @override
  String get tbAlignTop => 'Aligner en haut';

  @override
  String get tbAlignVerticalCenters => 'Aligner les centres verticaux';

  @override
  String get tbAnnotationsFlattened => 'Annotations aplaties dans les pages';

  @override
  String get tbApplyRedactionsMessage =>
      'Le contenu marqué sera définitivement supprimé du document. Cette action est irréversible.';

  @override
  String get tbApplyRedactionsTitle => 'Appliquer les caviardages ?';

  @override
  String get tbApplyRedactionsTooltip =>
      'Appliquer les caviardages (irréversible)';

  @override
  String get tbAutosizeTextBox =>
      'Ajuster automatiquement la zone de texte (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Tracez une ligne de longueur connue pour calibrer l\'échelle.';

  @override
  String get tbCharSpacing => 'Espacement des caractères';

  @override
  String get tbCheckBoxOption => 'Case à cocher';

  @override
  String get tbCheckMarksOnDocument => 'Coches sur le document';

  @override
  String get tbColorLabel => 'Couleur';

  @override
  String get tbColorProcessingTooltip =>
      'Traitement des couleurs - rechercher et remplacer les couleurs du contenu de page';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count couleurs remplacées',
      one: '1 couleur remplacée',
      zero: 'Aucune couleur correspondante trouvée',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Convertir en case à cocher';

  @override
  String get tbConvertToImageButton => 'Convertir en bouton image';

  @override
  String get tbConvertToTextField => 'Convertir en champ de texte';

  @override
  String get tbCornerRadius => 'Rayon des coins';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count annotations',
      one: 'Supprimer l\'annotation',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Supprimer l\'élément';

  @override
  String get tbDeleteField => 'Supprimer le champ';

  @override
  String get tbDiscardDrawing => 'Abandonner le dessin';

  @override
  String get tbDistributeHorizontally => 'Répartir horizontalement';

  @override
  String get tbDistributeVertically => 'Répartir verticalement';

  @override
  String get tbDrawNewSignature => 'Dessiner une nouvelle signature…';

  @override
  String get tbEditAnnotationText => 'Modifier le texte de l\'annotation';

  @override
  String get tbEditTextStyle => 'Modifier le texte et le style';

  @override
  String get tbElement => 'Élément';

  @override
  String get tbEraserSize => 'Taille de la gomme';

  @override
  String get tbFieldActions => 'Actions du champ';

  @override
  String get tbFieldName => 'Nom du champ';

  @override
  String tbFieldNamed(String name) {
    return 'Champ : $name';
  }

  @override
  String get tbFieldValue => 'Valeur du champ';

  @override
  String get tbFill => 'Remplissage';

  @override
  String get tbFingerDraws =>
      'Le doigt dessine - appuyez pour qu\'il fasse défiler à la place';

  @override
  String get tbFingerScrolls =>
      'Le doigt fait défiler (le stylet dessine) - appuyez pour qu\'il dessine';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Aplatir les annotations dans les pages';

  @override
  String get tbFlattenForm => 'Aplatir le formulaire';

  @override
  String get tbFlattenFormBakeValues =>
      'Aplatir le formulaire - fixer les valeurs dans les pages';

  @override
  String get tbFlattenLabel => 'Aplatir';

  @override
  String get tbFont => 'Police';

  @override
  String get tbFontSize => 'Taille de police';

  @override
  String get tbFontWidth => 'Largeur de police';

  @override
  String get tbFormFieldsFlattened =>
      'Champs de formulaire aplatis dans les pages';

  @override
  String get tbGroupDraw => 'Dessin';

  @override
  String get tbGroupEdit => 'Édition';

  @override
  String get tbGroupInsert => 'Insertion';

  @override
  String get tbGroupMarkup => 'Marquage';

  @override
  String get tbGroupMeasure => 'Mesure';

  @override
  String get tbGroupSelect => 'Sélection';

  @override
  String get tbGroupShapes => 'Formes';

  @override
  String get tbImageButtonOption => 'Bouton image';

  @override
  String get tbLineEnd => 'Fin de ligne';

  @override
  String get tbLineSpacing => 'Interligne';

  @override
  String get tbLineStart => 'Début de ligne';

  @override
  String get tbLineType => 'Type de ligne';

  @override
  String get tbManageStamps => 'Gérer les tampons…';

  @override
  String get tbMarkupHighlight => 'Surligner';

  @override
  String get tbMarkupHighlightTip => 'Surligner la sélection';

  @override
  String get tbMarkupSquiggly => 'Souligner en ondulé';

  @override
  String get tbMarkupSquigglyTip => 'Souligner la sélection en ondulé';

  @override
  String get tbMarkupStrikeOut => 'Barrer';

  @override
  String get tbMarkupStrikeOutTip => 'Barrer la sélection';

  @override
  String get tbMarkupUnderline => 'Souligner';

  @override
  String get tbMarkupUnderlineTip => 'Souligner la sélection';

  @override
  String get tbMoreColors => 'Plus de couleurs…';

  @override
  String get tbNameArrow => 'Flèche';

  @override
  String get tbNameCallout => 'Légende';

  @override
  String get tbNameCloudPolygon => 'Polygone nuage';

  @override
  String get tbNameCount => 'Comptage';

  @override
  String get tbNameDigitalSignature => 'Signature numérique';

  @override
  String get tbNameDraw => 'Dessin';

  @override
  String get tbNameEllipse => 'Ellipse';

  @override
  String get tbNameEraser => 'Effacer les traits d\'encre';

  @override
  String get tbNameHighlight => 'Surlignage';

  @override
  String get tbNameImage => 'Image';

  @override
  String get tbNameLine => 'Ligne';

  @override
  String get tbNameMeasureAngle => 'Mesurer un angle';

  @override
  String get tbNameMeasureArc => 'Mesurer une longueur d\'arc';

  @override
  String get tbNameMeasureArea => 'Mesurer une aire';

  @override
  String get tbNameMeasureDistance => 'Mesurer une distance';

  @override
  String get tbNameMeasurePerimeter => 'Mesurer un périmètre';

  @override
  String get tbNameMeasureSlope => 'Mesurer une pente (dénivelé/distance)';

  @override
  String get tbNameMeasureVolume => 'Mesurer un volume (aire × profondeur)';

  @override
  String get tbNameNote => 'Note';

  @override
  String get tbNamePolygon => 'Polygone';

  @override
  String get tbNamePolyline => 'Ligne brisée';

  @override
  String get tbNameRectangle => 'Rectangle';

  @override
  String get tbNameSelect => 'Sélectionner';

  @override
  String get tbNameSignature => 'Signature';

  @override
  String get tbNameStamp => 'Tampon';

  @override
  String get tbNameTextBox => 'Zone de texte';

  @override
  String get tbNewFieldType =>
      'Nouveau type de champ - faites glisser sur une page pour en ajouter un';

  @override
  String get tbNoAnnotationsToFlatten => 'Aucune annotation à aplatir';

  @override
  String get tbNoCustomStamps => 'Aucun tampon personnalisé';

  @override
  String get tbNoFormFieldsToFlatten => 'Aucun champ de formulaire à aplatir';

  @override
  String get tbNoRedactionsToApply => 'Aucun caviardage à appliquer';

  @override
  String get tbNoteTitle => 'Note';

  @override
  String get tbOpacity => 'Opacité';

  @override
  String get tbOutline => 'Contour';

  @override
  String get tbPatternScale => 'Échelle du motif';

  @override
  String get tbPickColorFromPage => 'Prélever une couleur sur la page';

  @override
  String get tbRedactionsApplied => 'Caviardages appliqués';

  @override
  String get tbRedoShortcut => 'Rétablir (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Redistribution impossible - ce n\'est pas un paragraphe à une seule colonne que cet outil peut redécouper. Essayez plutôt Remplacer le texte.';

  @override
  String get tbReflowParagraph => 'Redistribuer le paragraphe';

  @override
  String get tbRenameField => 'Renommer le champ';

  @override
  String get tbRenameFieldEllipsis => 'Renommer le champ…';

  @override
  String get tbReplaceImage => 'Remplacer l\'image';

  @override
  String get tbReplaceImageFailed => 'Impossible de remplacer l\'image';

  @override
  String get tbReplaceText => 'Remplacer le texte';

  @override
  String get tbSaveImage => 'Enregistrer l\'image';

  @override
  String get tbSaveShortcut => 'Enregistrer… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Échelle';

  @override
  String get tbSelectTextForMarkup =>
      'Sélectionnez du texte pour utiliser le marquage';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: 'Sélection',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Définir…';

  @override
  String get tbStamp => 'Tampon';

  @override
  String get tbStampText => 'Texte du tampon';

  @override
  String get tbStrokeOpacityFont => 'Trait, opacité, police';

  @override
  String get tbStrokeWidthLabel => 'Épaisseur du trait';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Trait $width';
  }

  @override
  String get tbStyle => 'Style';

  @override
  String get tbTakeoffTotals => 'Totaux du métré';

  @override
  String get tbTextBorder => 'Bordure du texte';

  @override
  String get tbTextColour => 'Couleur du texte';

  @override
  String get tbTextFieldOption => 'Champ de texte';

  @override
  String get tbTextFill => 'Remplissage du texte';

  @override
  String get tbTextStyleEllipsis => 'Style de texte…';

  @override
  String get tbTextTitle => 'Texte';

  @override
  String get tbTipCallout =>
      'Légende - faites glisser du point vers l\'emplacement de la zone';

  @override
  String get tbTipContent => 'Modifier le contenu de la page';

  @override
  String get tbTipCount =>
      'Comptage - appuyez pour placer des coches et les comptabiliser';

  @override
  String get tbTipDigitalSignature =>
      'Signature numérique - faites glisser un cadre pour la placer et signer';

  @override
  String get tbTipForm =>
      'Champs de formulaire - appuyez pour sélectionner, appuyez deux fois pour remplir, faites glisser pour ajouter';

  @override
  String get tbTipHighlightDraw => 'Surlignage - dessinez à main levée';

  @override
  String get tbTipImage =>
      'Image - appuyez pour placer, ou faites glisser un cadre';

  @override
  String get tbTipMeasureAngle => 'Mesurer un angle - cliquez sur trois points';

  @override
  String get tbTipMeasureArc =>
      'Mesurer une longueur d\'arc - cliquez sur trois points';

  @override
  String get tbTipRedact =>
      'Caviarder - faites glisser une région, puis appliquez';

  @override
  String get tbTipSignature =>
      'Signature - appuyez sur une page pour la placer';

  @override
  String get tbTipSnapshot =>
      'Capture - faites glisser une région pour la capturer (recollez-la comme vecteur)';

  @override
  String get tbToolContent => 'Contenu';

  @override
  String get tbToolForm => 'Formulaire';

  @override
  String get tbToolRedact => 'Caviarder';

  @override
  String get tbToolSnapshot => 'Capture';

  @override
  String get tbTools => 'Outils';

  @override
  String get tbTotals => 'Totaux';

  @override
  String get tbTypeTextEachTime => 'Saisir le texte à chaque fois';

  @override
  String get tbUnderline => 'Souligner';

  @override
  String get tbUndoShortcut => 'Annuler (⌘Z)';

  @override
  String get textStyleFont => 'Police';

  @override
  String get textStyleFontSize => 'Taille de police';

  @override
  String get textStyleKeep => 'conserver';

  @override
  String get textStyleStyle => 'Style';

  @override
  String get textStyleText => 'Texte';

  @override
  String get textStyleTextFill => 'Remplissage du texte';

  @override
  String get textStyleTitle => 'Modifier le texte et le style';

  @override
  String get thumbAddPage => 'Ajouter une page';

  @override
  String get thumbClearSelection => 'Effacer la sélection';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copier $count pages',
      one: 'Copier la page',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Copier les pages sélectionnées';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couper $count pages',
      one: 'Couper la page',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Couper les pages sélectionnées';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count pages',
      one: 'Supprimer la page',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Supprimer les pages sélectionnées';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dupliquer $count pages',
      one: 'Dupliquer la page',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Exporter les pages…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exporter $count pages…',
      one: 'Exporter la page…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Exporter les pages sélectionnées';

  @override
  String get thumbInsertBlankAfter => 'Insérer une page vierge après';

  @override
  String get thumbInsertBlankBefore => 'Insérer une page vierge avant';

  @override
  String get thumbInsertFileFailed => 'Impossible d\'insérer ce fichier.';

  @override
  String get thumbInsertPdf => 'Insérer un PDF…';

  @override
  String get thumbPageActions => 'Actions de page';

  @override
  String thumbPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get thumbPages => 'Pages';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Coller $count pages',
      one: 'Coller la page',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Pivoter de 180°';

  @override
  String get thumbRotateLeft => 'Pivoter à gauche';

  @override
  String get thumbRotatePageRight => 'Pivoter la page à droite';

  @override
  String get thumbRotateRight => 'Pivoter à droite';

  @override
  String get thumbRotateSelectedLeft =>
      'Pivoter les pages sélectionnées à gauche';

  @override
  String get thumbRotateSelectedRight =>
      'Pivoter les pages sélectionnées à droite';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '$count sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Annuler';

  @override
  String get viewerEditFontUnsafe =>
      'Cette police ou cet encodage PDF ne peut pas être modifié en toute sécurité.';

  @override
  String get viewerEditNeedsSinglePage =>
      'La modification nécessite une sélection sur une seule page.';

  @override
  String get viewerEditNotEditableRun =>
      'Cette sélection ne correspond pas à un seul segment de texte modifiable du contenu de la page.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Cette police PDF peut être ressaisie, mais son style ne peut pas être modifié.';

  @override
  String get viewerEditTextStyle => 'Modifier le texte et le style';

  @override
  String get viewerMarkup => 'Marquage';

  @override
  String get viewerMarkupHighlight => 'Surligner';

  @override
  String get viewerMarkupSquiggly => 'Ondulé';

  @override
  String get viewerMarkupStrikeOut => 'Barrer';

  @override
  String get viewerMarkupUnderline => 'Souligner';

  @override
  String get viewerSelectAll => 'Tout sélectionner';
}
