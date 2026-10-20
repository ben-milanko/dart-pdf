// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class DartPdfPrintingLocalizationsTr extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get cancel => 'İptal';

  @override
  String get printDlgPreparing => 'Hazırlanıyor…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Sayfa $rendered / $total işleniyor…';
  }

  @override
  String get printDlgTitle => 'Yazdırılıyor';

  @override
  String get printPreviewAll => 'Tümü';

  @override
  String get printPreviewCurrent => 'Geçerli';

  @override
  String get printPreviewNextPage => 'Sonraki sayfa';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Sayfa $page / $total';
  }

  @override
  String get printPreviewPreviousPage => 'Önceki sayfa';

  @override
  String get printPreviewPrint => 'Yazdır';

  @override
  String get printPreviewRange => 'Aralık';

  @override
  String printPreviewRangeError(int total) {
    return '1 ile $total arasında bir sayfa aralığı girin.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Yazdırılacak sayfa: $count';
  }

  @override
  String get printPreviewTitle => 'Yazdırma önizlemesi';

  @override
  String get printPreviewUnavailable => 'Önizleme kullanılamıyor';

  @override
  String get printOptionsPrinter => 'Yazıcı';

  @override
  String get printOptionsNativePrinter =>
      'Bir sonraki sistem yazdırma iletişim kutusunda yazıcıyı, kağıt tepsisini, rengi, çift taraflı yazdırmayı ve aygıt özelliklerini seçin. Burada gösterilen düzeni kullanmak için ölçeği %100 ve kopya sayısını 1 olarak bırakın.';

  @override
  String get printOptionsPages => 'Sayfalar';

  @override
  String get printOptionsSelected => 'Seçili';

  @override
  String get printOptionsPageRange => 'Sayfalar (örneğin 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Dosya ekle…';

  @override
  String get printOptionsAddFailed => 'Seçilen dosyalar eklenemedi.';

  @override
  String get printOptionsGetWindow => 'Alan seç';

  @override
  String get printOptionsClearWindow => 'Alanı temizle';

  @override
  String get printOptionsWindowHint =>
      'Yazdırılacak alanı seçmek için bu kaynak sayfa üzerinde bir dikdörtgen sürükleyin.';

  @override
  String get printOptionsPaper => 'Kağıt';

  @override
  String get printOptionsPaperSize => 'Kağıt boyutu';

  @override
  String get printOptionsPageSize => 'Belgenin sayfa boyutunu kullan';

  @override
  String get printOptionsOrientation => 'Yönlendirme';

  @override
  String get printOptionsAuto => 'Otomatik';

  @override
  String get printOptionsPortrait => 'Dikey';

  @override
  String get printOptionsLandscape => 'Yatay';

  @override
  String get printOptionsCopies => 'Kopya';

  @override
  String get printOptionsCollate => 'Harmanla';

  @override
  String get printOptionsReverse => 'Sayfa sırasını ters çevir';

  @override
  String get printOptionsLayout => 'Sayfa düzeni';

  @override
  String get printOptionsScaling => 'Sayfa ölçeklendirme';

  @override
  String get printOptionsScaleNone => 'Yok (gerçek boyut)';

  @override
  String get printOptionsFitPaper => 'Kağıda sığdır';

  @override
  String get printOptionsReducePaper => 'Kağıda sığacak kadar küçült';

  @override
  String get printOptionsFitMargins => 'Kenar boşluklarına sığdır';

  @override
  String get printOptionsReduceMargins =>
      'Kenar boşluklarına sığacak kadar küçült';

  @override
  String get printOptionsCustomScale => 'Özel ölçek';

  @override
  String get printOptionsMultiple => 'Yaprak başına birden çok sayfa';

  @override
  String get printOptionsScalePercent => 'Ölçek (%)';

  @override
  String get printOptionsMargin => 'Kenar boşlukları (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Yaprak başına sayfa';

  @override
  String get printOptionsPageOrder => 'Sayfa sırası';

  @override
  String get printOptionsHorizontal => 'Yatay';

  @override
  String get printOptionsHorizontalReverse => 'Ters yatay';

  @override
  String get printOptionsVertical => 'Dikey';

  @override
  String get printOptionsVerticalReverse => 'Ters dikey';

  @override
  String get printOptionsBorder => 'Sayfa kenarlıklarını yazdır';

  @override
  String get printOptionsRotation => 'Döndürme (saat yönünde)';

  @override
  String get printOptionsNoRotation => 'Yok';

  @override
  String get printOptionsCenter => 'Kağıtta ortala';

  @override
  String get printOptionsOffsetX => 'Sağa kaydırma (pt)';

  @override
  String get printOptionsOffsetY => 'Aşağı kaydırma (pt)';

  @override
  String get printOptionsContents => 'Yazdırılacak içerik';

  @override
  String get printOptionsDocumentAndMarkups => 'Belge ve açıklamalar';

  @override
  String get printOptionsDocumentOnly => 'Yalnızca belge';

  @override
  String get printOptionsMarkupsOnly => 'Yalnızca açıklamalar';

  @override
  String get printOptionsDimPage => 'Sayfa içeriğini soluklaştır';

  @override
  String get printOptionsDimMarkups => 'Açıklamaları soluklaştır';

  @override
  String get printOptionsHyperlinks => 'Görünür köprüleri yazdır';

  @override
  String get printOptionsDefaults => 'Varsayılanlar';

  @override
  String get printOptionsInvalidNumber =>
      'Yazdırmadan önce geçerli sayılar girin.';

  @override
  String get printOptionsInvalidValue => 'Geçersiz değer';

  @override
  String get printOptionsMarginGuide =>
      'Kırmızı çizgiler kenar boşluklarını gösterir; yazdırılmazlar.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Alan: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Kaynak: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Yaprak: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Yaprak $sheet / $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Bu düzen hazırlanamadı. Kağıt boyutunu, kenar boşluklarını ve ölçeği kontrol edin.';

  @override
  String get printOptionsChoosePrinter => 'Yazıcı seçin';

  @override
  String get printOptionsNoPrinters =>
      'Yüklü yazıcı yok. Windows Ayarları’ndan bir yazıcı ekleyip yeniden deneyin.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Kayıtlı “$printer” yazıcısı kullanılamıyor. Devam etmek için bir yazıcı seçin.';
  }

  @override
  String get printOptionsPrinterError =>
      'Yazıcı ayarları yüklenemedi. Yazıcı bağlantısını kontrol edip yeniden deneyin.';

  @override
  String get printOptionsRetry => 'Yeniden dene';

  @override
  String get printOptionsColor => 'Renkli';

  @override
  String get printOptionsGrayscale => 'Siyah beyaz';

  @override
  String get printOptionsDuplex => 'Çift taraflı yazdırma';

  @override
  String get printOptionsSimplex => 'Tek taraflı';

  @override
  String get printOptionsLongEdge => 'Uzun kenardan çevir';

  @override
  String get printOptionsShortEdge => 'Kısa kenardan çevir';

  @override
  String get printOptionsTray => 'Kağıt tepsisi';

  @override
  String get printOptionsDefaultTray => 'Yazıcı varsayılanı';

  @override
  String get printOptionsProperties => 'Yazıcı özellikleri…';

  @override
  String get printOptionsDirectPrinter =>
      'Yazdır, bu işi doğrudan seçili yazıcıya gönderir.';

  @override
  String get printOptionsPropertiesError => 'Yazıcı özellikleri açılamadı.';

  @override
  String get printOptionsLoadingPrinters => 'Yazıcılar yükleniyor…';
}
