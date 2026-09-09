// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class DartPdfPrintingLocalizationsId extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get cancel => 'Batal';

  @override
  String get printDlgPreparing => 'Menyiapkan…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Merender halaman $rendered dari $total…';
  }

  @override
  String get printDlgTitle => 'Mencetak';

  @override
  String get printPreviewAll => 'Semua';

  @override
  String get printPreviewCurrent => 'Saat ini';

  @override
  String get printPreviewNextPage => 'Halaman berikutnya';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Halaman $page dari $total';
  }

  @override
  String get printPreviewPreviousPage => 'Halaman sebelumnya';

  @override
  String get printPreviewPrint => 'Cetak';

  @override
  String get printPreviewRange => 'Rentang';

  @override
  String printPreviewRangeError(int total) {
    return 'Masukkan rentang halaman antara 1 dan $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Halaman yang akan dicetak: $count';
  }

  @override
  String get printPreviewTitle => 'Pratinjau cetak';

  @override
  String get printPreviewUnavailable => 'Pratinjau tidak tersedia';

  @override
  String get printOptionsPrinter => 'Printer';

  @override
  String get printOptionsNativePrinter =>
      'Pilih printer, baki kertas, warna, pencetakan dua sisi, dan properti perangkat pada dialog cetak sistem berikutnya. Biarkan skala pada 100% dan jumlah salinan pada 1 untuk menggunakan tata letak yang ditampilkan di sini.';

  @override
  String get printOptionsPages => 'Halaman';

  @override
  String get printOptionsSelected => 'Terpilih';

  @override
  String get printOptionsPageRange => 'Halaman (misalnya, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Tambahkan file…';

  @override
  String get printOptionsAddFailed =>
      'Tidak dapat menambahkan file yang dipilih.';

  @override
  String get printOptionsGetWindow => 'Pilih area';

  @override
  String get printOptionsClearWindow => 'Hapus area';

  @override
  String get printOptionsWindowHint =>
      'Seret untuk menggambar persegi panjang pada halaman sumber ini guna memilih area yang akan dicetak.';

  @override
  String get printOptionsPaper => 'Kertas';

  @override
  String get printOptionsPaperSize => 'Ukuran kertas';

  @override
  String get printOptionsPageSize => 'Gunakan ukuran halaman dokumen';

  @override
  String get printOptionsOrientation => 'Orientasi';

  @override
  String get printOptionsAuto => 'Otomatis';

  @override
  String get printOptionsPortrait => 'Potret';

  @override
  String get printOptionsLandscape => 'Lanskap';

  @override
  String get printOptionsCopies => 'Salinan';

  @override
  String get printOptionsCollate => 'Susun per set';

  @override
  String get printOptionsReverse => 'Balik urutan halaman';

  @override
  String get printOptionsLayout => 'Tata letak halaman';

  @override
  String get printOptionsScaling => 'Penskalaan halaman';

  @override
  String get printOptionsScaleNone => 'Tidak ada (ukuran sebenarnya)';

  @override
  String get printOptionsFitPaper => 'Sesuaikan ke kertas';

  @override
  String get printOptionsReducePaper => 'Perkecil agar muat di kertas';

  @override
  String get printOptionsFitMargins => 'Sesuaikan ke margin';

  @override
  String get printOptionsReduceMargins => 'Perkecil agar muat dalam margin';

  @override
  String get printOptionsCustomScale => 'Skala khusus';

  @override
  String get printOptionsMultiple => 'Beberapa halaman per lembar';

  @override
  String get printOptionsScalePercent => 'Skala (%)';

  @override
  String get printOptionsMargin => 'Margin (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Halaman per lembar';

  @override
  String get printOptionsPageOrder => 'Urutan halaman';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal terbalik';

  @override
  String get printOptionsVertical => 'Vertikal';

  @override
  String get printOptionsVerticalReverse => 'Vertikal terbalik';

  @override
  String get printOptionsBorder => 'Cetak bingkai halaman';

  @override
  String get printOptionsRotation => 'Rotasi (searah jarum jam)';

  @override
  String get printOptionsNoRotation => 'Tidak ada';

  @override
  String get printOptionsCenter => 'Posisikan di tengah kertas';

  @override
  String get printOptionsOffsetX => 'Geser ke kanan (pt)';

  @override
  String get printOptionsOffsetY => 'Geser ke bawah (pt)';

  @override
  String get printOptionsContents => 'Konten yang dicetak';

  @override
  String get printOptionsDocumentAndMarkups => 'Dokumen dan anotasi';

  @override
  String get printOptionsDocumentOnly => 'Hanya dokumen';

  @override
  String get printOptionsMarkupsOnly => 'Hanya anotasi';

  @override
  String get printOptionsDimPage => 'Redupkan konten halaman';

  @override
  String get printOptionsDimMarkups => 'Redupkan anotasi';

  @override
  String get printOptionsHyperlinks => 'Cetak hyperlink yang terlihat';

  @override
  String get printOptionsDefaults => 'Default';

  @override
  String get printOptionsInvalidNumber =>
      'Masukkan angka yang valid sebelum mencetak.';

  @override
  String get printOptionsInvalidValue => 'Nilai tidak valid';

  @override
  String get printOptionsMarginGuide =>
      'Garis merah menunjukkan margin dan tidak ikut dicetak.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Area: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Sumber: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Lembar: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Lembar $sheet dari $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Tata letak ini tidak dapat disiapkan. Periksa ukuran kertas, margin, dan skala.';

  @override
  String get printOptionsChoosePrinter => 'Pilih printer';

  @override
  String get printOptionsNoPrinters =>
      'Tidak ada printer yang terinstal. Tambahkan printer di Pengaturan Windows, lalu coba lagi.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Printer tersimpan “$printer” tidak tersedia. Pilih printer untuk melanjutkan.';
  }

  @override
  String get printOptionsPrinterError =>
      'Tidak dapat memuat pengaturan printer. Periksa koneksi printer dan coba lagi.';

  @override
  String get printOptionsRetry => 'Coba lagi';

  @override
  String get printOptionsColor => 'Warna';

  @override
  String get printOptionsGrayscale => 'Hitam putih';

  @override
  String get printOptionsDuplex => 'Pencetakan dua sisi';

  @override
  String get printOptionsSimplex => 'Satu sisi';

  @override
  String get printOptionsLongEdge => 'Balik pada sisi panjang';

  @override
  String get printOptionsShortEdge => 'Balik pada sisi pendek';

  @override
  String get printOptionsTray => 'Baki kertas';

  @override
  String get printOptionsDefaultTray => 'Default printer';

  @override
  String get printOptionsProperties => 'Properti printer…';

  @override
  String get printOptionsDirectPrinter =>
      'Cetak mengirim pekerjaan ini langsung ke printer yang dipilih.';

  @override
  String get printOptionsPropertiesError =>
      'Tidak dapat membuka properti printer.';

  @override
  String get printOptionsLoadingPrinters => 'Memuat printer…';
}
