// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get add => 'जोड़ें';

  @override
  String get appSigAddLogo => 'लोगो जोड़ें…';

  @override
  String appSigAllPages(int pageCount) {
    return 'सभी $pageCount पृष्ठ';
  }

  @override
  String get appSigAppearance => 'रूप';

  @override
  String get appSigAppearanceDescription =>
      'हस्ताक्षर वहीं बनाया जाता है जहाँ आपने इसे रखा है। हस्ताक्षरकर्ता का नाम और विवरण हमेशा दिखाए जाते हैं; आप एक हस्तलिखित चिह्न और एक लोगो पृष्ठभूमि जोड़ सकते हैं।';

  @override
  String appSigApplyTo(String label) {
    return 'इन पर लागू करें: $label';
  }

  @override
  String get appSigApplyToPages => 'पृष्ठों पर लागू करें…';

  @override
  String get appSigChooseCertificate => 'प्रमाणपत्र फ़ाइल चुनें…';

  @override
  String get appSigChooseKeyDescription =>
      'अपनी निजी कुंजी (RSA, PEM या DER) और उसकी प्रमाणपत्र फ़ाइल चुनें। कुंजी का उपयोग केवल हस्ताक्षर करने के लिए होता है और इसे कभी सहेजा नहीं जाता।';

  @override
  String get appSigChoosePngOrJpeg => 'कोई PNG या JPEG छवि चुनें।';

  @override
  String get appSigChoosePrivateKey => 'निजी कुंजी चुनें…';

  @override
  String get appSigContactInfo => 'संपर्क जानकारी';

  @override
  String get appSigCouldNotCaptureSignature => 'हस्ताक्षर कैप्चर नहीं कर सके।';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'प्रमाणपत्र नहीं पढ़ सके: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'कुंजी नहीं पढ़ सके: $error';
  }

  @override
  String get appSigCreateOnDevice => 'इस डिवाइस पर हस्ताक्षर बनाएँ';

  @override
  String appSigDate(String date) {
    return 'दिनांक: $date';
  }

  @override
  String get appSigDigitallySign => 'डिजिटल रूप से हस्ताक्षर करें';

  @override
  String get appSigDrawSignature => 'हस्ताक्षर बनाएँ…';

  @override
  String get appSigFieldHelper =>
      'नया हस्ताक्षर फ़ील्ड बनाने के लिए खाली छोड़ें।';

  @override
  String get appSigFieldLabel => 'मौजूदा हस्ताक्षर फ़ील्ड (वैकल्पिक)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count प्रमाणपत्र',
      one: '1 प्रमाणपत्र',
    );
    return '$_temp0 · $validFrom से $validUntil तक मान्य';
  }

  @override
  String get appSigIntro =>
      'एक डिजिटल हस्ताक्षर यह साबित करता है कि आपने इस दस्तावेज़ पर हस्ताक्षर किए हैं और तब से इसमें कोई बदलाव नहीं हुआ है। चुनें कि आप कैसे हस्ताक्षर करना चाहते हैं।';

  @override
  String get appSigKeyOrCertUnreadable =>
      'चयनित कुंजी या प्रमाणपत्र नहीं पढ़ा जा सका।';

  @override
  String get appSigKeylessDescription =>
      'सबसे आसान। हम ईमेल द्वारा पुष्टि करते हैं कि यह आप हैं और एक विश्वसनीय टाइमस्टैम्प के साथ आपके लिए हस्ताक्षर करते हैं। कुछ भी इंस्टॉल या सेट अप करने की ज़रूरत नहीं।';

  @override
  String get appSigKeylessIdentity => 'कुंजी-रहित पहचान';

  @override
  String get appSigKeylessSignInExpired =>
      'आपका कुंजी-रहित साइन-इन समाप्त हो गया। कृपया फिर से साइन इन करें।';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'कुंजी-रहित साइन-इन विफल: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'कुंजी-रहित · टाइमस्टैम्प किया गया · वैधता अज्ञात';

  @override
  String get appSigKeylessWebNote =>
      'अपने ईमेल से साइन इन करना सबसे आसान तरीका है — यह DartPDF डेस्कटॉप और मोबाइल ऐप्स में उपलब्ध है। सुरक्षा कारणों से यह वेब ब्राउज़र में नहीं चल सकता।';

  @override
  String get appSigLocation => 'स्थान';

  @override
  String get appSigLogoAdded => 'लोगो जोड़ा गया ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'पृष्ठ $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'पूर्वावलोकन - हस्ताक्षरित बॉक्स थोड़ा भिन्न हो सकता है।';

  @override
  String get appSigReason => 'कारण';

  @override
  String appSigReasonLine(String reason) {
    return 'कारण: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'साइन-इन रीफ़्रेश किया जा रहा है…';

  @override
  String get appSigRemoveLogo => 'लोगो हटाएँ';

  @override
  String get appSigRemoveSignature => 'हस्ताक्षर हटाएँ';

  @override
  String get appSigSelfSignedDescription =>
      'किसी साइन-इन या फ़ाइल की ज़रूरत नहीं। व्यक्तिगत उपयोग के लिए सर्वोत्तम — इसे अगली बार के लिए इस डिवाइस पर सहेजा जाता है। कुछ PDF रीडर इसे \"हस्ताक्षरित, वैधता अज्ञात\" के रूप में दिखाएँगे, जो आपके द्वारा स्वयं बनाए गए हस्ताक्षर के लिए सामान्य है।';

  @override
  String get appSigSelfSignedIdentity => 'स्व-हस्ताक्षरित पहचान';

  @override
  String get appSigSelfSignedSubtitle => 'स्व-हस्ताक्षरित · वैधता अज्ञात';

  @override
  String get appSigShowSignatureOnPages => 'इन पृष्ठों पर हस्ताक्षर दिखाएँ';

  @override
  String get appSigSign => 'हस्ताक्षर करें';

  @override
  String get appSigSignInWithEmail => 'अपने ईमेल से साइन इन करें';

  @override
  String get appSigSignatureAdded => 'हस्ताक्षर जोड़ा गया ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '$signerName द्वारा डिजिटल रूप से हस्ताक्षरित';
  }

  @override
  String get appSigSigner => 'हस्ताक्षरकर्ता';

  @override
  String get appSigSigningYouIn => 'आपको साइन इन किया जा रहा है…';

  @override
  String get appSigThisPageOnly => 'केवल यह पृष्ठ';

  @override
  String get appSigUseOwnCertificate => 'अपना स्वयं का प्रमाणपत्र उपयोग करें';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'आपके संगठन के हस्ताक्षर प्रमाणपत्र के लिए';

  @override
  String get appSigX509Signer => 'X.509 हस्ताक्षरकर्ता';

  @override
  String get apply => 'लागू करें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get clear => 'साफ़ करें';

  @override
  String get close => 'बंद करें';

  @override
  String get copy => 'कॉपी करें';

  @override
  String get cut => 'काटें';

  @override
  String get delete => 'हटाएँ';

  @override
  String get done => 'पूर्ण';

  @override
  String get edit => 'संपादित करें';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'इन $count PDF को नए टैब में खोलें, या उनके पृष्ठ \"$title\" में डालें?',
      one: 'इस PDF को नए टैब में खोलें, या इसके पृष्ठ \"$title\" में डालें?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'छोड़ी गई PDF जोड़ें',
      one: 'छोड़ी गई PDF जोड़ें',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'एनोटेशन टेक्स्ट कॉपी किया गया';

  @override
  String get editorAppMenuTooltip => 'DartPDF मेन्यू';

  @override
  String get editorCancelOcr => 'OCR रद्द करें';

  @override
  String get editorClearRecentFiles => 'हाल की फ़ाइलें साफ़ करें';

  @override
  String get editorCloseAll => 'सभी बंद करें';

  @override
  String get editorCloseOthers => 'अन्य बंद करें';

  @override
  String get editorCloseTab => 'टैब बंद करें';

  @override
  String get editorCloseTabsToRight => 'दाईं ओर के टैब बंद करें';

  @override
  String get editorCompareFailedTitle => 'तुलना विफल';

  @override
  String editorCompareTitle(String title) {
    return 'तुलना: $title';
  }

  @override
  String get editorCopiedToClipboard => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get editorCopySelectedTextTooltip => 'चयनित टेक्स्ट कॉपी करें (⌘C)';

  @override
  String get editorCopyText => 'टेक्स्ट कॉपी करें';

  @override
  String editorCouldNotExport(String title) {
    return '$title एक्सपोर्ट नहीं कर सके';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'स्टैम्प इम्पोर्ट नहीं कर सके: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'छोड़ी गई PDF नहीं डाल सके',
      one: 'छोड़ी गई PDF नहीं डाल सके',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '$title नहीं खोल सके\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'युक्त फ़ोल्डर नहीं खोल सके';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'दूसरी फ़ाइल नहीं खोल सके\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'चयनित फ़ाइल नहीं खोल सके\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '$url नहीं खोल सके';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '$title प्रिंट नहीं कर सके';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '$title फिर से नहीं खोल सके';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'डिजिटल रूप से हस्ताक्षर नहीं कर सके: $error';
  }

  @override
  String get editorDiscard => 'छोड़ें';

  @override
  String get editorDiscardChangesTitle => 'बदलाव छोड़ें?';

  @override
  String get editorDocumentSigned => 'दस्तावेज़ डिजिटल रूप से हस्ताक्षरित';

  @override
  String get editorDownload => 'डाउनलोड करें';

  @override
  String get editorDropToOpen => 'खोलने के लिए PDF छोड़ें';

  @override
  String get editorDropToOpenOrInsert => 'खोलने या डालने के लिए PDF छोड़ें';

  @override
  String get editorInsertPages => 'पृष्ठ डालें';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count डाले गए; $files नहीं पढ़ सके';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$title में $count PDF डाले गए',
      one: '$title में पृष्ठ डाले गए',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'अमान्य लिंक: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'इस दस्तावेज़ ने JavaScript चलाने का प्रयास किया (अनदेखा किया गया)';

  @override
  String get editorLoadingFullDocument => 'पूरा दस्तावेज़ लोड हो रहा है';

  @override
  String get editorMenuCompareWith => 'इससे तुलना करें…';

  @override
  String get editorMenuDigitallySign => 'डिजिटल रूप से हस्ताक्षर करें…';

  @override
  String get editorMenuDigitallySigning =>
      'डिजिटल रूप से हस्ताक्षर किया जा रहा है…';

  @override
  String get editorMenuExportImage => 'पृष्ठ को छवि के रूप में एक्सपोर्ट करें…';

  @override
  String get editorMenuNewDocument => 'नया दस्तावेज़…';

  @override
  String get editorMenuNewWindow => 'नई विंडो';

  @override
  String get editorMoveToNewWindow => 'नई विंडो में ले जाएँ';

  @override
  String get editorUnableToOpenNewWindow => 'नई विंडो नहीं खोली जा सकी';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'PDF खोलें…';

  @override
  String get editorMenuPrint => 'प्रिंट करें…';

  @override
  String get editorMenuSaveAs => 'इस रूप में सहेजें…';

  @override
  String get editorMenuScanDocument => 'नए दस्तावेज़ में स्कैन करें…';

  @override
  String get editorMenuInsertScan => 'स्कैन डालें…';

  @override
  String get editorScanFailed => 'दस्तावेज़ स्कैन नहीं किया जा सका।';

  @override
  String get editorInsertedScan => 'स्कैन किए गए पृष्ठ जोड़े गए।';

  @override
  String get editorMenuSettings => 'सेटिंग्स';

  @override
  String get editorMenuSwitchToEdit => 'संपादन मोड में जाएँ';

  @override
  String get editorMenuSwitchToReadOnly => 'केवल-पढ़ने में जाएँ';

  @override
  String editorNamedAction(String name) {
    return 'नामित क्रिया: $name';
  }

  @override
  String get editorNoRecentFiles => 'कोई हाल की फ़ाइल नहीं';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'OCR चलाने से पहले कोई दस्तावेज़ खोलें';

  @override
  String get editorOpenFailedTitle => 'खोलना विफल';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'नए टैब में खोलें',
      one: 'नए टैब में खोलें',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'PDF को नए टैब में खोलें';

  @override
  String get editorOpenRecent => 'हाल ही में खोले गए';

  @override
  String get editorOpenTabs => 'खुले टैब';

  @override
  String get editorOpeningDocumentSemantic => 'दस्तावेज़ खोला जा रहा है';

  @override
  String get editorOpeningPdf => 'PDF खोला जा रहा है…';

  @override
  String editorOpeningTitle(String title) {
    return '$title खोला जा रहा है…';
  }

  @override
  String editorPageNumber(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String get editorPreviewComparison => 'तुलना';

  @override
  String get editorPreviewCouldNotOpen => 'नहीं खोल सके';

  @override
  String get editorPreviewOpening => 'खोला जा रहा है';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'पिछले सत्र के $count दस्तावेज़ों में सहेजे न गए बदलाव पुनर्प्राप्त किए गए।',
      one: 'पिछले सत्र के सहेजे न गए बदलाव पुनर्प्राप्त किए गए।',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'हस्ताक्षर हटाया गया';

  @override
  String get editorSnapshotCopied => 'स्नैपशॉट क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get editorSnapshotCopyFailed =>
      'स्नैपशॉट क्लिपबोर्ड पर कॉपी नहीं कर सके';

  @override
  String get editorTabs => 'टैब';

  @override
  String editorTabsOpenCount(int count) {
    return '$count खुले';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count दस्तावेज़ों में असहेजे बदलाव हैं।',
      one: 'एक दस्तावेज़ में असहेजे बदलाव हैं।',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'असमर्थित क्रिया: $type';
  }

  @override
  String get editorUntitled => 'बिना शीर्षक';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version उपलब्ध है।';
  }

  @override
  String get editorUpdateLater => 'बाद में';

  @override
  String get updateInstallNow => 'अभी अपडेट करें';

  @override
  String get updateDownloadingTitle => 'अपडेट डाउनलोड हो रहा है';

  @override
  String get updatePreparing => 'तैयार हो रहा है…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'डाउनलोड हो रहा है… $percent%';
  }

  @override
  String get updateRestarting => 'अपडेट पूरा करने के लिए पुनरारंभ हो रहा है…';

  @override
  String get updateHandedOff =>
      'अपडेट डाउनलोड हो गया. इंस्टॉलर खोला जा रहा है…';

  @override
  String updateFailed(String error) {
    return 'अपडेट विफल: $error';
  }

  @override
  String get editorViewAllTabs => 'सभी टैब देखें';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'एक्सपोर्ट करें';

  @override
  String get imgExportFormat => 'फ़ॉर्मेट';

  @override
  String get imgExportResolution => 'रिज़ॉल्यूशन';

  @override
  String get imgExportTitle => 'पृष्ठ को छवि के रूप में एक्सपोर्ट करें';

  @override
  String get newDocCreate => 'बनाएँ';

  @override
  String get newDocLandscape => 'लैंडस्केप';

  @override
  String get newDocOrientation => 'अभिविन्यास';

  @override
  String get newDocPageSize => 'पृष्ठ आकार';

  @override
  String get newDocPortrait => 'पोर्ट्रेट';

  @override
  String get newDocTitle => 'नया दस्तावेज़';

  @override
  String get none => 'कोई नहीं';

  @override
  String get ocrAlreadyRunning =>
      'OCR पहले से चल रहा है - इसके पूरा होने की प्रतीक्षा करें या इसे रद्द करें';

  @override
  String get ocrBrowserInitFailed => 'ब्राउज़र OCR आरंभ नहीं हो सका';

  @override
  String get ocrCancelled => 'OCR रद्द किया गया';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count टेक्स्ट स्पैन के बाद OCR रद्द किया गया',
      one: '1 टेक्स्ट स्पैन के बाद OCR रद्द किया गया',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'डाउनलोड करें';

  @override
  String ocrDownloadFailed(String error) {
    return 'OCR मॉडल डाउनलोड नहीं कर सके: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'चयन योग्य टेक्स्ट परत जोड़ने के लिए डिवाइस पर OCR मॉडल$size की ज़रूरत है। यह एक बार डाउनलोड होता है और फिर ऑफ़लाइन चलता है।\n\nमॉडल: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR मॉडल डाउनलोड करें?';

  @override
  String ocrFailed(String error) {
    return 'OCR विफल: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'इस प्लेटफ़ॉर्म पर डिवाइस-आधारित OCR उपलब्ध नहीं है';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR ने $count टेक्स्ट स्पैन जोड़े - पृष्ठ का टेक्स्ट अब चयन योग्य है',
      one: 'OCR ने 1 टेक्स्ट स्पैन जोड़ा - पृष्ठ का टेक्स्ट अब चयन योग्य है',
      zero: 'OCR को इन पृष्ठों पर कोई टेक्स्ट नहीं मिला',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'वेब OCR एक Florence-2 विज़न-लैंग्वेज मॉडल डाउनलोड करता है और इसे Transformers.js के माध्यम से WebGPU/WASM के साथ स्थानीय रूप से चलाता है। PDF पृष्ठ इसी ब्राउज़र में रहते हैं; केवल मॉडल फ़ाइलें पहली बार उपयोग पर लाई जाती हैं।';

  @override
  String get ocrWebPromptTitle => 'इस ब्राउज़र में AI OCR चलाएँ?';

  @override
  String get ocrWebStart => 'OCR शुरू करें';

  @override
  String get ok => 'ठीक है';

  @override
  String get paste => 'पेस्ट करें';

  @override
  String get printDlgPreparing => 'तैयार किया जा रहा है…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '$total में से पृष्ठ $rendered रेंडर हो रहा है…';
  }

  @override
  String get printDlgTitle => 'प्रिंट किया जा रहा है';

  @override
  String get printPreviewAll => 'सभी';

  @override
  String get printPreviewCurrent => 'वर्तमान';

  @override
  String get printPreviewFrom => 'से';

  @override
  String get printPreviewNextPage => 'अगला पृष्ठ';

  @override
  String printPreviewPageOf(int page, int total) {
    return '$total में से पृष्ठ $page';
  }

  @override
  String get printPreviewPreviousPage => 'पिछला पृष्ठ';

  @override
  String get printPreviewPrint => 'प्रिंट करें';

  @override
  String get printPreviewRange => 'श्रेणी';

  @override
  String printPreviewRangeError(int total) {
    return '1 और $total के बीच पृष्ठ श्रेणी दर्ज करें।';
  }

  @override
  String printPreviewSelection(int count) {
    return 'प्रिंट किए जाने वाले पृष्ठ: $count';
  }

  @override
  String get printPreviewTitle => 'प्रिंट पूर्वावलोकन';

  @override
  String get printPreviewTo => 'तक';

  @override
  String get printPreviewUnavailable => 'पूर्वावलोकन उपलब्ध नहीं';

  @override
  String get redo => 'फिर से करें';

  @override
  String get remove => 'निकालें';

  @override
  String get rename => 'नाम बदलें';

  @override
  String get reset => 'रीसेट करें';

  @override
  String get save => 'सहेजें';

  @override
  String get settingsAbout => 'परिचय';

  @override
  String get settingsAppearance => 'रूप';

  @override
  String get settingsCheckNow => 'अभी जाँचें';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageSystem => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get settingsCheckingForUpdates => 'अपडेट की जाँच हो रही है…';

  @override
  String get settingsCouldNotOpenDownload => 'डाउनलोड नहीं खोल सके';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'सिस्टम सेटिंग्स नहीं खोल सके';

  @override
  String get settingsDeveloperTools => 'डेवलपर टूल';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'मेट्रिक्स, लॉग, रेंडर मोड (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version डाउनलोड करें';
  }

  @override
  String get settingsOpenSettings => 'सेटिंग्स खोलें';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count याद रखी गईं',
      one: '1 याद रखी गई',
      zero: 'कोई हाल की फ़ाइल नहीं',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'हाल की फ़ाइलें';

  @override
  String get settingsSetUpAsDefault => 'डिफ़ॉल्ट एप्लिकेशन के रूप में सेट करें';

  @override
  String get settingsSystem => 'सिस्टम';

  @override
  String get settingsThemeDark => 'डार्क';

  @override
  String get settingsThemeLight => 'लाइट';

  @override
  String get settingsThemeSystem => 'सिस्टम';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String settingsUpToDate(String version) {
    return 'आप नवीनतम संस्करण ($version) पर हैं।';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'संस्करण $version उपलब्ध है (आपके पास $currentVersion है)।';
  }

  @override
  String get settingsUpdateFailed =>
      'अपडेट की जाँच नहीं कर सके। बाद में पुनः प्रयास करें।';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'आपके पास $name $version है।';
  }

  @override
  String get settingsNightlyUpdates => 'नाइटली अपडेट';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'main से बिना हस्ताक्षर वाले Windows परीक्षण बिल्ड के लिए स्वचालित अपडेट सूचनाएँ पाएँ।';

  @override
  String get settingsUpdates => 'अपडेट';

  @override
  String get settingsViewSource => 'GitHub पर स्रोत देखें';

  @override
  String get undo => 'पूर्ववत करें';

  @override
  String get welcomeOpenPdf => 'PDF खोलें';

  @override
  String get welcomePickAgainToReopen => 'फिर से खोलने के लिए दोबारा चुनें';

  @override
  String get welcomeRecent => 'हाल ही में';

  @override
  String get welcomeRemoveFromRecent => 'हाल से हटाएँ';

  @override
  String get welcomeTapToReopen => 'फिर से खोलने के लिए टैप करें';

  @override
  String get welcomeViewAsGrid => 'ग्रिड दृश्य';

  @override
  String get welcomeViewAsList => 'सूची दृश्य';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'वेब ऐप इंस्टॉल करें, फिर इसे PDF फ़ाइलों के लिए चुनें।',
        'windows': 'PDF के लिए Windows डिफ़ॉल्ट ऐप्स सेटिंग्स खोलें।',
        'macos': 'Finder के “Always Open With” चरणों का पालन करें।',
        'linux': 'अपने डेस्कटॉप की डिफ़ॉल्ट एप्लिकेशन सेटिंग्स का उपयोग करें।',
        'android': 'PDF खोलते समय DartPDF चुनें, फिर Always टैप करें।',
        'ios': 'PDF यहाँ भेजने के लिए Files से Share या Open In का उपयोग करें।',
        'other': 'अपने सिस्टम का PDF फ़ाइल हैंडलर कॉन्फ़िगर करें।',
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
            'पहले अपने ब्राउज़र से DartPDF इंस्टॉल करें। फिर PDF फ़ाइलों को इंस्टॉल किए गए ऐप से जोड़ने के लिए ब्राउज़र या ऑपरेटिंग सिस्टम की फ़ाइल-हैंडलर सेटिंग्स का उपयोग करें।',
        'windows':
            'Windows सेटिंग्स Default apps पर खुलेंगी। “.pdf” या “PDF” खोजें, वर्तमान PDF ऐप चुनें, फिर DartPDF चुनें।',
        'macos':
            'Finder में, कोई भी PDF चुनें, File > Get Info चुनें, “Open with” विस्तृत करें, DartPDF चुनें, फिर “Change All…” पर क्लिक करें।',
        'linux':
            'Default Applications के लिए अपनी डेस्कटॉप सेटिंग्स खोलें, या Files में किसी PDF पर राइट-क्लिक करें, Properties चुनें, और DartPDF को PDF दस्तावेज़ों के लिए डिफ़ॉल्ट के रूप में सेट करें।',
        'android':
            'Files या Downloads से कोई PDF खोलें, ऐप पिकर में DartPDF चुनें, फिर Always चुनें। यदि कोई अन्य ऐप पहले से PDF खोलता है, तो पहले Android सेटिंग्स में उस ऐप के डिफ़ॉल्ट साफ़ करें।',
        'ios':
            'iOS कोई वैश्विक डिफ़ॉल्ट PDF संपादक प्रदान नहीं करता। Files > Share का उपयोग करें, या किसी PDF को लंबे समय तक दबाएँ और Share/Open In चुनें, फिर DartPDF चुनें।',
        'other':
            'PDF दस्तावेज़ों को DartPDF से जोड़ने के लिए फ़ाइल हैंडलर की सिस्टम सेटिंग्स का उपयोग करें।',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR मॉडल डाउनलोड हो रहा है…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'मॉडल डाउनलोड हो रहा है $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR पूरा किया जा रहा है…';

  @override
  String get fileTypePdf => 'PDF दस्तावेज़';

  @override
  String get fileTypeImages => 'छवियाँ';

  @override
  String get fileTypeStampBundle => 'DartPDF स्टैम्प';

  @override
  String get appSigKeyFileType => 'RSA निजी कुंजियाँ';

  @override
  String get appSigCertificateFileType => 'X.509 प्रमाणपत्र';

  @override
  String get appSigErrorNoCertificateSelected =>
      'कम से कम एक X.509 प्रमाणपत्र चुनें।';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'प्रमाणपत्र $index मान्य X.509 नहीं है।';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'निजी कुंजी किसी भी चयनित RSA प्रमाणपत्र से मेल नहीं खाती।';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'एन्क्रिप्टेड निजी कुंजियाँ समर्थित नहीं हैं। कोई अनएन्क्रिप्टेड RSA PKCS#1 या PKCS#8 कुंजी चुनें।';

  @override
  String get appSigErrorKeyNotRsa =>
      'निजी कुंजी अनएन्क्रिप्टेड RSA PKCS#1 या PKCS#8 कुंजी नहीं है।';

  @override
  String get appSigErrorNoCertificateFound => 'कोई X.509 प्रमाणपत्र नहीं मिला।';

  @override
  String get imageSourceTakePhoto => 'फ़ोटो लें';

  @override
  String get imageSourceChooseFile => 'फ़ाइल चुनें';

  @override
  String get imageSourceCameraFailed => 'फ़ोटो नहीं ली जा सकी';
}
