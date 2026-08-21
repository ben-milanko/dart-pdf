// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class DartPdfEditorLocalizationsAr extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get add => 'إضافة';

  @override
  String get annotCaret => 'علامة إقحام';

  @override
  String get annotCircle => 'دائرة';

  @override
  String get annotFileAttachment => 'مرفق ملف';

  @override
  String get annotFreeText => 'مربع نص';

  @override
  String get annotHighlight => 'تمييز';

  @override
  String get annotInk => 'حبر';

  @override
  String get annotLine => 'خط';

  @override
  String get annotLink => 'رابط';

  @override
  String get annotPolygon => 'مضلّع';

  @override
  String get annotPolyline => 'خط متعدد';

  @override
  String get annotRedact => 'تنقيح';

  @override
  String get annotSquare => 'مربع';

  @override
  String get annotSquiggly => 'متموّج';

  @override
  String get annotStamp => 'ختم';

  @override
  String get annotStrikeOut => 'شطب';

  @override
  String get annotText => 'ملاحظة';

  @override
  String get annotUnderline => 'تسطير';

  @override
  String get annotWidget => 'حقل نموذج';

  @override
  String get apply => 'تطبيق';

  @override
  String get bookmarkAdd => 'إضافة إشارة مرجعية';

  @override
  String get bookmarkAddChild => 'إضافة إشارة مرجعية فرعية';

  @override
  String get bookmarkCollapse => 'طي';

  @override
  String get bookmarkDelete => 'حذف الإشارة المرجعية';

  @override
  String get bookmarkEdit => 'تحرير الإشارة المرجعية';

  @override
  String get bookmarkEmpty => 'لا توجد إشارات مرجعية';

  @override
  String get bookmarkExpand => 'توسيع';

  @override
  String get bookmarkExpandedByDefault => 'موسّعة افتراضيًا';

  @override
  String get bookmarkNoDestination => 'بلا وجهة';

  @override
  String get bookmarkPageFieldLabel => 'صفحة';

  @override
  String bookmarkPageLabel(int number) {
    return 'صفحة $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'الإشارات المرجعية';

  @override
  String get bookmarkTitleLabel => 'العنوان';

  @override
  String get bookmarkUntitled => 'بلا عنوان';

  @override
  String get cancel => 'إلغاء';

  @override
  String get clear => 'مسح';

  @override
  String get close => 'إغلاق';

  @override
  String get colorApplyingChanges => 'جارٍ تطبيق تغييرات اللون…';

  @override
  String get colorColorFormat => 'تنسيق اللون';

  @override
  String get colorColorTitle => 'اللون';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count لون',
      many: 'تم تحديد $count لونًا',
      few: 'تم تحديد $count ألوان',
      two: 'تم تحديد لونين',
      one: 'تم تحديد لون واحد',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'ألوان المستند';

  @override
  String get colorFillColors => 'ألوان التعبئة';

  @override
  String get colorFind => 'بحث';

  @override
  String get colorInDocument => 'في المستند';

  @override
  String get colorNoColorsFound => 'لم يُعثر على ألوان بعد';

  @override
  String get colorNoPageContentColors => 'لم يُعثر على ألوان في محتوى الصفحة';

  @override
  String get colorPalette => 'لوحة الألوان';

  @override
  String get colorPickColor => 'اختيار لون';

  @override
  String get colorProcessingTitle => 'معالجة الألوان';

  @override
  String get colorRecent => 'الأخيرة';

  @override
  String get colorReplace => 'استبدال';

  @override
  String get colorReplaceWithTransparent => 'الاستبدال بشفاف';

  @override
  String get colorScanning => 'جارٍ الفحص…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'جارٍ الفحص $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'الصفحات المحددة ($count)';
  }

  @override
  String get colorStrokeColors => 'ألوان الحدود';

  @override
  String get colorTolerance => 'التسامح';

  @override
  String get colorTransparent => 'شفاف';

  @override
  String get colorWholeDocument => 'المستند بالكامل';

  @override
  String get compareAfter => 'بعد';

  @override
  String get compareBefore => 'قبل';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تغيير',
      many: '$count تغييرًا',
      few: '$count تغييرات',
      two: 'تغييران',
      one: 'تغيير واحد',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تغيير',
      many: '$count تغييرًا',
      few: '$count تغييرات',
      two: 'تغييران',
      one: 'تغيير واحد',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(فارغ)';

  @override
  String get compareNextChange => 'التغيير التالي';

  @override
  String get compareNoChanges => 'لا توجد تغييرات';

  @override
  String get compareNoDifferences => 'لا توجد اختلافات بين المستندين';

  @override
  String get compareOverlay => 'تراكب';

  @override
  String comparePageHeader(int page) {
    return 'صفحة $page';
  }

  @override
  String get comparePreviousChange => 'التغيير السابق';

  @override
  String get compareSideBySide => 'جنبًا إلى جنب';

  @override
  String get copy => 'نسخ';

  @override
  String get cut => 'قص';

  @override
  String get delete => 'حذف';

  @override
  String get done => 'تم';

  @override
  String get edit => 'تحرير';

  @override
  String get editorViewAuthorNameTitle => 'اسم المؤلف';

  @override
  String get lineStyleDashDot => 'شرطة-نقطة';

  @override
  String get lineStyleDashed => 'متقطع';

  @override
  String get lineStyleDotted => 'منقّط';

  @override
  String get lineStyleSolid => 'متصل';

  @override
  String get measCalibrate => 'معايرة';

  @override
  String get measCalibrateScale => 'معايرة المقياس';

  @override
  String get measDepthLabel => 'العمق: ';

  @override
  String get measKindAngle => 'زاوية';

  @override
  String get measKindArc => 'قوس';

  @override
  String get measKindArea => 'مساحة';

  @override
  String get measKindCount => 'عدد';

  @override
  String get measKindLength => 'طول';

  @override
  String get measKindNetArea => 'المساحة الصافية';

  @override
  String get measKindPerimeter => 'محيط';

  @override
  String get measKindSlope => 'ميل';

  @override
  String get measKindVolume => 'حجم';

  @override
  String get measLineRepresents => 'الخط الذي رسمته يمثل:';

  @override
  String get measMeasure => 'قياس';

  @override
  String get measSetScale => 'تعيين مقياس القياس';

  @override
  String get measSetScaleButton => 'تعيين المقياس';

  @override
  String get measVolumeDepth => 'عمق الحجم';

  @override
  String get menuAddNode => 'إضافة عقدة';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تطبيق التعليقات التوضيحية على الصفحات',
      one: 'تطبيق التعليق التوضيحي على الصفحات',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'التطبيق على الصفحات…';

  @override
  String get menuBringToFront => 'إحضار إلى الأمام';

  @override
  String get menuCheck => 'تحديد';

  @override
  String get menuChooseValue => 'اختيار قيمة…';

  @override
  String get menuClearCheck => 'إلغاء التحديد';

  @override
  String get menuConvertToCheckBox => 'تحويل إلى مربع اختيار';

  @override
  String get menuConvertToImageButton => 'تحويل إلى زر صورة';

  @override
  String get menuConvertToTextField => 'تحويل إلى حقل نص';

  @override
  String get menuDeleteField => 'حذف الحقل';

  @override
  String get menuEditValue => 'تحرير القيمة…';

  @override
  String get menuFieldName => 'اسم الحقل';

  @override
  String get menuFieldValue => 'قيمة الحقل';

  @override
  String get menuFlattenForm => 'تسطيح النموذج';

  @override
  String get menuLock => 'قفل';

  @override
  String get menuUnlock => 'إلغاء القفل';

  @override
  String get menuRecolour => 'إعادة التلوين…';

  @override
  String get menuRemoveNode => 'إزالة عقدة';

  @override
  String get menuSaveToStamps => 'حفظ في الأختام';

  @override
  String get menuSetAsDefaultStyle => 'تعيين كنمط افتراضي';

  @override
  String get menuRename => 'إعادة تسمية…';

  @override
  String get menuSelectOption => 'تحديد الخيار';

  @override
  String get menuSendToBack => 'إرسال إلى الخلف';

  @override
  String get menuSetImage => 'تعيين صورة…';

  @override
  String get menuTextStyle => 'نمط النص…';

  @override
  String get none => 'بلا';

  @override
  String get ok => 'موافق';

  @override
  String get overlayColor => 'اللون';

  @override
  String get overlayEditText => 'تحرير النص';

  @override
  String get overlayFont => 'الخط';

  @override
  String get overlayLarger => 'أكبر';

  @override
  String get overlayMore => 'المزيد';

  @override
  String get overlayNote => 'ملاحظة';

  @override
  String get overlaySmaller => 'أصغر';

  @override
  String get overlayStampText => 'نص الختم';

  @override
  String get linkDialogTitle => 'إضافة رابط';

  @override
  String get linkKindWeb => 'عنوان ويب';

  @override
  String get linkKindPage => 'صفحة في المستند';

  @override
  String get linkUrlLabel => 'عنوان URL';

  @override
  String get linkPageLabel => 'رقم الصفحة';

  @override
  String get toolLink => 'رابط';

  @override
  String get overlayUnderline => 'تسطير';

  @override
  String pageRangeErrorBounds(int count) {
    return 'أدخل صفحات بين 1 و$count.';
  }

  @override
  String get pageRangeErrorOrder => 'يجب ألا تكون الصفحة الأخيرة قبل الأولى.';

  @override
  String get pageRangeFrom => 'من';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صفحة',
      many: '$count صفحة',
      few: '$count صفحات',
      two: 'صفحتان',
      one: 'صفحة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'إلى';

  @override
  String get panelDragToMovePanel => 'اسحب لتحريك اللوحة';

  @override
  String get paste => 'لصق';

  @override
  String get propAlign => 'محاذاة';

  @override
  String get propAlignCenter => 'محاذاة للوسط';

  @override
  String get propAlignLeft => 'محاذاة لليسار';

  @override
  String get propAlignRight => 'محاذاة لليمين';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تعليق توضيحي',
      many: '$count تعليقًا توضيحيًا',
      few: '$count تعليقات توضيحية',
      two: 'تعليقان توضيحيان',
      one: 'تعليق توضيحي واحد',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'المؤلف';

  @override
  String get propAutoSize => 'حجم تلقائي';

  @override
  String get propBold => 'عريض';

  @override
  String get propBoldLetter => 'ع';

  @override
  String get propBundledFont => 'خط مضمّن';

  @override
  String get propCallout => 'وسيلة شرح';

  @override
  String get propCharSpacing => 'تباعد الأحرف';

  @override
  String get propColor => 'اللون';

  @override
  String get propColour => 'اللون';

  @override
  String get propContents => 'المحتويات';

  @override
  String get propCornerRadius => 'نصف قطر الزاوية';

  @override
  String get propEditsApplyToAll =>
      'تنطبق التعديلات على جميع التعليقات التوضيحية المتوافقة';

  @override
  String get propFieldName => 'اسم الحقل';

  @override
  String get propFieldTypeCheckBox => 'مربع اختيار';

  @override
  String get propFieldTypeComboBox => 'مربع تحرير وسرد';

  @override
  String get propFieldTypeImageButton => 'زر صورة';

  @override
  String get propFieldTypeListBox => 'مربع قائمة';

  @override
  String get propFieldTypeRadioGroup => 'مجموعة أزرار اختيار';

  @override
  String get propFieldTypeSignature => 'توقيع';

  @override
  String get propFieldTypeText => 'حقل نص';

  @override
  String propFieldTypeTooltip(String type) {
    return 'نوع الحقل: $type';
  }

  @override
  String get propFieldTypeUnknown => 'حقل غير معروف';

  @override
  String get propFill => 'تعبئة';

  @override
  String get propFont => 'الخط';

  @override
  String get propFontSubsetTooltip =>
      'هذا الخط مُجزّأ - يمكن كتابة الأحرف المستخدمة بالفعل في المستند فقط.';

  @override
  String get propFontWidth => 'عرض الخط';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'مائل';

  @override
  String get propItalicLetter => 'م';

  @override
  String get propLimitedCharacters => 'أحرف محدودة';

  @override
  String get propLineEnd => 'نهاية الخط';

  @override
  String get propLineEndingButt => 'مسطّحة';

  @override
  String get propLineEndingCircle => 'دائرة';

  @override
  String get propLineEndingClosedArrow => 'سهم مغلق';

  @override
  String get propLineEndingClosedArrowRev => 'سهم مغلق (معكوس)';

  @override
  String get propLineEndingDiamond => 'معيّن';

  @override
  String get propLineEndingOpenArrow => 'سهم مفتوح';

  @override
  String get propLineEndingOpenArrowRev => 'سهم مفتوح (معكوس)';

  @override
  String get propLineEndingSlash => 'شرطة مائلة';

  @override
  String get propLineEndingSquare => 'مربع';

  @override
  String get propLineSpacing => 'تباعد الأسطر';

  @override
  String get propLineStart => 'بداية الخط';

  @override
  String get propLineType => 'نوع الخط';

  @override
  String get propLoadFont => 'تحميل خط…';

  @override
  String get propLoadFontSubtitle => 'ملف TTF أو OTF';

  @override
  String get propMoreColors => 'مزيد من الألوان…';

  @override
  String get propMultiline => 'متعدد الأسطر';

  @override
  String get propNoFill => 'بلا تعبئة';

  @override
  String get propNoFontsFound => 'لم يُعثر على خطوط';

  @override
  String get propNoOutline => 'بلا إطار';

  @override
  String get propOpacity => 'العتامة';

  @override
  String get propOutline => 'الإطار';

  @override
  String get propPageLabel => 'صفحة';

  @override
  String propPageNumber(int number) {
    return 'صفحة $number';
  }

  @override
  String get propPropertiesTitle => 'الخصائص';

  @override
  String get propRecentlyUsed => 'المستخدمة مؤخرًا';

  @override
  String get propScale => 'المقياس';

  @override
  String get propSearchFonts => 'البحث في الخطوط';

  @override
  String get propSectionAllFonts => 'جميع الخطوط';

  @override
  String get propSectionAppearance => 'المظهر';

  @override
  String get propSectionContent => 'المحتوى';

  @override
  String get propSectionFormField => 'حقل النموذج';

  @override
  String get propSectionInThisDocument => 'في هذا المستند';

  @override
  String get propSectionPositionSize => 'الموضع والحجم (pt)';

  @override
  String get propSectionSelection => 'التحديد';

  @override
  String get propSectionText => 'النص';

  @override
  String get propSelectAnnotationPrompt => 'حدد تعليقًا توضيحيًا لعرض خصائصه';

  @override
  String get propSize => 'الحجم';

  @override
  String get propStandardPdfFont => 'خط PDF قياسي';

  @override
  String get propStroke => 'الحد';

  @override
  String get propStyle => 'النمط';

  @override
  String get propSystemFont => 'خط النظام';

  @override
  String get propType => 'النوع';

  @override
  String get propUnderline => 'تسطير';

  @override
  String get propVaries => 'متغير';

  @override
  String get redo => 'إعادة';

  @override
  String get reflowNoContent => 'لا يوجد محتوى قابل للاستخراج';

  @override
  String reflowPageLabel(int number) {
    return 'صفحة $number';
  }

  @override
  String get reflowSaveOrShare => 'حفظ أو مشاركة';

  @override
  String get reflowViewFigure => 'عرض الشكل';

  @override
  String get remove => 'إزالة';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get save => 'حفظ';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'صفحة $page';
  }

  @override
  String get sbarCallout => 'وسيلة شرح';

  @override
  String get sbarFieldButton => 'حقل زر';

  @override
  String get sbarFieldChoice => 'حقل اختيار';

  @override
  String get sbarFieldGeneric => 'حقل نموذج';

  @override
  String get sbarFieldSignature => 'حقل توقيع';

  @override
  String get sbarFieldText => 'حقل نص';

  @override
  String get sbarStateAccepted => 'مقبول';

  @override
  String get sbarStateCancelled => 'ملغى';

  @override
  String get sbarStateMarked => 'معلّم';

  @override
  String get sbarStateRejected => 'مرفوض';

  @override
  String get sbarStateResolved => 'تم الحل';

  @override
  String get sbarStateUnmarked => 'غير معلّم';

  @override
  String get searchAnnotations => 'البحث في التعليقات التوضيحية';

  @override
  String get searchClearSearch => 'مسح البحث';

  @override
  String get searchEmptyHint => 'ابحث في المستند لعرض كل تطابق هنا';

  @override
  String get searchMatchCase => 'مطابقة حالة الأحرف';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تطابق',
      many: '$count تطابقًا',
      few: '$count تطابقات',
      two: 'تطابقان',
      one: 'تطابق واحد',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'التطابق التالي';

  @override
  String searchNoMatches(String query) {
    return 'لا توجد نتائج عن “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'صفحة $page';
  }

  @override
  String get searchPreviousMatch => 'التطابق السابق';

  @override
  String get searchRegex => 'تعبير نمطي';

  @override
  String get searchReplace => 'استبدال';

  @override
  String get searchReplaceAll => 'استبدال الكل';

  @override
  String get searchReplaceHint => 'استبدال بـ';

  @override
  String get searchReplaceNotTargetable =>
      'يتعذّر استبدال هذا التطابق وحده — استخدم «استبدال الكل» أو حرّره بأداة المحتوى';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم استبدال $count تطابق',
      many: 'تم استبدال $count تطابقًا',
      few: 'تم استبدال $count تطابقات',
      two: 'تم استبدال تطابقين',
      one: 'تم استبدال تطابق واحد',
      zero: 'لم يتم استبدال أي شيء',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'نتائج البحث';

  @override
  String get searchWholeWord => 'كلمة كاملة';

  @override
  String get shellControls => 'عناصر التحكم';

  @override
  String get shellDefaultAuthor => 'المؤلف الافتراضي…';

  @override
  String get shellHighlightFormFields => 'تمييز حقول النموذج';

  @override
  String get shellKeyboardShortcutsMenu => 'اختصارات لوحة المفاتيح…';

  @override
  String get shellKeyboardShortcutsTitle => 'اختصارات لوحة المفاتيح';

  @override
  String get shellShortcutsSearchHint => 'البحث في الاختصارات';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'لا اختصارات تطابق “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'تحديد';

  @override
  String get shellShortcutGroupMarkup => 'علامات';

  @override
  String get shellShortcutGroupDraw => 'رسم';

  @override
  String get shellShortcutGroupShapes => 'أشكال';

  @override
  String get shellShortcutGroupInsert => 'إدراج';

  @override
  String get shellShortcutGroupMeasure => 'قياس';

  @override
  String get shellShortcutGroupEdit => 'تحرير';

  @override
  String get shellNotSet => 'غير معيّن';

  @override
  String get shellPageColor => 'لون الصفحة…';

  @override
  String get shellPageGrid => 'شبكة الصفحات';

  @override
  String get shellPanelAnnotations => 'التعليقات التوضيحية';

  @override
  String get shellPanelBookmarks => 'الإشارات المرجعية';

  @override
  String get shellPanelPages => 'الصفحات';

  @override
  String get shellPanelProperties => 'الخصائص';

  @override
  String get shellPanelSearchResults => 'نتائج البحث';

  @override
  String get shellPanels => 'اللوحات';

  @override
  String get shellPressAKey => 'اضغط مفتاحًا';

  @override
  String get shellPressLetterKeyHint => 'اضغط مفتاح حرف، أو Delete للمسح.';

  @override
  String get shellReflow => 'إعادة تدفق';

  @override
  String get shellReflowText => 'إعادة تدفق النص';

  @override
  String get shellResetZoom => 'إعادة تعيين التكبير';

  @override
  String get shellSectionShell => 'الواجهة';

  @override
  String get shellSectionView => 'عرض';

  @override
  String get shellSettings => 'الإعدادات';

  @override
  String get shellShowAnnotations => 'إظهار التعليقات التوضيحية';

  @override
  String get shellShowScrollbarChapters => 'إظهار الفصول على شريط التمرير';

  @override
  String get shellTabHere => 'علامة تبويب هنا';

  @override
  String get shellUnbound => 'غير مربوط';

  @override
  String get shellZoom => 'تكبير';

  @override
  String sidebarByAuthor(String author) {
    return 'بواسطة $author';
  }

  @override
  String get sidebarCancelSelection => 'إلغاء التحديد';

  @override
  String get sidebarClearSearch => 'مسح البحث';

  @override
  String get sidebarDeleteSelected => 'حذف المحدد';

  @override
  String get sidebarDeleteSignature => 'حذف التوقيع';

  @override
  String get sidebarLockAnnotation => 'قفل';

  @override
  String get sidebarUnlockAnnotation => 'إلغاء القفل';

  @override
  String get sidebarMore => 'المزيد';

  @override
  String get sidebarNoAnnotations => 'لا توجد تعليقات توضيحية';

  @override
  String get sidebarNoMatchingAnnotations => 'لا توجد تعليقات توضيحية مطابقة';

  @override
  String sidebarPageHeader(int number) {
    return 'صفحة $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'يؤدي هذا إلى إزالة التوقيع الرقمي من المستند. يمكنك التراجع عن ذلك.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'يؤدي هذا إلى إزالة التوقيع الرقمي الذي أنشأه \"$name\" من المستند. يمكنك التراجع عن ذلك.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'إزالة التوقيع؟';

  @override
  String get sidebarReopen => 'إعادة فتح';

  @override
  String get sidebarReply => 'رد';

  @override
  String get sidebarResolve => 'حل';

  @override
  String get sidebarSearchHint => 'البحث في التعليقات التوضيحية';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count',
      many: 'تم تحديد $count عنصرًا',
      few: 'تم تحديد $count عناصر',
      two: 'تم تحديد عنصرين',
      one: 'تم تحديد عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String get sidebarSignatureChecking => 'Checking…';

  @override
  String get sidebarSignatureTrusted => 'Valid — trusted';

  @override
  String get sidebarSignatureUnverified => 'Valid — unverified';

  @override
  String get sidebarSignatureInvalid => 'Invalid';

  @override
  String sidebarSignatureSignedBy(String name) {
    return 'Signed by $name';
  }

  @override
  String sidebarSignatureSignedAt(String time) {
    return 'Signed $time';
  }

  @override
  String sidebarSignatureTrustedVia(String authority) {
    return 'Trusted via $authority';
  }

  @override
  String get sidebarSignatureUntrustedDetail =>
      'Signer is not from a trusted authority';

  @override
  String get sidebarSignatureNoAnchors =>
      'No trusted authorities are configured';

  @override
  String get sidebarSignatureModified => 'Document was changed after signing';

  @override
  String get sidebarSignatureRevoked => 'The signer\'s certificate was revoked';

  @override
  String sidebarSignatureTimestamped(String time) {
    return 'Timestamped $time';
  }

  @override
  String sidebarSignatureLevel(String level) {
    return 'PAdES $level';
  }

  @override
  String get sidebarWriteReplyHint => 'اكتب ردًا…';

  @override
  String get sigTitle => 'التوقيع';

  @override
  String get signIdCreate => 'إنشاء';

  @override
  String get signIdEmail => 'البريد الإلكتروني (اختياري)';

  @override
  String get signIdName => 'الاسم';

  @override
  String get signIdNameHint => 'اسمك، كما ينبغي أن يظهر على التوقيع';

  @override
  String get signIdNameRequired => 'أدخل اسمًا';

  @override
  String get signIdOrganization => 'المؤسسة (اختياري)';

  @override
  String get signIdSelfSignedInfo =>
      'ينشئ هذا هوية موقّعة ذاتيًا. ستظهر التوقيعات كـ \"موقّع، الصلاحية غير معروفة\" في Adobe Acrobat وغيره من القارئات - تمامًا مثل هوياتها الموقّعة ذاتيًا. علامة الاختيار الخضراء تتطلب جهة تصديق CA موثوقة علنًا ومدفوعة.';

  @override
  String get signIdTitle => 'إنشاء هوية توقيع';

  @override
  String get stampBox => 'مربع';

  @override
  String get stampCircle => 'دائرة';

  @override
  String get stampCustomCaption => 'ختم مخصص';

  @override
  String get stampDateFormat => 'تنسيق التاريخ';

  @override
  String get stampDeleteComponent => 'حذف المكوّن المحدد';

  @override
  String get stampDeleteStamp => 'حذف الختم';

  @override
  String get stampEditStamp => 'تحرير الختم';

  @override
  String get stampExport => 'تصدير…';

  @override
  String get stampFieldDate => 'التاريخ';

  @override
  String get stampFieldDateTime => 'التاريخ والوقت';

  @override
  String get stampFieldTime => 'الوقت';

  @override
  String get stampFieldUsername => 'اسم المستخدم';

  @override
  String get stampFont => 'الخط';

  @override
  String get stampFontBold => 'عريض';

  @override
  String get stampFontItalic => 'مائل';

  @override
  String get stampHeight => 'الارتفاع';

  @override
  String get stampImage => 'صورة';

  @override
  String get stampImport => 'استيراد…';

  @override
  String get stampInsertField => 'إدراج حقل';

  @override
  String get stampMoreColors => 'مزيد من الألوان…';

  @override
  String get stampNewStamp => 'ختم جديد…';

  @override
  String get stampNewStampTitle => 'ختم جديد';

  @override
  String get stampSavedToCollection => 'تم الحفظ في الأختام';

  @override
  String get stampSelectTextToEdit => 'حدد نصًا للتحرير';

  @override
  String get stampSelectedText => 'النص المحدد';

  @override
  String get stampSignature => 'توقيع';

  @override
  String get stampStamps => 'الأختام';

  @override
  String get stampText => 'نص';

  @override
  String get stampTime12Hour => '12 ساعة';

  @override
  String get stampTime24Hour => '24 ساعة';

  @override
  String get stampTimeFormat => 'تنسيق الوقت';

  @override
  String get stampWidth => 'العرض';

  @override
  String get takeoffArea => 'المساحة';

  @override
  String get takeoffCount => 'العدد';

  @override
  String get takeoffEmpty => 'لا توجد قياسات بعد.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مجموعة',
      many: '$count مجموعة',
      few: '$count مجموعات',
      two: 'مجموعتان',
      one: 'مجموعة واحدة',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'الطول';

  @override
  String get takeoffTitle => 'الحصر';

  @override
  String get tbAddInkAnnotation => 'إضافة تعليق حبر توضيحي';

  @override
  String get tbAlign => 'محاذاة';

  @override
  String get tbAlignBottom => 'محاذاة للأسفل';

  @override
  String get tbAlignHorizontalCenters => 'محاذاة المراكز الأفقية';

  @override
  String get tbAlignLeft => 'محاذاة لليسار';

  @override
  String get tbAlignRight => 'محاذاة لليمين';

  @override
  String get tbAlignTop => 'محاذاة للأعلى';

  @override
  String get tbAlignVerticalCenters => 'محاذاة المراكز الرأسية';

  @override
  String get tbAnnotationsFlattened =>
      'تم تسطيح التعليقات التوضيحية في الصفحات';

  @override
  String get tbApplyRedactionsMessage =>
      'ستتم إزالة المحتوى المعلّم نهائيًا من المستند. لا يمكن التراجع عن ذلك.';

  @override
  String get tbApplyRedactionsTitle => 'تطبيق التنقيحات؟';

  @override
  String get tbApplyRedactionsTooltip => 'تطبيق التنقيحات (لا يمكن التراجع)';

  @override
  String get tbAutosizeTextBox => 'تحجيم مربع النص تلقائيًا (Alt+Z)';

  @override
  String get tbCalibrateScaleHint => 'ارسم خطًا بطول معلوم لمعايرة المقياس.';

  @override
  String get tbCharSpacing => 'تباعد الأحرف';

  @override
  String get tbCheckBoxOption => 'مربع اختيار';

  @override
  String get tbCheckMarksOnDocument => 'علامات الاختيار على المستند';

  @override
  String get tbCropImage => 'اقتصاص الصورة';

  @override
  String get tbCroppingImage => 'جارٍ اقتصاص الصورة';

  @override
  String get tbCropApply => 'تطبيق الاقتصاص';

  @override
  String get tbCropCancel => 'إلغاء الاقتصاص';

  @override
  String get tbCropReset => 'إعادة تعيين الاقتصاص';

  @override
  String get tbColorLabel => 'اللون';

  @override
  String get tbColorProcessingTooltip =>
      'معالجة الألوان - البحث عن ألوان محتوى الصفحة واستبدالها';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم استبدال $count لون',
      many: 'تم استبدال $count لونًا',
      few: 'تم استبدال $count ألوان',
      two: 'تم استبدال لونين',
      one: 'تم استبدال لون واحد',
      zero: 'لم يُعثر على ألوان مطابقة',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'تحويل إلى مربع اختيار';

  @override
  String get tbConvertToImageButton => 'تحويل إلى زر صورة';

  @override
  String get tbConvertToTextField => 'تحويل إلى حقل نص';

  @override
  String get tbCornerRadius => 'نصف قطر الزاوية';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حذف $count تعليق توضيحي',
      many: 'حذف $count تعليقًا توضيحيًا',
      few: 'حذف $count تعليقات توضيحية',
      two: 'حذف تعليقين توضيحيين',
      one: 'حذف التعليق التوضيحي',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'حذف العنصر';

  @override
  String get tbDeleteField => 'حذف الحقل';

  @override
  String get tbDiscardDrawing => 'تجاهل الرسم';

  @override
  String get tbDistributeHorizontally => 'التوزيع أفقيًا';

  @override
  String get tbDistributeVertically => 'التوزيع رأسيًا';

  @override
  String get tbDrawNewSignature => 'رسم توقيع جديد…';

  @override
  String get tbEditAnnotationText => 'تحرير نص التعليق التوضيحي';

  @override
  String get tbEditTextStyle => 'تحرير النص والنمط';

  @override
  String get tbElement => 'عنصر';

  @override
  String get tbEraserSize => 'حجم الممحاة';

  @override
  String get tbFieldActions => 'إجراءات الحقل';

  @override
  String get tbFieldName => 'اسم الحقل';

  @override
  String tbFieldNamed(String name) {
    return 'الحقل: $name';
  }

  @override
  String get tbFieldValue => 'قيمة الحقل';

  @override
  String get tbFill => 'تعبئة';

  @override
  String get tbFingerDraws => 'الإصبع يرسم - انقر ليمرّر بدلاً من ذلك';

  @override
  String get tbFingerScrolls => 'الإصبع يمرّر (القلم يرسم) - انقر ليرسم';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'تسطيح التعليقات التوضيحية في الصفحات';

  @override
  String get tbFlattenForm => 'تسطيح النموذج';

  @override
  String get tbFlattenFormBakeValues => 'تسطيح النموذج - دمج القيم في الصفحات';

  @override
  String get tbFlattenLabel => 'تسطيح';

  @override
  String get tbFont => 'الخط';

  @override
  String get tbFontSize => 'حجم الخط';

  @override
  String get tbFontWidth => 'عرض الخط';

  @override
  String get tbFormFieldsFlattened => 'تم تسطيح حقول النموذج في الصفحات';

  @override
  String get tbGroupDraw => 'رسم';

  @override
  String get tbGroupEdit => 'تحرير';

  @override
  String get tbGroupInsert => 'إدراج';

  @override
  String get tbGroupMarkup => 'علامات';

  @override
  String get tbGroupMeasure => 'قياس';

  @override
  String get tbGroupSelect => 'تحديد';

  @override
  String get tbGroupShapes => 'أشكال';

  @override
  String get tbImageButtonOption => 'زر صورة';

  @override
  String get tbLineEnd => 'نهاية الخط';

  @override
  String get tbLineSpacing => 'تباعد الأسطر';

  @override
  String get tbLineStart => 'بداية الخط';

  @override
  String get tbLineType => 'نوع الخط';

  @override
  String get tbManageStamps => 'إدارة الأختام…';

  @override
  String get tbMarkupHighlight => 'تمييز';

  @override
  String get tbMarkupHighlightTip => 'تمييز التحديد';

  @override
  String get tbMarkupSquiggly => 'تسطير متموّج';

  @override
  String get tbMarkupSquigglyTip => 'تسطير التحديد بخط متموّج';

  @override
  String get tbMarkupStrikeOut => 'شطب';

  @override
  String get tbMarkupStrikeOutTip => 'شطب التحديد';

  @override
  String get tbMarkupUnderline => 'تسطير';

  @override
  String get tbMarkupUnderlineTip => 'تسطير التحديد';

  @override
  String get tbMoreColors => 'مزيد من الألوان…';

  @override
  String get tbNameArrow => 'سهم';

  @override
  String get tbNameCallout => 'وسيلة شرح';

  @override
  String get tbNameCloudPolygon => 'مضلّع سحابي';

  @override
  String get tbNameCount => 'عدّ';

  @override
  String get tbNameDigitalSignature => 'توقيع رقمي';

  @override
  String get tbNameDraw => 'رسم';

  @override
  String get tbNameEllipse => 'قطع ناقص';

  @override
  String get tbNameEraser => 'محو خطوط الحبر';

  @override
  String get tbNameHand => 'أداة اليد';

  @override
  String get tbNameHighlight => 'تمييز';

  @override
  String get tbNameImage => 'صورة';

  @override
  String get tbNameLine => 'خط';

  @override
  String get tbNameMeasureAngle => 'قياس الزاوية';

  @override
  String get tbNameMeasureArc => 'قياس طول القوس';

  @override
  String get tbNameMeasureArea => 'قياس المساحة';

  @override
  String get tbNameMeasureDistance => 'قياس المسافة';

  @override
  String get tbNameMeasurePerimeter => 'قياس المحيط';

  @override
  String get tbNameMeasureSlope => 'قياس الميل (ارتفاع/امتداد)';

  @override
  String get tbNameMeasureVolume => 'قياس الحجم (المساحة × العمق)';

  @override
  String get tbNameNote => 'ملاحظة';

  @override
  String get tbNamePolygon => 'مضلّع';

  @override
  String get tbNamePolyline => 'خط متعدد';

  @override
  String get tbNameRectangle => 'مستطيل';

  @override
  String get tbNameSelect => 'تحديد';

  @override
  String get tbNameSignature => 'توقيع';

  @override
  String get tbNameStamp => 'ختم';

  @override
  String get tbNameTextBox => 'مربع نص';

  @override
  String get tbNewFieldType => 'نوع حقل جديد - اسحب على الصفحة لإضافة واحد';

  @override
  String get tbNoAnnotationsToFlatten => 'لا توجد تعليقات توضيحية لتسطيحها';

  @override
  String get tbNoCustomStamps => 'لا توجد أختام مخصصة';

  @override
  String get tbNoFormFieldsToFlatten => 'لا توجد حقول نموذج لتسطيحها';

  @override
  String get tbNoRedactionsToApply => 'لا توجد تنقيحات لتطبيقها';

  @override
  String get tbNoteTitle => 'ملاحظة';

  @override
  String get tbOpacity => 'العتامة';

  @override
  String get tbOutline => 'الإطار';

  @override
  String get tbPatternScale => 'مقياس النمط';

  @override
  String get tbPickColorFromPage => 'اختيار لون من الصفحة';

  @override
  String get tbRedactionsApplied => 'تم تطبيق التنقيحات';

  @override
  String get tbRedoShortcut => 'إعادة (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'تعذّرت إعادة التدفق - هذه ليست فقرة بعمود واحد يمكن لهذه الأداة إعادة لفّها. جرّب استبدال النص بدلاً من ذلك.';

  @override
  String get tbReflowParagraph => 'إعادة تدفق الفقرة';

  @override
  String get tbRenameField => 'إعادة تسمية الحقل';

  @override
  String get tbRenameFieldEllipsis => 'إعادة تسمية الحقل…';

  @override
  String get tbReplaceImage => 'استبدال الصورة';

  @override
  String get tbReplaceImageFailed => 'تعذّر استبدال الصورة';

  @override
  String get tbReplaceText => 'استبدال النص';

  @override
  String get tbSaveImage => 'حفظ الصورة';

  @override
  String get tbSaveShortcut => 'حفظ… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'المقياس';

  @override
  String get tbSelectTextForMarkup => 'حدد نصًا لاستخدام العلامات';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count',
      one: 'تحديد',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'تعيين…';

  @override
  String get tbStamp => 'ختم';

  @override
  String get tbStampText => 'نص الختم';

  @override
  String get tbStrokeOpacityFont => 'الحد والعتامة والخط';

  @override
  String get tbStrokeWidthLabel => 'سماكة الحد';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'الحد $width';
  }

  @override
  String get tbStyle => 'النمط';

  @override
  String get tbTakeoffTotals => 'إجماليات الحصر';

  @override
  String get tbTextBorder => 'حدود النص';

  @override
  String get tbTextColour => 'لون النص';

  @override
  String get tbTextFieldOption => 'حقل نص';

  @override
  String get tbTextFill => 'تعبئة النص';

  @override
  String get tbTextStyleEllipsis => 'نمط النص…';

  @override
  String get tbTextTitle => 'نص';

  @override
  String get tbTipCallout => 'وسيلة شرح - اسحب من النقطة إلى موضع المربع';

  @override
  String get tbTipContent => 'تحرير محتوى الصفحة';

  @override
  String get tbTipCount => 'عدّ - انقر لإسقاط علامات الاختيار وإحصائها';

  @override
  String get tbTipDigitalSignature => 'توقيع رقمي - اسحب مربعًا للوضع والتوقيع';

  @override
  String get tbTipForm =>
      'حقول النموذج - انقر للتحديد، انقر مرتين للتعبئة، اسحب للإضافة';

  @override
  String get tbTipHighlightDraw => 'تمييز - ارسم بحرية';

  @override
  String get tbTipImage => 'صورة - انقر للوضع، أو اسحب مربعًا';

  @override
  String get tbTipMeasureAngle => 'قياس الزاوية - انقر ثلاث نقاط';

  @override
  String get tbTipMeasureArc => 'قياس طول القوس - انقر ثلاث نقاط';

  @override
  String get tbTipRedact => 'تنقيح - اسحب منطقة، ثم طبّق';

  @override
  String get tbTipSignature => 'توقيع - انقر صفحة لوضعه';

  @override
  String get tbTipSnapshot => 'لقطة - اسحب منطقة لالتقاطها (الصقها كمتجه)';

  @override
  String get tbToolContent => 'المحتوى';

  @override
  String get tbToolForm => 'نموذج';

  @override
  String get tbToolRedact => 'تنقيح';

  @override
  String get tbToolSnapshot => 'لقطة';

  @override
  String get tbTools => 'الأدوات';

  @override
  String get tbTotals => 'الإجماليات';

  @override
  String get tbTypeTextEachTime => 'اكتب النص في كل مرة';

  @override
  String get tbUnderline => 'تسطير';

  @override
  String get tbUndoShortcut => 'تراجع (⌘Z)';

  @override
  String get textStyleFont => 'الخط';

  @override
  String get textStyleFontSize => 'حجم الخط';

  @override
  String get textStyleKeep => 'إبقاء';

  @override
  String get textStyleStyle => 'النمط';

  @override
  String get textStyleText => 'النص';

  @override
  String get textStyleTextFill => 'تعبئة النص';

  @override
  String get textStyleTitle => 'تحرير النص والنمط';

  @override
  String get thumbAddPage => 'إضافة صفحة';

  @override
  String get thumbClearSelection => 'مسح التحديد';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'نسخ $count صفحة',
      many: 'نسخ $count صفحة',
      few: 'نسخ $count صفحات',
      two: 'نسخ صفحتين',
      one: 'نسخ الصفحة',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'نسخ الصفحات المحددة';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قص $count صفحة',
      many: 'قص $count صفحة',
      few: 'قص $count صفحات',
      two: 'قص صفحتين',
      one: 'قص الصفحة',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'قص الصفحات المحددة';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حذف $count صفحة',
      many: 'حذف $count صفحة',
      few: 'حذف $count صفحات',
      two: 'حذف صفحتين',
      one: 'حذف الصفحة',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'حذف الصفحات المحددة';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تكرار $count صفحة',
      many: 'تكرار $count صفحة',
      few: 'تكرار $count صفحات',
      two: 'تكرار صفحتين',
      one: 'تكرار الصفحة',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'تصدير الصفحات…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تصدير $count صفحة…',
      many: 'تصدير $count صفحة…',
      few: 'تصدير $count صفحات…',
      two: 'تصدير صفحتين…',
      one: 'تصدير الصفحة…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'تصدير الصفحات المحددة';

  @override
  String get thumbInsertBlankAfter => 'إدراج صفحة فارغة بعد';

  @override
  String get thumbInsertBlankBefore => 'إدراج صفحة فارغة قبل';

  @override
  String get thumbInsertFileFailed => 'تعذّر إدراج هذا الملف.';

  @override
  String get thumbInsertPdf => 'إدراج PDF…';

  @override
  String get thumbPageActions => 'إجراءات الصفحة';

  @override
  String thumbPageNumber(int number) {
    return 'صفحة $number';
  }

  @override
  String get thumbPages => 'الصفحات';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لصق $count صفحة',
      many: 'لصق $count صفحة',
      few: 'لصق $count صفحات',
      two: 'لصق صفحتين',
      one: 'لصق الصفحة',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'تدوير 180°';

  @override
  String get thumbRotateLeft => 'تدوير لليسار';

  @override
  String get thumbRotatePageRight => 'تدوير الصفحة لليمين';

  @override
  String get thumbRotateRight => 'تدوير لليمين';

  @override
  String get thumbRotateSelectedLeft => 'تدوير الصفحات المحددة لليسار';

  @override
  String get thumbRotateSelectedRight => 'تدوير الصفحات المحددة لليمين';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count صفحة',
      many: 'تم تحديد $count صفحة',
      few: 'تم تحديد $count صفحات',
      two: 'تم تحديد صفحتين',
      one: 'تم تحديد صفحة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'تراجع';

  @override
  String get viewerEditFontUnsafe => 'لا يمكن تحرير خط أو ترميز PDF هذا بأمان.';

  @override
  String get viewerEditNeedsSinglePage =>
      'يتطلب التحرير تحديدًا على صفحة واحدة.';

  @override
  String get viewerEditNotEditableRun =>
      'هذا التحديد ليس تسلسل نص واحدًا قابلًا للتحرير من محتوى الصفحة.';

  @override
  String get viewerEditStyleUnchangeable =>
      'يمكن إعادة كتابة خط PDF هذا، لكن لا يمكن تغيير نمطه.';

  @override
  String get viewerEditTextStyle => 'تحرير النص والنمط';

  @override
  String get viewerMarkup => 'علامات';

  @override
  String get viewerMarkupHighlight => 'تمييز';

  @override
  String get viewerMarkupSquiggly => 'متموّج';

  @override
  String get viewerMarkupStrikeOut => 'شطب';

  @override
  String get viewerMarkupUnderline => 'تسطير';

  @override
  String get viewerSelectAll => 'تحديد الكل';
}
