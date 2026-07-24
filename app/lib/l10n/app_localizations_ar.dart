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
  String get appSigAddLogo => 'إضافة شعار…';

  @override
  String appSigAllPages(int pageCount) {
    return 'كل الصفحات $pageCount';
  }

  @override
  String get appSigAppearance => 'المظهر';

  @override
  String get appSigAppearanceDescription =>
      'يُرسم التوقيع في المكان الذي وضعته فيه. يظهر اسم الموقّع وتفاصيله دائمًا؛ ويمكنك إضافة علامة مرسومة يدويًا وخلفية شعار.';

  @override
  String appSigApplyTo(String label) {
    return 'التطبيق على: $label';
  }

  @override
  String get appSigApplyToPages => 'التطبيق على الصفحات…';

  @override
  String get appSigChooseCertificate => 'اختيار ملف شهادة…';

  @override
  String get appSigChooseKeyDescription =>
      'اختر مفتاحك الخاص (RSA، بصيغة PEM أو DER) وملف شهادته. يُستخدم المفتاح للتوقيع فقط ولا يُحفظ أبدًا.';

  @override
  String get appSigChoosePngOrJpeg => 'اختر صورة PNG أو JPEG.';

  @override
  String get appSigChoosePrivateKey => 'اختيار مفتاح خاص…';

  @override
  String get appSigContactInfo => 'معلومات الاتصال';

  @override
  String get appSigCouldNotCaptureSignature => 'تعذّر التقاط التوقيع.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'تعذّرت قراءة الشهادة: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'تعذّرت قراءة المفتاح: $error';
  }

  @override
  String get appSigCreateOnDevice => 'إنشاء توقيع على هذا الجهاز';

  @override
  String appSigDate(String date) {
    return 'التاريخ: $date';
  }

  @override
  String get appSigDigitallySign => 'التوقيع الرقمي';

  @override
  String get appSigDrawSignature => 'رسم توقيع…';

  @override
  String get appSigFieldHelper => 'اتركه فارغًا لإنشاء حقل توقيع جديد.';

  @override
  String get appSigFieldLabel => 'حقل توقيع موجود (اختياري)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count شهادة',
      many: '$count شهادة',
      few: '$count شهادات',
      two: 'شهادتان',
      one: 'شهادة واحدة',
    );
    return '$_temp0 · صالحة من $validFrom إلى $validUntil';
  }

  @override
  String get appSigIntro =>
      'يثبت التوقيع الرقمي أنك وقّعت هذا المستند وأنه لم يتغير منذ ذلك الحين. اختر كيف تريد التوقيع.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'تعذّرت قراءة المفتاح أو الشهادة المحددة.';

  @override
  String get appSigKeylessDescription =>
      'الأسهل. نؤكد هويتك عبر البريد الإلكتروني ونوقّع نيابةً عنك، مع طابع زمني موثوق. لا شيء لتثبيته أو إعداده.';

  @override
  String get appSigKeylessIdentity => 'هوية بدون مفتاح';

  @override
  String get appSigKeylessSignInExpired =>
      'انتهت صلاحية تسجيل الدخول بدون مفتاح. يرجى تسجيل الدخول مرة أخرى.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'فشل تسجيل الدخول بدون مفتاح: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'بدون مفتاح · مختوم زمنيًا · الصلاحية غير معروفة';

  @override
  String get appSigKeylessWebNote =>
      'تسجيل الدخول ببريدك الإلكتروني هو أسهل طريقة — وهو متاح في تطبيقي DartPDF لسطح المكتب والهاتف. ولأسباب أمنية لا يمكن تشغيله في متصفح ويب.';

  @override
  String get appSigLocation => 'الموقع';

  @override
  String get appSigLogoAdded => 'تمت إضافة الشعار ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'الصفحات $start–$end';
  }

  @override
  String get appSigPreviewNote => 'معاينة - قد يختلف المربع الموقّع قليلاً.';

  @override
  String get appSigReason => 'السبب';

  @override
  String appSigReasonLine(String reason) {
    return 'السبب: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'جارٍ تحديث تسجيل الدخول…';

  @override
  String get appSigRemoveLogo => 'إزالة الشعار';

  @override
  String get appSigRemoveSignature => 'إزالة التوقيع';

  @override
  String get appSigSelfSignedDescription =>
      'لا حاجة لتسجيل دخول أو ملفات. الأفضل للاستخدام الشخصي — يُحفظ على هذا الجهاز للمرة القادمة. ستُظهره بعض قارئات PDF كـ \"موقّع، الصلاحية غير معروفة\"، وهو أمر طبيعي لتوقيع تنشئه بنفسك.';

  @override
  String get appSigSelfSignedIdentity => 'هوية موقّعة ذاتيًا';

  @override
  String get appSigSelfSignedSubtitle => 'موقّع ذاتيًا · الصلاحية غير معروفة';

  @override
  String get appSigShowSignatureOnPages => 'إظهار التوقيع على الصفحات';

  @override
  String get appSigSign => 'توقيع';

  @override
  String get appSigSignInWithEmail => 'تسجيل الدخول ببريدك الإلكتروني';

  @override
  String get appSigSignatureAdded => 'تمت إضافة التوقيع ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'موقّع رقميًا بواسطة $signerName';
  }

  @override
  String get appSigSigner => 'الموقّع';

  @override
  String get appSigSigningYouIn => 'جارٍ تسجيل دخولك…';

  @override
  String get appSigThisPageOnly => 'هذه الصفحة فقط';

  @override
  String get appSigUseOwnCertificate => 'استخدام شهادتك الخاصة';

  @override
  String get appSigUseOwnCertificateSubtitle => 'لشهادة توقيع من مؤسستك';

  @override
  String get appSigX509Signer => 'موقّع X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'فتح ملفات PDF الـ $count في علامات تبويب جديدة، أم إدراج صفحاتها في \"$title\"؟',
      many:
          'فتح ملفات PDF الـ $count في علامات تبويب جديدة، أم إدراج صفحاتها في \"$title\"؟',
      few:
          'فتح ملفات PDF الـ $count في علامات تبويب جديدة، أم إدراج صفحاتها في \"$title\"؟',
      two:
          'فتح ملفَّي PDF هذين في علامتَي تبويب جديدتين، أم إدراج صفحاتهما في \"$title\"؟',
      one:
          'فتح ملف PDF هذا في علامة تبويب جديدة، أم إدراج صفحاته في \"$title\"؟',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'إضافة ملفات PDF المُسقَطة',
      many: 'إضافة ملفات PDF المُسقَطة',
      few: 'إضافة ملفات PDF المُسقَطة',
      two: 'إضافة ملفَّي PDF المُسقَطين',
      one: 'إضافة ملف PDF المُسقَط',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'تم نسخ نص التعليق التوضيحي';

  @override
  String get editorAppMenuTooltip => 'قائمة DartPDF';

  @override
  String get editorCancelOcr => 'إلغاء OCR';

  @override
  String get editorClearRecentFiles => 'مسح الملفات الأخيرة';

  @override
  String get editorCloseAll => 'إغلاق الكل';

  @override
  String get editorCloseOthers => 'إغلاق الأخرى';

  @override
  String get editorCloseTab => 'إغلاق علامة التبويب';

  @override
  String get editorCloseTabsToRight => 'إغلاق علامات التبويب على اليمين';

  @override
  String get editorCompareFailedTitle => 'فشلت المقارنة';

  @override
  String editorCompareTitle(String title) {
    return 'مقارنة: $title';
  }

  @override
  String get editorCopiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get editorCopySelectedTextTooltip => 'نسخ النص المحدد (⌘C)';

  @override
  String get editorCopyText => 'نسخ النص';

  @override
  String editorCouldNotExport(String title) {
    return 'تعذّر تصدير $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'تعذّر استيراد الأختام: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تعذّر إدراج ملفات PDF المُسقَطة',
      many: 'تعذّر إدراج ملفات PDF المُسقَطة',
      few: 'تعذّر إدراج ملفات PDF المُسقَطة',
      two: 'تعذّر إدراج ملفَّي PDF المُسقَطين',
      one: 'تعذّر إدراج ملف PDF المُسقَط',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'تعذّر فتح $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'تعذّر فتح المجلد الحاوي';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'تعذّر فتح الملف الثاني\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'تعذّر فتح الملف المحدد\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'تعذّر فتح $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'تعذّرت طباعة $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'تعذّرت إعادة فتح $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'تعذّر التوقيع الرقمي: $error';
  }

  @override
  String get editorDiscard => 'تجاهل';

  @override
  String get editorDiscardChangesTitle => 'تجاهل التغييرات؟';

  @override
  String get editorDocumentSigned => 'تم توقيع المستند رقميًا';

  @override
  String get editorDownload => 'تنزيل';

  @override
  String get editorDropToOpen => 'أفلت ملف PDF لفتحه';

  @override
  String get editorDropToOpenOrInsert => 'أفلت ملف PDF لفتحه أو إدراجه';

  @override
  String get editorInsertPages => 'إدراج الصفحات';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'تم إدراج $count؛ تعذّرت قراءة $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إدراج $count ملف PDF في $title',
      many: 'تم إدراج $count ملف PDF في $title',
      few: 'تم إدراج $count ملفات PDF في $title',
      two: 'تم إدراج ملفَّي PDF في $title',
      one: 'تم إدراج الصفحات في $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'رابط غير صالح: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'حاول هذا المستند تشغيل JavaScript (تم تجاهله)';

  @override
  String get editorLoadingFullDocument => 'جارٍ تحميل المستند الكامل';

  @override
  String get editorMenuCompareWith => 'المقارنة مع…';

  @override
  String get editorMenuDigitallySign => 'التوقيع الرقمي…';

  @override
  String get editorMenuDigitallySigning => 'جارٍ التوقيع الرقمي…';

  @override
  String get editorMenuExportImage => 'تصدير الصفحة كصورة…';

  @override
  String get editorMenuNewDocument => 'مستند جديد…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'فتح ملف PDF…';

  @override
  String get editorMenuPrint => 'طباعة…';

  @override
  String get editorMenuSaveAs => 'حفظ باسم…';

  @override
  String get editorMenuSettings => 'الإعدادات';

  @override
  String get editorMenuSwitchToEdit => 'التبديل إلى وضع التحرير';

  @override
  String get editorMenuSwitchToReadOnly => 'التبديل إلى وضع القراءة فقط';

  @override
  String editorNamedAction(String name) {
    return 'إجراء مُسمّى: $name';
  }

  @override
  String get editorNoRecentFiles => 'لا توجد ملفات أخيرة';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'افتح مستندًا قبل تشغيل OCR';

  @override
  String get editorOpenFailedTitle => 'فشل الفتح';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فتح في علامات تبويب جديدة',
      many: 'فتح في علامات تبويب جديدة',
      few: 'فتح في علامات تبويب جديدة',
      two: 'فتح في علامتَي تبويب جديدتين',
      one: 'فتح في علامة تبويب جديدة',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'فتح ملف PDF في علامة تبويب جديدة';

  @override
  String get editorOpenRecent => 'فتح ملف حديث';

  @override
  String get editorOpenTabs => 'علامات التبويب المفتوحة';

  @override
  String get editorOpeningDocumentSemantic => 'جارٍ فتح المستند';

  @override
  String get editorOpeningPdf => 'جارٍ فتح ملف PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'جارٍ فتح $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'صفحة $number';
  }

  @override
  String get editorPreviewComparison => 'مقارنة';

  @override
  String get editorPreviewCouldNotOpen => 'تعذّر الفتح';

  @override
  String get editorPreviewOpening => 'جارٍ الفتح';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'تمت إزالة التوقيع';

  @override
  String get editorSnapshotCopied => 'تم نسخ اللقطة إلى الحافظة';

  @override
  String get editorSnapshotCopyFailed => 'تعذّر نسخ اللقطة إلى الحافظة';

  @override
  String get editorTabs => 'علامات التبويب';

  @override
  String editorTabsOpenCount(int count) {
    return '$count مفتوحة';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مستند يحتوي على تغييرات غير محفوظة.',
      many: '$count مستندًا يحتوي على تغييرات غير محفوظة.',
      few: '$count مستندات تحتوي على تغييرات غير محفوظة.',
      two: 'يحتوي مستندان على تغييرات غير محفوظة.',
      one: 'يحتوي مستند على تغييرات غير محفوظة.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'إجراء غير مدعوم: $type';
  }

  @override
  String get editorUntitled => 'بلا عنوان';

  @override
  String editorUpdateAvailable(String version) {
    return 'الإصدار $version من DartPDF متاح.';
  }

  @override
  String get editorUpdateLater => 'لاحقًا';

  @override
  String get updateInstallNow => 'التحديث الآن';

  @override
  String get updateDownloadingTitle => 'جارٍ تنزيل التحديث';

  @override
  String get updatePreparing => 'جارٍ التحضير…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'جارٍ التنزيل… $percent%';
  }

  @override
  String get updateRestarting => 'جارٍ إعادة التشغيل لإكمال التحديث…';

  @override
  String get updateHandedOff => 'تم تنزيل التحديث. جارٍ فتح المُثبِّت…';

  @override
  String updateFailed(String error) {
    return 'فشل التحديث: $error';
  }

  @override
  String get editorViewAllTabs => 'عرض جميع علامات التبويب';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi نقطة/بوصة';
  }

  @override
  String get imgExportExport => 'تصدير';

  @override
  String get imgExportFormat => 'التنسيق';

  @override
  String get imgExportResolution => 'الدقة';

  @override
  String get imgExportTitle => 'تصدير الصفحة كصورة';

  @override
  String get newDocCreate => 'إنشاء';

  @override
  String get newDocLandscape => 'أفقي';

  @override
  String get newDocOrientation => 'الاتجاه';

  @override
  String get newDocPageSize => 'حجم الصفحة';

  @override
  String get newDocPortrait => 'عمودي';

  @override
  String get newDocTitle => 'مستند جديد';

  @override
  String get none => 'بلا';

  @override
  String get ocrAlreadyRunning =>
      'OCR قيد التشغيل بالفعل - انتظر انتهاءه أو ألغِه';

  @override
  String get ocrBrowserInitFailed => 'فشل تهيئة OCR في المتصفح';

  @override
  String get ocrCancelled => 'تم إلغاء OCR';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إلغاء OCR بعد $count مقطع نصي',
      many: 'تم إلغاء OCR بعد $count مقطعًا نصيًا',
      few: 'تم إلغاء OCR بعد $count مقاطع نصية',
      two: 'تم إلغاء OCR بعد مقطعين نصيين',
      one: 'تم إلغاء OCR بعد مقطع نصي واحد',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'تنزيل';

  @override
  String ocrDownloadFailed(String error) {
    return 'تعذّر تنزيل نموذج OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'تتطلب إضافة طبقة نص قابلة للتحديد نموذج OCR على الجهاز$size. يُنزَّل مرة واحدة ثم يعمل دون اتصال.\n\nالنموذج: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'تنزيل نموذج OCR؟';

  @override
  String ocrFailed(String error) {
    return 'فشل OCR: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb ميغابايت)';
  }

  @override
  String get ocrNotAvailable => 'OCR على الجهاز غير متاح على هذه المنصة';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أضاف OCR $count مقطع نصي - أصبح نص الصفحة قابلاً للتحديد الآن',
      many: 'أضاف OCR $count مقطعًا نصيًا - أصبح نص الصفحة قابلاً للتحديد الآن',
      few: 'أضاف OCR $count مقاطع نصية - أصبح نص الصفحة قابلاً للتحديد الآن',
      two: 'أضاف OCR مقطعين نصيين - أصبح نص الصفحة قابلاً للتحديد الآن',
      one: 'أضاف OCR مقطعًا نصيًا واحدًا - أصبح نص الصفحة قابلاً للتحديد الآن',
      zero: 'لم يعثر OCR على أي نص في هذه الصفحات',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'يُنزّل OCR على الويب نموذج Florence-2 للرؤية واللغة ويشغّله محليًا باستخدام WebGPU/WASM عبر Transformers.js. تبقى صفحات PDF في هذا المتصفح؛ ولا يُجلب سوى ملفات النموذج عند أول استخدام.';

  @override
  String get ocrWebPromptTitle => 'تشغيل OCR بالذكاء الاصطناعي في هذا المتصفح؟';

  @override
  String get ocrWebStart => 'بدء OCR';

  @override
  String get ok => 'موافق';

  @override
  String get paste => 'لصق';

  @override
  String get printDlgPreparing => 'جارٍ التحضير…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'جارٍ عرض الصفحة $rendered من $total…';
  }

  @override
  String get printDlgTitle => 'جارٍ الطباعة';

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
  String get settingsAbout => 'حول';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsCheckNow => 'التحقق الآن';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsLanguageSystem => 'افتراضي النظام';

  @override
  String get settingsCheckingForUpdates => 'جارٍ التحقق من التحديثات…';

  @override
  String get settingsCouldNotOpenDownload => 'تعذّر فتح التنزيل';

  @override
  String get settingsCouldNotOpenSystemSettings => 'تعذّر فتح إعدادات النظام';

  @override
  String get settingsDeveloperTools => 'أدوات المطوّر';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'المقاييس والسجلات وأوضاع العرض (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'تنزيل $version';
  }

  @override
  String get settingsOpenSettings => 'فتح الإعدادات';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف محفوظ',
      many: '$count ملفًا محفوظًا',
      few: '$count ملفات محفوظة',
      two: 'ملفان محفوظان',
      one: 'ملف واحد محفوظ',
      zero: 'لا توجد ملفات أخيرة',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'الملفات الأخيرة';

  @override
  String get settingsSetUpAsDefault => 'تعيين كتطبيق افتراضي';

  @override
  String get settingsSystem => 'النظام';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeSystem => 'النظام';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String settingsUpToDate(String version) {
    return 'أنت على أحدث إصدار ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'الإصدار $version متاح (لديك $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'تعذّر التحقق من التحديثات. حاول مرة أخرى لاحقًا.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'لديك $name $version.';
  }

  @override
  String get settingsUpdates => 'التحديثات';

  @override
  String get settingsViewSource => 'عرض المصدر على GitHub';

  @override
  String get undo => 'تراجع';

  @override
  String get welcomeOpenPdf => 'فتح ملف PDF';

  @override
  String get welcomePickAgainToReopen => 'اختره مجددًا لإعادة الفتح';

  @override
  String get welcomeRecent => 'الأخيرة';

  @override
  String get welcomeRemoveFromRecent => 'إزالة من الأخيرة';

  @override
  String get welcomeTapToReopen => 'انقر لإعادة الفتح';

  @override
  String get welcomeViewAsGrid => 'عرض شبكي';

  @override
  String get welcomeViewAsList => 'عرض القائمة';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'ثبّت تطبيق الويب، ثم اخترْه لملفات PDF.',
        'windows': 'افتح إعدادات التطبيقات الافتراضية في Windows لملفات PDF.',
        'macos': 'اتبع خطوات \"الفتح دائمًا باستخدام\" في Finder.',
        'linux': 'استخدم إعدادات التطبيقات الافتراضية لسطح مكتبك.',
        'android': 'اختر DartPDF عند فتح ملف PDF، ثم انقر \"دائمًا\".',
        'ios':
            'استخدم \"مشاركة\" أو \"فتح في\" من تطبيق الملفات لإرسال ملفات PDF إلى هنا.',
        'other': 'اضبط معالج ملفات PDF في نظامك.',
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
            'ثبّت DartPDF من متصفحك أولاً. ثم استخدم إعدادات معالج الملفات في المتصفح أو نظام التشغيل لربط ملفات PDF بالتطبيق المثبَّت.',
        'windows':
            'ستُفتح إعدادات Windows على \"التطبيقات الافتراضية\". ابحث عن \".pdf\" أو \"PDF\"، واختر تطبيق PDF الحالي، ثم حدد DartPDF.',
        'macos':
            'في Finder، حدد أي ملف PDF، واختر ملف > عرض المعلومات، ووسّع \"الفتح باستخدام\"، واختر DartPDF، ثم انقر \"تغيير الكل…\".',
        'linux':
            'افتح إعدادات سطح المكتب للتطبيقات الافتراضية، أو انقر بزر الفأرة الأيمن على ملف PDF في تطبيق الملفات، واختر الخصائص، وعيّن DartPDF كافتراضي لمستندات PDF.',
        'android':
            'افتح ملف PDF من الملفات أو التنزيلات، واختر DartPDF في منتقي التطبيقات، ثم حدد \"دائمًا\". إذا كان تطبيق آخر يفتح ملفات PDF بالفعل، فامسح افتراضيات ذلك التطبيق في إعدادات Android أولاً.',
        'ios':
            'لا يوفّر iOS محرّر PDF افتراضيًا شاملاً. استخدم الملفات > مشاركة، أو اضغط مطولاً على ملف PDF واختر مشاركة/فتح في، ثم اختر DartPDF.',
        'other':
            'استخدم إعدادات النظام لمعالجات الملفات لربط مستندات PDF بـ DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'جارٍ تنزيل نموذج OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'جارٍ تنزيل النموذج $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'جارٍ إنهاء OCR…';

  @override
  String get fileTypePdf => 'مستندات PDF';

  @override
  String get fileTypeImages => 'الصور';

  @override
  String get fileTypeStampBundle => 'أختام DartPDF';

  @override
  String get appSigKeyFileType => 'مفاتيح RSA الخاصة';

  @override
  String get appSigCertificateFileType => 'شهادات X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'حدد شهادة X.509 واحدة على الأقل.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'الشهادة $index ليست X.509 صالحة.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'المفتاح الخاص لا يطابق أي شهادة RSA محددة.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'المفاتيح الخاصة المشفّرة غير مدعومة. اختر مفتاح RSA غير مشفّر بصيغة PKCS#1 أو PKCS#8.';

  @override
  String get appSigErrorKeyNotRsa =>
      'المفتاح الخاص ليس مفتاح RSA غير مشفّر بصيغة PKCS#1 أو PKCS#8.';

  @override
  String get appSigErrorNoCertificateFound => 'لم يُعثر على أي شهادات X.509.';
}
