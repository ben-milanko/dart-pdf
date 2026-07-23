// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class DartPdfEditorLocalizationsTr extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get add => 'Ekle';

  @override
  String get annotCaret => 'Şapka işareti';

  @override
  String get annotCircle => 'Daire';

  @override
  String get annotFileAttachment => 'Dosya eki';

  @override
  String get annotFreeText => 'Metin kutusu';

  @override
  String get annotHighlight => 'Vurgu';

  @override
  String get annotInk => 'Kalem';

  @override
  String get annotLine => 'Çizgi';

  @override
  String get annotLink => 'Bağlantı';

  @override
  String get annotPolygon => 'Çokgen';

  @override
  String get annotPolyline => 'Çoklu çizgi';

  @override
  String get annotRedact => 'Karartma';

  @override
  String get annotSquare => 'Kare';

  @override
  String get annotSquiggly => 'Dalgalı';

  @override
  String get annotStamp => 'Damga';

  @override
  String get annotStrikeOut => 'Üstü çizili';

  @override
  String get annotText => 'Not';

  @override
  String get annotUnderline => 'Altı çizili';

  @override
  String get annotWidget => 'Form alanı';

  @override
  String get apply => 'Uygula';

  @override
  String get bookmarkAdd => 'Yer imi ekle';

  @override
  String get bookmarkAddChild => 'Alt yer imi ekle';

  @override
  String get bookmarkCollapse => 'Daralt';

  @override
  String get bookmarkDelete => 'Yer imini sil';

  @override
  String get bookmarkEdit => 'Yer imini düzenle';

  @override
  String get bookmarkEmpty => 'Yer imi yok';

  @override
  String get bookmarkExpand => 'Genişlet';

  @override
  String get bookmarkExpandedByDefault => 'Varsayılan olarak genişletilmiş';

  @override
  String get bookmarkNoDestination => 'Hedef yok';

  @override
  String get bookmarkPageFieldLabel => 'Sayfa';

  @override
  String bookmarkPageLabel(int number) {
    return 'Sayfa $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Yer imleri';

  @override
  String get bookmarkTitleLabel => 'Başlık';

  @override
  String get bookmarkUntitled => 'Başlıksız';

  @override
  String get cancel => 'İptal';

  @override
  String get clear => 'Temizle';

  @override
  String get close => 'Kapat';

  @override
  String get colorApplyingChanges => 'Renk değişiklikleri uygulanıyor…';

  @override
  String get colorColorFormat => 'Renk biçimi';

  @override
  String get colorColorTitle => 'Renk';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count renk seçildi',
      one: '$count renk seçildi',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Belge renkleri';

  @override
  String get colorFillColors => 'Dolgu renkleri';

  @override
  String get colorFind => 'Bul';

  @override
  String get colorInDocument => 'Belgede';

  @override
  String get colorNoColorsFound => 'Henüz renk bulunamadı';

  @override
  String get colorNoPageContentColors => 'Sayfa içeriği rengi bulunamadı';

  @override
  String get colorPalette => 'Palet';

  @override
  String get colorPickColor => 'Renk seç';

  @override
  String get colorProcessingTitle => 'Renk işleme';

  @override
  String get colorRecent => 'Son kullanılanlar';

  @override
  String get colorReplace => 'Değiştir';

  @override
  String get colorReplaceWithTransparent => 'Saydamla değiştir';

  @override
  String get colorScanning => 'Taranıyor…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Taranıyor $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Seçili sayfalar ($count)';
  }

  @override
  String get colorStrokeColors => 'Çizgi renkleri';

  @override
  String get colorTolerance => 'Tolerans';

  @override
  String get colorTransparent => 'Saydam';

  @override
  String get colorWholeDocument => 'Tüm belge';

  @override
  String get compareAfter => 'Sonra';

  @override
  String get compareBefore => 'Önce';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count değişiklik',
      one: '1 değişiklik',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count değişiklik',
      one: '1 değişiklik',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(boş)';

  @override
  String get compareNextChange => 'Sonraki değişiklik';

  @override
  String get compareNoChanges => 'Değişiklik yok';

  @override
  String get compareNoDifferences => 'İki belge arasında fark yok';

  @override
  String get compareOverlay => 'Bindirme';

  @override
  String comparePageHeader(int page) {
    return 'Sayfa $page';
  }

  @override
  String get comparePreviousChange => 'Önceki değişiklik';

  @override
  String get compareSideBySide => 'Yan yana';

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
  String get editorViewAuthorNameTitle => 'Yazar adı';

  @override
  String get lineStyleDashDot => 'Çizgi-nokta';

  @override
  String get lineStyleDashed => 'Kesikli';

  @override
  String get lineStyleDotted => 'Noktalı';

  @override
  String get lineStyleSolid => 'Düz';

  @override
  String get measCalibrate => 'Kalibre et';

  @override
  String get measCalibrateScale => 'Ölçeği kalibre et';

  @override
  String get measDepthLabel => 'Derinlik: ';

  @override
  String get measKindAngle => 'Açı';

  @override
  String get measKindArc => 'Yay';

  @override
  String get measKindArea => 'Alan';

  @override
  String get measKindCount => 'Sayım';

  @override
  String get measKindLength => 'Uzunluk';

  @override
  String get measKindNetArea => 'Net alan';

  @override
  String get measKindPerimeter => 'Çevre';

  @override
  String get measKindSlope => 'Eğim';

  @override
  String get measKindVolume => 'Hacim';

  @override
  String get measLineRepresents => 'Çizdiğiniz çizgi şunu temsil ediyor:';

  @override
  String get measMeasure => 'Ölç';

  @override
  String get measSetScale => 'Ölçüm ölçeğini ayarla';

  @override
  String get measSetScaleButton => 'Ölçeği ayarla';

  @override
  String get measVolumeDepth => 'Hacim derinliği';

  @override
  String get menuAddNode => 'Düğüm ekle';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ek açıklamaları sayfalara uygula',
      one: 'Ek açıklamayı sayfalara uygula',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Sayfalara uygula…';

  @override
  String get menuBringToFront => 'Öne getir';

  @override
  String get menuCheck => 'İşaretle';

  @override
  String get menuChooseValue => 'Değer seç…';

  @override
  String get menuClearCheck => 'İşareti kaldır';

  @override
  String get menuConvertToCheckBox => 'Onay kutusuna dönüştür';

  @override
  String get menuConvertToImageButton => 'Görsel düğmesine dönüştür';

  @override
  String get menuConvertToTextField => 'Metin alanına dönüştür';

  @override
  String get menuDeleteField => 'Alanı sil';

  @override
  String get menuEditValue => 'Değeri düzenle…';

  @override
  String get menuFieldName => 'Alan adı';

  @override
  String get menuFieldValue => 'Alan değeri';

  @override
  String get menuFlattenForm => 'Formu düzleştir';

  @override
  String get menuRecolour => 'Yeniden renklendir…';

  @override
  String get menuRemoveNode => 'Düğümü kaldır';

  @override
  String get menuSetAsDefaultStyle => 'Varsayılan stil olarak ayarla';

  @override
  String get menuRename => 'Yeniden adlandır…';

  @override
  String get menuSelectOption => 'Seçeneği seç';

  @override
  String get menuSendToBack => 'Arkaya gönder';

  @override
  String get menuSetImage => 'Görsel ayarla…';

  @override
  String get menuTextStyle => 'Metin stili…';

  @override
  String get none => 'Yok';

  @override
  String get ok => 'Tamam';

  @override
  String get overlayColor => 'Renk';

  @override
  String get overlayEditText => 'Metni düzenle';

  @override
  String get overlayFont => 'Yazı tipi';

  @override
  String get overlayLarger => 'Daha büyük';

  @override
  String get overlayMore => 'Daha fazla';

  @override
  String get overlayNote => 'Not';

  @override
  String get overlaySmaller => 'Daha küçük';

  @override
  String get overlayStampText => 'Damga metni';

  @override
  String get linkDialogTitle => 'Bağlantı ekle';

  @override
  String get linkKindWeb => 'Web adresi';

  @override
  String get linkKindPage => 'Belgedeki sayfa';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Sayfa numarası';

  @override
  String get toolLink => 'Bağlantı';

  @override
  String get overlayUnderline => 'Altı çizili';

  @override
  String pageRangeErrorBounds(int count) {
    return '1 ile $count arasında sayfalar girin.';
  }

  @override
  String get pageRangeErrorOrder => 'Son sayfa ilk sayfadan önce olamaz.';

  @override
  String get pageRangeFrom => 'Başlangıç';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfa',
      one: '1 sayfa',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Bitiş';

  @override
  String get panelDragToMovePanel => 'Paneli taşımak için sürükleyin';

  @override
  String get paste => 'Yapıştır';

  @override
  String get propAlign => 'Hizala';

  @override
  String get propAlignCenter => 'Ortala';

  @override
  String get propAlignLeft => 'Sola hizala';

  @override
  String get propAlignRight => 'Sağa hizala';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ek açıklama',
      one: '$count ek açıklama',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Yazar';

  @override
  String get propAutoSize => 'Otomatik boyut';

  @override
  String get propBold => 'Kalın';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Paketlenmiş yazı tipi';

  @override
  String get propCallout => 'Belirtme çizgisi';

  @override
  String get propCharSpacing => 'Karakter aralığı';

  @override
  String get propColor => 'Renk';

  @override
  String get propColour => 'Renk';

  @override
  String get propContents => 'İçerik';

  @override
  String get propEditsApplyToAll =>
      'Düzenlemeler tüm uyumlu ek açıklamalara uygulanır';

  @override
  String get propFieldName => 'Alan adı';

  @override
  String get propFieldTypeCheckBox => 'Onay kutusu';

  @override
  String get propFieldTypeComboBox => 'Açılır kutu';

  @override
  String get propFieldTypeImageButton => 'Görsel düğmesi';

  @override
  String get propFieldTypeListBox => 'Liste kutusu';

  @override
  String get propFieldTypeRadioGroup => 'Radyo grubu';

  @override
  String get propFieldTypeSignature => 'İmza';

  @override
  String get propFieldTypeText => 'Metin alanı';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Alan türü: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Bilinmeyen alan';

  @override
  String get propFill => 'Dolgu';

  @override
  String get propFont => 'Yazı tipi';

  @override
  String get propFontSubsetTooltip =>
      'Bu yazı tipi alt kümedir - yalnızca belgede zaten kullanılan karakterler yazılabilir.';

  @override
  String get propFontWidth => 'Yazı tipi genişliği';

  @override
  String get propGeometryHeight => 'Y';

  @override
  String get propGeometryWidth => 'G';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'İtalik';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Sınırlı karakterler';

  @override
  String get propLineEnd => 'Çizgi sonu';

  @override
  String get propLineEndingButt => 'Düz uç';

  @override
  String get propLineEndingCircle => 'Daire';

  @override
  String get propLineEndingClosedArrow => 'Kapalı ok';

  @override
  String get propLineEndingClosedArrowRev => 'Kapalı ok (ters)';

  @override
  String get propLineEndingDiamond => 'Elmas';

  @override
  String get propLineEndingOpenArrow => 'Açık ok';

  @override
  String get propLineEndingOpenArrowRev => 'Açık ok (ters)';

  @override
  String get propLineEndingSlash => 'Eğik çizgi';

  @override
  String get propLineEndingSquare => 'Kare';

  @override
  String get propLineSpacing => 'Satır aralığı';

  @override
  String get propLineStart => 'Çizgi başı';

  @override
  String get propLineType => 'Çizgi türü';

  @override
  String get propLoadFont => 'Yazı tipi yükle…';

  @override
  String get propLoadFontSubtitle => 'TTF veya OTF dosyası';

  @override
  String get propMoreColors => 'Daha fazla renk…';

  @override
  String get propMultiline => 'Çok satırlı';

  @override
  String get propNoFill => 'Dolgu yok';

  @override
  String get propNoFontsFound => 'Yazı tipi bulunamadı';

  @override
  String get propNoOutline => 'Ana hat yok';

  @override
  String get propOpacity => 'Opaklık';

  @override
  String get propOutline => 'Ana hat';

  @override
  String get propPageLabel => 'Sayfa';

  @override
  String propPageNumber(int number) {
    return 'Sayfa $number';
  }

  @override
  String get propPropertiesTitle => 'Özellikler';

  @override
  String get propRecentlyUsed => 'Son kullanılanlar';

  @override
  String get propScale => 'Ölçek';

  @override
  String get propSearchFonts => 'Yazı tiplerini ara';

  @override
  String get propSectionAllFonts => 'Tüm yazı tipleri';

  @override
  String get propSectionAppearance => 'Görünüm';

  @override
  String get propSectionContent => 'İçerik';

  @override
  String get propSectionFormField => 'Form alanı';

  @override
  String get propSectionInThisDocument => 'Bu belgede';

  @override
  String get propSectionPositionSize => 'Konum ve boyut (pt)';

  @override
  String get propSectionSelection => 'Seçim';

  @override
  String get propSectionText => 'Metin';

  @override
  String get propSelectAnnotationPrompt =>
      'Özelliklerini görmek için bir ek açıklama seçin';

  @override
  String get propSize => 'Boyut';

  @override
  String get propStandardPdfFont => 'Standart PDF yazı tipi';

  @override
  String get propStroke => 'Çizgi';

  @override
  String get propStyle => 'Stil';

  @override
  String get propSystemFont => 'Sistem yazı tipi';

  @override
  String get propType => 'Tür';

  @override
  String get propUnderline => 'Altı çizili';

  @override
  String get propVaries => 'Değişken';

  @override
  String get redo => 'Yinele';

  @override
  String get reflowNoContent => 'Çıkarılabilir içerik yok';

  @override
  String reflowPageLabel(int number) {
    return 'Sayfa $number';
  }

  @override
  String get reflowSaveOrShare => 'Kaydet veya paylaş';

  @override
  String get reflowViewFigure => 'Şekli görüntüle';

  @override
  String get remove => 'Kaldır';

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String get reset => 'Sıfırla';

  @override
  String get save => 'Kaydet';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Sayfa $page';
  }

  @override
  String get sbarCallout => 'Belirtme çizgisi';

  @override
  String get sbarFieldButton => 'Düğme alanı';

  @override
  String get sbarFieldChoice => 'Seçim alanı';

  @override
  String get sbarFieldGeneric => 'Form alanı';

  @override
  String get sbarFieldSignature => 'İmza alanı';

  @override
  String get sbarFieldText => 'Metin alanı';

  @override
  String get sbarStateAccepted => 'Kabul edildi';

  @override
  String get sbarStateCancelled => 'İptal edildi';

  @override
  String get sbarStateMarked => 'İşaretlendi';

  @override
  String get sbarStateRejected => 'Reddedildi';

  @override
  String get sbarStateResolved => 'Çözüldü';

  @override
  String get sbarStateUnmarked => 'İşareti kaldırıldı';

  @override
  String get searchAnnotations => 'Ek açıklamalarda ara';

  @override
  String get searchClearSearch => 'Aramayı temizle';

  @override
  String get searchEmptyHint =>
      'Her eşleşmeyi burada listelemek için belgede arama yapın';

  @override
  String get searchMatchCase => 'Büyük/küçük harf eşleştir';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eşleşme',
      one: '1 eşleşme',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Sonraki eşleşme';

  @override
  String searchNoMatches(String query) {
    return '“$query” için eşleşme yok';
  }

  @override
  String searchPageHeader(int page) {
    return 'Sayfa $page';
  }

  @override
  String get searchPreviousMatch => 'Önceki eşleşme';

  @override
  String get searchRegex => 'Düzenli ifade';

  @override
  String get searchResultsTitle => 'Arama sonuçları';

  @override
  String get searchWholeWord => 'Tam sözcük';

  @override
  String get shellControls => 'Denetimler';

  @override
  String get shellDefaultAuthor => 'Varsayılan yazar…';

  @override
  String get shellHighlightFormFields => 'Form alanlarını vurgula';

  @override
  String get shellKeyboardShortcutsMenu => 'Klavye kısayolları…';

  @override
  String get shellKeyboardShortcutsTitle => 'Klavye kısayolları';

  @override
  String get shellShortcutsSearchHint => 'Kısayolları ara';

  @override
  String shellShortcutsNoMatches(String query) {
    return '“$query” ile eşleşen kısayol yok';
  }

  @override
  String get shellShortcutGroupSelect => 'Seç';

  @override
  String get shellShortcutGroupMarkup => 'İşaretleme';

  @override
  String get shellShortcutGroupDraw => 'Çiz';

  @override
  String get shellShortcutGroupShapes => 'Şekiller';

  @override
  String get shellShortcutGroupInsert => 'Ekle';

  @override
  String get shellShortcutGroupMeasure => 'Ölç';

  @override
  String get shellShortcutGroupEdit => 'Düzenle';

  @override
  String get shellNotSet => 'Ayarlanmadı';

  @override
  String get shellPageColor => 'Sayfa rengi…';

  @override
  String get shellPageGrid => 'Sayfa ızgarası';

  @override
  String get shellPanelAnnotations => 'Ek açıklamalar';

  @override
  String get shellPanelBookmarks => 'Yer imleri';

  @override
  String get shellPanelPages => 'Sayfalar';

  @override
  String get shellPanelProperties => 'Özellikler';

  @override
  String get shellPanelSearchResults => 'Arama sonuçları';

  @override
  String get shellPanels => 'Paneller';

  @override
  String get shellPressAKey => 'Bir tuşa basın';

  @override
  String get shellPressLetterKeyHint =>
      'Bir harf tuşuna basın veya temizlemek için Delete tuşuna basın.';

  @override
  String get shellReflow => 'Yeniden akıt';

  @override
  String get shellReflowText => 'Metni yeniden akıt';

  @override
  String get shellResetZoom => 'Yakınlaştırmayı sıfırla';

  @override
  String get shellSectionShell => 'Kabuk';

  @override
  String get shellSectionView => 'Görünüm';

  @override
  String get shellSettings => 'Ayarlar';

  @override
  String get shellShowAnnotations => 'Ek açıklamaları göster';

  @override
  String get shellTabHere => 'Buraya sekmele';

  @override
  String get shellUnbound => 'Atanmamış';

  @override
  String get shellZoom => 'Yakınlaştırma';

  @override
  String sidebarByAuthor(String author) {
    return '$author tarafından';
  }

  @override
  String get sidebarCancelSelection => 'Seçimi iptal et';

  @override
  String get sidebarClearSearch => 'Aramayı temizle';

  @override
  String get sidebarDeleteSelected => 'Seçilenleri sil';

  @override
  String get sidebarDeleteSignature => 'İmzayı sil';

  @override
  String get sidebarMore => 'Daha fazla';

  @override
  String get sidebarNoAnnotations => 'Ek açıklama yok';

  @override
  String get sidebarNoMatchingAnnotations => 'Eşleşen ek açıklama yok';

  @override
  String sidebarPageHeader(int number) {
    return 'Sayfa $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Bu, dijital imzayı belgeden kaldırır. Bunu geri alabilirsiniz.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Bu, \"$name\" tarafından atılan dijital imzayı belgeden kaldırır. Bunu geri alabilirsiniz.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'İmza kaldırılsın mı?';

  @override
  String get sidebarReopen => 'Yeniden aç';

  @override
  String get sidebarReply => 'Yanıtla';

  @override
  String get sidebarResolve => 'Çöz';

  @override
  String get sidebarSearchHint => 'Ek açıklamaları ara';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seçili',
      one: '$count seçili',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Bir yanıt yazın…';

  @override
  String get sigTitle => 'İmza';

  @override
  String get signIdCreate => 'Oluştur';

  @override
  String get signIdEmail => 'E-posta (isteğe bağlı)';

  @override
  String get signIdName => 'Ad';

  @override
  String get signIdNameHint => 'İmzada görünmesi gereken adınız';

  @override
  String get signIdNameRequired => 'Bir ad girin';

  @override
  String get signIdOrganization => 'Kuruluş (isteğe bağlı)';

  @override
  String get signIdSelfSignedInfo =>
      'Bu, kendinden imzalı bir kimlik oluşturur. İmzalar, Adobe Acrobat ve diğer okuyucularda \"imzalandı, geçerlilik bilinmiyor\" olarak görünür - kendi kendine imzalanmış kimliklerinin aynısı gibi. Yeşil onay işareti, ücretli, herkesçe güvenilen bir CA gerektirir.';

  @override
  String get signIdTitle => 'İmzalama kimliği oluştur';

  @override
  String get stampBox => 'Kutu';

  @override
  String get stampCircle => 'Daire';

  @override
  String get stampCustomCaption => 'Özel damga';

  @override
  String get stampDateFormat => 'Tarih biçimi';

  @override
  String get stampDeleteComponent => 'Seçili bileşeni sil';

  @override
  String get stampDeleteStamp => 'Damgayı sil';

  @override
  String get stampEditStamp => 'Damgayı düzenle';

  @override
  String get stampExport => 'Dışa aktar…';

  @override
  String get stampFieldDate => 'Tarih';

  @override
  String get stampFieldDateTime => 'Tarih ve saat';

  @override
  String get stampFieldTime => 'Saat';

  @override
  String get stampFieldUsername => 'Kullanıcı adı';

  @override
  String get stampFont => 'Yazı tipi';

  @override
  String get stampFontBold => 'Kalın';

  @override
  String get stampFontItalic => 'İtalik';

  @override
  String get stampHeight => 'Yükseklik';

  @override
  String get stampImage => 'Görsel';

  @override
  String get stampImport => 'İçe aktar…';

  @override
  String get stampInsertField => 'Alan ekle';

  @override
  String get stampMoreColors => 'Daha fazla renk…';

  @override
  String get stampNewStamp => 'Yeni damga…';

  @override
  String get stampNewStampTitle => 'Yeni damga';

  @override
  String get stampSelectTextToEdit => 'Düzenlemek için metin seçin';

  @override
  String get stampSelectedText => 'Seçili metin';

  @override
  String get stampSignature => 'İmza';

  @override
  String get stampStamps => 'Damgalar';

  @override
  String get stampText => 'Metin';

  @override
  String get stampTime12Hour => '12 saat';

  @override
  String get stampTime24Hour => '24 saat';

  @override
  String get stampTimeFormat => 'Saat biçimi';

  @override
  String get stampWidth => 'Genişlik';

  @override
  String get takeoffArea => 'Alan';

  @override
  String get takeoffCount => 'Sayım';

  @override
  String get takeoffEmpty => 'Henüz ölçüm yok.';

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
      other: '$count öğe',
      one: '$count öğe',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Uzunluk';

  @override
  String get takeoffTitle => 'Metraj';

  @override
  String get tbAddInkAnnotation => 'Kalem ek açıklaması ekle';

  @override
  String get tbAlign => 'Hizala';

  @override
  String get tbAlignBottom => 'Alta hizala';

  @override
  String get tbAlignHorizontalCenters => 'Yatay merkezleri hizala';

  @override
  String get tbAlignLeft => 'Sola hizala';

  @override
  String get tbAlignRight => 'Sağa hizala';

  @override
  String get tbAlignTop => 'Üste hizala';

  @override
  String get tbAlignVerticalCenters => 'Dikey merkezleri hizala';

  @override
  String get tbAnnotationsFlattened => 'Ek açıklamalar sayfalara düzleştirildi';

  @override
  String get tbApplyRedactionsMessage =>
      'İşaretlenen içerik belgeden kalıcı olarak kaldırılacak. Bu geri alınamaz.';

  @override
  String get tbApplyRedactionsTitle => 'Karartmalar uygulansın mı?';

  @override
  String get tbApplyRedactionsTooltip => 'Karartmaları uygula (geri alınamaz)';

  @override
  String get tbAutosizeTextBox => 'Metin kutusunu otomatik boyutlandır (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Ölçeği kalibre etmek için bilinen uzunlukta bir çizgi çizin.';

  @override
  String get tbCharSpacing => 'Karakter aralığı';

  @override
  String get tbCheckBoxOption => 'Onay kutusu';

  @override
  String get tbCheckMarksOnDocument => 'Belge üzerindeki onay işaretleri';

  @override
  String get tbColorLabel => 'Renk';

  @override
  String get tbColorProcessingTooltip =>
      'Renk işleme - sayfa içeriği renklerini bul ve değiştir';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count renk değiştirildi',
      one: '1 renk değiştirildi',
      zero: 'Eşleşen renk bulunamadı',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Onay kutusuna dönüştür';

  @override
  String get tbConvertToImageButton => 'Görsel düğmesine dönüştür';

  @override
  String get tbConvertToTextField => 'Metin alanına dönüştür';

  @override
  String get tbCornerRadius => 'Köşe yarıçapı';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ek açıklamayı sil',
      one: 'Ek açıklamayı sil',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Öğeyi sil';

  @override
  String get tbDeleteField => 'Alanı sil';

  @override
  String get tbDiscardDrawing => 'Çizimi at';

  @override
  String get tbDistributeHorizontally => 'Yatay olarak dağıt';

  @override
  String get tbDistributeVertically => 'Dikey olarak dağıt';

  @override
  String get tbDrawNewSignature => 'Yeni bir imza çiz…';

  @override
  String get tbEditAnnotationText => 'Ek açıklama metnini düzenle';

  @override
  String get tbEditTextStyle => 'Metni ve stili düzenle';

  @override
  String get tbElement => 'Öğe';

  @override
  String get tbEraserSize => 'Silgi boyutu';

  @override
  String get tbFieldActions => 'Alan eylemleri';

  @override
  String get tbFieldName => 'Alan adı';

  @override
  String tbFieldNamed(String name) {
    return 'Alan: $name';
  }

  @override
  String get tbFieldValue => 'Alan değeri';

  @override
  String get tbFill => 'Dolgu';

  @override
  String get tbFingerDraws => 'Parmak çizer - kaydırması için dokunun';

  @override
  String get tbFingerScrolls =>
      'Parmak kaydırır (kalem çizer) - çizmesi için dokunun';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Ek açıklamaları sayfalara düzleştir';

  @override
  String get tbFlattenForm => 'Formu düzleştir';

  @override
  String get tbFlattenFormBakeValues =>
      'Formu düzleştir - değerleri sayfalara işle';

  @override
  String get tbFlattenLabel => 'Düzleştir';

  @override
  String get tbFont => 'Yazı tipi';

  @override
  String get tbFontSize => 'Yazı tipi boyutu';

  @override
  String get tbFontWidth => 'Yazı tipi genişliği';

  @override
  String get tbFormFieldsFlattened => 'Form alanları sayfalara düzleştirildi';

  @override
  String get tbGroupDraw => 'Çiz';

  @override
  String get tbGroupEdit => 'Düzenle';

  @override
  String get tbGroupInsert => 'Ekle';

  @override
  String get tbGroupMarkup => 'İşaretleme';

  @override
  String get tbGroupMeasure => 'Ölç';

  @override
  String get tbGroupSelect => 'Seç';

  @override
  String get tbGroupShapes => 'Şekiller';

  @override
  String get tbImageButtonOption => 'Görsel düğmesi';

  @override
  String get tbLineEnd => 'Çizgi sonu';

  @override
  String get tbLineSpacing => 'Satır aralığı';

  @override
  String get tbLineStart => 'Çizgi başı';

  @override
  String get tbLineType => 'Çizgi türü';

  @override
  String get tbManageStamps => 'Damgaları yönet…';

  @override
  String get tbMarkupHighlight => 'Vurgu';

  @override
  String get tbMarkupHighlightTip => 'Seçimi vurgula';

  @override
  String get tbMarkupSquiggly => 'Dalgalı alt çizgi';

  @override
  String get tbMarkupSquigglyTip => 'Seçime dalgalı alt çizgi ekle';

  @override
  String get tbMarkupStrikeOut => 'Üstünü çiz';

  @override
  String get tbMarkupStrikeOutTip => 'Seçimin üstünü çiz';

  @override
  String get tbMarkupUnderline => 'Altı çizili';

  @override
  String get tbMarkupUnderlineTip => 'Seçimin altını çiz';

  @override
  String get tbMoreColors => 'Daha fazla renk…';

  @override
  String get tbNameArrow => 'Ok';

  @override
  String get tbNameCallout => 'Belirtme çizgisi';

  @override
  String get tbNameCloudPolygon => 'Bulut çokgeni';

  @override
  String get tbNameCount => 'Sayım';

  @override
  String get tbNameDigitalSignature => 'Dijital imza';

  @override
  String get tbNameDraw => 'Çiz';

  @override
  String get tbNameEllipse => 'Elips';

  @override
  String get tbNameEraser => 'Kalem çizgilerini sil';

  @override
  String get tbNameHighlight => 'Vurgu';

  @override
  String get tbNameImage => 'Görsel';

  @override
  String get tbNameLine => 'Çizgi';

  @override
  String get tbNameMeasureAngle => 'Açı ölç';

  @override
  String get tbNameMeasureArc => 'Yay uzunluğunu ölç';

  @override
  String get tbNameMeasureArea => 'Alan ölç';

  @override
  String get tbNameMeasureDistance => 'Mesafe ölç';

  @override
  String get tbNameMeasurePerimeter => 'Çevre ölç';

  @override
  String get tbNameMeasureSlope => 'Eğim ölç (yükseklik/yatay)';

  @override
  String get tbNameMeasureVolume => 'Hacim ölç (alan × derinlik)';

  @override
  String get tbNameNote => 'Not';

  @override
  String get tbNamePolygon => 'Çokgen';

  @override
  String get tbNamePolyline => 'Çoklu çizgi';

  @override
  String get tbNameRectangle => 'Dikdörtgen';

  @override
  String get tbNameSelect => 'Seç';

  @override
  String get tbNameSignature => 'İmza';

  @override
  String get tbNameStamp => 'Damga';

  @override
  String get tbNameTextBox => 'Metin kutusu';

  @override
  String get tbNewFieldType =>
      'Yeni alan türü - eklemek için bir sayfada sürükleyin';

  @override
  String get tbNoAnnotationsToFlatten => 'Düzleştirilecek ek açıklama yok';

  @override
  String get tbNoCustomStamps => 'Özel damga yok';

  @override
  String get tbNoFormFieldsToFlatten => 'Düzleştirilecek form alanı yok';

  @override
  String get tbNoRedactionsToApply => 'Uygulanacak karartma yok';

  @override
  String get tbNoteTitle => 'Not';

  @override
  String get tbOpacity => 'Opaklık';

  @override
  String get tbOutline => 'Ana hat';

  @override
  String get tbPatternScale => 'Desen ölçeği';

  @override
  String get tbPickColorFromPage => 'Sayfadan bir renk seç';

  @override
  String get tbRedactionsApplied => 'Karartmalar uygulandı';

  @override
  String get tbRedoShortcut => 'Yinele (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Yeniden akıtılamadı - bu, bu aracın yeniden sarabileceği tek sütunlu bir paragraf değil. Bunun yerine Metni değiştir\'i deneyin.';

  @override
  String get tbReflowParagraph => 'Paragrafı yeniden akıt';

  @override
  String get tbRenameField => 'Alanı yeniden adlandır';

  @override
  String get tbRenameFieldEllipsis => 'Alanı yeniden adlandır…';

  @override
  String get tbReplaceImage => 'Görseli değiştir';

  @override
  String get tbReplaceImageFailed => 'Görsel değiştirilemedi';

  @override
  String get tbReplaceText => 'Metni değiştir';

  @override
  String get tbSaveImage => 'Görseli kaydet';

  @override
  String get tbSaveShortcut => 'Kaydet… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Ölçek';

  @override
  String get tbSelectTextForMarkup => 'İşaretleme kullanmak için metin seçin';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seçili',
      one: 'Seçim',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Ayarla…';

  @override
  String get tbStamp => 'Damga';

  @override
  String get tbStampText => 'Damga metni';

  @override
  String get tbStrokeOpacityFont => 'Çizgi, opaklık, yazı tipi';

  @override
  String get tbStrokeWidthLabel => 'Çizgi kalınlığı';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Çizgi $width';
  }

  @override
  String get tbStyle => 'Stil';

  @override
  String get tbTakeoffTotals => 'Metraj toplamları';

  @override
  String get tbTextBorder => 'Metin kenarlığı';

  @override
  String get tbTextColour => 'Metin rengi';

  @override
  String get tbTextFieldOption => 'Metin alanı';

  @override
  String get tbTextFill => 'Metin dolgusu';

  @override
  String get tbTextStyleEllipsis => 'Metin stili…';

  @override
  String get tbTextTitle => 'Metin';

  @override
  String get tbTipCallout =>
      'Belirtme çizgisi - noktadan kutunun geleceği yere sürükleyin';

  @override
  String get tbTipContent => 'Sayfa içeriğini düzenle';

  @override
  String get tbTipCount =>
      'Sayım - onay işaretleri bırakmak ve saymak için dokunun';

  @override
  String get tbTipDigitalSignature =>
      'Dijital imza - yerleştirmek ve imzalamak için bir kutu sürükleyin';

  @override
  String get tbTipForm =>
      'Form alanları - seçmek için dokunun, doldurmak için çift dokunun, eklemek için sürükleyin';

  @override
  String get tbTipHighlightDraw => 'Vurgu - serbest elle çizin';

  @override
  String get tbTipImage =>
      'Görsel - yerleştirmek için dokunun veya bir kutu çizin';

  @override
  String get tbTipMeasureAngle => 'Açı ölç - üç noktaya tıklayın';

  @override
  String get tbTipMeasureArc => 'Yay uzunluğunu ölç - üç noktaya tıklayın';

  @override
  String get tbTipRedact => 'Karart - bir bölge sürükleyin, sonra uygulayın';

  @override
  String get tbTipSignature => 'İmza - yerleştirmek için bir sayfaya dokunun';

  @override
  String get tbTipSnapshot =>
      'Anlık görüntü - yakalamak için bir bölge sürükleyin (vektör olarak geri yapıştırın)';

  @override
  String get tbToolContent => 'İçerik';

  @override
  String get tbToolForm => 'Form';

  @override
  String get tbToolRedact => 'Karart';

  @override
  String get tbToolSnapshot => 'Anlık görüntü';

  @override
  String get tbTools => 'Araçlar';

  @override
  String get tbTotals => 'Toplamlar';

  @override
  String get tbTypeTextEachTime => 'Her seferinde metin yaz';

  @override
  String get tbUnderline => 'Altı çizili';

  @override
  String get tbUndoShortcut => 'Geri al (⌘Z)';

  @override
  String get textStyleFont => 'Yazı tipi';

  @override
  String get textStyleFontSize => 'Yazı tipi boyutu';

  @override
  String get textStyleKeep => 'koru';

  @override
  String get textStyleStyle => 'Stil';

  @override
  String get textStyleText => 'Metin';

  @override
  String get textStyleTextFill => 'Metin dolgusu';

  @override
  String get textStyleTitle => 'Metni ve stili düzenle';

  @override
  String get thumbAddPage => 'Sayfa ekle';

  @override
  String get thumbClearSelection => 'Seçimi temizle';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı kopyala',
      one: 'Sayfayı kopyala',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Seçili sayfaları kopyala';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı kes',
      one: 'Sayfayı kes',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Seçili sayfaları kes';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı sil',
      one: 'Sayfayı sil',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Seçili sayfaları sil';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı çoğalt',
      one: 'Sayfayı çoğalt',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Sayfaları dışa aktar…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı dışa aktar…',
      one: 'Sayfayı dışa aktar…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Seçili sayfaları dışa aktar';

  @override
  String get thumbInsertBlankAfter => 'Sonrasına boş sayfa ekle';

  @override
  String get thumbInsertBlankBefore => 'Öncesine boş sayfa ekle';

  @override
  String get thumbInsertFileFailed => 'Bu dosya eklenemedi.';

  @override
  String get thumbInsertPdf => 'PDF ekle…';

  @override
  String get thumbPageActions => 'Sayfa eylemleri';

  @override
  String thumbPageNumber(int number) {
    return 'Sayfa $number';
  }

  @override
  String get thumbPages => 'Sayfalar';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfayı yapıştır',
      one: 'Sayfayı yapıştır',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '180° döndür';

  @override
  String get thumbRotateLeft => 'Sola döndür';

  @override
  String get thumbRotatePageRight => 'Sayfayı sağa döndür';

  @override
  String get thumbRotateRight => 'Sağa döndür';

  @override
  String get thumbRotateSelectedLeft => 'Seçili sayfaları sola döndür';

  @override
  String get thumbRotateSelectedRight => 'Seçili sayfaları sağa döndür';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seçili',
      one: '$count seçili',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Geri al';

  @override
  String get viewerEditFontUnsafe =>
      'Bu PDF yazı tipi veya kodlaması güvenli bir şekilde düzenlenemiyor.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Düzenleme, tek bir sayfada seçim gerektirir.';

  @override
  String get viewerEditNotEditableRun =>
      'Bu seçim, düzenlenebilir tek bir sayfa içeriği metin dizisi değil.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Bu PDF yazı tipi yeniden yazılabilir, ancak stili değiştirilemez.';

  @override
  String get viewerEditTextStyle => 'Metni ve stili düzenle';

  @override
  String get viewerMarkup => 'İşaretleme';

  @override
  String get viewerMarkupHighlight => 'Vurgu';

  @override
  String get viewerMarkupSquiggly => 'Dalgalı';

  @override
  String get viewerMarkupStrikeOut => 'Üstünü çiz';

  @override
  String get viewerMarkupUnderline => 'Altı çizili';

  @override
  String get viewerSelectAll => 'Tümünü seç';
}
