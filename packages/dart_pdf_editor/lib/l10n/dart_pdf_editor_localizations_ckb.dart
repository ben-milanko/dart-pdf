// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Central Kurdish (`ckb`).
class DartPdfEditorLocalizationsCkb extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsCkb([String locale = 'ckb']) : super(locale);

  @override
  String get add => 'زیادکردن';

  @override
  String get annotCaret => 'نیشانەی تێخستن';

  @override
  String get annotCircle => 'بازنە';

  @override
  String get annotFileAttachment => 'هاوپێچی پەڕگە';

  @override
  String get annotFreeText => 'چوارگۆشەی دەق';

  @override
  String get annotHighlight => 'دیاریکردن';

  @override
  String get annotInk => 'حوبر (قەڵەم)';

  @override
  String get annotLine => 'هێڵ';

  @override
  String get annotLink => 'بەستەر';

  @override
  String get annotPolygon => 'فرەگۆشە';

  @override
  String get annotPolyline => 'فرەهێڵ';

  @override
  String get annotRedact => 'ڕەشکردنەوە (سانسۆر)';

  @override
  String get annotSquare => 'چوارگۆشە';

  @override
  String get annotSquiggly => 'شەپۆلاوی';

  @override
  String get annotStamp => 'مۆر';

  @override
  String get annotStrikeOut => 'هێڵ بەسەرداکێشان';

  @override
  String get annotText => 'تێبینی';

  @override
  String get annotUnderline => 'هێڵی ژێرەوە';

  @override
  String get annotWidget => 'خانەی فۆرم';

  @override
  String get apply => 'جێبەجێکردن';

  @override
  String get bookmarkAdd => 'زیادکردنی نیشانە';

  @override
  String get bookmarkAddChild => 'زیادکردنی نیشانەی لاوەکی';

  @override
  String get bookmarkCollapse => 'کۆکردنەوە';

  @override
  String get bookmarkDelete => 'سڕینەوەی نیشانە';

  @override
  String get bookmarkEdit => 'دەستکاریکردنی نیشانە';

  @override
  String get bookmarkEmpty => 'هیچ نیشانەیەک نییە';

  @override
  String get bookmarkExpand => 'فراوانکردن';

  @override
  String get bookmarkExpandedByDefault => 'بە شێوەی بنەڕەتی کراوە بێت';

  @override
  String get bookmarkNoDestination => 'بێ شوێنی مەبەست';

  @override
  String get bookmarkPageFieldLabel => 'پەڕە';

  @override
  String bookmarkPageLabel(int number) {
    return 'پەڕەی $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'نیشانەکان';

  @override
  String get bookmarkTitleLabel => 'ناونیشان';

  @override
  String get bookmarkUntitled => 'بێ ناونیشان';

  @override
  String get cancel => 'هەڵوەشاندنەوە';

  @override
  String get clear => 'پاککردنەوە';

  @override
  String get close => 'داخستن';

  @override
  String get colorApplyingChanges => 'جێبەجێکردنی گۆڕانکارییەکانی ڕەنگ…';

  @override
  String get colorColorFormat => 'شێوازی ڕەنگ';

  @override
  String get colorColorTitle => 'ڕەنگ';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ڕەنگ دیاریکراون',
      one: 'ڕەنگێک دیاریکراوە',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'ڕەنگەکانی بەڵگەنامە';

  @override
  String get colorFillColors => 'ڕەنگەکانی پڕکردنەوە';

  @override
  String get colorFind => 'دۆزینەوە';

  @override
  String get colorInDocument => 'لە بەڵگەنامەدا';

  @override
  String get colorNoColorsFound => 'هێشتا هیچ ڕەنگێک نەدۆزراوەتەوە';

  @override
  String get colorNoPageContentColors =>
      'هیچ ڕەنگێک لە ناوەڕۆکی پەڕە نەدۆزرایەوە';

  @override
  String get colorPalette => 'تەختەی ڕەنگەکان';

  @override
  String get colorPickColor => 'هەڵبژاردنی ڕەنگ';

  @override
  String get colorProcessingTitle => 'دەستکاریکردنی ڕەنگ';

  @override
  String get colorRecent => 'دواین بەکارهاتوو';

  @override
  String get colorReplace => 'جێگرتنەوە';

  @override
  String get colorReplaceWithTransparent => 'جێگرتنەوە بە شەفاف';

  @override
  String get colorScanning => 'پشکنین…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'پشکنین $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'پەڕە دیاریکراوەکان ($count)';
  }

  @override
  String get colorStrokeColors => 'ڕەنگەکانی هێڵ';

  @override
  String get colorTolerance => 'مەودای لێبوردەیی';

  @override
  String get colorTransparent => 'شەفاف';

  @override
  String get colorWholeDocument => 'تەواوی بەڵگەنامە';

  @override
  String get compareAfter => 'دواتر';

  @override
  String get compareBefore => 'پێشتر';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count گۆڕانکاری',
      one: 'یەک گۆڕانکاری',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count گۆڕانکاری',
      one: 'یەک گۆڕانکاری',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(بەتاڵ)';

  @override
  String get compareNextChange => 'گۆڕانکاریی داهاتوو';

  @override
  String get compareNoChanges => 'هیچ گۆڕانکارییەک نییە';

  @override
  String get compareNoDifferences =>
      'هیچ جیاوازییەک لە نێوان هەردوو بەڵگەنامەکەدا نییە';

  @override
  String get compareOverlay => 'سەریەککەوتوو';

  @override
  String comparePageHeader(int page) {
    return 'پەڕەی $page';
  }

  @override
  String get comparePreviousChange => 'گۆڕانکاریی پێشوو';

  @override
  String get compareSideBySide => 'تەنیشت بە تەنیشت';

  @override
  String get copy => 'کۆپیکردن';

  @override
  String get cut => 'بڕین';

  @override
  String get delete => 'سڕینەوە';

  @override
  String get done => 'تەواو';

  @override
  String get edit => 'دەستکاریکردن';

  @override
  String get editorViewAuthorNameTitle => 'ناوی نووسەر';

  @override
  String get lineStyleDashDot => 'هێڵ و خاڵ';

  @override
  String get lineStyleDashed => 'پچڕپچڕ';

  @override
  String get lineStyleDotted => 'خاڵخاڵ';

  @override
  String get lineStyleSolid => 'بەردەوام';

  @override
  String get measCalibrate => 'کالیبرەکردن';

  @override
  String get measCalibrateScale => 'کالیبرەکردنی پێوەر';

  @override
  String get measDepthLabel => 'قووڵی: ';

  @override
  String get measKindAngle => 'گۆشە';

  @override
  String get measKindArc => 'کەوانە';

  @override
  String get measKindArea => 'ڕووبەر';

  @override
  String get measKindCount => 'ژماردن';

  @override
  String get measKindLength => 'درێژی';

  @override
  String get measKindNetArea => 'ڕووبەری سافی';

  @override
  String get measKindPerimeter => 'چێوە';

  @override
  String get measKindSlope => 'لێژی';

  @override
  String get measKindVolume => 'قەبارە';

  @override
  String get measLineRepresents => 'ئەو هێڵەی کێشاتە نوێنەرایەتی ئەمە دەکات:';

  @override
  String get measMeasure => 'پێوانەکردن';

  @override
  String get measSetScale => 'دیاریکردنی پێوەری پێوانەکردن';

  @override
  String get measSetScaleButton => 'دیاریکردنی پێوەر';

  @override
  String get measVolumeDepth => 'قووڵیی قەبارە';

  @override
  String get menuAddNode => 'زیادکردنی گرێ';

  @override
  String get menuAddLeader => 'زیادکردنی هێڵی ئاماژە';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'جێبەجێکردنی تێبینییەکان لەسەر پەڕەکان',
      one: 'جێبەجێکردنی تێبینی لەسەر پەڕەکان',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'جێبەجێکردن لەسەر پەڕەکان…';

  @override
  String get menuBringToFront => 'هێنانە پێشەوە';

  @override
  String get menuCheck => 'دیاریکردن';

  @override
  String get menuChooseValue => 'هەڵبژاردنی نرخ…';

  @override
  String get menuClearCheck => 'لابردنی دیاریکردن';

  @override
  String get menuConvertToCheckBox => 'گۆڕین بۆ چوارگۆشەی دیاریکردن';

  @override
  String get menuConvertToImageButton => 'گۆڕین بۆ دوگمەی وێنە';

  @override
  String get menuConvertToTextField => 'گۆڕین بۆ خانەی دەق';

  @override
  String get menuDeleteField => 'سڕینەوەی خانە';

  @override
  String get menuEditValue => 'دەستکاریکردنی نرخ…';

  @override
  String get menuFieldName => 'ناوی خانە';

  @override
  String get menuFieldValue => 'نرخی خانە';

  @override
  String get menuFlattenForm => 'تەختکردنی فۆرم';

  @override
  String get menuLock => 'قفڵکردن';

  @override
  String get menuUnlock => 'لادانی قفڵ';

  @override
  String get menuRecolour => 'گۆڕینی ڕەنگ…';

  @override
  String get menuRemoveNode => 'لابردنی گرێ';

  @override
  String get menuRemoveLeader => 'لابردنی هێڵی ئاماژە';

  @override
  String get menuSaveToStamps => 'پاشەکەوتکردن لە مۆرەکان';

  @override
  String get menuSetAsDefaultStyle => 'دیاریکردن وەک شێوازی بنەڕەتی';

  @override
  String get menuRename => 'گۆڕینی ناو…';

  @override
  String get menuSelectOption => 'هەڵبژاردنی بژاردە';

  @override
  String get menuSendToBack => 'بردنە دواوە';

  @override
  String get menuSetImage => 'دانانی وێنە…';

  @override
  String get menuTextStyle => 'شێوازی دەق…';

  @override
  String get none => 'هیچ';

  @override
  String get ok => 'باشە';

  @override
  String get overlayColor => 'ڕەنگ';

  @override
  String get overlayEditText => 'دەستکاریکردنی دەق';

  @override
  String get overlayFont => 'فۆنت';

  @override
  String get overlayLarger => 'گەورەتر';

  @override
  String get overlayMore => 'زیاتر';

  @override
  String get overlayNote => 'تێبینی';

  @override
  String get overlaySmaller => 'بچووکتر';

  @override
  String get overlayStampText => 'دەقی مۆر';

  @override
  String get linkDialogTitle => 'زیادکردنی بەستەر';

  @override
  String get linkKindWeb => 'ناونیشانی وێب';

  @override
  String get linkKindPage => 'پەڕە لە بەڵگەنامەدا';

  @override
  String get linkUrlLabel => 'ناونیشانی بەستەر (URL)';

  @override
  String get linkPageLabel => 'ژمارەی پەڕە';

  @override
  String get toolLink => 'بەستەر';

  @override
  String get overlayUnderline => 'هێڵی ژێرەوە';

  @override
  String pageRangeErrorBounds(int count) {
    return 'ژمارەی پەڕەکان لە نێوان 1 و $count بنووسە.';
  }

  @override
  String get pageRangeErrorOrder => 'نابێت پەڕەی کۆتایی پێش پەڕەی یەکەم بێت.';

  @override
  String get pageRangeFrom => 'لە';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count پەڕە',
      one: 'یەک پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'بۆ';

  @override
  String get panelDragToMovePanel => 'ڕابکێشە بۆ جووڵاندنی بەشەکە';

  @override
  String get paste => 'لکاندن';

  @override
  String get propAlign => 'ڕێکخستنی شوێن';

  @override
  String get propAlignCenter => 'ڕێکخستن لە ناوەڕاست';

  @override
  String get propAlignLeft => 'ڕێکخستن لە چەپ';

  @override
  String get propAlignRight => 'ڕێکخستن لە ڕاست';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تێبینی',
      one: 'یەک تێبینی',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'نووسەر';

  @override
  String get propAutoSize => 'قەبارەی خۆکار';

  @override
  String get propBold => 'تۆخ';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'فۆنتی ناوخۆیی';

  @override
  String get propCallout => 'دەرخەری تێبینی';

  @override
  String get propCharSpacing => 'بۆشایی نێوان پیتەکان';

  @override
  String get propColor => 'ڕەنگ';

  @override
  String get propColour => 'ڕەنگ';

  @override
  String get propContents => 'ناوەڕۆک';

  @override
  String get propCornerRadius => 'چەماوەیی گۆشە';

  @override
  String get propEditsApplyToAll =>
      'دەستکارییەکان بەسەر هەموو تێبینییە هاوشێوەکاندا جێبەجێ دەبن';

  @override
  String get propFieldName => 'ناوی خانە';

  @override
  String get propFieldTypeCheckBox => 'چوارگۆشەی دیاریکردن';

  @override
  String get propFieldTypeComboBox => 'پێرستی کشاوە';

  @override
  String get propFieldTypeImageButton => 'دوگمەی وێنە';

  @override
  String get propFieldTypeListBox => 'چوارگۆشەی پێرست';

  @override
  String get propFieldTypeRadioGroup => 'گرووپی بژاردەکان';

  @override
  String get propFieldTypeSignature => 'واژوو';

  @override
  String get propFieldTypeText => 'خانەی دەق';

  @override
  String propFieldTypeTooltip(String type) {
    return 'جۆری خانە: $type';
  }

  @override
  String get propFieldTypeUnknown => 'خانەی نەناسراو';

  @override
  String get propFill => 'پڕکردنەوە';

  @override
  String get propFont => 'فۆنت';

  @override
  String get propFontSubsetTooltip =>
      'ئەم فۆنتە سنووردار کراوە - تەنها ئەو پیتانە دەنووسرێن کە پێشتر لە بەڵگەنامەکەدا بەکارهاتوون.';

  @override
  String get propFontWidth => 'پانتایی فۆنت';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'لار';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'پیتە سنووردارەکان';

  @override
  String get propLineEnd => 'کۆتایی هێڵ';

  @override
  String get propLineEndingButt => 'تەخت';

  @override
  String get propLineEndingCircle => 'بازنە';

  @override
  String get propLineEndingClosedArrow => 'تیرێکی داخراو';

  @override
  String get propLineEndingClosedArrowRev => 'تیرێکی داخراو (پێچەوانە)';

  @override
  String get propLineEndingDiamond => 'ئەڵماس';

  @override
  String get propLineEndingOpenArrow => 'تیرێکی کراوە';

  @override
  String get propLineEndingOpenArrowRev => 'تیرێکی کراوە (پێچەوانە)';

  @override
  String get propLineEndingSlash => 'هێڵی لار';

  @override
  String get propLineEndingSquare => 'چوارگۆشە';

  @override
  String get propLineSpacing => 'بۆشایی دێڕەکان';

  @override
  String get propLineStart => 'دەستپێکی هێڵ';

  @override
  String get propLineType => 'جۆری هێڵ';

  @override
  String get propLoadFont => 'بارکردنی فۆنت…';

  @override
  String get propLoadFontSubtitle => 'پەڕگەی TTF یان OTF';

  @override
  String get propMoreColors => 'ڕەنگی زیاتر…';

  @override
  String get propMultiline => 'فرەدێڕ';

  @override
  String get propNoFill => 'بێ پڕکردنەوە';

  @override
  String get propNoFontsFound => 'هیچ فۆنتێک نەدۆزرایەوە';

  @override
  String get propNoOutline => 'بێ چوارچێوە';

  @override
  String get propOpacity => 'شەفافییەت';

  @override
  String get propOutline => 'چوارچێوە';

  @override
  String get propPageLabel => 'پەڕە';

  @override
  String propPageNumber(int number) {
    return 'پەڕەی $number';
  }

  @override
  String get propPropertiesTitle => 'تایبەتمەندییەکان';

  @override
  String get propRecentlyUsed => 'دواین بەکارهاتوو';

  @override
  String get propScale => 'پێوەر';

  @override
  String get propSearchFonts => 'گەڕان لە فۆنتەکان';

  @override
  String get propSectionAllFonts => 'هەموو فۆنتەکان';

  @override
  String get propSectionAppearance => 'ڕووکار';

  @override
  String get propSectionContent => 'ناوەڕۆک';

  @override
  String get propSectionFormField => 'خانەی فۆرم';

  @override
  String get propSectionInThisDocument => 'لەم بەڵگەنامەیەدا';

  @override
  String get propSectionPositionSize => 'شوێن و قەبارە (pt)';

  @override
  String get propSectionSelection => 'دیاریکراو';

  @override
  String get propSectionText => 'دەق';

  @override
  String get propSelectAnnotationPrompt =>
      'تێبینییەک دیاری بکە بۆ بینینی تایبەتمەندییەکانی';

  @override
  String get propSize => 'قەبارە';

  @override
  String get propStandardPdfFont => 'فۆنتی پێوانەیی PDF';

  @override
  String get propStroke => 'هێڵ';

  @override
  String get propStyle => 'شێواز';

  @override
  String get propSystemFont => 'فۆنتی سیستەم';

  @override
  String get propType => 'جۆر';

  @override
  String get propUnderline => 'هێڵی ژێرەوە';

  @override
  String get propVaries => 'جیاواز';

  @override
  String get redo => 'دووبارەکردنەوە';

  @override
  String get reflowNoContent => 'هیچ ناوەڕۆکێک شیاوی دەرهێنان نییە';

  @override
  String reflowPageLabel(int number) {
    return 'پەڕەی $number';
  }

  @override
  String get reflowSaveOrShare => 'پاشەکەوتکردن یان هاوبەشکردن';

  @override
  String get reflowViewFigure => 'پیشاندانی وێنە/شێوە';

  @override
  String get remove => 'لابردن';

  @override
  String get rename => 'گۆڕینی ناو';

  @override
  String get reset => 'گەڕاندنەوە بۆ بنەڕەت';

  @override
  String get save => 'پاشەکەوتکردن';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'پەڕەی $page';
  }

  @override
  String get sbarCallout => 'دەرخەری تێبینی';

  @override
  String get sbarFieldButton => 'خانەی دوگمە';

  @override
  String get sbarFieldChoice => 'خانەی هەڵبژاردن';

  @override
  String get sbarFieldGeneric => 'خانەی فۆرم';

  @override
  String get sbarFieldSignature => 'خانەی واژوو';

  @override
  String get sbarFieldText => 'خانەی دەق';

  @override
  String get sbarStateAccepted => 'پەسەندکراو';

  @override
  String get sbarStateCancelled => 'هەڵوەشاوەتەوە';

  @override
  String get sbarStateMarked => 'نیشانکراو';

  @override
  String get sbarStateRejected => 'ڕەتکراوەتەوە';

  @override
  String get sbarStateResolved => 'چارەسەرکراو';

  @override
  String get sbarStateUnmarked => 'نیشان نەکراو';

  @override
  String get searchAnnotations => 'گەڕان لە تێبینییەکان';

  @override
  String get searchClearSearch => 'پاککردنەوەی گەڕان';

  @override
  String get searchEmptyHint =>
      'لە بەڵگەنامەکەدا بگەڕێ بۆ بینینی هەموو ئەنجامەکان لێرە';

  @override
  String get searchMatchCase => 'ڕەچاوکردنی پیتی گەورە و بچووک';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count هاوتا',
      one: 'یەک هاوتا',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'هاوتای داهاتوو';

  @override
  String searchNoMatches(String query) {
    return 'هیچ ئەنجامێک بۆ «$query» نەدۆزرایەوە';
  }

  @override
  String searchPageHeader(int page) {
    return 'پەڕەی $page';
  }

  @override
  String get searchPreviousMatch => 'هاوتای پێشوو';

  @override
  String get searchRegex => 'دەربڕینی ڕێکخراو (Regex)';

  @override
  String get searchReplace => 'جێگرتنەوە';

  @override
  String get searchReplaceAll => 'جێگرتنەوەی هەمووی';

  @override
  String get searchReplaceHint => 'جێگرتنەوە بە';

  @override
  String get searchReplaceNotTargetable =>
      'ناتوانرێت ئەم هاوتایە بە تەنیا بگۆڕدرێت — «جێگرتنەوەی هەمووی» بەکاربهێنە، یان بە ئامرازی ناوەڕۆک دەستکاری بکە';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count هاوتا جێگۆڕکێ کران',
      one: 'یەک هاوتا جێگۆڕکێ کرا',
      zero: 'هیچ نەگۆڕدرا',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'ئەنجامەکانی گەڕان';

  @override
  String get searchWholeWord => 'تەواوی وشە';

  @override
  String get shellControls => 'کۆنترۆڵەکان';

  @override
  String get shellDefaultAuthor => 'نووسەری بنەڕەتی…';

  @override
  String get formXfaUnsupportedNotice =>
      'ئەم فۆرمە شێوازی XFA بەکاردەهێنێت کە لێرە پڕناکرێتەوە، بۆیە خانەکانی دەرناکەون. لە بەرنامەیەکدا بیکەرەوە کە پشتگیری لە فۆرمەکانی XFA بکات.';

  @override
  String get shellHighlightFormFields => 'دیاریکردنی خانەکانی فۆرم';

  @override
  String get shellKeyboardShortcutsMenu => 'کورتەڕێکانی تەختەکلیل…';

  @override
  String get shellKeyboardShortcutsTitle => 'کورتەڕێکانی تەختەکلیل';

  @override
  String get shellShortcutsSearchHint => 'گەڕان لە کورتەڕێکان';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'هیچ کورتەڕێیەک لەگەڵ «$query» ناگونجێت';
  }

  @override
  String get shellShortcutGroupSelect => 'دیاریکردن';

  @override
  String get shellShortcutGroupMarkup => 'هێماکردن';

  @override
  String get shellShortcutGroupDraw => 'وێنەکێشان';

  @override
  String get shellShortcutGroupShapes => 'شێوەکان';

  @override
  String get shellShortcutGroupInsert => 'خستنەناو';

  @override
  String get shellShortcutGroupMeasure => 'پێوانەکردن';

  @override
  String get shellShortcutGroupEdit => 'دەستکاریکردن';

  @override
  String get shellNotSet => 'دیاری نەکراوە';

  @override
  String get shellPageColor => 'ڕەنگی پەڕە…';

  @override
  String get shellPageGrid => 'تۆڕی پەڕە';

  @override
  String get shellViewPages => 'پەڕەکان';

  @override
  String get shellPanelAnnotations => 'تێبینییەکان';

  @override
  String get shellPanelBookmarks => 'نیشانەکان';

  @override
  String get shellPanelPages => 'پەڕەکان';

  @override
  String get shellPanelProperties => 'تایبەتمەندییەکان';

  @override
  String get shellPanelSearchResults => 'ئەنجامەکانی گەڕان';

  @override
  String get shellPanels => 'پانێڵەکان';

  @override
  String get shellPressAKey => 'پەنجە بنێ بە دوگمەیەکدا';

  @override
  String get shellPressLetterKeyHint =>
      'پەنجە بنێ بە پیتێکدا، یان Shift بۆ جۆرێکی تر، یان Delete بۆ سڕینەوە.';

  @override
  String get shellReflow => 'ڕێکخستنەوەی دەق';

  @override
  String get shellReflowText => 'ڕێکخستنەوەی دەق';

  @override
  String get shellResetZoom => 'گەڕاندنەوەی قەبارەی بنەڕەتی';

  @override
  String get shellSectionShell => 'واژە و ڕووکار';

  @override
  String get shellSectionView => 'پیشاندان';

  @override
  String get shellSettings => 'ڕێکخستنەکان';

  @override
  String get shellShowAnnotations => 'پیشاندانی تێبینییەکان';

  @override
  String get shellShowScrollbarChapters =>
      'پیشاندانی بەشەکان لەسەر شریتی جووڵە';

  @override
  String get shellTabHere => 'تابی نوێ لێرە';

  @override
  String get shellUnbound => 'پەیوەست نەکراو';

  @override
  String get shellZoom => 'گەورەکردن/بچووککردن';

  @override
  String sidebarByAuthor(String author) {
    return 'لەلایەن $author';
  }

  @override
  String get sidebarCancelSelection => 'هەڵوەشاندنەوەی دیاریکردن';

  @override
  String get sidebarClearSearch => 'پاککردنەوەی گەڕان';

  @override
  String get sidebarDeleteSelected => 'سڕینەوەی دیاریکراوەکان';

  @override
  String get sidebarDeleteSignature => 'سڕینەوەی واژوو';

  @override
  String get sidebarLockAnnotation => 'قفڵکردن';

  @override
  String get sidebarUnlockAnnotation => 'لادانی قفڵ';

  @override
  String get sidebarMore => 'زیاتر';

  @override
  String get sidebarNoAnnotations => 'هیچ تێبینییەک نییە';

  @override
  String get sidebarNoMatchingAnnotations => 'هیچ تێبینییەکی هاوتا نییە';

  @override
  String sidebarPageHeader(int number) {
    return 'پەڕەی $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'ئەمە واژووی دیجیتاڵی لە بەڵگەنامەکە دەسڕێتەوە. دەتوانیت ئەم کردارە پاشگەز بکەیتەوە.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'ئەمە واژووی دیجیتاڵیی «$name» لە بەڵگەنامەکە دەسڕێتەوە. دەتوانیت ئەم کردارە پاشگەز بکەیتەوە.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'واژوو بسڕدرێتەوە؟';

  @override
  String get sidebarReopen => 'کردنەوەی دووبارە';

  @override
  String get sidebarReply => 'وەڵامدانەوە';

  @override
  String get sidebarResolve => 'چارەسەرکراو';

  @override
  String get sidebarSearchHint => 'گەڕان لە تێبینییەکان';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دیاریکراون',
      one: 'یەک دیاریکراوە',
    );
    return '$_temp0';
  }

  @override
  String get sidebarSignatureChecking => 'پشکنین…';

  @override
  String get sidebarSignatureTrusted => 'باوەڕپێکراو — دروستە';

  @override
  String get sidebarSignatureUnverified => 'نەپشکنراو — دروستە';

  @override
  String get sidebarSignatureInvalid => 'نادروستە';

  @override
  String sidebarSignatureSignedBy(String name) {
    return 'واژوو کراوە لەلایەن $name';
  }

  @override
  String sidebarSignatureSignedAt(String time) {
    return 'لە کاتی $time واژوو کراوە';
  }

  @override
  String sidebarSignatureTrustedVia(String authority) {
    return 'باوەڕپێکراوە لە ڕێگەی $authority';
  }

  @override
  String sidebarSignatureTrustedViaList(String authority, String list) {
    return 'باوەڕپێکراوە لە ڕێگەی $authority ($list)';
  }

  @override
  String get sidebarSignatureUntrustedDetail =>
      'واژووکەر لە دەسەڵاتێکی باوەڕپێکراوەوە نییە';

  @override
  String get sidebarSignatureNoAnchors =>
      'هیچ دەسەڵاتێکی باوەڕپێکراو ڕێکنەخراوە';

  @override
  String get sidebarSignatureModified =>
      'بەڵگەنامەکە دوای واژووکردن گۆڕانکاریی تێدا کراوە';

  @override
  String get sidebarSignatureRevoked => 'بڕوانامەی واژووکەر هەڵوەشاوەتەوە';

  @override
  String sidebarSignatureTimestamped(String time) {
    return 'مۆری کاتی لێدراوە لە $time';
  }

  @override
  String sidebarSignatureLevel(String level) {
    return 'ئاستی PAdES: $level';
  }

  @override
  String get sidebarSignatureRevokedStatus => 'هەڵوەشاوەتەوە';

  @override
  String get sidebarSignatureSelfSigned =>
      'واژووی خۆیی: هیچ دەسەڵاتێک پشتڕاستی نەکردووەتەوە کە واژووکەر کێیە';

  @override
  String sidebarSignatureUnknownIssuer(String authority) {
    return 'دەرچووە لەلایەن $authority، کە دەسەڵاتێکی باوەڕپێکراو نییە';
  }

  @override
  String sidebarSignatureRevokedOn(String time) {
    return 'بڕوانامەی واژووکەر لە $time هەڵوەشاوەتەوە';
  }

  @override
  String sidebarSignatureRevokedAfterSigning(String time) {
    return 'بڕوانامەکە لە $time هەڵوەشاوەتەوە دوای مۆرکردنی واژووەکە';
  }

  @override
  String get sidebarSignatureRevocationGoodLive =>
      'بڕوانامەکە هەڵنەوەشاوەتەوە (پشکنراوە بە ئۆنلاین)';

  @override
  String get sidebarSignatureRevocationGoodEmbedded =>
      'بڕوانامەکە هەڵنەوەشاوەتەوە (بەپێی زانیاریی ناو بەڵگەنامەکە)';

  @override
  String get sidebarSignatureRevocationUnknown => 'دۆخی هەڵوەشاندنەوە نەپشکنرا';

  @override
  String get sidebarWriteReplyHint => 'وەڵامێک بنووسە…';

  @override
  String get sigTitle => 'واژوو';

  @override
  String get sigUseTrackpad => 'بەکارهێنانی تەختەی دەستلێدان (Trackpad)';

  @override
  String get sigTrackpadHint =>
      'بە یەک پەنجە لەسەر تەختەی دەستلێدان بنووسە. دوای تەواوبوون هەر دوگمەیەک دابگرە.';

  @override
  String get signIdCreate => 'دروستکردن';

  @override
  String get signIdEmail => 'ئیمەیڵ (ئارەزوومەندانە)';

  @override
  String get signIdName => 'ناو';

  @override
  String get signIdNameHint =>
      'ناوت، بەو شێوەیەی پێویستە لەسەر واژووەکە دەربکەوێت';

  @override
  String get signIdNameRequired => 'ناوێک بنووسە';

  @override
  String get signIdOrganization => 'دامەزراوە (ئارەزوومەندانە)';

  @override
  String get signIdSelfSignedInfo =>
      'ئەمە پێناسەیەکی خۆ-واژووکراو دروست دەکات. واژووەکان وەک «واژوو کراوە، دروستیی نەزانراوە» لە Adobe Acrobat و بەرنامەکانی تر دەردەکەون. نیشانەی پەسەندکردنی سەوز پێویستی بە بڕوانامەی باوەڕپێکراوی فەرمیی پارەدار هەیە.';

  @override
  String get signIdTitle => 'دروستکردنی پێناسەی واژووکردن';

  @override
  String get stampBox => 'چوارگۆشە';

  @override
  String get stampCircle => 'بازنە';

  @override
  String get stampCustomCaption => 'مۆری تایبەت';

  @override
  String get stampDateFormat => 'شێوازی بەروار';

  @override
  String get stampDeleteComponent => 'سڕینەوەی بەشی دیاریکراو';

  @override
  String get stampDeleteStamp => 'سڕینەوەی مۆر';

  @override
  String get stampEditStamp => 'دەستکاریکردنی مۆر';

  @override
  String get stampExport => 'هەناردەکردن…';

  @override
  String get stampFieldDate => 'بەروار';

  @override
  String get stampFieldDateTime => 'بەروار و کات';

  @override
  String get stampFieldTime => 'کات';

  @override
  String get stampFieldUsername => 'ناوی بەکارهێنەر';

  @override
  String get stampFont => 'فۆنت';

  @override
  String get stampFontBold => 'تۆخ';

  @override
  String get stampFontItalic => 'لار';

  @override
  String get stampHeight => 'بەرزی';

  @override
  String get stampImage => 'وێنە';

  @override
  String get stampImport => 'هاوردەکردن…';

  @override
  String get stampInsertField => 'خستنەناوی خانە';

  @override
  String get stampMoreColors => 'ڕەنگی زیاتر…';

  @override
  String get stampNewStamp => 'مۆری نوێ…';

  @override
  String get stampNewStampTitle => 'مۆری نوێ';

  @override
  String get stampSavedToCollection => 'لە ناو مۆرەکاندا پاشەکەوت کرا';

  @override
  String get stampSelectTextToEdit => 'دەقێک هەڵبژێرە بۆ دەستکاریکردن';

  @override
  String get stampSelectedText => 'دەقی دیاریکراو';

  @override
  String get stampSignature => 'واژوو';

  @override
  String get stampStamps => 'مۆرەکان';

  @override
  String get stampText => 'دەق';

  @override
  String get stampTime12Hour => '١٢ کاتژمێر';

  @override
  String get stampTime24Hour => '٢٤ کاتژمێر';

  @override
  String get stampTimeFormat => 'شێوازی کات';

  @override
  String get stampWidth => 'پانی';

  @override
  String get takeoffArea => 'ڕووبەر';

  @override
  String get takeoffCount => 'ژمارە';

  @override
  String get takeoffEmpty => 'هێشتا هیچ پێوانەیەک نییە.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count گرووپ',
      one: 'یەک گرووپ',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بڕگە',
      one: 'یەک بڕگە',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'درێژی';

  @override
  String get takeoffTitle => 'پوختەی پێوانەکان';

  @override
  String get tbAddInkAnnotation => 'زیادکردنی تێبینی بە قەڵەم';

  @override
  String get tbAlign => 'ڕێکخستن';

  @override
  String get tbAlignBottom => 'ڕێکخستن بۆ خوارەوە';

  @override
  String get tbAlignHorizontalCenters => 'ڕێکخستن لە ناوەڕاستی ئاسۆیی';

  @override
  String get tbAlignLeft => 'ڕێکخستن بۆ چەپ';

  @override
  String get tbAlignRight => 'ڕێکخستن بۆ ڕاست';

  @override
  String get tbAlignTop => 'ڕێکخستن بۆ سەرەوە';

  @override
  String get tbAlignVerticalCenters => 'ڕێکخستن لە ناوەڕاستی ستوونی';

  @override
  String get tbAnnotationsFlattened =>
      'تێبینییەکان و خانەکانی فۆرم لەگەڵ پەڕەکاندا تەخت کران';

  @override
  String get tbApplyRedactionsMessage =>
      'ناوەڕۆکە دیاریکراوەکە بە یەکجاری لە بەڵگەنامەکە دەسڕدرێتەوە. ئەم کردارە ناگەڕێتەوە.';

  @override
  String get tbApplyRedactionsTitle => 'سانسۆرکردن (ڕەشکردنەوە) جێبەجێ بکرێت؟';

  @override
  String get tbApplyRedactionsTooltip => 'جێبەجێکردنی سانسۆرکردن (ناگەڕێتەوە)';

  @override
  String get tbAutosizeTextBox => 'قەبارەی خۆکاری چوارگۆشەی دەق (Alt+Z)';

  @override
  String get tbAutosizeTextFont => 'گونجاندنی قەبارەی فۆنت لەگەڵ چوارگۆشەی دەق';

  @override
  String get tbCalibrateScaleHint =>
      'هێڵێک بە درێژییەکی دیاریکراو بکێشە بۆ کالیبرەکردنی پێوەر.';

  @override
  String get tbCharSpacing => 'بۆشایی پیتەکان';

  @override
  String get tbCheckBoxOption => 'چوارگۆشەی دیاریکردن';

  @override
  String get tbCheckMarksOnDocument => 'نیشانەکانی دیاریکردن لەسەر بەڵگەنامە';

  @override
  String get tbCropImage => 'بڕینی وێنە';

  @override
  String get tbCroppingImage => 'بڕینی وێنە…';

  @override
  String get tbCropApply => 'پەسەندکردنی بڕین';

  @override
  String get tbCropCancel => 'هەڵوەشاندنەوەی بڕین';

  @override
  String get tbCropReset => 'گەڕاندنەوەی بڕین بۆ بنەڕەت';

  @override
  String get tbColorLabel => 'ڕەنگ';

  @override
  String get tbColorProcessingTooltip =>
      'دەستکاریکردنی ڕەنگ — دۆزینەوە و گۆڕینی ڕەنگەکانی ناوەڕۆکی پەڕە';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ڕەنگ گۆڕدران',
      one: 'یەک ڕەنگ گۆڕدرا',
      zero: 'هیچ ڕەنگێکی هاوتا نەدۆزرایەوە',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'گۆڕین بۆ چوارگۆشەی دیاریکردن';

  @override
  String get tbConvertToImageButton => 'گۆڕین بۆ دوگمەی وێنە';

  @override
  String get tbConvertToTextField => 'گۆڕین بۆ خانەی دەق';

  @override
  String get tbCornerRadius => 'چەماوەیی گۆشە';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'سڕینەوەی $count تێبینی',
      one: 'سڕینەوەی تێبینی',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'سڕینەوەی بڕگە';

  @override
  String get tbDeleteField => 'سڕینەوەی خانە';

  @override
  String get tbDiscardDrawing => 'فڕێدانی وێنەکێشان';

  @override
  String get tbDistributeHorizontally => 'دابەشکردنی یەکسانی ئاسۆیی';

  @override
  String get tbDistributeVertically => 'دابەشکردنی یەکسانی ستوونی';

  @override
  String get tbDrawNewSignature => 'کێشانی واژووی نوێ…';

  @override
  String get tbEditAnnotationText => 'دەستکاریکردنی دەقی تێبینی';

  @override
  String get tbEditTextStyle => 'دەستکاریکردنی دەق و شێواز';

  @override
  String get tbElement => 'بڕگە';

  @override
  String get tbEraserSize => 'قەبارەی سڕەرەوە';

  @override
  String get tbFieldActions => 'کردارەکانی خانە';

  @override
  String get tbFieldName => 'ناوی خانە';

  @override
  String tbFieldNamed(String name) {
    return 'خانە: $name';
  }

  @override
  String get tbFieldValue => 'نرخی خانە';

  @override
  String get tbFill => 'پڕکردنەوە';

  @override
  String get tbFingerDraws =>
      'پەنجە دەنەخشێنێت - لێبدە بۆ ئەوەی لەبری ئەوە پەڕەکە بجوڵێنێت';

  @override
  String get tbFingerScrolls =>
      'پەنجە دەجوڵێنێت (قەڵەم دەنەخشێنێت) - لێبدە تا بنەخشێنێت';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'تەختکردنی تێبینییەکان و خانەکانی فۆرم لەگەڵ پەڕەکان';

  @override
  String get tbFlattenForm => 'تەختکردنی فۆرم';

  @override
  String get tbFlattenFormBakeValues =>
      'تەختکردنی فۆرم - چەسپاندنی نرخەکان لە پەڕەکاندا';

  @override
  String get tbFlattenLabel => 'تەختکردن';

  @override
  String get tbFont => 'فۆنت';

  @override
  String get tbFontSize => 'قەبارەی فۆنت';

  @override
  String get tbFontWidth => 'پانتایی فۆنت';

  @override
  String get tbFormFieldsFlattened => 'خانەکانی فۆرم لە پەڕەکاندا تەخت کران';

  @override
  String get tbGroupDraw => 'نەخشاندن';

  @override
  String get tbGroupEdit => 'دەستکاریکردن';

  @override
  String get tbGroupInsert => 'خستنەناو';

  @override
  String get tbGroupMarkup => 'هێماکردن';

  @override
  String get tbGroupMeasure => 'پێوانەکردن';

  @override
  String get tbGroupSelect => 'دیاریکردن';

  @override
  String get tbGroupShapes => 'شێوەکان';

  @override
  String get tbImageButtonOption => 'دوگمەی وێنە';

  @override
  String get tbLineEnd => 'کۆتایی هێڵ';

  @override
  String get tbLineSpacing => 'بۆشایی دێڕەکان';

  @override
  String get tbLineStart => 'دەستپێکی هێڵ';

  @override
  String get tbLineType => 'جۆری هێڵ';

  @override
  String get tbManageStamps => 'بەڕێوەبردنی مۆرەکان…';

  @override
  String get tbMarkupHighlight => 'دیاریکردن';

  @override
  String get tbMarkupHighlightTip => 'دیاریکردنی دەق';

  @override
  String get tbMarkupSquiggly => 'شەپۆلاوی';

  @override
  String get tbMarkupSquigglyTip => 'هێڵی ژێرەوەی شەپۆلاوی بۆ دەق';

  @override
  String get tbMarkupStrikeOut => 'هێڵ بەسەرداکێشان';

  @override
  String get tbMarkupStrikeOutTip => 'کێشانی هێڵ بەسەر دەقدا';

  @override
  String get tbMarkupUnderline => 'هێڵی ژێرەوە';

  @override
  String get tbMarkupUnderlineTip => 'هێڵی ژێرەوە بۆ دەق';

  @override
  String get tbMoreColors => 'ڕەنگی زیاتر…';

  @override
  String get tbNameArrow => 'تیر';

  @override
  String get tbNameCallout => 'دەرخەری تێبینی';

  @override
  String get tbNameCloudPolygon => 'فرەگۆشەی هەوری';

  @override
  String get tbNameCount => 'ژماردن';

  @override
  String get tbNameDigitalSignature => 'واژووی دیجیتاڵی';

  @override
  String get tbNameDraw => 'وێنەکێشان';

  @override
  String get tbNameEllipse => 'هێلکەیی';

  @override
  String get tbNameEraser => 'سڕینەوەی هێڵەکانی قەڵەم';

  @override
  String get tbNameHand => 'دەست';

  @override
  String get tbNameHighlight => 'دیاریکردن';

  @override
  String get tbNameImage => 'وێنە';

  @override
  String get tbNameLine => 'هێڵ';

  @override
  String get tbNameMeasureAngle => 'پێوانەکردنی گۆشە';

  @override
  String get tbNameMeasureArc => 'پێوانەکردنی درێژیی کەوانە';

  @override
  String get tbNameMeasureArea => 'پێوانەکردنی ڕووبەر';

  @override
  String get tbNameMeasureDistance => 'پێوانەکردنی دووری';

  @override
  String get tbNameMeasurePerimeter => 'پێوانەکردنی چێوە';

  @override
  String get tbNameMeasureSlope => 'پێوانەکردنی لێژی (بەرزبوونەوە/امتداد)';

  @override
  String get tbNameMeasureVolume => 'پێوانەکردنی قەبارە (ڕووبەر × قووڵی)';

  @override
  String get tbNameNote => 'تێبینی';

  @override
  String get tbNamePolygon => 'فرەگۆشە';

  @override
  String get tbNamePolyline => 'فرەهێڵ';

  @override
  String get tbNameRectangle => 'چوارگۆشە';

  @override
  String get tbNameSelect => 'دیاریکردن';

  @override
  String get tbNameSignature => 'واژوو';

  @override
  String get tbNameStamp => 'مۆر';

  @override
  String get tbNameTextBox => 'چوارگۆشەی دەق';

  @override
  String get tbNewFieldType =>
      'جۆری خانەی نوێ - ڕایبکێشە سەر پەڕەکە بۆ زیادکردن';

  @override
  String get tbNoAnnotationsToFlatten =>
      'هیچ تێبینی یان خانەیەکی فۆرم نییە بۆ تەختکردن';

  @override
  String get tbNoCustomStamps => 'هیچ مۆرێکی تایبەت نییە';

  @override
  String get tbNoFormFieldsToFlatten => 'هیچ خانەیەکی فۆرم نییە بۆ تەختکردن';

  @override
  String get tbNoRedactionsToApply => 'هیچ سانسۆرێک نییە بۆ جێبەجێکردن';

  @override
  String get tbNoteTitle => 'تێبینی';

  @override
  String get tbOpacity => 'شەفافییەت';

  @override
  String get tbOutline => 'چوارچێوە';

  @override
  String get tbPatternScale => 'پێوەری نەخش';

  @override
  String get tbPickColorFromPage => 'هەڵبژاردنی ڕەنگ لە پەڕەکەوە';

  @override
  String get tbRedactionsApplied => 'سانسۆرکردنەکان جێبەجێ کران';

  @override
  String get tbRedoShortcut => 'دووبارەکردنەوە (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'ڕێکخستنەوەی دەق نەکرا - ئەمە بڕگەیەکی یەک ستوونی نییە. لەبری ئەوە گۆڕینی دەق تاقی بکەرەوە.';

  @override
  String get tbReflowParagraph => 'ڕێکخستنەوەی بڕگە';

  @override
  String get tbRenameField => 'گۆڕینی ناوی خانە';

  @override
  String get tbRenameFieldEllipsis => 'گۆڕینی ناوی خانە…';

  @override
  String get tbReplaceImage => 'گۆڕینی وێنە';

  @override
  String get tbReplaceImageFailed => 'گۆڕینی وێنە سەرکەوتوو نەبوو';

  @override
  String get tbReplaceText => 'گۆڕینی دەق';

  @override
  String get tbSaveImage => 'پاشەکەوتکردنی وێنە';

  @override
  String get tbSaveShortcut => 'پاشەکەوتکردن… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'پێوەر';

  @override
  String get tbSelectTextForMarkup =>
      'جۆری هێما دیاری بکە، پاشان دەقەکە هەڵبژێرە';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دیاریکراون',
      one: 'دیاریکردن',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'دیاریکردن…';

  @override
  String get tbStamp => 'مۆر';

  @override
  String get tbStampText => 'دەقی مۆر';

  @override
  String get tbStrokeOpacityFont => 'هێڵ، شەفافییەت، فۆنت';

  @override
  String get tbStrokeWidthLabel => 'ئەستووریی هێڵ';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'ئەستووریی هێڵ: $width';
  }

  @override
  String get tbStyle => 'شێواز';

  @override
  String get tbTakeoffTotals => 'سەرجەمی پێوانەکان';

  @override
  String get tbTextBorder => 'چوارچێوەی دەق';

  @override
  String get tbTextColour => 'ڕەنگی دەق';

  @override
  String get tbTextFieldOption => 'خانەی دەق';

  @override
  String get tbTextFill => 'پڕکردنەوەی دەق';

  @override
  String get tbTextStyleEllipsis => 'شێوازی دەق…';

  @override
  String get tbTextTitle => 'دەق';

  @override
  String get tbTipCallout =>
      'دەرخەری تێبینی - لە خاڵەکەوە ڕایبکێشە بۆ شوێنی چوارگۆشەکە';

  @override
  String get tbTipContent => 'دەستکاریکردنی ناوەڕۆکی پەڕە';

  @override
  String get tbTipCount => 'ژماردن - کلیک بکە بۆ دانانی نیشانەکان و ژماردنیان';

  @override
  String get tbTipDigitalSignature =>
      'واژووی دیجیتاڵی - چوارگۆشەیەک بکێشە بۆ دانان و واژووکردن';

  @override
  String get tbTipForm =>
      'خانەکانی فۆرم - کلیک بکە بۆ دیاریکردن، دوو کلیک بۆ پڕکردنەوە، ڕابکێشە بۆ زیادکردن';

  @override
  String get tbTipHighlightDraw => 'دیاریکردن - کێشان بە دەستی ئازاد';

  @override
  String get tbTipImage => 'وێنە - کلیک بکە بۆ دانان، یان چوارگۆشەیەک ڕابکێشە';

  @override
  String get tbTipMeasureAngle => 'پێوانەکردنی گۆشە - کلیک لە سێ خاڵ بکە';

  @override
  String get tbTipMeasureArc =>
      'پێوانەکردنی درێژیی کەوانە - کلیک لە سێ خاڵ بکە';

  @override
  String get tbTipRedact =>
      'سانسۆر (ڕەشکردنەوە) - ناوچەیەک دیاری بکە، پاشان جێبەجێی بکە';

  @override
  String get tbTipSignature => 'واژوو - کلیک لە پەڕەکە بکە بۆ دانانی';

  @override
  String get tbTipSnapshot =>
      'گرتنی بەشێک وەک وێنە - ناوچەیەک دیاری بکە بۆ گرتنی';

  @override
  String get tbToolContent => 'ناوەڕۆک';

  @override
  String get tbToolForm => 'فۆرم';

  @override
  String get tbToolRedact => 'سانسۆر';

  @override
  String get tbToolSnapshot => 'وێنەی خێرا (Snapshot)';

  @override
  String get tbTools => 'ئامرازەکان';

  @override
  String get tbTotals => 'سەرجەمەکان';

  @override
  String get tbTypeTextEachTime => 'نووسینی دەق لە هەر جارێکدا';

  @override
  String get tbUnderline => 'هێڵی ژێرەوە';

  @override
  String get tbUndoShortcut => 'پاشگەزبوونەوە (⌘Z)';

  @override
  String get textStyleFont => 'فۆنت';

  @override
  String get textStyleFontSize => 'قەبارەی فۆنت';

  @override
  String get textStyleKeep => 'هێشتنەوە';

  @override
  String get textStyleStyle => 'شێواز';

  @override
  String get textStyleText => 'دەق';

  @override
  String get textStyleTextFill => 'پڕکردنەوەی دەق';

  @override
  String get textStyleTitle => 'دەستکاریکردنی دەق و شێواز';

  @override
  String get thumbAddPage => 'زیادکردنی پەڕە';

  @override
  String get thumbClearSelection => 'پاککردنەوەی دیاریکردن';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'کۆپیکردنی $count پەڕە',
      one: 'کۆپیکردنی پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'کۆپیکردنی پەڕە دیاریکراوەکان';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بڕینی $count پەڕە',
      one: 'بڕینی پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'بڕینی پەڕە دیاریکراوەکان';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'سڕینەوەی $count پەڕە',
      one: 'سڕینەوەی پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'سڕینەوەی پەڕە دیاریکراوەکان';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'دووبارەکردنەوەی $count پەڕە',
      one: 'دووبارەکردنەوەی پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'هەناردەکردنی پەڕەکان…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'هەناردەکردنی $count پەڕە…',
      one: 'هەناردەکردنی پەڕە…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'هەناردەکردنی پەڕە دیاریکراوەکان';

  @override
  String get thumbInsertBlankAfter => 'خستنەناوی پەڕەی بەتاڵ لە دوای';

  @override
  String get thumbInsertBlankBefore => 'خستنەناوی پەڕەی بەتاڵ لە پێش';

  @override
  String get thumbInsertFileFailed => 'نەتوانرا ئەم پەڕگەیە بخرێتە ناوەوە.';

  @override
  String get thumbInsertPdf => 'خستنەناوی PDF…';

  @override
  String get thumbPageActions => 'کردارەکانی پەڕە';

  @override
  String thumbPageNumber(int number) {
    return 'پەڕەی $number';
  }

  @override
  String get thumbPages => 'پەڕەکان';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لکاندنی $count پەڕە',
      one: 'لکاندنی پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'سووڕاندن ١٨٠ پلە';

  @override
  String get thumbRotateLeft => 'سووڕاندن بۆ چەپ';

  @override
  String get thumbRotatePageRight => 'سووڕاندنی پەڕە بۆ ڕاست';

  @override
  String get thumbRotateRight => 'سووڕاندن بۆ ڕاست';

  @override
  String get thumbRotateSelectedLeft => 'سووڕاندنی پەڕە دیاریکراوەکان بۆ چەپ';

  @override
  String get thumbRotateSelectedRight => 'سووڕاندنی پەڕە دیاریکراوەکان بۆ ڕاست';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count پەڕە دیاریکراون',
      one: 'یەک پەڕە دیاریکراوە',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'پاشگەزبوونەوە';

  @override
  String get viewerEditFontUnsafe =>
      'ئەم فۆنتە یان کۆدکردنەی PDF ناتوانرێت بە دڵنیایی دەستکاری بکرێت.';

  @override
  String get viewerEditNeedsSinglePage =>
      'دەستکاریکردن پێویستی بە دیاریکردنی دەقە لە یەک پەڕەدا.';

  @override
  String get viewerEditNotEditableRun =>
      'ئەم بەشە دیاریکراوە دەقێکی شیاوی دەستکاریکردن نییە لە ناوەڕۆکی پەڕەکەدا.';

  @override
  String get viewerEditStyleUnchangeable =>
      'دەتوانرێت فۆنتی ئەم PDFـە دووبارە بنووسرێتەوە، بەڵام شێوازەکەی ناگۆڕدرێت.';

  @override
  String get viewerEditTextStyle => 'دەستکاریکردنی دەق و شێواز';

  @override
  String get viewerMarkup => 'هێماکردن';

  @override
  String get viewerMarkupHighlight => 'دیاریکردن';

  @override
  String get viewerMarkupSquiggly => 'شەپۆلاوی';

  @override
  String get viewerMarkupStrikeOut => 'هێڵ بەسەرداکێشان';

  @override
  String get viewerMarkupUnderline => 'هێڵی ژێرەوە';

  @override
  String get viewerSelectAll => 'دیاریکردنی هەموو';

  @override
  String get annotationLibraryTitle => 'کتێبخانەی تێبینییەکان';

  @override
  String get annotationLibraryEmpty => 'هیچ تێبینییەکی پاشەکەوتکراو نییە.';

  @override
  String get annotationLibraryHelp =>
      'تێبینییەکی گونجاو دیاری بکە و لە پێرستەکەی «پاشەکەوتکردن لە کتێبخانە» هەڵبژێرە. بەستەر و خانەکانی فۆرم پاشەکەوت ناکرێن.';

  @override
  String get annotationLibrarySave => 'پاشەکەوتکردن لە کتێبخانەی تێبینییەکان';

  @override
  String get annotationLibrarySaveTitle => 'پاشەکەوتکردنی تێبینی';

  @override
  String get annotationLibraryRenameTitle => 'گۆڕینی ناوی بڕگەی کتێبخانە';

  @override
  String get annotationLibrarySearchHint => 'گەڕان لە کتێبخانە';

  @override
  String get annotationLibraryNoMatches => 'هیچ تێبینییەکی هاوتا نییە.';

  @override
  String get annotationLibraryUngrouped => 'گرووپ نەکراو';

  @override
  String get annotationLibraryChooseGroup => 'گواستنەوە بۆ گرووپ';

  @override
  String get annotationLibraryNewGroup => 'گرووپی نوێ…';

  @override
  String get annotationLibraryGroupTitle => 'گرووپی تێبینیی نوێ';

  @override
  String get annotationLibraryRenameGroupTitle => 'گۆڕینی ناوی گرووپی تێبینی';

  @override
  String get annotationLibraryRemoveGroup => 'لابردنی گرووپ';

  @override
  String get annotationLibraryPlacementHint =>
      'کلیک لەسەر پەڕەکە بکە بۆ دانان. دوگمەی Escape دابگرە بۆ هەڵوەشاندنەوە.';

  @override
  String get annotationLibraryCustomStamps => 'مۆری تایبەت…';

  @override
  String get signatureLibraryManage => 'بەڕێوەبردنی واژووەکان';

  @override
  String get signatureLibraryRenameTitle => 'گۆڕینی ناوی واژوو';

  @override
  String get signatureLibraryEmpty => 'هیچ واژوویەکی پاشەکەوتکراو نییە.';

  @override
  String get splitTitle => 'دابەشکردنی PDF…';

  @override
  String get splitHelp =>
      'مەودای پەڕەکان بنووسە بە کۆما جیاکراوەتەوە. هەر مەودایەک PDFـێکی جیا دروست دەکات.';

  @override
  String get splitRanges => 'مەودای پەڕەکان';

  @override
  String splitInvalidRanges(int count) {
    return 'پەڕەکانی 1–$count بەکاربهێنە، بە کۆما جیاکراونەتەوە. دەبێت بە ڕیزبەندی بن.';
  }

  @override
  String get splitConfirm => 'دابەشکردن';

  @override
  String get splitFailed => 'نەتوانرا ئەم پەڕگەی PDFـە دابەش بکرێت.';

  @override
  String get guidesSnapHint =>
      'ڕێکخستنی کەنار و ناوەڕاستی تێبینییەکان • دوگمەی Alt دابگرە بۆ ڕێگریکردن لە ڕاکێشان';

  @override
  String get tbToolContentDelete => 'سڕینەوە';

  @override
  String get tbTipContentDelete =>
      'سڕینەوەی ناوەڕۆک — چوارگۆشەیەک دیاری بکە، یان خاڵەکانی فرەگۆشە دیاری بکە و دوو کلیک بکە بۆ تەواوکردن';

  @override
  String get menuConvertToRadioGroup => 'گۆڕین بۆ گرووپی بژاردەکان';

  @override
  String get menuConvertToComboBox => 'گۆڕین بۆ پێرستی کشاوە';

  @override
  String get menuConvertToListBox => 'گۆڕین بۆ چوارگۆشەی پێرست';

  @override
  String get menuConvertToSignatureField => 'گۆڕین بۆ خانەی واژوو';

  @override
  String get menuEditOptions => 'دەستکاریکردنی هەڵبژاردنەکان…';

  @override
  String get menuAddRadioButton => 'زیادکردنی دوگمە بۆ گرووپ';

  @override
  String get formOptionsTitle => 'هەڵبژاردنەکانی خانە';

  @override
  String get formOptionsExportValue => 'نرخی هەناردەکردن';

  @override
  String get formOptionsDisplayText => 'دەقی پیشاندراو';

  @override
  String get formOptionsAllowCustomText => 'ڕێگەدان بە دەقی تایبەت';

  @override
  String get formOptionsMultiSelect => 'ڕێگەدان بە چەندین هەڵبژاردن';

  @override
  String get searchFieldHint => 'گەڕان';

  @override
  String progressiveOpenFailed(String error) {
    return 'کردنەوەی بەڵگەنامە سەرکەوتوو نەبوو: $error';
  }

  @override
  String get pageRangeExportTitle => 'هەناردەکردنی پەڕەکان';

  @override
  String get pageRangeExportConfirm => 'هەناردەکردن';

  @override
  String get textStyleKeepFont => 'هێشتنەوە';

  @override
  String get guidesDialogTitle => 'ڕێبەرەکان، ڕاکێشانی گونجاو و ڕاستەکان';

  @override
  String get guidesSmartAlignment => 'هێڵە ڕێبەرە زیرەکەکانی ڕێکخستن';

  @override
  String get guidesPageRulers => 'ڕاستەکانی پەڕە';

  @override
  String get guidesPageRulersHint =>
      'پیشاندانی پێوانەکان بە خاڵ لە کەنارەکانی پەڕە';

  @override
  String get guidesVerticalCursorLine => 'هێڵی ستوونیی نیشاندەری مشک';

  @override
  String get guidesHorizontalCursorLine => 'هێڵی ئاسۆیی نیشاندەری مشک';

  @override
  String get guidesSnapToGrid => 'ڕاکێشان بۆ سەر تۆڕ';

  @override
  String get guidesSnapToGridHint =>
      'دوگمەی Alt دابگرە بۆ ڕێگریکردن لە ڕاکێشان';

  @override
  String get guidesShowGrid => 'پیشاندانی هێڵەکانی تۆڕ';

  @override
  String get guidesShowGridHint => 'تەنها بۆ پیشاندانە؛ بۆ ناو PDF زیاد ناکرێت';

  @override
  String get guidesGridSpacing => 'بۆشایی تۆڕ';

  @override
  String guidesGridSpacingValue(String value) {
    return '$value خاڵ';
  }

  @override
  String get shellCursorGuidesAndGrid => 'هێڵی ڕێبەر و تۆڕی پەڕە';

  @override
  String get commandSaveAs => 'پاشەکەوتکردن بە ناوی…';

  @override
  String get dialogDismiss => 'ڕەتکردنەوە';

  @override
  String get insertPagesTitle => 'خستنەناوی پەڕەکان';

  @override
  String get insertPagesFiles => 'پەڕگەکان';

  @override
  String get insertPagesAddFiles => 'زیادکردنی پەڕگە…';

  @override
  String get insertPagesSortByName => 'ڕیزکردن بەپێی ناو';

  @override
  String get insertPagesNoFiles => 'یەک یان چەند PDFێک زیاد بکە بۆ خستنەناو.';

  @override
  String insertPagesOpenFailed(String names) {
    return 'نەتوانرا $names بکرێتەوە. لەوانەیە پەڕگەکە تێکچووبێت یان بە وشەی نهێنی پارێزرابێت.';
  }

  @override
  String insertPagesFilePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count پەڕە',
      one: '1 پەڕە',
    );
    return '$_temp0';
  }

  @override
  String get insertPagesMoveUp => 'بردنە سەرەوە';

  @override
  String get insertPagesMoveDown => 'بردنە خوارەوە';

  @override
  String get insertPagesRemoveFile => 'لابردن لە لیستەکە';

  @override
  String get insertPagesRange => 'پەڕەکان';

  @override
  String get insertPagesRangeHint => 'هەموو (بۆ نموونە 1-3, 7)';

  @override
  String insertPagesRangeInvalid(int count) {
    return 'پەڕەکانی 1–$count بەکاربهێنە، بۆ نموونە 1-3, 7';
  }

  @override
  String get insertPagesSubsetAll => 'هەموو پەڕەکان';

  @override
  String get insertPagesSubsetOdd => 'پەڕە تاکەکان';

  @override
  String get insertPagesSubsetEven => 'پەڕە جووتەکان';

  @override
  String get insertPagesReverse => 'پێچەوانەکردنەوەی ڕیزبەندی';

  @override
  String get insertPagesPlacement => 'شوێندانان';

  @override
  String get insertPagesBefore => 'پێش';

  @override
  String get insertPagesAfter => 'دوای';

  @override
  String get insertPagesFirstPage => 'یەکەم پەڕە';

  @override
  String get insertPagesLastPage => 'دوایین پەڕە';

  @override
  String get insertPagesPage => 'پەڕە';

  @override
  String get insertPagesPageNumber => 'ژمارەی پەڕە';

  @override
  String insertPagesOfCount(int count) {
    return 'لە $count';
  }

  @override
  String insertPagesPageInvalid(int count) {
    return '1–$count بنووسە';
  }

  @override
  String get insertPagesInterleave => 'تێکەڵکردنی پەڕەکان بە نۆرە';

  @override
  String get insertPagesInterleaveHelp =>
      'لە شوێنی دانانەوە بە نۆرە پەڕەی خراوەناو و پەڕەی هەبوو دابنێ - بۆ نموونە، بۆ پێکەوەلکاندنەوەی پەڕە تاک و جووتەکان کە بە جیا سکان کراون.';

  @override
  String get insertPagesRunInserted => 'پەڕەی خراوەناو لە هەر جارێکدا';

  @override
  String get insertPagesRunExisting => 'پەڕەکانی بەڵگەنامە لە نێوانیاندا';

  @override
  String get insertPagesIncludeBookmarks => 'نیشانەکانیش لەخۆبگرێت';

  @override
  String get insertPagesBookmarkFiles => 'نیشانەیەک بۆ هەر پەڕگەیەک زیاد بکە';

  @override
  String insertPagesSummary(int inserted, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      inserted,
      locale: localeName,
      other: '$inserted پەڕە دەخاتە ناوەوە',
      one: '1 پەڕە دەخاتە ناوەوە',
    );
    String _temp1 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total پەڕەی',
      one: '1 پەڕەی',
    );
    return '$_temp0 - بەڵگەنامەکە $_temp1 دەبێت.';
  }

  @override
  String get insertPagesConfirm => 'خستنەناو';
}
