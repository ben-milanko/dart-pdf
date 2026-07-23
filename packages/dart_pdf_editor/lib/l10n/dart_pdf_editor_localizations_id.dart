// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class DartPdfEditorLocalizationsId extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get add => 'Tambah';

  @override
  String get annotCaret => 'Sisipan';

  @override
  String get annotCircle => 'Lingkaran';

  @override
  String get annotFileAttachment => 'Lampiran berkas';

  @override
  String get annotFreeText => 'Kotak teks';

  @override
  String get annotHighlight => 'Sorotan';

  @override
  String get annotInk => 'Tinta';

  @override
  String get annotLine => 'Garis';

  @override
  String get annotLink => 'Tautan';

  @override
  String get annotPolygon => 'Poligon';

  @override
  String get annotPolyline => 'Garis banyak';

  @override
  String get annotRedact => 'Redaksi';

  @override
  String get annotSquare => 'Persegi';

  @override
  String get annotSquiggly => 'Bergelombang';

  @override
  String get annotStamp => 'Stempel';

  @override
  String get annotStrikeOut => 'Coret';

  @override
  String get annotText => 'Catatan';

  @override
  String get annotUnderline => 'Garis bawah';

  @override
  String get annotWidget => 'Bidang formulir';

  @override
  String get apply => 'Terapkan';

  @override
  String get bookmarkAdd => 'Tambah markah';

  @override
  String get bookmarkAddChild => 'Tambah markah anak';

  @override
  String get bookmarkCollapse => 'Ciutkan';

  @override
  String get bookmarkDelete => 'Hapus markah';

  @override
  String get bookmarkEdit => 'Edit markah';

  @override
  String get bookmarkEmpty => 'Tidak ada markah';

  @override
  String get bookmarkExpand => 'Perluas';

  @override
  String get bookmarkExpandedByDefault => 'Diperluas secara bawaan';

  @override
  String get bookmarkNoDestination => 'Tidak ada tujuan';

  @override
  String get bookmarkPageFieldLabel => 'Halaman';

  @override
  String bookmarkPageLabel(int number) {
    return 'Halaman $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Markah';

  @override
  String get bookmarkTitleLabel => 'Judul';

  @override
  String get bookmarkUntitled => 'Tanpa judul';

  @override
  String get cancel => 'Batal';

  @override
  String get clear => 'Bersihkan';

  @override
  String get close => 'Tutup';

  @override
  String get colorApplyingChanges => 'Menerapkan perubahan warna…';

  @override
  String get colorColorFormat => 'Format warna';

  @override
  String get colorColorTitle => 'Warna';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warna dipilih',
      one: '$count warna dipilih',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Warna dokumen';

  @override
  String get colorFillColors => 'Warna isian';

  @override
  String get colorFind => 'Cari';

  @override
  String get colorInDocument => 'Dalam dokumen';

  @override
  String get colorNoColorsFound => 'Belum ada warna yang ditemukan';

  @override
  String get colorNoPageContentColors =>
      'Tidak ada warna konten halaman yang ditemukan';

  @override
  String get colorPalette => 'Palet';

  @override
  String get colorPickColor => 'Pilih warna';

  @override
  String get colorProcessingTitle => 'Pemrosesan warna';

  @override
  String get colorRecent => 'Terkini';

  @override
  String get colorReplace => 'Ganti';

  @override
  String get colorReplaceWithTransparent => 'Ganti dengan transparan';

  @override
  String get colorScanning => 'Memindai…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Memindai $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Halaman terpilih ($count)';
  }

  @override
  String get colorStrokeColors => 'Warna garis';

  @override
  String get colorTolerance => 'Toleransi';

  @override
  String get colorTransparent => 'Transparan';

  @override
  String get colorWholeDocument => 'Seluruh dokumen';

  @override
  String get compareAfter => 'Sesudah';

  @override
  String get compareBefore => 'Sebelum';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count perubahan',
      one: '1 perubahan',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count perubahan',
      one: '1 perubahan',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(kosong)';

  @override
  String get compareNextChange => 'Perubahan berikutnya';

  @override
  String get compareNoChanges => 'Tidak ada perubahan';

  @override
  String get compareNoDifferences => 'Tidak ada perbedaan antara kedua dokumen';

  @override
  String get compareOverlay => 'Hamparan';

  @override
  String comparePageHeader(int page) {
    return 'Halaman $page';
  }

  @override
  String get comparePreviousChange => 'Perubahan sebelumnya';

  @override
  String get compareSideBySide => 'Berdampingan';

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
  String get editorViewAuthorNameTitle => 'Nama penulis';

  @override
  String get lineStyleDashDot => 'Garis-titik';

  @override
  String get lineStyleDashed => 'Putus-putus';

  @override
  String get lineStyleDotted => 'Titik-titik';

  @override
  String get lineStyleSolid => 'Padat';

  @override
  String get measCalibrate => 'Kalibrasi';

  @override
  String get measCalibrateScale => 'Kalibrasi skala';

  @override
  String get measDepthLabel => 'Kedalaman: ';

  @override
  String get measKindAngle => 'Sudut';

  @override
  String get measKindArc => 'Busur';

  @override
  String get measKindArea => 'Luas';

  @override
  String get measKindCount => 'Jumlah';

  @override
  String get measKindLength => 'Panjang';

  @override
  String get measKindNetArea => 'Luas bersih';

  @override
  String get measKindPerimeter => 'Keliling';

  @override
  String get measKindSlope => 'Kemiringan';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'Garis yang Anda gambar mewakili:';

  @override
  String get measMeasure => 'Ukur';

  @override
  String get measSetScale => 'Atur skala pengukuran';

  @override
  String get measSetScaleButton => 'Atur skala';

  @override
  String get measVolumeDepth => 'Kedalaman volume';

  @override
  String get menuAddNode => 'Tambah simpul';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Terapkan anotasi ke halaman',
      one: 'Terapkan anotasi ke halaman',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Terapkan ke halaman…';

  @override
  String get menuBringToFront => 'Bawa ke depan';

  @override
  String get menuCheck => 'Centang';

  @override
  String get menuChooseValue => 'Pilih nilai…';

  @override
  String get menuClearCheck => 'Hapus centang';

  @override
  String get menuConvertToCheckBox => 'Ubah menjadi kotak centang';

  @override
  String get menuConvertToImageButton => 'Ubah menjadi tombol gambar';

  @override
  String get menuConvertToTextField => 'Ubah menjadi bidang teks';

  @override
  String get menuDeleteField => 'Hapus bidang';

  @override
  String get menuEditValue => 'Edit nilai…';

  @override
  String get menuFieldName => 'Nama bidang';

  @override
  String get menuFieldValue => 'Nilai bidang';

  @override
  String get menuFlattenForm => 'Ratakan formulir';

  @override
  String get menuLock => 'Kunci';

  @override
  String get menuUnlock => 'Buka kunci';

  @override
  String get menuRecolour => 'Warnai ulang…';

  @override
  String get menuRemoveNode => 'Hapus simpul';

  @override
  String get menuSetAsDefaultStyle => 'Jadikan gaya bawaan';

  @override
  String get menuRename => 'Ganti nama…';

  @override
  String get menuSelectOption => 'Pilih opsi';

  @override
  String get menuSendToBack => 'Kirim ke belakang';

  @override
  String get menuSetImage => 'Atur gambar…';

  @override
  String get menuTextStyle => 'Gaya teks…';

  @override
  String get none => 'Tidak ada';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Warna';

  @override
  String get overlayEditText => 'Edit teks';

  @override
  String get overlayFont => 'Font';

  @override
  String get overlayLarger => 'Lebih besar';

  @override
  String get overlayMore => 'Lainnya';

  @override
  String get overlayNote => 'Catatan';

  @override
  String get overlaySmaller => 'Lebih kecil';

  @override
  String get overlayStampText => 'Teks stempel';

  @override
  String get linkDialogTitle => 'Tambahkan tautan';

  @override
  String get linkKindWeb => 'Alamat web';

  @override
  String get linkKindPage => 'Halaman dalam dokumen';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Nomor halaman';

  @override
  String get toolLink => 'Tautan';

  @override
  String get overlayUnderline => 'Garis bawah';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Masukkan halaman antara 1 dan $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Halaman terakhir tidak boleh sebelum halaman pertama.';

  @override
  String get pageRangeFrom => 'Dari';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count halaman',
      one: '1 halaman',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Sampai';

  @override
  String get panelDragToMovePanel => 'Seret untuk memindahkan panel';

  @override
  String get paste => 'Tempel';

  @override
  String get propAlign => 'Rata';

  @override
  String get propAlignCenter => 'Rata tengah';

  @override
  String get propAlignLeft => 'Rata kiri';

  @override
  String get propAlignRight => 'Rata kanan';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anotasi',
      one: '$count anotasi',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Penulis';

  @override
  String get propAutoSize => 'Ukuran otomatis';

  @override
  String get propBold => 'Tebal';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Font bawaan';

  @override
  String get propCallout => 'Keterangan';

  @override
  String get propCharSpacing => 'Spasi karakter';

  @override
  String get propColor => 'Warna';

  @override
  String get propColour => 'Warna';

  @override
  String get propContents => 'Isi';

  @override
  String get propEditsApplyToAll =>
      'Perubahan berlaku untuk semua anotasi yang kompatibel';

  @override
  String get propFieldName => 'Nama bidang';

  @override
  String get propFieldTypeCheckBox => 'Kotak centang';

  @override
  String get propFieldTypeComboBox => 'Kotak kombo';

  @override
  String get propFieldTypeImageButton => 'Tombol gambar';

  @override
  String get propFieldTypeListBox => 'Kotak daftar';

  @override
  String get propFieldTypeRadioGroup => 'Grup radio';

  @override
  String get propFieldTypeSignature => 'Tanda tangan';

  @override
  String get propFieldTypeText => 'Bidang teks';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Tipe bidang: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Bidang tak dikenal';

  @override
  String get propFill => 'Isian';

  @override
  String get propFont => 'Font';

  @override
  String get propFontSubsetTooltip =>
      'Font ini adalah subset - hanya karakter yang sudah digunakan dalam dokumen yang dapat diketik.';

  @override
  String get propFontWidth => 'Lebar font';

  @override
  String get propGeometryHeight => 'T';

  @override
  String get propGeometryWidth => 'L';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Miring';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Karakter terbatas';

  @override
  String get propLineEnd => 'Ujung garis';

  @override
  String get propLineEndingButt => 'Rata';

  @override
  String get propLineEndingCircle => 'Lingkaran';

  @override
  String get propLineEndingClosedArrow => 'Panah tertutup';

  @override
  String get propLineEndingClosedArrowRev => 'Panah tertutup (terbalik)';

  @override
  String get propLineEndingDiamond => 'Wajik';

  @override
  String get propLineEndingOpenArrow => 'Panah terbuka';

  @override
  String get propLineEndingOpenArrowRev => 'Panah terbuka (terbalik)';

  @override
  String get propLineEndingSlash => 'Garis miring';

  @override
  String get propLineEndingSquare => 'Persegi';

  @override
  String get propLineSpacing => 'Spasi baris';

  @override
  String get propLineStart => 'Awal garis';

  @override
  String get propLineType => 'Tipe garis';

  @override
  String get propLoadFont => 'Muat font…';

  @override
  String get propLoadFontSubtitle => 'Berkas TTF atau OTF';

  @override
  String get propMoreColors => 'Lebih banyak warna…';

  @override
  String get propMultiline => 'Banyak baris';

  @override
  String get propNoFill => 'Tanpa isian';

  @override
  String get propNoFontsFound => 'Tidak ada font yang ditemukan';

  @override
  String get propNoOutline => 'Tanpa garis luar';

  @override
  String get propOpacity => 'Opasitas';

  @override
  String get propOutline => 'Garis luar';

  @override
  String get propPageLabel => 'Halaman';

  @override
  String propPageNumber(int number) {
    return 'Halaman $number';
  }

  @override
  String get propPropertiesTitle => 'Properti';

  @override
  String get propRecentlyUsed => 'Baru digunakan';

  @override
  String get propScale => 'Skala';

  @override
  String get propSearchFonts => 'Cari font';

  @override
  String get propSectionAllFonts => 'Semua font';

  @override
  String get propSectionAppearance => 'Tampilan';

  @override
  String get propSectionContent => 'Konten';

  @override
  String get propSectionFormField => 'Bidang formulir';

  @override
  String get propSectionInThisDocument => 'Dalam dokumen ini';

  @override
  String get propSectionPositionSize => 'Posisi & ukuran (pt)';

  @override
  String get propSectionSelection => 'Pilihan';

  @override
  String get propSectionText => 'Teks';

  @override
  String get propSelectAnnotationPrompt =>
      'Pilih anotasi untuk melihat propertinya';

  @override
  String get propSize => 'Ukuran';

  @override
  String get propStandardPdfFont => 'Font PDF standar';

  @override
  String get propStroke => 'Garis';

  @override
  String get propStyle => 'Gaya';

  @override
  String get propSystemFont => 'Font sistem';

  @override
  String get propType => 'Tipe';

  @override
  String get propUnderline => 'Garis bawah';

  @override
  String get propVaries => 'Bervariasi';

  @override
  String get redo => 'Ulangi';

  @override
  String get reflowNoContent => 'Tidak ada konten yang dapat diekstrak';

  @override
  String reflowPageLabel(int number) {
    return 'Halaman $number';
  }

  @override
  String get reflowSaveOrShare => 'Simpan atau bagikan';

  @override
  String get reflowViewFigure => 'Lihat gambar';

  @override
  String get remove => 'Hapus';

  @override
  String get rename => 'Ganti nama';

  @override
  String get reset => 'Setel ulang';

  @override
  String get save => 'Simpan';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Halaman $page';
  }

  @override
  String get sbarCallout => 'Keterangan';

  @override
  String get sbarFieldButton => 'Bidang tombol';

  @override
  String get sbarFieldChoice => 'Bidang pilihan';

  @override
  String get sbarFieldGeneric => 'Bidang formulir';

  @override
  String get sbarFieldSignature => 'Bidang tanda tangan';

  @override
  String get sbarFieldText => 'Bidang teks';

  @override
  String get sbarStateAccepted => 'Diterima';

  @override
  String get sbarStateCancelled => 'Dibatalkan';

  @override
  String get sbarStateMarked => 'Ditandai';

  @override
  String get sbarStateRejected => 'Ditolak';

  @override
  String get sbarStateResolved => 'Diselesaikan';

  @override
  String get sbarStateUnmarked => 'Tak ditandai';

  @override
  String get searchAnnotations => 'Cari anotasi';

  @override
  String get searchClearSearch => 'Bersihkan pencarian';

  @override
  String get searchEmptyHint =>
      'Cari dokumen untuk menampilkan setiap kecocokan di sini';

  @override
  String get searchMatchCase => 'Cocokkan huruf besar/kecil';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kecocokan',
      one: '1 kecocokan',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Kecocokan berikutnya';

  @override
  String searchNoMatches(String query) {
    return 'Tidak ada kecocokan untuk “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Halaman $page';
  }

  @override
  String get searchPreviousMatch => 'Kecocokan sebelumnya';

  @override
  String get searchRegex => 'Ekspresi reguler';

  @override
  String get searchResultsTitle => 'Hasil pencarian';

  @override
  String get searchWholeWord => 'Seluruh kata';

  @override
  String get shellControls => 'Kontrol';

  @override
  String get shellDefaultAuthor => 'Penulis bawaan…';

  @override
  String get shellHighlightFormFields => 'Sorot bidang formulir';

  @override
  String get shellKeyboardShortcutsMenu => 'Pintasan papan ketik…';

  @override
  String get shellKeyboardShortcutsTitle => 'Pintasan papan ketik';

  @override
  String get shellShortcutsSearchHint => 'Cari pintasan';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Tidak ada pintasan yang cocok dengan “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Pilih';

  @override
  String get shellShortcutGroupMarkup => 'Markah';

  @override
  String get shellShortcutGroupDraw => 'Gambar';

  @override
  String get shellShortcutGroupShapes => 'Bentuk';

  @override
  String get shellShortcutGroupInsert => 'Sisipkan';

  @override
  String get shellShortcutGroupMeasure => 'Ukur';

  @override
  String get shellShortcutGroupEdit => 'Edit';

  @override
  String get shellNotSet => 'Tidak diatur';

  @override
  String get shellPageColor => 'Warna halaman…';

  @override
  String get shellPageGrid => 'Kisi halaman';

  @override
  String get shellPanelAnnotations => 'Anotasi';

  @override
  String get shellPanelBookmarks => 'Markah';

  @override
  String get shellPanelPages => 'Halaman';

  @override
  String get shellPanelProperties => 'Properti';

  @override
  String get shellPanelSearchResults => 'Hasil pencarian';

  @override
  String get shellPanels => 'Panel';

  @override
  String get shellPressAKey => 'Tekan sebuah tombol';

  @override
  String get shellPressLetterKeyHint =>
      'Tekan tombol huruf, atau Delete untuk menghapus.';

  @override
  String get shellReflow => 'Alir ulang';

  @override
  String get shellReflowText => 'Alir ulang teks';

  @override
  String get shellResetZoom => 'Setel ulang zoom';

  @override
  String get shellSectionShell => 'Cangkang';

  @override
  String get shellSectionView => 'Tampilan';

  @override
  String get shellSettings => 'Pengaturan';

  @override
  String get shellShowAnnotations => 'Tampilkan anotasi';

  @override
  String get shellTabHere => 'Tab di sini';

  @override
  String get shellUnbound => 'Tak terikat';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'oleh $author';
  }

  @override
  String get sidebarCancelSelection => 'Batalkan pilihan';

  @override
  String get sidebarClearSearch => 'Bersihkan pencarian';

  @override
  String get sidebarDeleteSelected => 'Hapus yang dipilih';

  @override
  String get sidebarDeleteSignature => 'Hapus tanda tangan';

  @override
  String get sidebarLockAnnotation => 'Kunci';

  @override
  String get sidebarUnlockAnnotation => 'Buka kunci';

  @override
  String get sidebarMore => 'Lainnya';

  @override
  String get sidebarNoAnnotations => 'Tidak ada anotasi';

  @override
  String get sidebarNoMatchingAnnotations => 'Tidak ada anotasi yang cocok';

  @override
  String sidebarPageHeader(int number) {
    return 'Halaman $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Ini menghapus tanda tangan digital dari dokumen. Anda dapat mengurungkan tindakan ini.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Ini menghapus tanda tangan digital oleh \"$name\" dari dokumen. Anda dapat mengurungkan tindakan ini.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Hapus tanda tangan?';

  @override
  String get sidebarReopen => 'Buka kembali';

  @override
  String get sidebarReply => 'Balas';

  @override
  String get sidebarResolve => 'Selesaikan';

  @override
  String get sidebarSearchHint => 'Cari anotasi';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dipilih',
      one: '$count dipilih',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Tulis balasan…';

  @override
  String get sigTitle => 'Tanda tangan';

  @override
  String get signIdCreate => 'Buat';

  @override
  String get signIdEmail => 'Email (opsional)';

  @override
  String get signIdName => 'Nama';

  @override
  String get signIdNameHint =>
      'Nama Anda, seperti yang akan muncul pada tanda tangan';

  @override
  String get signIdNameRequired => 'Masukkan nama';

  @override
  String get signIdOrganization => 'Organisasi (opsional)';

  @override
  String get signIdSelfSignedInfo =>
      'Ini membuat identitas yang ditandatangani sendiri. Tanda tangan akan terbaca sebagai \"ditandatangani, validitas tidak diketahui\" di Adobe Acrobat dan pembaca lainnya - sama seperti ID yang mereka tandatangani sendiri. Tanda centang hijau memerlukan CA berbayar yang tepercaya secara publik.';

  @override
  String get signIdTitle => 'Buat identitas penanda tangan';

  @override
  String get stampBox => 'Kotak';

  @override
  String get stampCircle => 'Lingkaran';

  @override
  String get stampCustomCaption => 'Stempel kustom';

  @override
  String get stampDateFormat => 'Format tanggal';

  @override
  String get stampDeleteComponent => 'Hapus komponen terpilih';

  @override
  String get stampDeleteStamp => 'Hapus stempel';

  @override
  String get stampEditStamp => 'Edit stempel';

  @override
  String get stampExport => 'Ekspor…';

  @override
  String get stampFieldDate => 'Tanggal';

  @override
  String get stampFieldDateTime => 'Tanggal & waktu';

  @override
  String get stampFieldTime => 'Waktu';

  @override
  String get stampFieldUsername => 'Nama pengguna';

  @override
  String get stampFont => 'Font';

  @override
  String get stampFontBold => 'Tebal';

  @override
  String get stampFontItalic => 'Miring';

  @override
  String get stampHeight => 'Tinggi';

  @override
  String get stampImage => 'Gambar';

  @override
  String get stampImport => 'Impor…';

  @override
  String get stampInsertField => 'Sisipkan bidang';

  @override
  String get stampMoreColors => 'Lebih banyak warna…';

  @override
  String get stampNewStamp => 'Stempel baru…';

  @override
  String get stampNewStampTitle => 'Stempel baru';

  @override
  String get stampSelectTextToEdit => 'Pilih teks untuk diedit';

  @override
  String get stampSelectedText => 'Teks terpilih';

  @override
  String get stampSignature => 'Tanda tangan';

  @override
  String get stampStamps => 'Stempel';

  @override
  String get stampText => 'Teks';

  @override
  String get stampTime12Hour => '12 jam';

  @override
  String get stampTime24Hour => '24 jam';

  @override
  String get stampTimeFormat => 'Format waktu';

  @override
  String get stampWidth => 'Lebar';

  @override
  String get takeoffArea => 'Luas';

  @override
  String get takeoffCount => 'Jumlah';

  @override
  String get takeoffEmpty => 'Belum ada pengukuran.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grup',
      one: '$count grup',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count item',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Panjang';

  @override
  String get takeoffTitle => 'Takeoff';

  @override
  String get tbAddInkAnnotation => 'Tambah anotasi tinta';

  @override
  String get tbAlign => 'Rata';

  @override
  String get tbAlignBottom => 'Rata bawah';

  @override
  String get tbAlignHorizontalCenters => 'Ratakan pusat horizontal';

  @override
  String get tbAlignLeft => 'Rata kiri';

  @override
  String get tbAlignRight => 'Rata kanan';

  @override
  String get tbAlignTop => 'Rata atas';

  @override
  String get tbAlignVerticalCenters => 'Ratakan pusat vertikal';

  @override
  String get tbAnnotationsFlattened => 'Anotasi diratakan ke dalam halaman';

  @override
  String get tbApplyRedactionsMessage =>
      'Konten yang ditandai akan dihapus secara permanen dari dokumen. Ini tidak dapat diurungkan.';

  @override
  String get tbApplyRedactionsTitle => 'Terapkan redaksi?';

  @override
  String get tbApplyRedactionsTooltip =>
      'Terapkan redaksi (tidak dapat dibatalkan)';

  @override
  String get tbAutosizeTextBox => 'Ukuran otomatis kotak teks (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Gambar garis dengan panjang yang diketahui untuk mengkalibrasi skala.';

  @override
  String get tbCharSpacing => 'Spasi karakter';

  @override
  String get tbCheckBoxOption => 'Kotak centang';

  @override
  String get tbCheckMarksOnDocument => 'Tanda centang pada dokumen';

  @override
  String get tbColorLabel => 'Warna';

  @override
  String get tbColorProcessingTooltip =>
      'Pemrosesan warna - cari dan ganti warna konten halaman';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mengganti $count warna',
      one: 'Mengganti 1 warna',
      zero: 'Tidak ada warna cocok yang ditemukan',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Ubah menjadi kotak centang';

  @override
  String get tbConvertToImageButton => 'Ubah menjadi tombol gambar';

  @override
  String get tbConvertToTextField => 'Ubah menjadi bidang teks';

  @override
  String get tbCornerRadius => 'Radius sudut';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hapus $count anotasi',
      one: 'Hapus anotasi',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Hapus elemen';

  @override
  String get tbDeleteField => 'Hapus bidang';

  @override
  String get tbDiscardDrawing => 'Buang gambar';

  @override
  String get tbDistributeHorizontally => 'Distribusikan horizontal';

  @override
  String get tbDistributeVertically => 'Distribusikan vertikal';

  @override
  String get tbDrawNewSignature => 'Gambar tanda tangan baru…';

  @override
  String get tbEditAnnotationText => 'Edit teks anotasi';

  @override
  String get tbEditTextStyle => 'Edit teks & gaya';

  @override
  String get tbElement => 'Elemen';

  @override
  String get tbEraserSize => 'Ukuran penghapus';

  @override
  String get tbFieldActions => 'Tindakan bidang';

  @override
  String get tbFieldName => 'Nama bidang';

  @override
  String tbFieldNamed(String name) {
    return 'Bidang: $name';
  }

  @override
  String get tbFieldValue => 'Nilai bidang';

  @override
  String get tbFill => 'Isian';

  @override
  String get tbFingerDraws =>
      'Jari menggambar - ketuk agar menggulir sebagai gantinya';

  @override
  String get tbFingerScrolls =>
      'Jari menggulir (pena menggambar) - ketuk agar menggambar';

  @override
  String get tbFlattenAnnotationsTooltip => 'Ratakan anotasi ke dalam halaman';

  @override
  String get tbFlattenForm => 'Ratakan formulir';

  @override
  String get tbFlattenFormBakeValues =>
      'Ratakan formulir - satukan nilai ke dalam halaman';

  @override
  String get tbFlattenLabel => 'Ratakan';

  @override
  String get tbFont => 'Font';

  @override
  String get tbFontSize => 'Ukuran font';

  @override
  String get tbFontWidth => 'Lebar font';

  @override
  String get tbFormFieldsFlattened =>
      'Bidang formulir diratakan ke dalam halaman';

  @override
  String get tbGroupDraw => 'Gambar';

  @override
  String get tbGroupEdit => 'Edit';

  @override
  String get tbGroupInsert => 'Sisipkan';

  @override
  String get tbGroupMarkup => 'Markah';

  @override
  String get tbGroupMeasure => 'Ukur';

  @override
  String get tbGroupSelect => 'Pilih';

  @override
  String get tbGroupShapes => 'Bentuk';

  @override
  String get tbImageButtonOption => 'Tombol gambar';

  @override
  String get tbLineEnd => 'Ujung garis';

  @override
  String get tbLineSpacing => 'Spasi baris';

  @override
  String get tbLineStart => 'Awal garis';

  @override
  String get tbLineType => 'Tipe garis';

  @override
  String get tbManageStamps => 'Kelola stempel…';

  @override
  String get tbMarkupHighlight => 'Sorot';

  @override
  String get tbMarkupHighlightTip => 'Sorot pilihan';

  @override
  String get tbMarkupSquiggly => 'Garis bawah bergelombang';

  @override
  String get tbMarkupSquigglyTip => 'Garis bawah bergelombang pada pilihan';

  @override
  String get tbMarkupStrikeOut => 'Coret';

  @override
  String get tbMarkupStrikeOutTip => 'Coret pilihan';

  @override
  String get tbMarkupUnderline => 'Garis bawah';

  @override
  String get tbMarkupUnderlineTip => 'Garis bawah pilihan';

  @override
  String get tbMoreColors => 'Lebih banyak warna…';

  @override
  String get tbNameArrow => 'Panah';

  @override
  String get tbNameCallout => 'Keterangan';

  @override
  String get tbNameCloudPolygon => 'Poligon awan';

  @override
  String get tbNameCount => 'Jumlah';

  @override
  String get tbNameDigitalSignature => 'Tanda tangan digital';

  @override
  String get tbNameDraw => 'Gambar';

  @override
  String get tbNameEllipse => 'Elips';

  @override
  String get tbNameEraser => 'Hapus goresan tinta';

  @override
  String get tbNameHighlight => 'Sorot';

  @override
  String get tbNameImage => 'Gambar';

  @override
  String get tbNameLine => 'Garis';

  @override
  String get tbNameMeasureAngle => 'Ukur sudut';

  @override
  String get tbNameMeasureArc => 'Ukur panjang busur';

  @override
  String get tbNameMeasureArea => 'Ukur luas';

  @override
  String get tbNameMeasureDistance => 'Ukur jarak';

  @override
  String get tbNameMeasurePerimeter => 'Ukur keliling';

  @override
  String get tbNameMeasureSlope => 'Ukur kemiringan (naik/mendatar)';

  @override
  String get tbNameMeasureVolume => 'Ukur volume (luas × kedalaman)';

  @override
  String get tbNameNote => 'Catatan';

  @override
  String get tbNamePolygon => 'Poligon';

  @override
  String get tbNamePolyline => 'Garis banyak';

  @override
  String get tbNameRectangle => 'Persegi panjang';

  @override
  String get tbNameSelect => 'Pilih';

  @override
  String get tbNameSignature => 'Tanda tangan';

  @override
  String get tbNameStamp => 'Stempel';

  @override
  String get tbNameTextBox => 'Kotak teks';

  @override
  String get tbNewFieldType =>
      'Tipe bidang baru - seret pada halaman untuk menambahkannya';

  @override
  String get tbNoAnnotationsToFlatten => 'Tidak ada anotasi untuk diratakan';

  @override
  String get tbNoCustomStamps => 'Tidak ada stempel kustom';

  @override
  String get tbNoFormFieldsToFlatten =>
      'Tidak ada bidang formulir untuk diratakan';

  @override
  String get tbNoRedactionsToApply => 'Tidak ada redaksi untuk diterapkan';

  @override
  String get tbNoteTitle => 'Catatan';

  @override
  String get tbOpacity => 'Opasitas';

  @override
  String get tbOutline => 'Garis luar';

  @override
  String get tbPatternScale => 'Skala pola';

  @override
  String get tbPickColorFromPage => 'Pilih warna dari halaman';

  @override
  String get tbRedactionsApplied => 'Redaksi diterapkan';

  @override
  String get tbRedoShortcut => 'Ulangi (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Tidak dapat mengalirkan ulang - ini bukan paragraf satu kolom yang dapat dibungkus ulang alat ini. Coba Ganti teks sebagai gantinya.';

  @override
  String get tbReflowParagraph => 'Alir ulang paragraf';

  @override
  String get tbRenameField => 'Ganti nama bidang';

  @override
  String get tbRenameFieldEllipsis => 'Ganti nama bidang…';

  @override
  String get tbReplaceImage => 'Ganti gambar';

  @override
  String get tbReplaceImageFailed => 'Tidak dapat mengganti gambar';

  @override
  String get tbReplaceText => 'Ganti teks';

  @override
  String get tbSaveImage => 'Simpan gambar';

  @override
  String get tbSaveShortcut => 'Simpan… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Skala';

  @override
  String get tbSelectTextForMarkup => 'Pilih teks untuk menggunakan markah';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dipilih',
      one: 'Pilihan',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Atur…';

  @override
  String get tbStamp => 'Stempel';

  @override
  String get tbStampText => 'Teks stempel';

  @override
  String get tbStrokeOpacityFont => 'Garis, opasitas, font';

  @override
  String get tbStrokeWidthLabel => 'Lebar garis';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Garis $width';
  }

  @override
  String get tbStyle => 'Gaya';

  @override
  String get tbTakeoffTotals => 'Total takeoff';

  @override
  String get tbTextBorder => 'Batas teks';

  @override
  String get tbTextColour => 'Warna teks';

  @override
  String get tbTextFieldOption => 'Bidang teks';

  @override
  String get tbTextFill => 'Isian teks';

  @override
  String get tbTextStyleEllipsis => 'Gaya teks…';

  @override
  String get tbTextTitle => 'Teks';

  @override
  String get tbTipCallout =>
      'Keterangan - seret dari titik ke tempat kotak berada';

  @override
  String get tbTipContent => 'Edit konten halaman';

  @override
  String get tbTipCount =>
      'Jumlah - ketuk untuk menaruh tanda centang dan menghitungnya';

  @override
  String get tbTipDigitalSignature =>
      'Tanda tangan digital - seret kotak untuk menempatkan dan menandatangani';

  @override
  String get tbTipForm =>
      'Bidang formulir - ketuk untuk memilih, ketuk dua kali untuk mengisi, seret untuk menambah';

  @override
  String get tbTipHighlightDraw => 'Sorot - gambar bebas';

  @override
  String get tbTipImage =>
      'Gambar - ketuk untuk menempatkan, atau seret membentuk kotak';

  @override
  String get tbTipMeasureAngle => 'Ukur sudut - klik tiga titik';

  @override
  String get tbTipMeasureArc => 'Ukur panjang busur - klik tiga titik';

  @override
  String get tbTipRedact => 'Redaksi - seret sebuah area, lalu terapkan';

  @override
  String get tbTipSignature =>
      'Tanda tangan - ketuk halaman untuk menempatkannya';

  @override
  String get tbTipSnapshot =>
      'Cuplikan - seret sebuah area untuk menangkapnya (tempel kembali sebagai vektor)';

  @override
  String get tbToolContent => 'Konten';

  @override
  String get tbToolForm => 'Formulir';

  @override
  String get tbToolRedact => 'Redaksi';

  @override
  String get tbToolSnapshot => 'Cuplikan';

  @override
  String get tbTools => 'Alat';

  @override
  String get tbTotals => 'Total';

  @override
  String get tbTypeTextEachTime => 'Ketik teks setiap kali';

  @override
  String get tbUnderline => 'Garis bawah';

  @override
  String get tbUndoShortcut => 'Urungkan (⌘Z)';

  @override
  String get textStyleFont => 'Font';

  @override
  String get textStyleFontSize => 'Ukuran font';

  @override
  String get textStyleKeep => 'pertahankan';

  @override
  String get textStyleStyle => 'Gaya';

  @override
  String get textStyleText => 'Teks';

  @override
  String get textStyleTextFill => 'Isian teks';

  @override
  String get textStyleTitle => 'Edit teks & gaya';

  @override
  String get thumbAddPage => 'Tambah halaman';

  @override
  String get thumbClearSelection => 'Bersihkan pilihan';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Salin $count halaman',
      one: 'Salin halaman',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Salin halaman terpilih';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Potong $count halaman',
      one: 'Potong halaman',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Potong halaman terpilih';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hapus $count halaman',
      one: 'Hapus halaman',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Hapus halaman terpilih';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gandakan $count halaman',
      one: 'Gandakan halaman',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Ekspor halaman…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ekspor $count halaman…',
      one: 'Ekspor halaman…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Ekspor halaman terpilih';

  @override
  String get thumbInsertBlankAfter => 'Sisipkan halaman kosong setelahnya';

  @override
  String get thumbInsertBlankBefore => 'Sisipkan halaman kosong sebelumnya';

  @override
  String get thumbInsertFileFailed => 'Tidak dapat menyisipkan berkas itu.';

  @override
  String get thumbInsertPdf => 'Sisipkan PDF…';

  @override
  String get thumbPageActions => 'Tindakan halaman';

  @override
  String thumbPageNumber(int number) {
    return 'Halaman $number';
  }

  @override
  String get thumbPages => 'Halaman';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tempel $count halaman',
      one: 'Tempel halaman',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Putar 180°';

  @override
  String get thumbRotateLeft => 'Putar ke kiri';

  @override
  String get thumbRotatePageRight => 'Putar halaman ke kanan';

  @override
  String get thumbRotateRight => 'Putar ke kanan';

  @override
  String get thumbRotateSelectedLeft => 'Putar halaman terpilih ke kiri';

  @override
  String get thumbRotateSelectedRight => 'Putar halaman terpilih ke kanan';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dipilih',
      one: '$count dipilih',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Urungkan';

  @override
  String get viewerEditFontUnsafe =>
      'Font atau enkode PDF ini tidak dapat diedit dengan aman.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Pengeditan memerlukan pilihan pada satu halaman.';

  @override
  String get viewerEditNotEditableRun =>
      'Pilihan ini bukan satu deret teks konten halaman yang dapat diedit.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Font PDF ini dapat diketik ulang, tetapi gayanya tidak dapat diubah.';

  @override
  String get viewerEditTextStyle => 'Edit teks & gaya';

  @override
  String get viewerMarkup => 'Markah';

  @override
  String get viewerMarkupHighlight => 'Sorot';

  @override
  String get viewerMarkupSquiggly => 'Bergelombang';

  @override
  String get viewerMarkupStrikeOut => 'Coret';

  @override
  String get viewerMarkupUnderline => 'Garis bawah';

  @override
  String get viewerSelectAll => 'Pilih semua';
}
