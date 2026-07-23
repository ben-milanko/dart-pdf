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
  String get appSigAddLogo => 'Ajouter un logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Les $pageCount pages';
  }

  @override
  String get appSigAppearance => 'Apparence';

  @override
  String get appSigAppearanceDescription =>
      'La signature est dessinée à l\'endroit où vous l\'avez placée. Le nom du signataire et les détails sont toujours affichés ; vous pouvez ajouter une marque manuscrite et un logo en arrière-plan.';

  @override
  String appSigApplyTo(String label) {
    return 'Appliquer à : $label';
  }

  @override
  String get appSigApplyToPages => 'Appliquer aux pages…';

  @override
  String get appSigChooseCertificate => 'Choisir un fichier de certificat…';

  @override
  String get appSigChooseKeyDescription =>
      'Choisissez votre clé privée (RSA, PEM ou DER) et son fichier de certificat. La clé sert uniquement à signer et n\'est jamais enregistrée.';

  @override
  String get appSigChoosePngOrJpeg => 'Choisissez une image PNG ou JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Choisir une clé privée…';

  @override
  String get appSigContactInfo => 'Coordonnées';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Impossible de capturer la signature.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Impossible de lire le certificat : $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Impossible de lire la clé : $error';
  }

  @override
  String get appSigCreateOnDevice => 'Créer une signature sur cet appareil';

  @override
  String appSigDate(String date) {
    return 'Date : $date';
  }

  @override
  String get appSigDigitallySign => 'Signer numériquement';

  @override
  String get appSigDrawSignature => 'Dessiner une signature…';

  @override
  String get appSigFieldHelper =>
      'Laissez vide pour créer un nouveau champ de signature.';

  @override
  String get appSigFieldLabel => 'Champ de signature existant (facultatif)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificats',
      one: '1 certificat',
    );
    return '$_temp0 · valide du $validFrom au $validUntil';
  }

  @override
  String get appSigIntro =>
      'Une signature numérique prouve que vous avez signé ce document et qu\'il n\'a pas été modifié depuis. Choisissez comment vous souhaitez signer.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Impossible de lire la clé ou le certificat sélectionné.';

  @override
  String get appSigKeylessDescription =>
      'Le plus simple. Nous confirmons votre identité par e-mail et signons pour vous, avec un horodatage de confiance. Rien à installer ni à configurer.';

  @override
  String get appSigKeylessIdentity => 'Identité sans clé';

  @override
  String get appSigKeylessSignInExpired =>
      'Votre connexion sans clé a expiré. Veuillez vous reconnecter.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Échec de la connexion sans clé : $failure';
  }

  @override
  String get appSigKeylessSubtitle => 'Sans clé · horodaté · validité inconnue';

  @override
  String get appSigKeylessWebNote =>
      'Se connecter avec votre e-mail est le moyen le plus simple — cette option est disponible dans les applications DartPDF pour ordinateur et mobile. Pour des raisons de sécurité, elle ne peut pas fonctionner dans un navigateur web.';

  @override
  String get appSigLocation => 'Lieu';

  @override
  String get appSigLogoAdded => 'Logo ajouté ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Pages $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Aperçu - le cadre signé peut légèrement différer.';

  @override
  String get appSigReason => 'Motif';

  @override
  String appSigReasonLine(String reason) {
    return 'Motif : $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Actualisation de la connexion…';

  @override
  String get appSigRemoveLogo => 'Retirer le logo';

  @override
  String get appSigRemoveSignature => 'Retirer la signature';

  @override
  String get appSigSelfSignedDescription =>
      'Aucune connexion ni fichier nécessaire. Idéal pour un usage personnel — l\'identité est enregistrée sur cet appareil pour la prochaine fois. Certains lecteurs PDF l\'afficheront comme « signé, validité inconnue », ce qui est normal pour une signature que vous créez vous-même.';

  @override
  String get appSigSelfSignedIdentity => 'Identité auto-signée';

  @override
  String get appSigSelfSignedSubtitle => 'Auto-signé · validité inconnue';

  @override
  String get appSigShowSignatureOnPages =>
      'Afficher la signature sur les pages';

  @override
  String get appSigSign => 'Signer';

  @override
  String get appSigSignInWithEmail => 'Se connecter avec votre e-mail';

  @override
  String get appSigSignatureAdded => 'Signature ajoutée ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Signé numériquement par $signerName';
  }

  @override
  String get appSigSigner => 'Signataire';

  @override
  String get appSigSigningYouIn => 'Connexion en cours…';

  @override
  String get appSigThisPageOnly => 'Cette page uniquement';

  @override
  String get appSigUseOwnCertificate => 'Utiliser votre propre certificat';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Pour un certificat de signature provenant de votre organisation';

  @override
  String get appSigX509Signer => 'Signataire X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Ouvrir ces $count PDF dans un nouvel onglet, ou insérer leurs pages dans « $title » ?',
      one:
          'Ouvrir ce PDF dans un nouvel onglet, ou insérer ses pages dans « $title » ?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ajouter les PDF déposés',
      one: 'Ajouter le PDF déposé',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Texte de l\'annotation copié';

  @override
  String get editorAppMenuTooltip => 'Menu DartPDF';

  @override
  String get editorCancelOcr => 'Annuler l\'OCR';

  @override
  String get editorClearRecentFiles => 'Effacer les fichiers récents';

  @override
  String get editorCloseAll => 'Tout fermer';

  @override
  String get editorCloseOthers => 'Fermer les autres';

  @override
  String get editorCloseTab => 'Fermer l\'onglet';

  @override
  String get editorCloseTabsToRight => 'Fermer les onglets à droite';

  @override
  String get editorCompareFailedTitle => 'Échec de la comparaison';

  @override
  String editorCompareTitle(String title) {
    return 'Comparer : $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get editorCopySelectedTextTooltip =>
      'Copier le texte sélectionné (⌘C)';

  @override
  String get editorCopyText => 'Copier le texte';

  @override
  String editorCouldNotExport(String title) {
    return 'Impossible d\'exporter $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Impossible d\'importer les tampons : $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossible d\'insérer les PDF déposés',
      one: 'Impossible d\'insérer le PDF déposé',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Impossible d\'ouvrir $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Impossible d\'ouvrir le dossier contenant';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Impossible d\'ouvrir le second fichier\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Impossible d\'ouvrir le fichier sélectionné\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Impossible d\'ouvrir $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Impossible d\'imprimer $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Impossible de rouvrir $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Impossible de signer numériquement : $error';
  }

  @override
  String get editorDiscard => 'Ignorer';

  @override
  String get editorDiscardChangesTitle => 'Ignorer les modifications ?';

  @override
  String get editorDocumentSigned => 'Document signé numériquement';

  @override
  String get editorDownload => 'Télécharger';

  @override
  String get editorDropToOpen => 'Déposez un PDF pour l\'ouvrir';

  @override
  String get editorDropToOpenOrInsert =>
      'Déposez un PDF pour l\'ouvrir ou l\'insérer';

  @override
  String get editorInsertPages => 'Insérer les pages';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count inséré(s) ; impossible de lire $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF insérés dans $title',
      one: 'Pages insérées dans $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Lien non valide : $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Ce document a tenté d\'exécuter du JavaScript (ignoré)';

  @override
  String get editorLoadingFullDocument => 'Chargement du document complet';

  @override
  String get editorMenuCompareWith => 'Comparer avec…';

  @override
  String get editorMenuDigitallySign => 'Signer numériquement…';

  @override
  String get editorMenuDigitallySigning => 'Signature numérique en cours…';

  @override
  String get editorMenuExportImage => 'Exporter la page comme image…';

  @override
  String get editorMenuNewDocument => 'Nouveau document…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Ouvrir un PDF…';

  @override
  String get editorMenuPrint => 'Imprimer…';

  @override
  String get editorMenuSaveAs => 'Enregistrer sous…';

  @override
  String get editorMenuScanDocument => 'Scan to new document…';

  @override
  String get editorMenuInsertScan => 'Insert scan…';

  @override
  String get editorScanFailed => 'Couldn\'t scan the document.';

  @override
  String get editorInsertedScan => 'Inserted scanned pages.';

  @override
  String get editorMenuSettings => 'Paramètres';

  @override
  String get editorMenuSwitchToEdit => 'Passer en mode édition';

  @override
  String get editorMenuSwitchToReadOnly => 'Passer en lecture seule';

  @override
  String editorNamedAction(String name) {
    return 'Action nommée : $name';
  }

  @override
  String get editorNoRecentFiles => 'Aucun fichier récent';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr =>
      'Ouvrez un document avant de lancer l\'OCR';

  @override
  String get editorOpenFailedTitle => 'Échec de l\'ouverture';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ouvrir dans de nouveaux onglets',
      one: 'Ouvrir dans un nouvel onglet',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Ouvrir le PDF dans un nouvel onglet';

  @override
  String get editorOpenRecent => 'Ouvrir un fichier récent';

  @override
  String get editorOpenTabs => 'Onglets ouverts';

  @override
  String get editorOpeningDocumentSemantic => 'Ouverture du document';

  @override
  String get editorOpeningPdf => 'Ouverture du PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Ouverture de $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get editorPreviewComparison => 'Comparaison';

  @override
  String get editorPreviewCouldNotOpen => 'Ouverture impossible';

  @override
  String get editorPreviewOpening => 'Ouverture';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Signature retirée';

  @override
  String get editorSnapshotCopied => 'Capture copiée dans le presse-papiers';

  @override
  String get editorSnapshotCopyFailed =>
      'Impossible de copier la capture dans le presse-papiers';

  @override
  String get editorTabs => 'Onglets';

  @override
  String editorTabsOpenCount(int count) {
    return '$count ouvert(s)';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents comportent des modifications non enregistrées.',
      one: 'Un document comporte des modifications non enregistrées.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Action non prise en charge : $type';
  }

  @override
  String get editorUntitled => 'Sans titre';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version est disponible.';
  }

  @override
  String get editorUpdateLater => 'Plus tard';

  @override
  String get editorViewAllTabs => 'Afficher tous les onglets';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi ppp';
  }

  @override
  String get imgExportExport => 'Exporter';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Résolution';

  @override
  String get imgExportTitle => 'Exporter la page comme image';

  @override
  String get newDocCreate => 'Créer';

  @override
  String get newDocLandscape => 'Paysage';

  @override
  String get newDocOrientation => 'Orientation';

  @override
  String get newDocPageSize => 'Taille de page';

  @override
  String get newDocPortrait => 'Portrait';

  @override
  String get newDocTitle => 'Nouveau document';

  @override
  String get none => 'Aucun';

  @override
  String get ocrAlreadyRunning =>
      'L\'OCR est déjà en cours - attendez qu\'il se termine ou annulez-le';

  @override
  String get ocrBrowserInitFailed =>
      'Échec de l\'initialisation de l\'OCR du navigateur';

  @override
  String get ocrCancelled => 'OCR annulé';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR annulé après $count zones de texte',
      one: 'OCR annulé après 1 zone de texte',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Télécharger';

  @override
  String ocrDownloadFailed(String error) {
    return 'Impossible de télécharger le modèle OCR : $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'L\'ajout d\'une couche de texte sélectionnable nécessite le modèle OCR sur l\'appareil$size. Il se télécharge une seule fois puis fonctionne hors ligne.\n\nModèle : $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Télécharger le modèle OCR ?';

  @override
  String ocrFailed(String error) {
    return 'Échec de l\'OCR : $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb Mo)';
  }

  @override
  String get ocrNotAvailable =>
      'L\'OCR sur l\'appareil n\'est pas disponible sur cette plateforme';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'L\'OCR a ajouté $count zones de texte - le texte de la page est désormais sélectionnable',
      one:
          'L\'OCR a ajouté 1 zone de texte - le texte de la page est désormais sélectionnable',
      zero: 'L\'OCR n\'a trouvé aucun texte sur ces pages',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'L\'OCR web télécharge un modèle vision-langage Florence-2 et l\'exécute localement avec WebGPU/WASM via Transformers.js. Les pages du PDF restent dans ce navigateur ; seuls les fichiers du modèle sont récupérés lors de la première utilisation.';

  @override
  String get ocrWebPromptTitle => 'Exécuter l\'OCR IA dans ce navigateur ?';

  @override
  String get ocrWebStart => 'Lancer l\'OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Coller';

  @override
  String get printDlgPreparing => 'Préparation…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Rendu de la page $rendered sur $total…';
  }

  @override
  String get printDlgTitle => 'Impression';

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
  String get settingsAbout => 'À propos';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsCheckNow => 'Vérifier maintenant';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Paramètre système par défaut';

  @override
  String get settingsCheckingForUpdates => 'Recherche de mises à jour…';

  @override
  String get settingsCouldNotOpenDownload =>
      'Impossible d\'ouvrir le téléchargement';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Impossible d\'ouvrir les paramètres système';

  @override
  String get settingsDeveloperTools => 'Outils de développement';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Métriques, journaux, modes de rendu (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Télécharger $version';
  }

  @override
  String get settingsOpenSettings => 'Ouvrir les paramètres';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mémorisés',
      one: '1 mémorisé',
      zero: 'Aucun fichier récent',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Fichiers récents';

  @override
  String get settingsSetUpAsDefault => 'Définir comme application par défaut';

  @override
  String get settingsSystem => 'Système';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeSystem => 'Système';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String settingsUpToDate(String version) {
    return 'Vous disposez de la dernière version ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'La version $version est disponible (vous avez $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Impossible de vérifier les mises à jour. Réessayez plus tard.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Vous avez $name $version.';
  }

  @override
  String get settingsUpdates => 'Mises à jour';

  @override
  String get settingsViewSource => 'Voir le code source sur GitHub';

  @override
  String get undo => 'Annuler';

  @override
  String get welcomeOpenPdf => 'Ouvrir un PDF';

  @override
  String get welcomePickAgainToReopen => 'Sélectionnez à nouveau pour rouvrir';

  @override
  String get welcomeRecent => 'Récents';

  @override
  String get welcomeRemoveFromRecent => 'Retirer des récents';

  @override
  String get welcomeTapToReopen => 'Appuyez pour rouvrir';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Installez l\'application web, puis choisissez-la pour les fichiers PDF.',
        'windows':
            'Ouvrez les paramètres des applications par défaut de Windows pour les PDF.',
        'macos': 'Suivez les étapes « Toujours ouvrir avec » du Finder.',
        'linux':
            'Utilisez les paramètres des applications par défaut de votre bureau.',
        'android':
            'Choisissez DartPDF à l\'ouverture d\'un PDF, puis appuyez sur Toujours.',
        'ios':
            'Utilisez Partager ou Ouvrir dans depuis Fichiers pour envoyer des PDF ici.',
        'other': 'Configurez le gestionnaire de fichiers PDF de votre système.',
      },
    );
    return '$_temp0';
  }

  @override
  String settingsDefaultAppInstructions(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Installez d\'abord DartPDF depuis votre navigateur. Utilisez ensuite les paramètres de gestion des fichiers du navigateur ou du système d\'exploitation pour associer les fichiers PDF à l\'application installée.',
        'windows':
            'Les paramètres Windows s\'ouvriront sur Applications par défaut. Recherchez « .pdf » ou « PDF », choisissez l\'application PDF actuelle, puis sélectionnez DartPDF.',
        'macos':
            'Dans le Finder, sélectionnez un PDF, choisissez Fichier > Lire les informations, développez « Ouvrir avec », choisissez DartPDF, puis cliquez sur « Tout modifier… ».',
        'linux':
            'Ouvrez les paramètres des applications par défaut de votre bureau, ou faites un clic droit sur un PDF dans Fichiers, choisissez Propriétés, et définissez DartPDF comme application par défaut pour les documents PDF.',
        'android':
            'Ouvrez un PDF depuis Fichiers ou Téléchargements, choisissez DartPDF dans le sélecteur d\'applications, puis sélectionnez Toujours. Si une autre application ouvre déjà les PDF, effacez d\'abord ses valeurs par défaut dans les paramètres Android.',
        'ios':
            'iOS ne propose pas d\'éditeur PDF par défaut global. Utilisez Fichiers > Partager, ou appuyez longuement sur un PDF et choisissez Partager/Ouvrir dans, puis choisissez DartPDF.',
        'other':
            'Utilisez les paramètres système de gestion des fichiers pour associer les documents PDF à DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Téléchargement du modèle OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Téléchargement du modèle $percent %';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Finalisation de l\'OCR…';

  @override
  String get fileTypePdf => 'Documents PDF';

  @override
  String get fileTypeImages => 'Images';

  @override
  String get fileTypeStampBundle => 'Tampons DartPDF';

  @override
  String get appSigKeyFileType => 'Clés privées RSA';

  @override
  String get appSigCertificateFileType => 'Certificats X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Sélectionnez au moins un certificat X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Le certificat $index n\'est pas un X.509 valide.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'La clé privée ne correspond à aucun certificat RSA sélectionné.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Les clés privées chiffrées ne sont pas prises en charge. Choisissez une clé RSA PKCS#1 ou PKCS#8 non chiffrée.';

  @override
  String get appSigErrorKeyNotRsa =>
      'La clé privée n\'est pas une clé RSA PKCS#1 ou PKCS#8 non chiffrée.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Aucun certificat X.509 n\'a été trouvé.';
}
