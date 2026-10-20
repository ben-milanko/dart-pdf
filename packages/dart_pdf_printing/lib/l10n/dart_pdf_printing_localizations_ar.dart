// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class DartPdfPrintingLocalizationsAr extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get cancel => 'إلغاء';

  @override
  String get printDlgPreparing => 'جارٍ التحضير…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'جارٍ عرض الصفحة $rendered من $total…';
  }

  @override
  String get printDlgTitle => 'جارٍ الطباعة';

  @override
  String get printPreviewAll => 'الكل';

  @override
  String get printPreviewCurrent => 'الحالية';

  @override
  String get printPreviewNextPage => 'الصفحة التالية';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'الصفحة $page من $total';
  }

  @override
  String get printPreviewPreviousPage => 'الصفحة السابقة';

  @override
  String get printPreviewPrint => 'طباعة';

  @override
  String get printPreviewRange => 'نطاق';

  @override
  String printPreviewRangeError(int total) {
    return 'أدخل نطاق صفحات بين 1 و$total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'الصفحات المطلوب طباعتها: $count';
  }

  @override
  String get printPreviewTitle => 'معاينة الطباعة';

  @override
  String get printPreviewUnavailable => 'المعاينة غير متاحة';

  @override
  String get printOptionsPrinter => 'الطابعة';

  @override
  String get printOptionsNativePrinter =>
      'اختر الطابعة ودرج الورق والألوان والطباعة على الوجهين وخصائص الجهاز في مربع حوار الطباعة الخاص بالنظام الذي سيظهر بعد ذلك. اترك المقياس عند 100% وعدد النسخ عند 1 لاستخدام التخطيط المعروض هنا.';

  @override
  String get printOptionsPages => 'الصفحات';

  @override
  String get printOptionsSelected => 'المحددة';

  @override
  String get printOptionsPageRange => 'الصفحات (مثلاً: 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'إضافة ملفات…';

  @override
  String get printOptionsAddFailed => 'تعذرت إضافة الملفات المحددة.';

  @override
  String get printOptionsGetWindow => 'تحديد منطقة';

  @override
  String get printOptionsClearWindow => 'مسح المنطقة';

  @override
  String get printOptionsWindowHint =>
      'اسحب لرسم مستطيل على هذه الصفحة الأصلية لتحديد المنطقة المراد طباعتها.';

  @override
  String get printOptionsPaper => 'الورق';

  @override
  String get printOptionsPaperSize => 'حجم الورق';

  @override
  String get printOptionsPageSize => 'استخدام حجم صفحة المستند';

  @override
  String get printOptionsOrientation => 'الاتجاه';

  @override
  String get printOptionsAuto => 'تلقائي';

  @override
  String get printOptionsPortrait => 'عمودي';

  @override
  String get printOptionsLandscape => 'أفقي';

  @override
  String get printOptionsCopies => 'النسخ';

  @override
  String get printOptionsCollate => 'ترتيب النسخ';

  @override
  String get printOptionsReverse => 'عكس ترتيب الصفحات';

  @override
  String get printOptionsLayout => 'تخطيط الصفحة';

  @override
  String get printOptionsScaling => 'تحجيم الصفحة';

  @override
  String get printOptionsScaleNone => 'بدون (الحجم الفعلي)';

  @override
  String get printOptionsFitPaper => 'ملاءمة للورق';

  @override
  String get printOptionsReducePaper => 'تصغير لملاءمة الورق';

  @override
  String get printOptionsFitMargins => 'ملاءمة للهوامش';

  @override
  String get printOptionsReduceMargins => 'تصغير لملاءمة الهوامش';

  @override
  String get printOptionsCustomScale => 'مقياس مخصص';

  @override
  String get printOptionsMultiple => 'عدة صفحات لكل ورقة';

  @override
  String get printOptionsScalePercent => 'المقياس (%)';

  @override
  String get printOptionsMargin => 'الهوامش (نقطة)';

  @override
  String get printOptionsPagesPerSheet => 'الصفحات لكل ورقة';

  @override
  String get printOptionsPageOrder => 'ترتيب الصفحات';

  @override
  String get printOptionsHorizontal => 'أفقي';

  @override
  String get printOptionsHorizontalReverse => 'أفقي معكوس';

  @override
  String get printOptionsVertical => 'عمودي';

  @override
  String get printOptionsVerticalReverse => 'عمودي معكوس';

  @override
  String get printOptionsBorder => 'طباعة حدود الصفحات';

  @override
  String get printOptionsRotation => 'التدوير (باتجاه عقارب الساعة)';

  @override
  String get printOptionsNoRotation => 'بدون';

  @override
  String get printOptionsCenter => 'توسيط على الورق';

  @override
  String get printOptionsOffsetX => 'إزاحة لليمين (نقطة)';

  @override
  String get printOptionsOffsetY => 'إزاحة للأسفل (نقطة)';

  @override
  String get printOptionsContents => 'المحتوى المراد طباعته';

  @override
  String get printOptionsDocumentAndMarkups => 'المستند والتعليقات التوضيحية';

  @override
  String get printOptionsDocumentOnly => 'المستند فقط';

  @override
  String get printOptionsMarkupsOnly => 'التعليقات التوضيحية فقط';

  @override
  String get printOptionsDimPage => 'تخفيف لون محتوى الصفحة';

  @override
  String get printOptionsDimMarkups => 'تخفيف لون التعليقات التوضيحية';

  @override
  String get printOptionsHyperlinks => 'طباعة الارتباطات التشعبية المرئية';

  @override
  String get printOptionsDefaults => 'الإعدادات الافتراضية';

  @override
  String get printOptionsInvalidNumber => 'أدخل أرقامًا صالحة قبل الطباعة.';

  @override
  String get printOptionsInvalidValue => 'قيمة غير صالحة';

  @override
  String get printOptionsMarginGuide =>
      'تُظهر الخطوط الحمراء الهوامش، ولا تتم طباعتها.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'المنطقة: $width × $height نقطة';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'الأصل: $width × $height نقطة';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'الورقة: $width × $height نقطة';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'الورقة $sheet من $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'تعذر إعداد هذا التخطيط. تحقق من حجم الورق والهوامش والمقياس.';

  @override
  String get printOptionsChoosePrinter => 'اختيار طابعة';

  @override
  String get printOptionsNoPrinters =>
      'لا توجد طابعات مثبتة. أضف طابعة في إعدادات Windows، ثم أعد المحاولة.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'الطابعة المحفوظة «$printer» غير متاحة. اختر طابعة للمتابعة.';
  }

  @override
  String get printOptionsPrinterError =>
      'تعذّر تحميل إعدادات الطابعة. تحقق من اتصال الطابعة وأعد المحاولة.';

  @override
  String get printOptionsRetry => 'إعادة المحاولة';

  @override
  String get printOptionsColor => 'ألوان';

  @override
  String get printOptionsGrayscale => 'أبيض وأسود';

  @override
  String get printOptionsDuplex => 'طباعة على الوجهين';

  @override
  String get printOptionsSimplex => 'وجه واحد';

  @override
  String get printOptionsLongEdge => 'قلب على الحافة الطويلة';

  @override
  String get printOptionsShortEdge => 'قلب على الحافة القصيرة';

  @override
  String get printOptionsTray => 'درج الورق';

  @override
  String get printOptionsDefaultTray => 'الإعداد الافتراضي للطابعة';

  @override
  String get printOptionsProperties => 'خصائص الطابعة…';

  @override
  String get printOptionsDirectPrinter =>
      'يرسل زر الطباعة هذه المهمة مباشرة إلى الطابعة المحددة.';

  @override
  String get printOptionsPropertiesError => 'تعذّر فتح خصائص الطابعة.';

  @override
  String get printOptionsLoadingPrinters => 'جارٍ تحميل الطابعات…';
}
