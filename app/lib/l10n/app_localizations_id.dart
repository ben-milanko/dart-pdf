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
  String get appSigAddLogo => 'Tambah logo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Semua $pageCount halaman';
  }

  @override
  String get appSigAppearance => 'Tampilan';

  @override
  String get appSigAppearanceDescription =>
      'Tanda tangan digambar di tempat Anda menempatkannya. Nama penanda tangan dan detailnya selalu ditampilkan; Anda dapat menambahkan tanda gambar tangan dan latar logo.';

  @override
  String appSigApplyTo(String label) {
    return 'Terapkan ke: $label';
  }

  @override
  String get appSigApplyToPages => 'Terapkan ke halaman…';

  @override
  String get appSigChooseCertificate => 'Pilih berkas sertifikat…';

  @override
  String get appSigChooseKeyDescription =>
      'Pilih kunci privat Anda (RSA, PEM atau DER) dan berkas sertifikatnya. Kunci hanya digunakan untuk menandatangani dan tidak pernah disimpan.';

  @override
  String get appSigChoosePngOrJpeg => 'Pilih gambar PNG atau JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Pilih kunci privat…';

  @override
  String get appSigContactInfo => 'Info kontak';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Tidak dapat menangkap tanda tangan.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Tidak dapat membaca sertifikat: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Tidak dapat membaca kunci: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Buat tanda tangan di perangkat ini';

  @override
  String appSigDate(String date) {
    return 'Tanggal: $date';
  }

  @override
  String get appSigDigitallySign => 'Tandatangani secara digital';

  @override
  String get appSigDrawSignature => 'Gambar tanda tangan…';

  @override
  String get appSigFieldHelper =>
      'Biarkan kosong untuk membuat bidang tanda tangan baru.';

  @override
  String get appSigFieldLabel => 'Bidang tanda tangan yang ada (opsional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sertifikat',
      one: '1 sertifikat',
    );
    return '$_temp0 · berlaku $validFrom hingga $validUntil';
  }

  @override
  String get appSigIntro =>
      'Tanda tangan digital membuktikan bahwa Anda menandatangani dokumen ini dan bahwa dokumen tersebut tidak berubah sejak itu. Pilih cara Anda ingin menandatangani.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Kunci atau sertifikat yang dipilih tidak dapat dibaca.';

  @override
  String get appSigKeylessDescription =>
      'Termudah. Kami memastikan bahwa itu Anda melalui email dan menandatangani untuk Anda, dengan stempel waktu tepercaya. Tidak ada yang perlu dipasang atau disiapkan.';

  @override
  String get appSigKeylessIdentity => 'Identitas tanpa kunci';

  @override
  String get appSigKeylessSignInExpired =>
      'Masuk tanpa kunci Anda telah kedaluwarsa. Silakan masuk lagi.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Masuk tanpa kunci gagal: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Tanpa kunci · berstempel waktu · validitas tidak diketahui';

  @override
  String get appSigKeylessWebNote =>
      'Masuk dengan email Anda adalah cara termudah — tersedia di aplikasi DartPDF desktop dan seluler. Untuk alasan keamanan, ini tidak dapat berjalan di peramban web.';

  @override
  String get appSigLocation => 'Lokasi';

  @override
  String get appSigLogoAdded => 'Logo ditambahkan ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Halaman $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Pratinjau - kotak yang ditandatangani mungkin sedikit berbeda.';

  @override
  String get appSigReason => 'Alasan';

  @override
  String appSigReasonLine(String reason) {
    return 'Alasan: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Menyegarkan masuk…';

  @override
  String get appSigRemoveLogo => 'Hapus logo';

  @override
  String get appSigRemoveSignature => 'Hapus tanda tangan';

  @override
  String get appSigSelfSignedDescription =>
      'Tidak perlu masuk atau berkas. Terbaik untuk penggunaan pribadi — disimpan di perangkat ini untuk lain kali. Beberapa pembaca PDF akan menampilkannya sebagai \"ditandatangani, validitas tidak diketahui\", yang normal untuk tanda tangan yang Anda buat sendiri.';

  @override
  String get appSigSelfSignedIdentity =>
      'Identitas yang ditandatangani sendiri';

  @override
  String get appSigSelfSignedSubtitle =>
      'Ditandatangani sendiri · validitas tidak diketahui';

  @override
  String get appSigShowSignatureOnPages =>
      'Tampilkan tanda tangan pada halaman';

  @override
  String get appSigSign => 'Tandatangani';

  @override
  String get appSigSignInWithEmail => 'Masuk dengan email Anda';

  @override
  String get appSigSignatureAdded => 'Tanda tangan ditambahkan ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Ditandatangani secara digital oleh $signerName';
  }

  @override
  String get appSigSigner => 'Penanda tangan';

  @override
  String get appSigSigningYouIn => 'Memasukkan Anda…';

  @override
  String get appSigThisPageOnly => 'Halaman ini saja';

  @override
  String get appSigUseOwnCertificate => 'Gunakan sertifikat Anda sendiri';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Untuk sertifikat penandatanganan dari organisasi Anda';

  @override
  String get appSigX509Signer => 'Penanda tangan X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Buka $count PDF ini di tab baru, atau sisipkan halamannya ke \"$title\"?',
      one: 'Buka PDF ini di tab baru, atau sisipkan halamannya ke \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tambah PDF yang dijatuhkan',
      one: 'Tambah PDF yang dijatuhkan',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Teks anotasi disalin';

  @override
  String get editorAppMenuTooltip => 'Menu DartPDF';

  @override
  String get editorCancelOcr => 'Batalkan OCR';

  @override
  String get editorClearRecentFiles => 'Bersihkan berkas terkini';

  @override
  String get editorCloseAll => 'Tutup semua';

  @override
  String get editorCloseOthers => 'Tutup lainnya';

  @override
  String get editorCloseTab => 'Tutup tab';

  @override
  String get editorCloseTabsToRight => 'Tutup tab di sebelah kanan';

  @override
  String get editorCompareFailedTitle => 'Perbandingan gagal';

  @override
  String editorCompareTitle(String title) {
    return 'Bandingkan: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Disalin ke papan klip';

  @override
  String get editorCopySelectedTextTooltip => 'Salin teks terpilih (⌘C)';

  @override
  String get editorCopyText => 'Salin teks';

  @override
  String editorCouldNotExport(String title) {
    return 'Tidak dapat mengekspor $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Tidak dapat mengimpor stempel: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tidak dapat menyisipkan PDF yang dijatuhkan',
      one: 'Tidak dapat menyisipkan PDF yang dijatuhkan',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Tidak dapat membuka $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Tidak dapat membuka folder penyimpan';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Tidak dapat membuka berkas kedua\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Tidak dapat membuka berkas yang dipilih\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Tidak dapat membuka $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Tidak dapat mencetak $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Tidak dapat membuka kembali $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Tidak dapat menandatangani secara digital: $error';
  }

  @override
  String get editorDiscard => 'Buang';

  @override
  String get editorDiscardChangesTitle => 'Buang perubahan?';

  @override
  String get editorDocumentSigned => 'Dokumen ditandatangani secara digital';

  @override
  String get editorDownload => 'Unduh';

  @override
  String get editorDropToOpen => 'Jatuhkan PDF untuk membuka';

  @override
  String get editorDropToOpenOrInsert =>
      'Jatuhkan PDF untuk membuka atau menyisipkan';

  @override
  String get editorInsertPages => 'Sisipkan halaman';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Menyisipkan $count; tidak dapat membaca $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Menyisipkan $count PDF ke $title',
      one: 'Menyisipkan halaman ke $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Tautan tidak valid: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Dokumen ini mencoba menjalankan JavaScript (diabaikan)';

  @override
  String get editorLoadingFullDocument => 'Memuat dokumen penuh';

  @override
  String get editorMenuCompareWith => 'Bandingkan dengan…';

  @override
  String get editorMenuDigitallySign => 'Tandatangani secara digital…';

  @override
  String get editorMenuDigitallySigning => 'Menandatangani secara digital…';

  @override
  String get editorMenuExportImage => 'Ekspor halaman sebagai gambar…';

  @override
  String get editorMenuNewDocument => 'Dokumen baru…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Buka PDF…';

  @override
  String get editorMenuPrint => 'Cetak…';

  @override
  String get editorMenuSaveAs => 'Simpan sebagai…';

  @override
  String get editorMenuScanDocument => 'Pindai ke dokumen baru…';

  @override
  String get editorMenuInsertScan => 'Sisipkan pindaian…';

  @override
  String get editorScanFailed => 'Tidak dapat memindai dokumen.';

  @override
  String get editorInsertedScan => 'Halaman pindaian disisipkan.';

  @override
  String get editorMenuSettings => 'Pengaturan';

  @override
  String get editorMenuSwitchToEdit => 'Beralih ke mode edit';

  @override
  String get editorMenuSwitchToReadOnly => 'Beralih ke hanya-baca';

  @override
  String editorNamedAction(String name) {
    return 'Tindakan bernama: $name';
  }

  @override
  String get editorNoRecentFiles => 'Tidak ada berkas terkini';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Buka dokumen sebelum menjalankan OCR';

  @override
  String get editorOpenFailedTitle => 'Gagal membuka';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Buka di tab baru',
      one: 'Buka di tab baru',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Buka PDF di tab baru';

  @override
  String get editorOpenRecent => 'Buka Terkini';

  @override
  String get editorOpenTabs => 'Buka tab';

  @override
  String get editorOpeningDocumentSemantic => 'Membuka dokumen';

  @override
  String get editorOpeningPdf => 'Membuka PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Membuka $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Halaman $number';
  }

  @override
  String get editorPreviewComparison => 'Perbandingan';

  @override
  String get editorPreviewCouldNotOpen => 'Tidak dapat membuka';

  @override
  String get editorPreviewOpening => 'Membuka';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Tanda tangan dihapus';

  @override
  String get editorSnapshotCopied => 'Cuplikan disalin ke papan klip';

  @override
  String get editorSnapshotCopyFailed =>
      'Tidak dapat menyalin cuplikan ke papan klip';

  @override
  String get editorTabs => 'Tab';

  @override
  String editorTabsOpenCount(int count) {
    return '$count terbuka';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dokumen memiliki perubahan yang belum disimpan.',
      one: 'Sebuah dokumen memiliki perubahan yang belum disimpan.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Tindakan tidak didukung: $type';
  }

  @override
  String get editorUntitled => 'Tanpa judul';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version tersedia.';
  }

  @override
  String get editorUpdateLater => 'Nanti';

  @override
  String get updateInstallNow => 'Perbarui sekarang';

  @override
  String get updateDownloadingTitle => 'Mengunduh pembaruan';

  @override
  String get updatePreparing => 'Menyiapkan…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Mengunduh… $percent%';
  }

  @override
  String get updateRestarting => 'Memulai ulang untuk menyelesaikan pembaruan…';

  @override
  String get updateHandedOff => 'Pembaruan diunduh. Membuka penginstal…';

  @override
  String updateFailed(String error) {
    return 'Pembaruan gagal: $error';
  }

  @override
  String get editorViewAllTabs => 'Lihat semua tab';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Ekspor';

  @override
  String get imgExportFormat => 'Format';

  @override
  String get imgExportResolution => 'Resolusi';

  @override
  String get imgExportTitle => 'Ekspor halaman sebagai gambar';

  @override
  String get newDocCreate => 'Buat';

  @override
  String get newDocLandscape => 'Lanskap';

  @override
  String get newDocOrientation => 'Orientasi';

  @override
  String get newDocPageSize => 'Ukuran halaman';

  @override
  String get newDocPortrait => 'Potret';

  @override
  String get newDocTitle => 'Dokumen baru';

  @override
  String get none => 'Tidak ada';

  @override
  String get ocrAlreadyRunning =>
      'OCR sudah berjalan - tunggu hingga selesai atau batalkan';

  @override
  String get ocrBrowserInitFailed => 'OCR peramban gagal diinisialisasi';

  @override
  String get ocrCancelled => 'OCR dibatalkan';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR dibatalkan setelah $count rentang teks',
      one: 'OCR dibatalkan setelah 1 rentang teks',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Unduh';

  @override
  String ocrDownloadFailed(String error) {
    return 'Tidak dapat mengunduh model OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Menambahkan lapisan teks yang dapat dipilih memerlukan model OCR di perangkat$size. Model diunduh sekali lalu berjalan luring.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Unduh model OCR?';

  @override
  String ocrFailed(String error) {
    return 'OCR gagal: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'OCR di perangkat tidak tersedia di platform ini';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR menambahkan $count rentang teks - teks halaman kini dapat dipilih',
      one: 'OCR menambahkan 1 rentang teks - teks halaman kini dapat dipilih',
      zero: 'OCR tidak menemukan teks pada halaman ini',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'OCR web mengunduh model bahasa-visual Florence-2 dan menjalankannya secara lokal dengan WebGPU/WASM melalui Transformers.js. Halaman PDF tetap di peramban ini; hanya berkas model yang diambil saat pertama kali digunakan.';

  @override
  String get ocrWebPromptTitle => 'Jalankan OCR AI di peramban ini?';

  @override
  String get ocrWebStart => 'Mulai OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Tempel';

  @override
  String get printDlgPreparing => 'Menyiapkan…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Merender halaman $rendered dari $total…';
  }

  @override
  String get printDlgTitle => 'Mencetak';

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
  String get settingsAbout => 'Tentang';

  @override
  String get settingsAppearance => 'Tampilan';

  @override
  String get settingsCheckNow => 'Periksa sekarang';

  @override
  String get settingsLanguage => 'Bahasa';

  @override
  String get settingsLanguageSystem => 'Bawaan sistem';

  @override
  String get settingsCheckingForUpdates => 'Memeriksa pembaruan…';

  @override
  String get settingsCouldNotOpenDownload => 'Tidak dapat membuka unduhan';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Tidak dapat membuka pengaturan sistem';

  @override
  String get settingsDeveloperTools => 'Alat pengembang';

  @override
  String get settingsDeveloperToolsSubtitle => 'Metrik, log, mode render (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Unduh $version';
  }

  @override
  String get settingsOpenSettings => 'Buka Pengaturan';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count diingat',
      one: '1 diingat',
      zero: 'Tidak ada berkas terkini',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Berkas terkini';

  @override
  String get settingsSetUpAsDefault => 'Siapkan sebagai aplikasi bawaan';

  @override
  String get settingsSystem => 'Sistem';

  @override
  String get settingsThemeDark => 'Gelap';

  @override
  String get settingsThemeLight => 'Terang';

  @override
  String get settingsThemeSystem => 'Sistem';

  @override
  String get settingsTitle => 'Pengaturan';

  @override
  String settingsUpToDate(String version) {
    return 'Anda menggunakan versi terbaru ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Versi $version tersedia (Anda memiliki $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Tidak dapat memeriksa pembaruan. Coba lagi nanti.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Anda memiliki $name $version.';
  }

  @override
  String get settingsUpdates => 'Pembaruan';

  @override
  String get settingsViewSource => 'Lihat sumber di GitHub';

  @override
  String get undo => 'Urungkan';

  @override
  String get welcomeOpenPdf => 'Buka PDF';

  @override
  String get welcomePickAgainToReopen => 'Pilih lagi untuk membuka kembali';

  @override
  String get welcomeRecent => 'Terkini';

  @override
  String get welcomeRemoveFromRecent => 'Hapus dari terkini';

  @override
  String get welcomeTapToReopen => 'Ketuk untuk membuka kembali';

  @override
  String get welcomeViewAsGrid => 'Tampilan kisi';

  @override
  String get welcomeViewAsList => 'Tampilan daftar';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Pasang aplikasi web, lalu pilih untuk berkas PDF.',
        'windows': 'Buka pengaturan aplikasi bawaan Windows untuk PDF.',
        'macos': 'Ikuti langkah “Always Open With” di Finder.',
        'linux': 'Gunakan pengaturan aplikasi bawaan desktop Anda.',
        'android': 'Pilih DartPDF saat membuka PDF, lalu ketuk Selalu.',
        'ios':
            'Gunakan Bagikan atau Buka Di dari Files untuk mengirim PDF ke sini.',
        'other': 'Konfigurasikan penangan berkas PDF sistem Anda.',
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
            'Pasang DartPDF dari peramban Anda terlebih dahulu. Kemudian gunakan pengaturan penangan berkas peramban atau sistem operasi untuk mengaitkan berkas PDF dengan aplikasi yang terpasang.',
        'windows':
            'Pengaturan Windows akan terbuka ke Aplikasi bawaan. Cari “.pdf” atau “PDF”, pilih aplikasi PDF saat ini, lalu pilih DartPDF.',
        'macos':
            'Di Finder, pilih PDF apa pun, pilih File > Get Info, perluas “Open with”, pilih DartPDF, lalu klik “Change All…”.',
        'linux':
            'Buka pengaturan desktop Anda untuk Aplikasi Bawaan, atau klik kanan PDF di Files, pilih Properties, dan atur DartPDF sebagai bawaan untuk dokumen PDF.',
        'android':
            'Buka PDF dari Files atau Downloads, pilih DartPDF di pemilih aplikasi, lalu pilih Selalu. Jika aplikasi lain sudah membuka PDF, hapus dulu bawaan aplikasi itu di Pengaturan Android.',
        'ios':
            'iOS tidak menyediakan editor PDF bawaan global. Gunakan Files > Bagikan, atau tekan lama PDF dan pilih Bagikan/Buka Di, lalu pilih DartPDF.',
        'other':
            'Gunakan pengaturan sistem untuk penangan berkas guna mengaitkan dokumen PDF dengan DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Mengunduh model OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Mengunduh model $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Menyelesaikan OCR…';

  @override
  String get fileTypePdf => 'Dokumen PDF';

  @override
  String get fileTypeImages => 'Gambar';

  @override
  String get fileTypeStampBundle => 'Stempel DartPDF';

  @override
  String get appSigKeyFileType => 'Kunci privat RSA';

  @override
  String get appSigCertificateFileType => 'Sertifikat X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Pilih setidaknya satu sertifikat X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Sertifikat $index bukan X.509 yang valid.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Kunci privat tidak cocok dengan sertifikat RSA yang dipilih mana pun.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Kunci privat terenkripsi tidak didukung. Pilih kunci RSA PKCS#1 atau PKCS#8 yang tidak terenkripsi.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Kunci privat bukan kunci RSA PKCS#1 atau PKCS#8 yang tidak terenkripsi.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Tidak ada sertifikat X.509 yang ditemukan.';
}
