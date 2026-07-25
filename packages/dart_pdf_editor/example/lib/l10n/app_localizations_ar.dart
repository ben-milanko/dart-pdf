// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get add => 'إضافة';

  @override
  String get apply => 'تطبيق';

  @override
  String get cancel => 'إلغاء';

  @override
  String get clear => 'مسح';

  @override
  String get close => 'إغلاق';

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
  String exActionJavaScript(String script) {
    return 'تم عرض JavaScript للتطبيق: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'رابط: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'إجراء مُسمّى: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'نوع إجراء غير معالَج: $type';
  }

  @override
  String get exAnnotationTextCopied => 'تم نسخ نص التعليق التوضيحي';

  @override
  String get exApiKeyHelper => 'يُرسل بصيغة Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'مفتاح API / رمز مميز (اختياري)';

  @override
  String get exAppMenuTooltip => 'قائمة DartPDF';

  @override
  String get exClearRecentFiles => 'مسح الملفات الأخيرة';

  @override
  String get exCloseTab => 'إغلاق علامة التبويب';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'مقارنة: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'المقارنة مع ملف PDF آخر…';

  @override
  String get exCopiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get exCopySelectedText => 'نسخ النص المحدد (⌘C)';

  @override
  String get exCopyText => 'نسخ النص';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'تعذّر فتح $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'تعذّر فتح $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'تعذّر فتح $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'تعذّر فتح $uri\n$error\n\nعلى الويب يكون هذا غالبًا قيدًا من CORS: يجب أن يرسل الخادم Access-Control-Allow-Origin وأن يكشف ترويسات Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'تعذّرت إعادة فتح $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'تعذّرت إعادة فتح $title - لم تعد نسخته المحفوظة متاحة.';
  }

  @override
  String get exDemoNoteHint => 'اكتب هنا - يطفو مربع النص هذا فوق الصفحة';

  @override
  String get exDiagnosticsCopied => 'تم نسخ التشخيصات إلى الحافظة';

  @override
  String exDownloaded(String name) {
    return 'تم تنزيل $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'تم تنزيل $name - الصقها في ملف PDF بالضغط على Ctrl+V';
  }

  @override
  String get exExport => 'تصدير';

  @override
  String exExportFailed(String error) {
    return 'فشل التصدير: $error';
  }

  @override
  String get exExportPageImageMenu => 'تصدير الصفحة كصورة…';

  @override
  String get exExportPageImageTitle => 'تصدير الصفحة كصورة';

  @override
  String get exFeatureShowcase => 'عرض الميزات';

  @override
  String get exFormat => 'التنسيق';

  @override
  String get exHide => 'إخفاء';

  @override
  String get exHorizontalLayout => 'تخطيط صفحات أفقي';

  @override
  String get exHowToSetupOcr => 'كيفية إعداد خادم OCR';

  @override
  String get exModelName => 'اسم النموذج';

  @override
  String get exNoMessage => 'لا توجد رسالة';

  @override
  String get exNoRecentFiles => 'لا توجد ملفات أخيرة';

  @override
  String exNotAValidUrl(String url) {
    return 'عنوان URL غير صالح:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أضاف OCR $count مقطع نصي - أصبح نص الصفحة قابلاً للتحديد الآن',
      many: 'أضاف OCR $count مقطعًا نصيًا - أصبح نص الصفحة قابلاً للتحديد الآن',
      few: 'أضاف OCR $count مقاطع نصية - أصبح نص الصفحة قابلاً للتحديد الآن',
      two: 'أضاف OCR مقطعين نصيين - أصبح نص الصفحة قابلاً للتحديد الآن',
      one: 'أضاف OCR مقطعًا نصيًا واحدًا - أصبح نص الصفحة قابلاً للتحديد الآن',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'يضيف طبقة نص قابلة للتحديد والبحث فوق الصفحات الممسوحة ضوئيًا باستخدام نموذج OCR للرؤية واللغة تستضيفه أنت (dots.ocr على vLLM، أو أي نقطة نهاية OCR متوافقة مع OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'فشل OCR: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'فتح';

  @override
  String get exOpenDocumentBeforeOcr => 'افتح مستندًا قبل تشغيل OCR';

  @override
  String get exOpenDocumentFirst => 'افتح مستندًا أولاً';

  @override
  String get exOpenFromUrl => 'الفتح من عنوان URL…';

  @override
  String get exOpenFromUrlTitle => 'الفتح من عنوان URL';

  @override
  String get exOpenInNewTab => 'فتح ملف PDF في علامة تبويب جديدة';

  @override
  String get exOpenInteractiveDemo => 'فتح العرض التفاعلي';

  @override
  String get exOpenPdf => 'فتح ملف PDF…';

  @override
  String get exOpenPdfButton => 'فتح ملف PDF';

  @override
  String get exOpenRecent => 'فتح ملف حديث';

  @override
  String get exOpenUrlDescription =>
      'يبثّ ملف PDF عبر طلبات HTTP Range من خلال PdfHttpByteSource، فيجلب فقط ما يحتاجه المحلّل ويعود إلى تنزيل كامل عندما لا يدعم الخادم النطاقات.';

  @override
  String get exOpeningDocument => 'جارٍ فتح المستند';

  @override
  String get exOpeningPdf => 'جارٍ فتح ملف PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'جارٍ فتح $title…';
  }

  @override
  String get exPdfUrlLabel => 'عنوان URL لملف PDF';

  @override
  String get exPerformanceAuto => 'الأداء: تلقائي';

  @override
  String get exPreparing => 'جارٍ التحضير…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor على pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'جارٍ التعرّف على الصفحة $current من $count…';
  }

  @override
  String get exResolution => 'الدقة';

  @override
  String get exRunOcr => 'تشغيل OCR';

  @override
  String get exSaveAs => 'حفظ باسم…';

  @override
  String exSaveFailed(String error) {
    return 'فشل الحفظ: $error';
  }

  @override
  String exSavedName(String name) {
    return 'تم حفظ $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'تم حفظ $name - الصقها في ملف PDF بالضغط على ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'تم الحفظ في $path';
  }

  @override
  String get exScrollIndicatorDemo => 'عرض واجهة برمجة مؤشر التمرير';

  @override
  String get exServiceEndpoint => 'نقطة نهاية الخدمة';

  @override
  String get exShow => 'إظهار';

  @override
  String get exSingleWorker => 'عامل واحد';

  @override
  String get exSupplyFeedback => 'إرسال ملاحظات…';

  @override
  String get exSwitchToEdit => 'التبديل إلى وضع التحرير';

  @override
  String get exSwitchToReadOnly => 'التبديل إلى وضع القراءة فقط';

  @override
  String get exThemeDark => 'السمة: داكنة - التبديل إلى النظام';

  @override
  String get exThemeLight => 'السمة: فاتحة - التبديل إلى الداكنة';

  @override
  String get exThemeSystem => 'السمة: النظام - التبديل إلى الفاتحة';

  @override
  String get exTryDemo => 'جرّب العرض التفاعلي';

  @override
  String get exUntitled => 'بلا عنوان';

  @override
  String get exVerticalLayout => 'تخطيط صفحات رأسي';

  @override
  String get exViewSource => 'عرض المصدر على GitHub';

  @override
  String get exWorkerAuto => 'تلقائي';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الأداء: $count عامل',
      many: 'الأداء: $count عاملًا',
      few: 'الأداء: $count عوامل',
      two: 'الأداء: عاملان',
      one: 'الأداء: عامل واحد',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عامل',
      many: '$count عاملًا',
      few: '$count عوامل',
      two: 'عاملان',
      one: 'عامل واحد',
    );
    return '$_temp0';
  }

  @override
  String get feedbackAttachDiagnostics => 'إرفاق هذه التشخيصات بالتقرير';

  @override
  String get feedbackClearLog => 'مسح السجل';

  @override
  String get feedbackCopyDiagnostics => 'نسخ التشخيصات';

  @override
  String get feedbackDiagnosticsNotice =>
      'يُفتح نموذج الملاحظات في متصفحك. تُجمع التشخيصات أدناه على هذا الجهاز فقط وتُرفق للمساعدة في إعادة إنتاج المشكلة. راجعها أولاً - لا تُضمّن أي شيء تفضّل إبقاءه خاصًا.';

  @override
  String get feedbackOpenForm => 'فتح نموذج الملاحظات';

  @override
  String get feedbackTitle => 'إرسال ملاحظات';

  @override
  String get none => 'بلا';

  @override
  String get ok => 'موافق';

  @override
  String get paste => 'لصق';

  @override
  String get redo => 'إعادة';

  @override
  String get remove => 'إزالة';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get save => 'حفظ';

  @override
  String get scrollDemoNextPage => 'الصفحة التالية';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'صفحة $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'الصفحة السابقة';

  @override
  String get scrollDemoSwitchHorizontal => 'التبديل إلى التخطيط الأفقي';

  @override
  String get scrollDemoSwitchVertical => 'التبديل إلى التخطيط الرأسي';

  @override
  String get scrollDemoTitle => 'واجهة برمجة مؤشر التمرير';

  @override
  String get undo => 'تراجع';

  @override
  String get exFileTypePdf => 'مستندات PDF';

  @override
  String get exFileTypeImages => 'الصور';

  @override
  String get exFileTypeFonts => 'الخطوط';
}
