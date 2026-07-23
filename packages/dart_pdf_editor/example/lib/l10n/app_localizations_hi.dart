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
  String exActionJavaScript(String script) {
    return 'ऐप को दिखाया गया JavaScript: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'लिंक: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'नामित क्रिया: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'असमर्थित क्रिया प्रकार: $type';
  }

  @override
  String get exAnnotationTextCopied => 'एनोटेशन टेक्स्ट कॉपी किया गया';

  @override
  String get exApiKeyHelper => 'Authorization: Bearer … के रूप में भेजा गया';

  @override
  String get exApiKeyLabel => 'API कुंजी / टोकन (वैकल्पिक)';

  @override
  String get exAppMenuTooltip => 'DartPDF मेन्यू';

  @override
  String get exClearRecentFiles => 'हाल की फ़ाइलें साफ़ करें';

  @override
  String get exCloseTab => 'टैब बंद करें';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'तुलना करें: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'किसी अन्य PDF से तुलना करें…';

  @override
  String get exCopiedToClipboard => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get exCopySelectedText => 'चयनित टेक्स्ट कॉपी करें (⌘C)';

  @override
  String get exCopyText => 'टेक्स्ट कॉपी करें';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '$name नहीं खोल सके\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '$path नहीं खोल सके\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '$url नहीं खोल सके';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '$uri नहीं खोल सके\n$error\n\nवेब पर यह अक्सर एक CORS प्रतिबंध होता है: सर्वर को Access-Control-Allow-Origin भेजना चाहिए और Range हेडर उजागर करने चाहिए।';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '$title फिर से नहीं खोल सके\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '$title फिर से नहीं खोल सके - इसकी सहेजी गई प्रति अब उपलब्ध नहीं है।';
  }

  @override
  String get exDemoNoteHint =>
      'यहाँ टाइप करें - यह टेक्स्ट बॉक्स पृष्ठ के ऊपर तैरता है';

  @override
  String get exDiagnosticsCopied => 'डायग्नोस्टिक्स क्लिपबोर्ड पर कॉपी किए गए';

  @override
  String exDownloaded(String name) {
    return '$name डाउनलोड किया गया';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name डाउनलोड किया गया - Ctrl+V से इसे वापस PDF में पेस्ट करें';
  }

  @override
  String get exExport => 'एक्सपोर्ट करें';

  @override
  String exExportFailed(String error) {
    return 'एक्सपोर्ट विफल: $error';
  }

  @override
  String get exExportPageImageMenu => 'पृष्ठ को छवि के रूप में एक्सपोर्ट करें…';

  @override
  String get exExportPageImageTitle => 'पृष्ठ को छवि के रूप में एक्सपोर्ट करें';

  @override
  String get exFeatureShowcase => 'फ़ीचर शोकेस';

  @override
  String get exFormat => 'फ़ॉर्मेट';

  @override
  String get exHide => 'छिपाएँ';

  @override
  String get exHorizontalLayout => 'क्षैतिज पृष्ठ लेआउट';

  @override
  String get exHowToSetupOcr => 'OCR सर्वर कैसे सेट करें';

  @override
  String get exModelName => 'मॉडल नाम';

  @override
  String get exNoMessage => 'कोई संदेश नहीं';

  @override
  String get exNoRecentFiles => 'कोई हाल की फ़ाइल नहीं';

  @override
  String exNotAValidUrl(String url) {
    return 'मान्य URL नहीं:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR ने $count टेक्स्ट स्पैन जोड़े - पृष्ठ का टेक्स्ट अब चयन योग्य है',
      one: 'OCR ने 1 टेक्स्ट स्पैन जोड़ा - पृष्ठ का टेक्स्ट अब चयन योग्य है',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'आपके द्वारा होस्ट किए गए विज़न-लैंग्वेज OCR मॉडल (vLLM पर dots.ocr, या कोई भी OpenAI-संगत OCR एंडपॉइंट) का उपयोग करके स्कैन किए गए पृष्ठों पर एक चयन योग्य, खोजने योग्य टेक्स्ट परत जोड़ता है।';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR विफल: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'खोलें';

  @override
  String get exOpenDocumentBeforeOcr => 'OCR चलाने से पहले कोई दस्तावेज़ खोलें';

  @override
  String get exOpenDocumentFirst => 'पहले कोई दस्तावेज़ खोलें';

  @override
  String get exOpenFromUrl => 'URL से खोलें…';

  @override
  String get exOpenFromUrlTitle => 'URL से खोलें';

  @override
  String get exOpenInNewTab => 'PDF को नए टैब में खोलें';

  @override
  String get exOpenInteractiveDemo => 'इंटरैक्टिव डेमो खोलें';

  @override
  String get exOpenPdf => 'PDF खोलें…';

  @override
  String get exOpenPdfButton => 'PDF खोलें';

  @override
  String get exOpenRecent => 'हाल ही में खोले गए';

  @override
  String get exOpenUrlDescription =>
      'PdfHttpByteSource के माध्यम से HTTP Range अनुरोधों पर PDF स्ट्रीम करता है, केवल वही लाता है जो पार्सर को चाहिए, और सर्वर पर रेंज समर्थन न होने पर पूर्ण डाउनलोड पर वापस लौट आता है।';

  @override
  String get exOpeningDocument => 'दस्तावेज़ खोला जा रहा है';

  @override
  String get exOpeningPdf => 'PDF खोला जा रहा है…';

  @override
  String exOpeningTitle(String title) {
    return '$title खोला जा रहा है…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => 'प्रदर्शन: स्वतः';

  @override
  String get exPreparing => 'तैयार किया जा रहा है…';

  @override
  String get exPubDevMenuItem => 'pub.dev पर dart_pdf_editor';

  @override
  String exRecognisingPage(int current, int count) {
    return 'पृष्ठ $current / $count पहचाना जा रहा है…';
  }

  @override
  String get exResolution => 'रिज़ॉल्यूशन';

  @override
  String get exRunOcr => 'OCR चलाएँ';

  @override
  String get exSaveAs => 'इस रूप में सहेजें…';

  @override
  String exSaveFailed(String error) {
    return 'सहेजना विफल: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name सहेजा गया';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name सहेजा गया - ⌘V से इसे वापस PDF में पेस्ट करें';
  }

  @override
  String exSavedTo(String path) {
    return '$path पर सहेजा गया';
  }

  @override
  String get exScrollIndicatorDemo => 'स्क्रॉल इंडिकेटर API डेमो';

  @override
  String get exServiceEndpoint => 'सेवा एंडपॉइंट';

  @override
  String get exShow => 'दिखाएँ';

  @override
  String get exSingleWorker => 'एकल वर्कर';

  @override
  String get exSupplyFeedback => 'फ़ीडबैक दें…';

  @override
  String get exSwitchToEdit => 'संपादन मोड में जाएँ';

  @override
  String get exSwitchToReadOnly => 'केवल-पढ़ने में जाएँ';

  @override
  String get exThemeDark => 'थीम: डार्क - सिस्टम पर स्विच करें';

  @override
  String get exThemeLight => 'थीम: लाइट - डार्क पर स्विच करें';

  @override
  String get exThemeSystem => 'थीम: सिस्टम - लाइट पर स्विच करें';

  @override
  String get exTryDemo => 'इंटरैक्टिव डेमो आज़माएँ';

  @override
  String get exUntitled => 'बिना शीर्षक';

  @override
  String get exVerticalLayout => 'लंबवत पृष्ठ लेआउट';

  @override
  String get exViewSource => 'GitHub पर स्रोत देखें';

  @override
  String get exWorkerAuto => 'स्वतः';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'प्रदर्शन: $count वर्कर',
      one: 'प्रदर्शन: एकल वर्कर',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count वर्कर';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'इन डायग्नोस्टिक्स को रिपोर्ट में संलग्न करें';

  @override
  String get feedbackClearLog => 'लॉग साफ़ करें';

  @override
  String get feedbackCopyDiagnostics => 'डायग्नोस्टिक्स कॉपी करें';

  @override
  String get feedbackDiagnosticsNotice =>
      'फ़ीडबैक फ़ॉर्म आपके ब्राउज़र में खुलता है। नीचे दिए गए डायग्नोस्टिक्स केवल इस डिवाइस पर एकत्र किए जाते हैं और समस्या को दोहराने में मदद के लिए संलग्न किए जाते हैं। पहले इन्हें देख लें - ऐसा कुछ भी शामिल न करें जिसे आप निजी रखना चाहें।';

  @override
  String get feedbackOpenForm => 'फ़ीडबैक फ़ॉर्म खोलें';

  @override
  String get feedbackTitle => 'फ़ीडबैक भेजें';

  @override
  String get none => 'कोई नहीं';

  @override
  String get ok => 'ठीक है';

  @override
  String get paste => 'पेस्ट करें';

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
  String get scrollDemoNextPage => 'अगला पृष्ठ';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'पृष्ठ $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'पिछला पृष्ठ';

  @override
  String get scrollDemoSwitchHorizontal => 'क्षैतिज लेआउट पर स्विच करें';

  @override
  String get scrollDemoSwitchVertical => 'लंबवत लेआउट पर स्विच करें';

  @override
  String get scrollDemoTitle => 'स्क्रॉल इंडिकेटर API';

  @override
  String get undo => 'पूर्ववत करें';

  @override
  String get exFileTypePdf => 'PDF दस्तावेज़';

  @override
  String get exFileTypeImages => 'छवियाँ';

  @override
  String get exFileTypeFonts => 'फ़ॉन्ट';
}
