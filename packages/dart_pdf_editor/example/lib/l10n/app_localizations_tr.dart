// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get add => 'Ekle';

  @override
  String get apply => 'Uygula';

  @override
  String get cancel => 'İptal';

  @override
  String get clear => 'Temizle';

  @override
  String get close => 'Kapat';

  @override
  String get copy => 'Kopyala';

  @override
  String get cut => 'Kes';

  @override
  String get delete => 'Sil';

  @override
  String get done => 'Bitti';

  @override
  String get edit => 'Düzenle';

  @override
  String exActionJavaScript(String script) {
    return 'Uygulamaya sunulan JavaScript: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Bağlantı: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Adlandırılmış eylem: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'İşlenmeyen eylem türü: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Ek açıklama metni kopyalandı';

  @override
  String get exApiKeyHelper => 'Authorization: Bearer … olarak gönderilir';

  @override
  String get exApiKeyLabel => 'API anahtarı / belirteç (isteğe bağlı)';

  @override
  String get exAppMenuTooltip => 'DartPDF menüsü';

  @override
  String get exClearRecentFiles => 'Son dosyaları temizle';

  @override
  String get exCloseTab => 'Sekmeyi kapat';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Karşılaştır: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Başka bir PDF ile karşılaştır…';

  @override
  String get exCopiedToClipboard => 'Panoya kopyalandı';

  @override
  String get exCopySelectedText => 'Seçili metni kopyala (⌘C)';

  @override
  String get exCopyText => 'Metni kopyala';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '$name açılamadı\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '$path açılamadı\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '$url açılamadı';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '$uri açılamadı\n$error\n\nWeb\'de bu genellikle bir CORS kısıtlamasıdır: sunucu Access-Control-Allow-Origin göndermeli ve Range üstbilgilerini açığa çıkarmalıdır.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '$title yeniden açılamadı\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '$title yeniden açılamadı - kaydedilmiş kopyası artık kullanılamıyor.';
  }

  @override
  String get exDemoNoteHint =>
      'Buraya yazın - bu metin kutusu sayfanın üzerinde yüzer';

  @override
  String get exDiagnosticsCopied => 'Tanılamalar panoya kopyalandı';

  @override
  String exDownloaded(String name) {
    return '$name indirildi';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name indirildi - Ctrl+V ile PDF\'ye geri yapıştırın';
  }

  @override
  String get exExport => 'Dışa aktar';

  @override
  String exExportFailed(String error) {
    return 'Dışa aktarma başarısız: $error';
  }

  @override
  String get exExportPageImageMenu => 'Sayfayı görsel olarak dışa aktar…';

  @override
  String get exExportPageImageTitle => 'Sayfayı görsel olarak dışa aktar';

  @override
  String get exFeatureShowcase => 'Özellik vitrini';

  @override
  String get exFormat => 'Biçim';

  @override
  String get exHide => 'Gizle';

  @override
  String get exHorizontalLayout => 'Yatay sayfa düzeni';

  @override
  String get exHowToSetupOcr => 'OCR sunucusu nasıl kurulur';

  @override
  String get exModelName => 'Model adı';

  @override
  String get exNoMessage => 'Mesaj yok';

  @override
  String get exNoRecentFiles => 'Son dosya yok';

  @override
  String exNotAValidUrl(String url) {
    return 'Geçerli bir URL değil:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR $count metin dizisi ekledi - sayfa metni artık seçilebilir',
      one: 'OCR 1 metin dizisi ekledi - sayfa metni artık seçilebilir',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Barındırdığınız bir görsel-dil OCR modeli (vLLM üzerinde dots.ocr veya OpenAI uyumlu herhangi bir OCR uç noktası) kullanarak taranan sayfaların üzerine seçilebilir, aranabilir bir metin katmanı ekler.';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR başarısız: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Aç';

  @override
  String get exOpenDocumentBeforeOcr => 'OCR çalıştırmadan önce bir belge açın';

  @override
  String get exOpenDocumentFirst => 'Önce bir belge açın';

  @override
  String get exOpenFromUrl => 'Bir URL\'den aç…';

  @override
  String get exOpenFromUrlTitle => 'Bir URL\'den aç';

  @override
  String get exOpenInNewTab => 'PDF\'yi yeni sekmede aç';

  @override
  String get exOpenInteractiveDemo => 'Etkileşimli demoyu aç';

  @override
  String get exOpenPdf => 'Bir PDF aç…';

  @override
  String get exOpenPdfButton => 'Bir PDF aç';

  @override
  String get exOpenRecent => 'Son Kullanılanları Aç';

  @override
  String get exRecentFiles => 'Son dosyalar';

  @override
  String get exViewAllRecentFiles => 'Tüm son dosyaları görüntüle…';

  @override
  String get exSearchRecentFiles => 'Son dosyalarda ara';

  @override
  String get exNoMatchingRecentFiles => 'Aramanızla eşleşen son dosya yok';

  @override
  String get exGridView => 'Izgara görünümü';

  @override
  String get exListView => 'Liste görünümü';

  @override
  String get exOpenUrlDescription =>
      'PDF\'yi PdfHttpByteSource aracılığıyla HTTP Range istekleriyle akıtır, yalnızca ayrıştırıcının ihtiyaç duyduğunu getirir ve sunucunun Range desteği olmadığında tam indirmeye geri döner.';

  @override
  String get exOpeningDocument => 'Belge açılıyor';

  @override
  String get exOpeningPdf => 'PDF açılıyor…';

  @override
  String exOpeningTitle(String title) {
    return '$title açılıyor…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL\'si';

  @override
  String get exPerformanceAuto => 'Performans: Otomatik';

  @override
  String get exPreparing => 'Hazırlanıyor…';

  @override
  String get exPubDevMenuItem => 'pub.dev\'de dart_pdf_editor';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Sayfa $current / $count tanınıyor…';
  }

  @override
  String get exResolution => 'Çözünürlük';

  @override
  String get exRunOcr => 'OCR çalıştır';

  @override
  String get exSaveAs => 'Farklı kaydet…';

  @override
  String exSaveFailed(String error) {
    return 'Kaydetme başarısız: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name kaydedildi';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name kaydedildi - ⌘V ile PDF\'ye geri yapıştırın';
  }

  @override
  String exSavedTo(String path) {
    return '$path konumuna kaydedildi';
  }

  @override
  String get exScrollIndicatorDemo => 'Kaydırma göstergesi API demosu';

  @override
  String get exServiceEndpoint => 'Servis uç noktası';

  @override
  String get exShow => 'Göster';

  @override
  String get exSingleWorker => 'Tek çalışan';

  @override
  String get exSupplyFeedback => 'Geri bildirim gönder…';

  @override
  String get exSwitchToEdit => 'Düzenleme moduna geç';

  @override
  String get exSwitchToReadOnly => 'Salt okunura geç';

  @override
  String get exThemeDark => 'Tema: koyu - sisteme geç';

  @override
  String get exThemeLight => 'Tema: açık - koyuya geç';

  @override
  String get exThemeSystem => 'Tema: sistem - açığa geç';

  @override
  String get exTryDemo => 'Etkileşimli demoyu deneyin';

  @override
  String get exUntitled => 'Başlıksız';

  @override
  String get exVerticalLayout => 'Dikey sayfa düzeni';

  @override
  String get exViewSource => 'GitHub\'da kaynağı görüntüle';

  @override
  String get exWorkerAuto => 'Otomatik';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performans: $count çalışan',
      one: 'Performans: tek çalışan',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count çalışan';
  }

  @override
  String get feedbackAttachDiagnostics => 'Bu tanılamaları rapora ekle';

  @override
  String get feedbackClearLog => 'Günlüğü temizle';

  @override
  String get feedbackCopyDiagnostics => 'Tanılamaları kopyala';

  @override
  String get feedbackDiagnosticsNotice =>
      'Geri bildirim formu tarayıcınızda açılır. Aşağıdaki tanılamalar yalnızca bu cihazda toplanır ve sorunu yeniden oluşturmaya yardımcı olmak için eklenir. Önce bunları gözden geçirin - gizli tutmak istediğiniz hiçbir şeyi eklemeyin.';

  @override
  String get feedbackOpenForm => 'Geri bildirim formunu aç';

  @override
  String get feedbackTitle => 'Geri bildirim gönder';

  @override
  String get none => 'Yok';

  @override
  String get ok => 'Tamam';

  @override
  String get paste => 'Yapıştır';

  @override
  String get redo => 'Yinele';

  @override
  String get remove => 'Kaldır';

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String get reset => 'Sıfırla';

  @override
  String get save => 'Kaydet';

  @override
  String get scrollDemoNextPage => 'Sonraki sayfa';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Sayfa $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Önceki sayfa';

  @override
  String get scrollDemoSwitchHorizontal => 'Yatay düzene geç';

  @override
  String get scrollDemoSwitchVertical => 'Dikey düzene geç';

  @override
  String get scrollDemoTitle => 'Kaydırma göstergesi API\'si';

  @override
  String get undo => 'Geri al';

  @override
  String get exFileTypePdf => 'PDF belgeleri';

  @override
  String get exFileTypeImages => 'Görseller';

  @override
  String get exFileTypeFonts => 'Yazı tipleri';
}
