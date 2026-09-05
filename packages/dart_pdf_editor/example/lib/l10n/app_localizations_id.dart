// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get add => 'Tambah';

  @override
  String get apply => 'Terapkan';

  @override
  String get cancel => 'Batal';

  @override
  String get clear => 'Bersihkan';

  @override
  String get close => 'Tutup';

  @override
  String get copy => 'Salin';

  @override
  String get cut => 'Potong';

  @override
  String get delete => 'Hapus';

  @override
  String get done => 'Selesai';

  @override
  String get edit => 'Edit';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript ditampilkan ke aplikasi: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Tautan: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Tindakan bernama: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Tipe tindakan tak tertangani: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Teks anotasi disalin';

  @override
  String get exApiKeyHelper => 'Dikirim sebagai Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Kunci API / token (opsional)';

  @override
  String get exAppMenuTooltip => 'Menu DartPDF';

  @override
  String get exClearRecentFiles => 'Bersihkan berkas terkini';

  @override
  String get exCloseTab => 'Tutup tab';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Bandingkan: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Bandingkan dengan PDF lain…';

  @override
  String get exCopiedToClipboard => 'Disalin ke papan klip';

  @override
  String get exCopySelectedText => 'Salin teks terpilih (⌘C)';

  @override
  String get exCopyText => 'Salin teks';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Tidak dapat membuka $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Tidak dapat membuka $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Tidak dapat membuka $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Tidak dapat membuka $uri\n$error\n\nDi web, ini sering merupakan pembatasan CORS: server harus mengirim Access-Control-Allow-Origin dan mengekspos header Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Tidak dapat membuka kembali $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Tidak dapat membuka kembali $title - salinan tersimpannya tidak lagi tersedia.';
  }

  @override
  String get exDemoNoteHint =>
      'Ketik di sini - kotak teks ini mengambang di atas halaman';

  @override
  String get exDiagnosticsCopied => 'Diagnostik disalin ke papan klip';

  @override
  String exDownloaded(String name) {
    return 'Mengunduh $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Mengunduh $name - tempel kembali ke PDF dengan Ctrl+V';
  }

  @override
  String get exExport => 'Ekspor';

  @override
  String exExportFailed(String error) {
    return 'Ekspor gagal: $error';
  }

  @override
  String get exExportPageImageMenu => 'Ekspor halaman sebagai gambar…';

  @override
  String get exExportPageImageTitle => 'Ekspor halaman sebagai gambar';

  @override
  String get exFeatureShowcase => 'Etalase fitur';

  @override
  String get exFormat => 'Format';

  @override
  String get exHide => 'Sembunyikan';

  @override
  String get exHorizontalLayout => 'Tata letak halaman horizontal';

  @override
  String get exHowToSetupOcr => 'Cara menyiapkan server OCR';

  @override
  String get exModelName => 'Nama model';

  @override
  String get exNoMessage => 'Tidak ada pesan';

  @override
  String get exNoRecentFiles => 'Tidak ada berkas terkini';

  @override
  String exNotAValidUrl(String url) {
    return 'Bukan URL yang valid:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR menambahkan $count rentang teks - teks halaman kini dapat dipilih',
      one: 'OCR menambahkan 1 rentang teks - teks halaman kini dapat dipilih',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Menambahkan lapisan teks yang dapat dipilih dan dicari di atas halaman terpindai menggunakan model OCR bahasa-visual yang Anda hos (dots.ocr di vLLM, atau titik akhir OCR apa pun yang kompatibel dengan OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR gagal: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Buka';

  @override
  String get exOpenDocumentBeforeOcr => 'Buka dokumen sebelum menjalankan OCR';

  @override
  String get exOpenDocumentFirst => 'Buka dokumen terlebih dahulu';

  @override
  String get exOpenFromUrl => 'Buka dari URL…';

  @override
  String get exOpenFromUrlTitle => 'Buka dari URL';

  @override
  String get exOpenInNewTab => 'Buka PDF di tab baru';

  @override
  String get exOpenInteractiveDemo => 'Buka demo interaktif';

  @override
  String get exOpenPdf => 'Buka PDF…';

  @override
  String get exOpenPdfButton => 'Buka PDF';

  @override
  String get exOpenRecent => 'Buka Terkini';

  @override
  String get exOpenUrlDescription =>
      'Mengalirkan PDF melalui permintaan HTTP Range via PdfHttpByteSource, hanya mengambil apa yang diperlukan parser dan beralih ke unduhan penuh saat server tidak mendukung range.';

  @override
  String get exOpeningDocument => 'Membuka dokumen';

  @override
  String get exOpeningPdf => 'Membuka PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Membuka $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL PDF';

  @override
  String get exPerformanceAuto => 'Performa: Otomatis';

  @override
  String get exPreparing => 'Menyiapkan…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor di pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Mengenali halaman $current dari $count…';
  }

  @override
  String get exResolution => 'Resolusi';

  @override
  String get exRunOcr => 'Jalankan OCR';

  @override
  String get exSaveAs => 'Simpan sebagai…';

  @override
  String exSaveFailed(String error) {
    return 'Penyimpanan gagal: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Menyimpan $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Menyimpan $name - tempel kembali ke PDF dengan ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Disimpan ke $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Demo API indikator gulir';

  @override
  String get exServiceEndpoint => 'Titik akhir layanan';

  @override
  String get exShow => 'Tampilkan';

  @override
  String get exSingleWorker => 'Pekerja tunggal';

  @override
  String get exSupplyFeedback => 'Berikan umpan balik…';

  @override
  String get exSwitchToEdit => 'Beralih ke mode edit';

  @override
  String get exSwitchToReadOnly => 'Beralih ke hanya-baca';

  @override
  String get exThemeDark => 'Tema: gelap - beralih ke sistem';

  @override
  String get exThemeLight => 'Tema: terang - beralih ke gelap';

  @override
  String get exThemeSystem => 'Tema: sistem - beralih ke terang';

  @override
  String get exTryDemo => 'Coba demo interaktif';

  @override
  String get exUntitled => 'Tanpa judul';

  @override
  String get exVerticalLayout => 'Tata letak halaman vertikal';

  @override
  String get exViewSource => 'Lihat sumber di GitHub';

  @override
  String get exWorkerAuto => 'Otomatis';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Performa: $count pekerja',
      one: 'Performa: pekerja tunggal',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count pekerja';
  }

  @override
  String get feedbackAttachDiagnostics => 'Lampirkan diagnostik ini ke laporan';

  @override
  String get feedbackClearLog => 'Bersihkan log';

  @override
  String get feedbackCopyDiagnostics => 'Salin diagnostik';

  @override
  String get feedbackDiagnosticsNotice =>
      'Formulir umpan balik terbuka di peramban Anda. Diagnostik di bawah ini dikumpulkan hanya di perangkat ini dan dilampirkan untuk membantu mereproduksi masalah. Tinjau terlebih dahulu - jangan sertakan apa pun yang lebih baik Anda rahasiakan.';

  @override
  String get feedbackOpenForm => 'Buka formulir umpan balik';

  @override
  String get feedbackTitle => 'Kirim umpan balik';

  @override
  String get none => 'Tidak ada';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Tempel';

  @override
  String get redo => 'Ulangi';

  @override
  String get remove => 'Hapus';

  @override
  String get rename => 'Ganti nama';

  @override
  String get reset => 'Setel ulang';

  @override
  String get save => 'Simpan';

  @override
  String get scrollDemoNextPage => 'Halaman berikutnya';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Halaman $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Halaman sebelumnya';

  @override
  String get scrollDemoSwitchHorizontal => 'Beralih ke tata letak horizontal';

  @override
  String get scrollDemoSwitchVertical => 'Beralih ke tata letak vertikal';

  @override
  String get scrollDemoTitle => 'API indikator gulir';

  @override
  String get undo => 'Urungkan';

  @override
  String get exFileTypePdf => 'Dokumen PDF';

  @override
  String get exFileTypeImages => 'Gambar';

  @override
  String get exFileTypeFonts => 'Font';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - bagian $part.pdf';
  }
}
