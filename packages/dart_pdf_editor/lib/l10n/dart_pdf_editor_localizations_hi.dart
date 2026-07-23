// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class DartPdfEditorLocalizationsHi extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get add => 'जोड़ें';

  @override
  String get annotCaret => 'कैरेट';

  @override
  String get annotCircle => 'वृत्त';

  @override
  String get annotFileAttachment => 'फ़ाइल अटैचमेंट';

  @override
  String get annotFreeText => 'टेक्स्ट बॉक्स';

  @override
  String get annotHighlight => 'हाइलाइट';

  @override
  String get annotInk => 'इंक';

  @override
  String get annotLine => 'रेखा';

  @override
  String get annotLink => 'लिंक';

  @override
  String get annotPolygon => 'बहुभुज';

  @override
  String get annotPolyline => 'पॉलीलाइन';

  @override
  String get annotRedact => 'रिडैक्शन';

  @override
  String get annotSquare => 'वर्ग';

  @override
  String get annotSquiggly => 'लहरदार';

  @override
  String get annotStamp => 'स्टैम्प';

  @override
  String get annotStrikeOut => 'स्ट्राइक-आउट';

  @override
  String get annotText => 'नोट';

  @override
  String get annotUnderline => 'रेखांकन';

  @override
  String get annotWidget => 'फ़ॉर्म फ़ील्ड';

  @override
  String get apply => 'लागू करें';

  @override
  String get bookmarkAdd => 'बुकमार्क जोड़ें';

  @override
  String get bookmarkAddChild => 'चाइल्ड बुकमार्क जोड़ें';

  @override
  String get bookmarkCollapse => 'संक्षिप्त करें';

  @override
  String get bookmarkDelete => 'बुकमार्क हटाएँ';

  @override
  String get bookmarkEdit => 'बुकमार्क संपादित करें';

  @override
  String get bookmarkEmpty => 'कोई बुकमार्क नहीं';

  @override
  String get bookmarkExpand => 'विस्तृत करें';

  @override
  String get bookmarkExpandedByDefault => 'डिफ़ॉल्ट रूप से विस्तृत';

  @override
  String get bookmarkNoDestination => 'कोई गंतव्य नहीं';

  @override
  String get bookmarkPageFieldLabel => 'पृष्ठ';

  @override
  String bookmarkPageLabel(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'बुकमार्क';

  @override
  String get bookmarkTitleLabel => 'शीर्षक';

  @override
  String get bookmarkUntitled => 'बिना शीर्षक';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get clear => 'साफ़ करें';

  @override
  String get close => 'बंद करें';

  @override
  String get colorApplyingChanges => 'रंग बदलाव लागू किए जा रहे हैं…';

  @override
  String get colorColorFormat => 'रंग फ़ॉर्मेट';

  @override
  String get colorColorTitle => 'रंग';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count रंग चयनित',
      one: '$count रंग चयनित',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'दस्तावेज़ के रंग';

  @override
  String get colorFillColors => 'भरण रंग';

  @override
  String get colorFind => 'खोजें';

  @override
  String get colorInDocument => 'दस्तावेज़ में';

  @override
  String get colorNoColorsFound => 'अभी तक कोई रंग नहीं मिला';

  @override
  String get colorNoPageContentColors => 'कोई पृष्ठ-सामग्री रंग नहीं मिला';

  @override
  String get colorPalette => 'पैलेट';

  @override
  String get colorPickColor => 'रंग चुनें';

  @override
  String get colorProcessingTitle => 'रंग प्रसंस्करण';

  @override
  String get colorRecent => 'हाल के';

  @override
  String get colorReplace => 'बदलें';

  @override
  String get colorReplaceWithTransparent => 'पारदर्शी से बदलें';

  @override
  String get colorScanning => 'स्कैन हो रहा है…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'स्कैन हो रहा है $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'चयनित पृष्ठ ($count)';
  }

  @override
  String get colorStrokeColors => 'स्ट्रोक रंग';

  @override
  String get colorTolerance => 'सहनशीलता';

  @override
  String get colorTransparent => 'पारदर्शी';

  @override
  String get colorWholeDocument => 'संपूर्ण दस्तावेज़';

  @override
  String get compareAfter => 'बाद';

  @override
  String get compareBefore => 'पहले';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदलाव',
      one: '1 बदलाव',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count बदलाव',
      one: '1 बदलाव',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(खाली)';

  @override
  String get compareNextChange => 'अगला बदलाव';

  @override
  String get compareNoChanges => 'कोई बदलाव नहीं';

  @override
  String get compareNoDifferences => 'दोनों दस्तावेज़ों के बीच कोई अंतर नहीं';

  @override
  String get compareOverlay => 'ओवरले';

  @override
  String comparePageHeader(int page) {
    return 'पृष्ठ $page';
  }

  @override
  String get comparePreviousChange => 'पिछला बदलाव';

  @override
  String get compareSideBySide => 'साथ-साथ';

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
  String get editorViewAuthorNameTitle => 'लेखक का नाम';

  @override
  String get lineStyleDashDot => 'डैश-डॉट';

  @override
  String get lineStyleDashed => 'धराशायी';

  @override
  String get lineStyleDotted => 'बिंदुदार';

  @override
  String get lineStyleSolid => 'ठोस';

  @override
  String get measCalibrate => 'कैलिब्रेट करें';

  @override
  String get measCalibrateScale => 'स्केल कैलिब्रेट करें';

  @override
  String get measDepthLabel => 'गहराई: ';

  @override
  String get measKindAngle => 'कोण';

  @override
  String get measKindArc => 'चाप';

  @override
  String get measKindArea => 'क्षेत्रफल';

  @override
  String get measKindCount => 'गिनती';

  @override
  String get measKindLength => 'लंबाई';

  @override
  String get measKindNetArea => 'शुद्ध क्षेत्रफल';

  @override
  String get measKindPerimeter => 'परिमाप';

  @override
  String get measKindSlope => 'ढलान';

  @override
  String get measKindVolume => 'आयतन';

  @override
  String get measLineRepresents => 'आपके द्वारा खींची गई रेखा दर्शाती है:';

  @override
  String get measMeasure => 'मापें';

  @override
  String get measSetScale => 'मापन स्केल सेट करें';

  @override
  String get measSetScaleButton => 'स्केल सेट करें';

  @override
  String get measVolumeDepth => 'आयतन गहराई';

  @override
  String get menuAddNode => 'नोड जोड़ें';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'एनोटेशन को पृष्ठों पर लागू करें',
      one: 'एनोटेशन को पृष्ठों पर लागू करें',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'पृष्ठों पर लागू करें…';

  @override
  String get menuBringToFront => 'सबसे आगे लाएँ';

  @override
  String get menuCheck => 'चेक करें';

  @override
  String get menuChooseValue => 'मान चुनें…';

  @override
  String get menuClearCheck => 'चेक साफ़ करें';

  @override
  String get menuConvertToCheckBox => 'चेक बॉक्स में बदलें';

  @override
  String get menuConvertToImageButton => 'छवि बटन में बदलें';

  @override
  String get menuConvertToTextField => 'टेक्स्ट फ़ील्ड में बदलें';

  @override
  String get menuDeleteField => 'फ़ील्ड हटाएँ';

  @override
  String get menuEditValue => 'मान संपादित करें…';

  @override
  String get menuFieldName => 'फ़ील्ड नाम';

  @override
  String get menuFieldValue => 'फ़ील्ड मान';

  @override
  String get menuFlattenForm => 'फ़ॉर्म फ़्लैटन करें';

  @override
  String get menuLock => 'लॉक करें';

  @override
  String get menuUnlock => 'अनलॉक करें';

  @override
  String get menuRecolour => 'पुनः रंग दें…';

  @override
  String get menuRemoveNode => 'नोड हटाएँ';

  @override
  String get menuSetAsDefaultStyle => 'डिफ़ॉल्ट शैली के रूप में सेट करें';

  @override
  String get menuRename => 'नाम बदलें…';

  @override
  String get menuSelectOption => 'विकल्प चुनें';

  @override
  String get menuSendToBack => 'सबसे पीछे भेजें';

  @override
  String get menuSetImage => 'छवि सेट करें…';

  @override
  String get menuTextStyle => 'टेक्स्ट शैली…';

  @override
  String get none => 'कोई नहीं';

  @override
  String get ok => 'ठीक है';

  @override
  String get overlayColor => 'रंग';

  @override
  String get overlayEditText => 'टेक्स्ट संपादित करें';

  @override
  String get overlayFont => 'फ़ॉन्ट';

  @override
  String get overlayLarger => 'बड़ा';

  @override
  String get overlayMore => 'अधिक';

  @override
  String get overlayNote => 'नोट';

  @override
  String get overlaySmaller => 'छोटा';

  @override
  String get overlayStampText => 'स्टैम्प टेक्स्ट';

  @override
  String get linkDialogTitle => 'लिंक जोड़ें';

  @override
  String get linkKindWeb => 'वेब पता';

  @override
  String get linkKindPage => 'दस्तावेज़ में पृष्ठ';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'पृष्ठ संख्या';

  @override
  String get toolLink => 'लिंक';

  @override
  String get overlayUnderline => 'रेखांकन';

  @override
  String pageRangeErrorBounds(int count) {
    return '1 और $count के बीच पृष्ठ दर्ज करें।';
  }

  @override
  String get pageRangeErrorOrder =>
      'अंतिम पृष्ठ पहले पृष्ठ से पहले नहीं होना चाहिए।';

  @override
  String get pageRangeFrom => 'से';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ',
      one: '1 पृष्ठ',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'तक';

  @override
  String get panelDragToMovePanel => 'पैनल हिलाने के लिए खींचें';

  @override
  String get paste => 'पेस्ट करें';

  @override
  String get propAlign => 'संरेखण';

  @override
  String get propAlignCenter => 'केंद्र में संरेखित करें';

  @override
  String get propAlignLeft => 'बाएँ संरेखित करें';

  @override
  String get propAlignRight => 'दाएँ संरेखित करें';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count एनोटेशन',
      one: '$count एनोटेशन',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'लेखक';

  @override
  String get propAutoSize => 'स्वतः-आकार';

  @override
  String get propBold => 'बोल्ड';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'बंडल किया गया फ़ॉन्ट';

  @override
  String get propCallout => 'कॉलआउट';

  @override
  String get propCharSpacing => 'अक्षर अंतराल';

  @override
  String get propColor => 'रंग';

  @override
  String get propColour => 'रंग';

  @override
  String get propContents => 'सामग्री';

  @override
  String get propEditsApplyToAll => 'संपादन सभी संगत एनोटेशन पर लागू होते हैं';

  @override
  String get propFieldName => 'फ़ील्ड नाम';

  @override
  String get propFieldTypeCheckBox => 'चेक बॉक्स';

  @override
  String get propFieldTypeComboBox => 'कॉम्बो बॉक्स';

  @override
  String get propFieldTypeImageButton => 'छवि बटन';

  @override
  String get propFieldTypeListBox => 'लिस्ट बॉक्स';

  @override
  String get propFieldTypeRadioGroup => 'रेडियो समूह';

  @override
  String get propFieldTypeSignature => 'हस्ताक्षर';

  @override
  String get propFieldTypeText => 'टेक्स्ट फ़ील्ड';

  @override
  String propFieldTypeTooltip(String type) {
    return 'फ़ील्ड प्रकार: $type';
  }

  @override
  String get propFieldTypeUnknown => 'अज्ञात फ़ील्ड';

  @override
  String get propFill => 'भरण';

  @override
  String get propFont => 'फ़ॉन्ट';

  @override
  String get propFontSubsetTooltip =>
      'यह फ़ॉन्ट सबसेट है - केवल वे अक्षर टाइप किए जा सकते हैं जो दस्तावेज़ में पहले से उपयोग हुए हैं।';

  @override
  String get propFontWidth => 'फ़ॉन्ट चौड़ाई';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'इटैलिक';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'सीमित अक्षर';

  @override
  String get propLineEnd => 'रेखा का अंत';

  @override
  String get propLineEndingButt => 'बट';

  @override
  String get propLineEndingCircle => 'वृत्त';

  @override
  String get propLineEndingClosedArrow => 'बंद तीर';

  @override
  String get propLineEndingClosedArrowRev => 'बंद तीर (उल्टा)';

  @override
  String get propLineEndingDiamond => 'हीरा';

  @override
  String get propLineEndingOpenArrow => 'खुला तीर';

  @override
  String get propLineEndingOpenArrowRev => 'खुला तीर (उल्टा)';

  @override
  String get propLineEndingSlash => 'स्लैश';

  @override
  String get propLineEndingSquare => 'वर्ग';

  @override
  String get propLineSpacing => 'पंक्ति अंतराल';

  @override
  String get propLineStart => 'रेखा का आरंभ';

  @override
  String get propLineType => 'रेखा प्रकार';

  @override
  String get propLoadFont => 'फ़ॉन्ट लोड करें…';

  @override
  String get propLoadFontSubtitle => 'TTF या OTF फ़ाइल';

  @override
  String get propMoreColors => 'अधिक रंग…';

  @override
  String get propMultiline => 'बहु-पंक्ति';

  @override
  String get propNoFill => 'कोई भरण नहीं';

  @override
  String get propNoFontsFound => 'कोई फ़ॉन्ट नहीं मिला';

  @override
  String get propNoOutline => 'कोई रूपरेखा नहीं';

  @override
  String get propOpacity => 'अपारदर्शिता';

  @override
  String get propOutline => 'रूपरेखा';

  @override
  String get propPageLabel => 'पृष्ठ';

  @override
  String propPageNumber(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String get propPropertiesTitle => 'गुण';

  @override
  String get propRecentlyUsed => 'हाल में उपयोग किए गए';

  @override
  String get propScale => 'स्केल';

  @override
  String get propSearchFonts => 'फ़ॉन्ट खोजें';

  @override
  String get propSectionAllFonts => 'सभी फ़ॉन्ट';

  @override
  String get propSectionAppearance => 'रूप';

  @override
  String get propSectionContent => 'सामग्री';

  @override
  String get propSectionFormField => 'फ़ॉर्म फ़ील्ड';

  @override
  String get propSectionInThisDocument => 'इस दस्तावेज़ में';

  @override
  String get propSectionPositionSize => 'स्थिति और आकार (pt)';

  @override
  String get propSectionSelection => 'चयन';

  @override
  String get propSectionText => 'टेक्स्ट';

  @override
  String get propSelectAnnotationPrompt => 'गुण देखने के लिए कोई एनोटेशन चुनें';

  @override
  String get propSize => 'आकार';

  @override
  String get propStandardPdfFont => 'मानक PDF फ़ॉन्ट';

  @override
  String get propStroke => 'स्ट्रोक';

  @override
  String get propStyle => 'शैली';

  @override
  String get propSystemFont => 'सिस्टम फ़ॉन्ट';

  @override
  String get propType => 'प्रकार';

  @override
  String get propUnderline => 'रेखांकन';

  @override
  String get propVaries => 'भिन्न-भिन्न';

  @override
  String get redo => 'फिर से करें';

  @override
  String get reflowNoContent => 'कोई निकालने योग्य सामग्री नहीं';

  @override
  String reflowPageLabel(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String get reflowSaveOrShare => 'सहेजें या साझा करें';

  @override
  String get reflowViewFigure => 'आकृति देखें';

  @override
  String get remove => 'निकालें';

  @override
  String get rename => 'नाम बदलें';

  @override
  String get reset => 'रीसेट करें';

  @override
  String get save => 'सहेजें';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'पृष्ठ $page';
  }

  @override
  String get sbarCallout => 'कॉलआउट';

  @override
  String get sbarFieldButton => 'बटन फ़ील्ड';

  @override
  String get sbarFieldChoice => 'चॉइस फ़ील्ड';

  @override
  String get sbarFieldGeneric => 'फ़ॉर्म फ़ील्ड';

  @override
  String get sbarFieldSignature => 'हस्ताक्षर फ़ील्ड';

  @override
  String get sbarFieldText => 'टेक्स्ट फ़ील्ड';

  @override
  String get sbarStateAccepted => 'स्वीकृत';

  @override
  String get sbarStateCancelled => 'रद्द किया गया';

  @override
  String get sbarStateMarked => 'चिह्नित';

  @override
  String get sbarStateRejected => 'अस्वीकृत';

  @override
  String get sbarStateResolved => 'हल किया गया';

  @override
  String get sbarStateUnmarked => 'अचिह्नित';

  @override
  String get searchAnnotations => 'एनोटेशन खोजें';

  @override
  String get searchClearSearch => 'खोज साफ़ करें';

  @override
  String get searchEmptyHint =>
      'हर मिलान यहाँ सूचीबद्ध करने के लिए दस्तावेज़ में खोजें';

  @override
  String get searchMatchCase => 'केस मिलान';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count मिलान',
      one: '1 मिलान',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'अगला मिलान';

  @override
  String searchNoMatches(String query) {
    return '“$query” के लिए कोई मिलान नहीं';
  }

  @override
  String searchPageHeader(int page) {
    return 'पृष्ठ $page';
  }

  @override
  String get searchPreviousMatch => 'पिछला मिलान';

  @override
  String get searchRegex => 'रेगुलर एक्सप्रेशन';

  @override
  String get searchResultsTitle => 'खोज परिणाम';

  @override
  String get searchWholeWord => 'पूरा शब्द';

  @override
  String get shellControls => 'नियंत्रण';

  @override
  String get shellDefaultAuthor => 'डिफ़ॉल्ट लेखक…';

  @override
  String get shellHighlightFormFields => 'फ़ॉर्म फ़ील्ड हाइलाइट करें';

  @override
  String get shellKeyboardShortcutsMenu => 'कीबोर्ड शॉर्टकट…';

  @override
  String get shellKeyboardShortcutsTitle => 'कीबोर्ड शॉर्टकट';

  @override
  String get shellShortcutsSearchHint => 'शॉर्टकट खोजें';

  @override
  String shellShortcutsNoMatches(String query) {
    return '“$query” से कोई शॉर्टकट मेल नहीं खाता';
  }

  @override
  String get shellShortcutGroupSelect => 'चयन';

  @override
  String get shellShortcutGroupMarkup => 'मार्कअप';

  @override
  String get shellShortcutGroupDraw => 'ड्रा';

  @override
  String get shellShortcutGroupShapes => 'आकृतियाँ';

  @override
  String get shellShortcutGroupInsert => 'इंसर्ट';

  @override
  String get shellShortcutGroupMeasure => 'मापें';

  @override
  String get shellShortcutGroupEdit => 'संपादन';

  @override
  String get shellNotSet => 'सेट नहीं';

  @override
  String get shellPageColor => 'पृष्ठ रंग…';

  @override
  String get shellPageGrid => 'पृष्ठ ग्रिड';

  @override
  String get shellPanelAnnotations => 'एनोटेशन';

  @override
  String get shellPanelBookmarks => 'बुकमार्क';

  @override
  String get shellPanelPages => 'पृष्ठ';

  @override
  String get shellPanelProperties => 'गुण';

  @override
  String get shellPanelSearchResults => 'खोज परिणाम';

  @override
  String get shellPanels => 'पैनल';

  @override
  String get shellPressAKey => 'कोई कुंजी दबाएँ';

  @override
  String get shellPressLetterKeyHint =>
      'कोई अक्षर कुंजी दबाएँ, या साफ़ करने के लिए Delete।';

  @override
  String get shellReflow => 'रीफ़्लो';

  @override
  String get shellReflowText => 'टेक्स्ट रीफ़्लो';

  @override
  String get shellResetZoom => 'ज़ूम रीसेट करें';

  @override
  String get shellSectionShell => 'शेल';

  @override
  String get shellSectionView => 'दृश्य';

  @override
  String get shellSettings => 'सेटिंग्स';

  @override
  String get shellShowAnnotations => 'एनोटेशन दिखाएँ';

  @override
  String get shellTabHere => 'यहाँ टैब करें';

  @override
  String get shellUnbound => 'अनबाउंड';

  @override
  String get shellZoom => 'ज़ूम';

  @override
  String sidebarByAuthor(String author) {
    return '$author द्वारा';
  }

  @override
  String get sidebarCancelSelection => 'चयन रद्द करें';

  @override
  String get sidebarClearSearch => 'खोज साफ़ करें';

  @override
  String get sidebarDeleteSelected => 'चयनित हटाएँ';

  @override
  String get sidebarDeleteSignature => 'हस्ताक्षर हटाएँ';

  @override
  String get sidebarLockAnnotation => 'लॉक करें';

  @override
  String get sidebarUnlockAnnotation => 'अनलॉक करें';

  @override
  String get sidebarMore => 'अधिक';

  @override
  String get sidebarNoAnnotations => 'कोई एनोटेशन नहीं';

  @override
  String get sidebarNoMatchingAnnotations => 'कोई मेल खाता एनोटेशन नहीं';

  @override
  String sidebarPageHeader(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'यह दस्तावेज़ से डिजिटल हस्ताक्षर हटा देता है। आप इसे पूर्ववत कर सकते हैं।';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'यह दस्तावेज़ से \"$name\" द्वारा किया गया डिजिटल हस्ताक्षर हटा देता है। आप इसे पूर्ववत कर सकते हैं।';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'हस्ताक्षर हटाएँ?';

  @override
  String get sidebarReopen => 'फिर से खोलें';

  @override
  String get sidebarReply => 'उत्तर दें';

  @override
  String get sidebarResolve => 'हल करें';

  @override
  String get sidebarSearchHint => 'एनोटेशन खोजें';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चयनित',
      one: '$count चयनित',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'उत्तर लिखें…';

  @override
  String get sigTitle => 'हस्ताक्षर';

  @override
  String get signIdCreate => 'बनाएँ';

  @override
  String get signIdEmail => 'ईमेल (वैकल्पिक)';

  @override
  String get signIdName => 'नाम';

  @override
  String get signIdNameHint => 'आपका नाम, जैसा कि हस्ताक्षर पर दिखना चाहिए';

  @override
  String get signIdNameRequired => 'कोई नाम दर्ज करें';

  @override
  String get signIdOrganization => 'संगठन (वैकल्पिक)';

  @override
  String get signIdSelfSignedInfo =>
      'यह एक स्व-हस्ताक्षरित पहचान बनाता है। Adobe Acrobat और अन्य रीडर में हस्ताक्षर \"हस्ताक्षरित, वैधता अज्ञात\" के रूप में दिखेंगे - ठीक उनके अपने स्व-हस्ताक्षरित IDs की तरह। हरे चेकमार्क के लिए एक भुगतान किए गए, सार्वजनिक रूप से विश्वसनीय CA की आवश्यकता होती है।';

  @override
  String get signIdTitle => 'हस्ताक्षर पहचान बनाएँ';

  @override
  String get stampBox => 'बॉक्स';

  @override
  String get stampCircle => 'वृत्त';

  @override
  String get stampCustomCaption => 'कस्टम स्टैम्प';

  @override
  String get stampDateFormat => 'दिनांक फ़ॉर्मेट';

  @override
  String get stampDeleteComponent => 'चयनित घटक हटाएँ';

  @override
  String get stampDeleteStamp => 'स्टैम्प हटाएँ';

  @override
  String get stampEditStamp => 'स्टैम्प संपादित करें';

  @override
  String get stampExport => 'एक्सपोर्ट करें…';

  @override
  String get stampFieldDate => 'दिनांक';

  @override
  String get stampFieldDateTime => 'दिनांक और समय';

  @override
  String get stampFieldTime => 'समय';

  @override
  String get stampFieldUsername => 'उपयोगकर्ता नाम';

  @override
  String get stampFont => 'फ़ॉन्ट';

  @override
  String get stampFontBold => 'बोल्ड';

  @override
  String get stampFontItalic => 'इटैलिक';

  @override
  String get stampHeight => 'ऊँचाई';

  @override
  String get stampImage => 'छवि';

  @override
  String get stampImport => 'इम्पोर्ट…';

  @override
  String get stampInsertField => 'फ़ील्ड डालें';

  @override
  String get stampMoreColors => 'अधिक रंग…';

  @override
  String get stampNewStamp => 'नया स्टैम्प…';

  @override
  String get stampNewStampTitle => 'नया स्टैम्प';

  @override
  String get stampSelectTextToEdit => 'संपादित करने के लिए टेक्स्ट चुनें';

  @override
  String get stampSelectedText => 'चयनित टेक्स्ट';

  @override
  String get stampSignature => 'हस्ताक्षर';

  @override
  String get stampStamps => 'स्टैम्प';

  @override
  String get stampText => 'टेक्स्ट';

  @override
  String get stampTime12Hour => '12 घं';

  @override
  String get stampTime24Hour => '24 घं';

  @override
  String get stampTimeFormat => 'समय फ़ॉर्मेट';

  @override
  String get stampWidth => 'चौड़ाई';

  @override
  String get takeoffArea => 'क्षेत्रफल';

  @override
  String get takeoffCount => 'गिनती';

  @override
  String get takeoffEmpty => 'अभी तक कोई माप नहीं।';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count समूह',
      one: '$count समूह',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम',
      one: '$count आइटम',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'लंबाई';

  @override
  String get takeoffTitle => 'टेकऑफ़';

  @override
  String get tbAddInkAnnotation => 'इंक एनोटेशन जोड़ें';

  @override
  String get tbAlign => 'संरेखण';

  @override
  String get tbAlignBottom => 'नीचे संरेखित करें';

  @override
  String get tbAlignHorizontalCenters => 'क्षैतिज केंद्रों पर संरेखित करें';

  @override
  String get tbAlignLeft => 'बाएँ संरेखित करें';

  @override
  String get tbAlignRight => 'दाएँ संरेखित करें';

  @override
  String get tbAlignTop => 'ऊपर संरेखित करें';

  @override
  String get tbAlignVerticalCenters => 'लंबवत केंद्रों पर संरेखित करें';

  @override
  String get tbAnnotationsFlattened => 'एनोटेशन पृष्ठों में फ़्लैटन किए गए';

  @override
  String get tbApplyRedactionsMessage =>
      'चिह्नित सामग्री दस्तावेज़ से स्थायी रूप से हटा दी जाएगी। इसे पूर्ववत नहीं किया जा सकता।';

  @override
  String get tbApplyRedactionsTitle => 'रिडैक्शन लागू करें?';

  @override
  String get tbApplyRedactionsTooltip => 'रिडैक्शन लागू करें (अपरिवर्तनीय)';

  @override
  String get tbAutosizeTextBox => 'टेक्स्ट बॉक्स स्वतः-आकार दें (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'स्केल कैलिब्रेट करने के लिए ज्ञात लंबाई की एक रेखा खींचें।';

  @override
  String get tbCharSpacing => 'अक्षर अंतराल';

  @override
  String get tbCheckBoxOption => 'चेक बॉक्स';

  @override
  String get tbCheckMarksOnDocument => 'दस्तावेज़ पर चेक-मार्क';

  @override
  String get tbColorLabel => 'रंग';

  @override
  String get tbColorProcessingTooltip =>
      'रंग प्रसंस्करण - पृष्ठ-सामग्री के रंग खोजें और बदलें';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count रंग बदले गए',
      one: '1 रंग बदला गया',
      zero: 'कोई मेल खाता रंग नहीं मिला',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'चेक बॉक्स में बदलें';

  @override
  String get tbConvertToImageButton => 'छवि बटन में बदलें';

  @override
  String get tbConvertToTextField => 'टेक्स्ट फ़ील्ड में बदलें';

  @override
  String get tbCornerRadius => 'कोना त्रिज्या';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count एनोटेशन हटाएँ',
      one: 'एनोटेशन हटाएँ',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'तत्व हटाएँ';

  @override
  String get tbDeleteField => 'फ़ील्ड हटाएँ';

  @override
  String get tbDiscardDrawing => 'ड्राइंग छोड़ें';

  @override
  String get tbDistributeHorizontally => 'क्षैतिज रूप से वितरित करें';

  @override
  String get tbDistributeVertically => 'लंबवत रूप से वितरित करें';

  @override
  String get tbDrawNewSignature => 'नया हस्ताक्षर बनाएँ…';

  @override
  String get tbEditAnnotationText => 'एनोटेशन टेक्स्ट संपादित करें';

  @override
  String get tbEditTextStyle => 'टेक्स्ट और शैली संपादित करें';

  @override
  String get tbElement => 'तत्व';

  @override
  String get tbEraserSize => 'इरेज़र आकार';

  @override
  String get tbFieldActions => 'फ़ील्ड क्रियाएँ';

  @override
  String get tbFieldName => 'फ़ील्ड नाम';

  @override
  String tbFieldNamed(String name) {
    return 'फ़ील्ड: $name';
  }

  @override
  String get tbFieldValue => 'फ़ील्ड मान';

  @override
  String get tbFill => 'भरण';

  @override
  String get tbFingerDraws =>
      'उँगली से ड्रा - टैप करें ताकि यह इसके बजाय स्क्रॉल करे';

  @override
  String get tbFingerScrolls =>
      'उँगली स्क्रॉल करती है (पेन ड्रा करता है) - टैप करें ताकि यह ड्रा करे';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'एनोटेशन को पृष्ठों में फ़्लैटन करें';

  @override
  String get tbFlattenForm => 'फ़ॉर्म फ़्लैटन करें';

  @override
  String get tbFlattenFormBakeValues =>
      'फ़ॉर्म फ़्लैटन करें - मानों को पृष्ठों में बेक करें';

  @override
  String get tbFlattenLabel => 'फ़्लैटन';

  @override
  String get tbFont => 'फ़ॉन्ट';

  @override
  String get tbFontSize => 'फ़ॉन्ट आकार';

  @override
  String get tbFontWidth => 'फ़ॉन्ट चौड़ाई';

  @override
  String get tbFormFieldsFlattened =>
      'फ़ॉर्म फ़ील्ड पृष्ठों में फ़्लैटन किए गए';

  @override
  String get tbGroupDraw => 'ड्रा';

  @override
  String get tbGroupEdit => 'संपादन';

  @override
  String get tbGroupInsert => 'इंसर्ट';

  @override
  String get tbGroupMarkup => 'मार्कअप';

  @override
  String get tbGroupMeasure => 'मापें';

  @override
  String get tbGroupSelect => 'चयन';

  @override
  String get tbGroupShapes => 'आकृतियाँ';

  @override
  String get tbImageButtonOption => 'छवि बटन';

  @override
  String get tbLineEnd => 'रेखा का अंत';

  @override
  String get tbLineSpacing => 'पंक्ति अंतराल';

  @override
  String get tbLineStart => 'रेखा का आरंभ';

  @override
  String get tbLineType => 'रेखा प्रकार';

  @override
  String get tbManageStamps => 'स्टैम्प प्रबंधित करें…';

  @override
  String get tbMarkupHighlight => 'हाइलाइट';

  @override
  String get tbMarkupHighlightTip => 'चयन हाइलाइट करें';

  @override
  String get tbMarkupSquiggly => 'लहरदार-रेखांकन';

  @override
  String get tbMarkupSquigglyTip => 'चयन को लहरदार-रेखांकित करें';

  @override
  String get tbMarkupStrikeOut => 'स्ट्राइक आउट';

  @override
  String get tbMarkupStrikeOutTip => 'चयन को स्ट्राइक आउट करें';

  @override
  String get tbMarkupUnderline => 'रेखांकन';

  @override
  String get tbMarkupUnderlineTip => 'चयन रेखांकित करें';

  @override
  String get tbMoreColors => 'अधिक रंग…';

  @override
  String get tbNameArrow => 'तीर';

  @override
  String get tbNameCallout => 'कॉलआउट';

  @override
  String get tbNameCloudPolygon => 'क्लाउड बहुभुज';

  @override
  String get tbNameCount => 'गिनती';

  @override
  String get tbNameDigitalSignature => 'डिजिटल हस्ताक्षर';

  @override
  String get tbNameDraw => 'ड्रा';

  @override
  String get tbNameEllipse => 'दीर्घवृत्त';

  @override
  String get tbNameEraser => 'इंक स्ट्रोक मिटाएँ';

  @override
  String get tbNameHighlight => 'हाइलाइट';

  @override
  String get tbNameImage => 'छवि';

  @override
  String get tbNameLine => 'रेखा';

  @override
  String get tbNameMeasureAngle => 'कोण मापें';

  @override
  String get tbNameMeasureArc => 'चाप लंबाई मापें';

  @override
  String get tbNameMeasureArea => 'क्षेत्रफल मापें';

  @override
  String get tbNameMeasureDistance => 'दूरी मापें';

  @override
  String get tbNameMeasurePerimeter => 'परिमाप मापें';

  @override
  String get tbNameMeasureSlope => 'ढलान मापें (उठान/दौड़)';

  @override
  String get tbNameMeasureVolume => 'आयतन मापें (क्षेत्रफल × गहराई)';

  @override
  String get tbNameNote => 'नोट';

  @override
  String get tbNamePolygon => 'बहुभुज';

  @override
  String get tbNamePolyline => 'पॉलीलाइन';

  @override
  String get tbNameRectangle => 'आयत';

  @override
  String get tbNameSelect => 'चयन';

  @override
  String get tbNameSignature => 'हस्ताक्षर';

  @override
  String get tbNameStamp => 'स्टैम्प';

  @override
  String get tbNameTextBox => 'टेक्स्ट बॉक्स';

  @override
  String get tbNewFieldType =>
      'नया फ़ील्ड प्रकार - एक जोड़ने के लिए पृष्ठ पर खींचें';

  @override
  String get tbNoAnnotationsToFlatten => 'फ़्लैटन करने के लिए कोई एनोटेशन नहीं';

  @override
  String get tbNoCustomStamps => 'कोई कस्टम स्टैम्प नहीं';

  @override
  String get tbNoFormFieldsToFlatten =>
      'फ़्लैटन करने के लिए कोई फ़ॉर्म फ़ील्ड नहीं';

  @override
  String get tbNoRedactionsToApply => 'लागू करने के लिए कोई रिडैक्शन नहीं';

  @override
  String get tbNoteTitle => 'नोट';

  @override
  String get tbOpacity => 'अपारदर्शिता';

  @override
  String get tbOutline => 'रूपरेखा';

  @override
  String get tbPatternScale => 'पैटर्न स्केल';

  @override
  String get tbPickColorFromPage => 'पृष्ठ से एक रंग चुनें';

  @override
  String get tbRedactionsApplied => 'रिडैक्शन लागू किए गए';

  @override
  String get tbRedoShortcut => 'फिर से करें (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'रीफ़्लो नहीं कर सके - यह एकल-स्तंभ अनुच्छेद नहीं है जिसे यह टूल फिर से लपेट सके। इसके बजाय टेक्स्ट बदलें आज़माएँ।';

  @override
  String get tbReflowParagraph => 'अनुच्छेद रीफ़्लो करें';

  @override
  String get tbRenameField => 'फ़ील्ड का नाम बदलें';

  @override
  String get tbRenameFieldEllipsis => 'फ़ील्ड का नाम बदलें…';

  @override
  String get tbReplaceImage => 'छवि बदलें';

  @override
  String get tbReplaceImageFailed => 'छवि नहीं बदल सके';

  @override
  String get tbReplaceText => 'टेक्स्ट बदलें';

  @override
  String get tbSaveImage => 'छवि सहेजें';

  @override
  String get tbSaveShortcut => 'सहेजें… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'स्केल';

  @override
  String get tbSelectTextForMarkup =>
      'मार्कअप का उपयोग करने के लिए टेक्स्ट चुनें';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चयनित',
      one: 'चयन',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'सेट करें…';

  @override
  String get tbStamp => 'स्टैम्प';

  @override
  String get tbStampText => 'स्टैम्प टेक्स्ट';

  @override
  String get tbStrokeOpacityFont => 'स्ट्रोक, अपारदर्शिता, फ़ॉन्ट';

  @override
  String get tbStrokeWidthLabel => 'स्ट्रोक चौड़ाई';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'स्ट्रोक $width';
  }

  @override
  String get tbStyle => 'शैली';

  @override
  String get tbTakeoffTotals => 'टेकऑफ़ योग';

  @override
  String get tbTextBorder => 'टेक्स्ट बॉर्डर';

  @override
  String get tbTextColour => 'टेक्स्ट रंग';

  @override
  String get tbTextFieldOption => 'टेक्स्ट फ़ील्ड';

  @override
  String get tbTextFill => 'टेक्स्ट भरण';

  @override
  String get tbTextStyleEllipsis => 'टेक्स्ट शैली…';

  @override
  String get tbTextTitle => 'टेक्स्ट';

  @override
  String get tbTipCallout =>
      'कॉलआउट - बिंदु से उस जगह तक खींचें जहाँ बॉक्स जाता है';

  @override
  String get tbTipContent => 'पृष्ठ सामग्री संपादित करें';

  @override
  String get tbTipCount =>
      'गिनती - चेक-मार्क छोड़ने और उन्हें गिनने के लिए टैप करें';

  @override
  String get tbTipDigitalSignature =>
      'डिजिटल हस्ताक्षर - रखने और हस्ताक्षर करने के लिए एक बॉक्स खींचें';

  @override
  String get tbTipForm =>
      'फ़ॉर्म फ़ील्ड - चुनने के लिए टैप करें, भरने के लिए डबल-टैप करें, जोड़ने के लिए खींचें';

  @override
  String get tbTipHighlightDraw => 'हाइलाइट - फ्रीहैंड ड्रा करें';

  @override
  String get tbTipImage => 'छवि - रखने के लिए टैप करें, या एक बॉक्स खींचें';

  @override
  String get tbTipMeasureAngle => 'कोण मापें - तीन बिंदु क्लिक करें';

  @override
  String get tbTipMeasureArc => 'चाप लंबाई मापें - तीन बिंदु क्लिक करें';

  @override
  String get tbTipRedact => 'रिडैक्ट करें - एक क्षेत्र खींचें, फिर लागू करें';

  @override
  String get tbTipSignature => 'हस्ताक्षर - रखने के लिए किसी पृष्ठ पर टैप करें';

  @override
  String get tbTipSnapshot =>
      'स्नैपशॉट - कैप्चर करने के लिए एक क्षेत्र खींचें (वेक्टर के रूप में वापस पेस्ट करें)';

  @override
  String get tbToolContent => 'सामग्री';

  @override
  String get tbToolForm => 'फ़ॉर्म';

  @override
  String get tbToolRedact => 'रिडैक्ट';

  @override
  String get tbToolSnapshot => 'स्नैपशॉट';

  @override
  String get tbTools => 'टूल';

  @override
  String get tbTotals => 'योग';

  @override
  String get tbTypeTextEachTime => 'हर बार टेक्स्ट टाइप करें';

  @override
  String get tbUnderline => 'रेखांकन';

  @override
  String get tbUndoShortcut => 'पूर्ववत करें (⌘Z)';

  @override
  String get textStyleFont => 'फ़ॉन्ट';

  @override
  String get textStyleFontSize => 'फ़ॉन्ट आकार';

  @override
  String get textStyleKeep => 'रखें';

  @override
  String get textStyleStyle => 'शैली';

  @override
  String get textStyleText => 'टेक्स्ट';

  @override
  String get textStyleTextFill => 'टेक्स्ट भरण';

  @override
  String get textStyleTitle => 'टेक्स्ट और शैली संपादित करें';

  @override
  String get thumbAddPage => 'पृष्ठ जोड़ें';

  @override
  String get thumbClearSelection => 'चयन साफ़ करें';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ कॉपी करें',
      one: 'पृष्ठ कॉपी करें',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'चयनित पृष्ठ कॉपी करें';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ काटें',
      one: 'पृष्ठ काटें',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'चयनित पृष्ठ काटें';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ हटाएँ',
      one: 'पृष्ठ हटाएँ',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'चयनित पृष्ठ हटाएँ';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ डुप्लिकेट करें',
      one: 'पृष्ठ डुप्लिकेट करें',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'पृष्ठ एक्सपोर्ट करें…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ एक्सपोर्ट करें…',
      one: 'पृष्ठ एक्सपोर्ट करें…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'चयनित पृष्ठ एक्सपोर्ट करें';

  @override
  String get thumbInsertBlankAfter => 'बाद में रिक्त पृष्ठ डालें';

  @override
  String get thumbInsertBlankBefore => 'पहले रिक्त पृष्ठ डालें';

  @override
  String get thumbInsertFileFailed => 'उस फ़ाइल को नहीं डाल सके।';

  @override
  String get thumbInsertPdf => 'PDF डालें…';

  @override
  String get thumbPageActions => 'पृष्ठ क्रियाएँ';

  @override
  String thumbPageNumber(int number) {
    return 'पृष्ठ $number';
  }

  @override
  String get thumbPages => 'पृष्ठ';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count पृष्ठ पेस्ट करें',
      one: 'पृष्ठ पेस्ट करें',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '180° घुमाएँ';

  @override
  String get thumbRotateLeft => 'बाएँ घुमाएँ';

  @override
  String get thumbRotatePageRight => 'पृष्ठ दाएँ घुमाएँ';

  @override
  String get thumbRotateRight => 'दाएँ घुमाएँ';

  @override
  String get thumbRotateSelectedLeft => 'चयनित पृष्ठ बाएँ घुमाएँ';

  @override
  String get thumbRotateSelectedRight => 'चयनित पृष्ठ दाएँ घुमाएँ';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चयनित',
      one: '$count चयनित',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'पूर्ववत करें';

  @override
  String get viewerEditFontUnsafe =>
      'इस PDF फ़ॉन्ट या एन्कोडिंग को सुरक्षित रूप से संपादित नहीं किया जा सकता।';

  @override
  String get viewerEditNeedsSinglePage =>
      'संपादन के लिए एक पृष्ठ पर चयन आवश्यक है।';

  @override
  String get viewerEditNotEditableRun =>
      'यह चयन एक संपादन योग्य पृष्ठ-सामग्री टेक्स्ट रन नहीं है।';

  @override
  String get viewerEditStyleUnchangeable =>
      'इस PDF फ़ॉन्ट को फिर से टाइप किया जा सकता है, लेकिन इसकी शैली नहीं बदली जा सकती।';

  @override
  String get viewerEditTextStyle => 'टेक्स्ट और शैली संपादित करें';

  @override
  String get viewerMarkup => 'मार्कअप';

  @override
  String get viewerMarkupHighlight => 'हाइलाइट';

  @override
  String get viewerMarkupSquiggly => 'लहरदार';

  @override
  String get viewerMarkupStrikeOut => 'स्ट्राइक आउट';

  @override
  String get viewerMarkupUnderline => 'रेखांकन';

  @override
  String get viewerSelectAll => 'सभी चुनें';
}
