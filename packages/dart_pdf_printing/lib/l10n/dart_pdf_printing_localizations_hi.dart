// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class DartPdfPrintingLocalizationsHi extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get cancel => 'रद्द करें';

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
  String get printPreviewUnavailable => 'पूर्वावलोकन उपलब्ध नहीं';

  @override
  String get printOptionsPrinter => 'प्रिंटर';

  @override
  String get printOptionsNativePrinter =>
      'अगले सिस्टम प्रिंट संवाद में प्रिंटर, पेपर ट्रे, रंग, दोतरफ़ा प्रिंटिंग और डिवाइस के गुण चुनें। यहाँ दिखाए गए लेआउट का उपयोग करने के लिए स्केल 100% और प्रतियों की संख्या 1 ही रखें।';

  @override
  String get printOptionsPages => 'पृष्ठ';

  @override
  String get printOptionsSelected => 'चुने गए';

  @override
  String get printOptionsPageRange => 'पृष्ठ (उदाहरण के लिए, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'फ़ाइलें जोड़ें…';

  @override
  String get printOptionsAddFailed => 'चुनी गई फ़ाइलें जोड़ी नहीं जा सकीं।';

  @override
  String get printOptionsGetWindow => 'क्षेत्र चुनें';

  @override
  String get printOptionsClearWindow => 'क्षेत्र हटाएँ';

  @override
  String get printOptionsWindowHint =>
      'प्रिंट करने का क्षेत्र चुनने के लिए इस मूल पृष्ठ पर खींचकर एक आयत बनाएँ।';

  @override
  String get printOptionsPaper => 'कागज़';

  @override
  String get printOptionsPaperSize => 'कागज़ का आकार';

  @override
  String get printOptionsPageSize => 'दस्तावेज़ के पृष्ठ का आकार उपयोग करें';

  @override
  String get printOptionsOrientation => 'ओरिएंटेशन';

  @override
  String get printOptionsAuto => 'अपने आप';

  @override
  String get printOptionsPortrait => 'पोर्ट्रेट';

  @override
  String get printOptionsLandscape => 'लैंडस्केप';

  @override
  String get printOptionsCopies => 'प्रतियाँ';

  @override
  String get printOptionsCollate => 'प्रतियाँ क्रम में रखें';

  @override
  String get printOptionsReverse => 'पृष्ठों का क्रम उलटें';

  @override
  String get printOptionsLayout => 'पृष्ठ लेआउट';

  @override
  String get printOptionsScaling => 'पृष्ठ का स्केल';

  @override
  String get printOptionsScaleNone => 'कोई नहीं (वास्तविक आकार)';

  @override
  String get printOptionsFitPaper => 'कागज़ के अनुसार फ़िट करें';

  @override
  String get printOptionsReducePaper => 'कागज़ में फ़िट करने के लिए छोटा करें';

  @override
  String get printOptionsFitMargins => 'मार्जिन के भीतर फ़िट करें';

  @override
  String get printOptionsReduceMargins =>
      'मार्जिन में फ़िट करने के लिए छोटा करें';

  @override
  String get printOptionsCustomScale => 'कस्टम स्केल';

  @override
  String get printOptionsMultiple => 'प्रति शीट कई पृष्ठ';

  @override
  String get printOptionsScalePercent => 'स्केल (%)';

  @override
  String get printOptionsMargin => 'मार्जिन (पॉइंट)';

  @override
  String get printOptionsPagesPerSheet => 'प्रति शीट पृष्ठ';

  @override
  String get printOptionsPageOrder => 'पृष्ठों का क्रम';

  @override
  String get printOptionsHorizontal => 'क्षैतिज';

  @override
  String get printOptionsHorizontalReverse => 'उलटा क्षैतिज क्रम';

  @override
  String get printOptionsVertical => 'लंबवत';

  @override
  String get printOptionsVerticalReverse => 'उलटा लंबवत क्रम';

  @override
  String get printOptionsBorder => 'पृष्ठों के बॉर्डर प्रिंट करें';

  @override
  String get printOptionsRotation => 'घुमाव (घड़ी की दिशा में)';

  @override
  String get printOptionsNoRotation => 'कोई नहीं';

  @override
  String get printOptionsCenter => 'कागज़ के बीच में रखें';

  @override
  String get printOptionsOffsetX => 'दाईं ओर खिसकाएँ (पॉइंट)';

  @override
  String get printOptionsOffsetY => 'नीचे खिसकाएँ (पॉइंट)';

  @override
  String get printOptionsContents => 'प्रिंट सामग्री';

  @override
  String get printOptionsDocumentAndMarkups => 'दस्तावेज़ और टिप्पणियाँ';

  @override
  String get printOptionsDocumentOnly => 'केवल दस्तावेज़';

  @override
  String get printOptionsMarkupsOnly => 'केवल टिप्पणियाँ';

  @override
  String get printOptionsDimPage => 'पृष्ठ की सामग्री हल्की करें';

  @override
  String get printOptionsDimMarkups => 'टिप्पणियाँ हल्की करें';

  @override
  String get printOptionsHyperlinks => 'दिखाई देने वाले हाइपरलिंक प्रिंट करें';

  @override
  String get printOptionsDefaults => 'डिफ़ॉल्ट';

  @override
  String get printOptionsInvalidNumber =>
      'प्रिंट करने से पहले मान्य संख्याएँ दर्ज करें।';

  @override
  String get printOptionsInvalidValue => 'अमान्य मान';

  @override
  String get printOptionsMarginGuide =>
      'लाल रेखाएँ मार्जिन दिखाती हैं; वे प्रिंट नहीं होंगी।';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'क्षेत्र: $width × $height पॉइंट';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'मूल: $width × $height पॉइंट';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'शीट: $width × $height पॉइंट';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'शीट $sheet / $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'यह लेआउट तैयार नहीं किया जा सका। कागज़ का आकार, मार्जिन और स्केल जाँचें।';

  @override
  String get printOptionsChoosePrinter => 'प्रिंटर चुनें';

  @override
  String get printOptionsNoPrinters =>
      'कोई प्रिंटर इंस्टॉल नहीं है। Windows सेटिंग्स में प्रिंटर जोड़ें, फिर दोबारा कोशिश करें।';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'सहेजा गया प्रिंटर “$printer” उपलब्ध नहीं है। जारी रखने के लिए प्रिंटर चुनें।';
  }

  @override
  String get printOptionsPrinterError =>
      'प्रिंटर सेटिंग्स लोड नहीं हो सकीं। प्रिंटर का कनेक्शन जाँचें और दोबारा कोशिश करें।';

  @override
  String get printOptionsRetry => 'फिर कोशिश करें';

  @override
  String get printOptionsColor => 'रंगीन';

  @override
  String get printOptionsGrayscale => 'श्वेत-श्याम';

  @override
  String get printOptionsDuplex => 'दोनों तरफ़ प्रिंट करें';

  @override
  String get printOptionsSimplex => 'एक तरफ़';

  @override
  String get printOptionsLongEdge => 'लंबे किनारे पर पलटें';

  @override
  String get printOptionsShortEdge => 'छोटे किनारे पर पलटें';

  @override
  String get printOptionsTray => 'पेपर ट्रे';

  @override
  String get printOptionsDefaultTray => 'प्रिंटर का डिफ़ॉल्ट';

  @override
  String get printOptionsProperties => 'प्रिंटर गुण…';

  @override
  String get printOptionsDirectPrinter =>
      'प्रिंट दबाने पर यह कार्य सीधे चुने गए प्रिंटर को भेजा जाता है।';

  @override
  String get printOptionsPropertiesError => 'प्रिंटर गुण नहीं खोले जा सके।';

  @override
  String get printOptionsLoadingPrinters => 'प्रिंटर लोड हो रहे हैं…';
}
