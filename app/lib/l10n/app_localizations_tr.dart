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
  String get appSigAddLogo => 'Logo ekle…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Tüm $pageCount sayfa';
  }

  @override
  String get appSigAppearance => 'Görünüm';

  @override
  String get appSigAppearanceDescription =>
      'İmza, yerleştirdiğiniz yere çizilir. İmzalayanın adı ve ayrıntıları her zaman gösterilir; elle çizilmiş bir işaret ve logo arka planı ekleyebilirsiniz.';

  @override
  String appSigApplyTo(String label) {
    return 'Uygulanacak: $label';
  }

  @override
  String get appSigApplyToPages => 'Sayfalara uygula…';

  @override
  String get appSigChooseCertificate => 'Sertifika dosyası seç…';

  @override
  String get appSigChooseKeyDescription =>
      'Özel anahtarınızı (RSA, PEM veya DER) ve sertifika dosyasını seçin. Anahtar yalnızca imzalamak için kullanılır ve asla kaydedilmez.';

  @override
  String get appSigChoosePngOrJpeg => 'Bir PNG veya JPEG görseli seçin.';

  @override
  String get appSigChoosePrivateKey => 'Özel anahtar seç…';

  @override
  String get appSigContactInfo => 'İletişim bilgileri';

  @override
  String get appSigCouldNotCaptureSignature => 'İmza yakalanamadı.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Sertifika okunamadı: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Anahtar okunamadı: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Bu cihazda bir imza oluştur';

  @override
  String appSigDate(String date) {
    return 'Tarih: $date';
  }

  @override
  String get appSigDigitallySign => 'Dijital olarak imzala';

  @override
  String get appSigDrawSignature => 'İmza çiz…';

  @override
  String get appSigFieldHelper =>
      'Yeni bir imza alanı oluşturmak için boş bırakın.';

  @override
  String get appSigFieldLabel => 'Mevcut imza alanı (isteğe bağlı)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sertifika',
      one: '1 sertifika',
    );
    return '$_temp0 · geçerlilik $validFrom - $validUntil';
  }

  @override
  String get appSigIntro =>
      'Dijital imza, bu belgeyi imzaladığınızı ve o zamandan beri değiştirilmediğini kanıtlar. Nasıl imzalamak istediğinizi seçin.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Seçilen anahtar veya sertifika okunamadı.';

  @override
  String get appSigKeylessDescription =>
      'En kolayı. E-posta ile kimliğinizi doğrular ve güvenilir bir zaman damgasıyla sizin adınıza imzalarız. Kurulacak veya ayarlanacak bir şey yok.';

  @override
  String get appSigKeylessIdentity => 'Anahtarsız kimlik';

  @override
  String get appSigKeylessSignInExpired =>
      'Anahtarsız oturumunuzun süresi doldu. Lütfen tekrar oturum açın.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Anahtarsız oturum açma başarısız: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Anahtarsız · zaman damgalı · geçerlilik bilinmiyor';

  @override
  String get appSigKeylessWebNote =>
      'E-postanızla oturum açmak en kolay yoldur — DartPDF masaüstü ve mobil uygulamalarında kullanılabilir. Güvenlik nedeniyle bir web tarayıcısında çalışamaz.';

  @override
  String get appSigLocation => 'Konum';

  @override
  String get appSigLogoAdded => 'Logo eklendi ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Sayfa $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Önizleme - imzalanan kutu biraz farklı olabilir.';

  @override
  String get appSigReason => 'Neden';

  @override
  String appSigReasonLine(String reason) {
    return 'Neden: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Oturum yenileniyor…';

  @override
  String get appSigRemoveLogo => 'Logoyu kaldır';

  @override
  String get appSigRemoveSignature => 'İmzayı kaldır';

  @override
  String get appSigSelfSignedDescription =>
      'Oturum açmaya veya dosyaya gerek yok. Kişisel kullanım için en iyisi — bir sonraki sefer için bu cihaza kaydedilir. Bazı PDF okuyucuları bunu \"imzalandı, geçerlilik bilinmiyor\" olarak gösterir, bu kendiniz oluşturduğunuz bir imza için normaldir.';

  @override
  String get appSigSelfSignedIdentity => 'Kendinden imzalı kimlik';

  @override
  String get appSigSelfSignedSubtitle =>
      'Kendinden imzalı · geçerlilik bilinmiyor';

  @override
  String get appSigShowSignatureOnPages => 'İmzayı sayfalarda göster';

  @override
  String get appSigSign => 'İmzala';

  @override
  String get appSigSignInWithEmail => 'E-postanızla oturum açın';

  @override
  String get appSigSignatureAdded => 'İmza eklendi ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '$signerName tarafından dijital olarak imzalandı';
  }

  @override
  String get appSigSigner => 'İmzalayan';

  @override
  String get appSigSigningYouIn => 'Oturumunuz açılıyor…';

  @override
  String get appSigThisPageOnly => 'Yalnızca bu sayfa';

  @override
  String get appSigUseOwnCertificate => 'Kendi sertifikanızı kullanın';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Kuruluşunuzdan bir imzalama sertifikası için';

  @override
  String get appSigX509Signer => 'X.509 imzalayan';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bu $count PDF\'yi yeni bir sekmede açmak mı yoksa sayfalarını \"$title\" içine eklemek mi istiyorsunuz?',
      one:
          'Bu PDF\'yi yeni bir sekmede açmak mı yoksa sayfalarını \"$title\" içine eklemek mi istiyorsunuz?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bırakılan PDF\'leri ekle',
      one: 'Bırakılan PDF\'yi ekle',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Ek açıklama metni kopyalandı';

  @override
  String get editorAppMenuTooltip => 'DartPDF menüsü';

  @override
  String get editorCancelOcr => 'OCR\'yi iptal et';

  @override
  String get editorClearRecentFiles => 'Son dosyaları temizle';

  @override
  String get editorCloseAll => 'Tümünü kapat';

  @override
  String get editorCloseOthers => 'Diğerlerini kapat';

  @override
  String get editorCloseTab => 'Sekmeyi kapat';

  @override
  String get editorCloseTabsToRight => 'Sağdaki sekmeleri kapat';

  @override
  String get editorCompareFailedTitle => 'Karşılaştırma başarısız';

  @override
  String editorCompareTitle(String title) {
    return 'Karşılaştır: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Panoya kopyalandı';

  @override
  String get editorCopySelectedTextTooltip => 'Seçili metni kopyala (⌘C)';

  @override
  String get editorCopyText => 'Metni kopyala';

  @override
  String editorCouldNotExport(String title) {
    return '$title dışa aktarılamadı';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Damgalar içe aktarılamadı: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bırakılan PDF\'ler eklenemedi',
      one: 'Bırakılan PDF eklenemedi',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '$title açılamadı\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'İçeren klasör açılamadı';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'İkinci dosya açılamadı\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Seçilen dosya açılamadı\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '$url açılamadı';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '$title yazdırılamadı';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '$title yeniden açılamadı';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Dijital olarak imzalanamadı: $error';
  }

  @override
  String get editorDiscard => 'At';

  @override
  String get editorDiscardChangesTitle => 'Değişiklikler atılsın mı?';

  @override
  String get editorDocumentSigned => 'Belge dijital olarak imzalandı';

  @override
  String get editorDownload => 'İndir';

  @override
  String get editorDropToOpen => 'Açmak için PDF bırakın';

  @override
  String get editorDropToOpenOrInsert => 'Açmak veya eklemek için PDF bırakın';

  @override
  String get editorInsertPages => 'Sayfaları ekle';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count eklendi; $files okunamadı';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF $title içine eklendi',
      one: 'Sayfalar $title içine eklendi',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Geçersiz bağlantı: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Bu belge JavaScript çalıştırmaya çalıştı (yoksayıldı)';

  @override
  String get editorLoadingFullDocument => 'Tam belge yükleniyor';

  @override
  String get editorMenuCompareWith => 'Şununla karşılaştır…';

  @override
  String get editorMenuDigitallySign => 'Dijital olarak imzala…';

  @override
  String get editorMenuDigitallySigning => 'Dijital olarak imzalanıyor…';

  @override
  String get editorMenuExportImage => 'Sayfayı görsel olarak dışa aktar…';

  @override
  String get editorMenuNewDocument => 'Yeni belge…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Bir PDF aç…';

  @override
  String get editorMenuPrint => 'Yazdır…';

  @override
  String get editorMenuSaveAs => 'Farklı kaydet…';

  @override
  String get editorMenuSettings => 'Ayarlar';

  @override
  String get editorMenuSwitchToEdit => 'Düzenleme moduna geç';

  @override
  String get editorMenuSwitchToReadOnly => 'Salt okunura geç';

  @override
  String editorNamedAction(String name) {
    return 'Adlandırılmış eylem: $name';
  }

  @override
  String get editorNoRecentFiles => 'Son dosya yok';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'OCR çalıştırmadan önce bir belge açın';

  @override
  String get editorOpenFailedTitle => 'Açma başarısız';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yeni sekmelerde aç',
      one: 'Yeni sekmede aç',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'PDF\'yi yeni sekmede aç';

  @override
  String get editorOpenRecent => 'Son Kullanılanları Aç';

  @override
  String get editorOpenTabs => 'Açık sekmeler';

  @override
  String get editorOpeningDocumentSemantic => 'Belge açılıyor';

  @override
  String get editorOpeningPdf => 'PDF açılıyor…';

  @override
  String editorOpeningTitle(String title) {
    return '$title açılıyor…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Sayfa $number';
  }

  @override
  String get editorPreviewComparison => 'Karşılaştırma';

  @override
  String get editorPreviewCouldNotOpen => 'Açılamadı';

  @override
  String get editorPreviewOpening => 'Açılıyor';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'İmza kaldırıldı';

  @override
  String get editorSnapshotCopied => 'Anlık görüntü panoya kopyalandı';

  @override
  String get editorSnapshotCopyFailed => 'Anlık görüntü panoya kopyalanamadı';

  @override
  String get editorTabs => 'Sekmeler';

  @override
  String editorTabsOpenCount(int count) {
    return '$count açık';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count belgede kaydedilmemiş değişiklikler var.',
      one: 'Bir belgede kaydedilmemiş değişiklikler var.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Desteklenmeyen eylem: $type';
  }

  @override
  String get editorUntitled => 'Başlıksız';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version kullanılabilir.';
  }

  @override
  String get editorUpdateLater => 'Daha sonra';

  @override
  String get editorViewAllTabs => 'Tüm sekmeleri görüntüle';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Dışa aktar';

  @override
  String get imgExportFormat => 'Biçim';

  @override
  String get imgExportResolution => 'Çözünürlük';

  @override
  String get imgExportTitle => 'Sayfayı görsel olarak dışa aktar';

  @override
  String get newDocCreate => 'Oluştur';

  @override
  String get newDocLandscape => 'Yatay';

  @override
  String get newDocOrientation => 'Yönlendirme';

  @override
  String get newDocPageSize => 'Sayfa boyutu';

  @override
  String get newDocPortrait => 'Dikey';

  @override
  String get newDocTitle => 'Yeni belge';

  @override
  String get none => 'Yok';

  @override
  String get ocrAlreadyRunning =>
      'OCR zaten çalışıyor - bitmesini bekleyin veya iptal edin';

  @override
  String get ocrBrowserInitFailed => 'Tarayıcı OCR\'si başlatılamadı';

  @override
  String get ocrCancelled => 'OCR iptal edildi';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR $count metin dizisinden sonra iptal edildi',
      one: 'OCR 1 metin dizisinden sonra iptal edildi',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'İndir';

  @override
  String ocrDownloadFailed(String error) {
    return 'OCR modeli indirilemedi: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Seçilebilir bir metin katmanı eklemek, cihaz üzerindeki OCR modelini$size gerektirir. Bir kez indirilir ve sonra çevrimdışı çalışır.\n\nModel: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR modeli indirilsin mi?';

  @override
  String ocrFailed(String error) {
    return 'OCR başarısız: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'Cihaz üzerinde OCR bu platformda kullanılamıyor';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR $count metin dizisi ekledi - sayfa metni artık seçilebilir',
      one: 'OCR 1 metin dizisi ekledi - sayfa metni artık seçilebilir',
      zero: 'OCR bu sayfalarda metin bulamadı',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Web OCR, bir Florence-2 görsel-dil modeli indirir ve Transformers.js aracılığıyla WebGPU/WASM ile yerel olarak çalıştırır. PDF sayfaları bu tarayıcıda kalır; yalnızca model dosyaları ilk kullanımda getirilir.';

  @override
  String get ocrWebPromptTitle => 'Bu tarayıcıda AI OCR çalıştırılsın mı?';

  @override
  String get ocrWebStart => 'OCR\'yi başlat';

  @override
  String get ok => 'Tamam';

  @override
  String get paste => 'Yapıştır';

  @override
  String get printDlgPreparing => 'Hazırlanıyor…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Sayfa $rendered / $total işleniyor…';
  }

  @override
  String get printDlgTitle => 'Yazdırılıyor';

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
  String get settingsAbout => 'Hakkında';

  @override
  String get settingsAppearance => 'Görünüm';

  @override
  String get settingsCheckNow => 'Şimdi denetle';

  @override
  String get settingsLanguage => 'Dil';

  @override
  String get settingsLanguageSystem => 'Sistem varsayılanı';

  @override
  String get settingsCheckingForUpdates => 'Güncellemeler denetleniyor…';

  @override
  String get settingsCouldNotOpenDownload => 'İndirme açılamadı';

  @override
  String get settingsCouldNotOpenSystemSettings => 'Sistem ayarları açılamadı';

  @override
  String get settingsDeveloperTools => 'Geliştirici araçları';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Metrikler, günlükler, işleme modları (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version indir';
  }

  @override
  String get settingsOpenSettings => 'Ayarları Aç';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hatırlanan',
      one: '1 hatırlanan',
      zero: 'Son dosya yok',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Son dosyalar';

  @override
  String get settingsSetUpAsDefault => 'Varsayılan uygulama olarak ayarla';

  @override
  String get settingsSystem => 'Sistem';

  @override
  String get settingsThemeDark => 'Koyu';

  @override
  String get settingsThemeLight => 'Açık';

  @override
  String get settingsThemeSystem => 'Sistem';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String settingsUpToDate(String version) {
    return 'En son sürümü ($version) kullanıyorsunuz.';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return '$version sürümü kullanılabilir ($currentVersion sürümüne sahipsiniz).';
  }

  @override
  String get settingsUpdateFailed =>
      'Güncellemeler denetlenemedi. Daha sonra tekrar deneyin.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return '$name $version sürümüne sahipsiniz.';
  }

  @override
  String get settingsUpdates => 'Güncellemeler';

  @override
  String get settingsViewSource => 'GitHub\'da kaynağı görüntüle';

  @override
  String get undo => 'Geri al';

  @override
  String get welcomeOpenPdf => 'Bir PDF aç';

  @override
  String get welcomePickAgainToReopen => 'Yeniden açmak için tekrar seçin';

  @override
  String get welcomeRecent => 'Son kullanılanlar';

  @override
  String get welcomeRemoveFromRecent => 'Son kullanılanlardan kaldır';

  @override
  String get welcomeTapToReopen => 'Yeniden açmak için dokunun';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Web uygulamasını yükleyin, ardından PDF dosyaları için seçin.',
        'windows': 'PDF\'ler için Windows varsayılan uygulama ayarlarını açın.',
        'macos': 'Finder\'ın \"Her Zaman Şununla Aç\" adımlarını izleyin.',
        'linux': 'Masaüstünüzün varsayılan uygulama ayarlarını kullanın.',
        'android':
            'Bir PDF açarken DartPDF\'yi seçin, ardından Her Zaman\'a dokunun.',
        'ios':
            'PDF\'leri buraya göndermek için Dosyalar\'dan Paylaş veya İçinde Aç seçeneğini kullanın.',
        'other': 'Sisteminizin PDF dosya işleyicisini yapılandırın.',
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
            'Önce DartPDF\'yi tarayıcınızdan yükleyin. Ardından PDF dosyalarını yüklü uygulamayla ilişkilendirmek için tarayıcı veya işletim sistemi dosya işleyici ayarlarını kullanın.',
        'windows':
            'Windows Ayarları, Varsayılan uygulamalar bölümünü açacak. \".pdf\" veya \"PDF\" araması yapın, mevcut PDF uygulamasını seçin, ardından DartPDF\'yi seçin.',
        'macos':
            'Finder\'da herhangi bir PDF seçin, Dosya > Bilgi Al\'ı seçin, \"Şununla aç\" bölümünü genişletin, DartPDF\'yi seçin, ardından \"Tümünü Değiştir…\"e tıklayın.',
        'linux':
            'Masaüstü ayarlarınızı Varsayılan Uygulamalar için açın veya Dosyalar\'da bir PDF\'ye sağ tıklayın, Özellikler\'i seçin ve DartPDF\'yi PDF belgeleri için varsayılan olarak ayarlayın.',
        'android':
            'Dosyalar veya İndirilenler\'den bir PDF açın, uygulama seçicide DartPDF\'yi seçin, ardından Her Zaman\'ı seçin. Başka bir uygulama zaten PDF\'leri açıyorsa, önce Android Ayarları\'nda o uygulamanın varsayılanlarını temizleyin.',
        'ios':
            'iOS küresel bir varsayılan PDF düzenleyici sağlamaz. Dosyalar > Paylaş\'ı kullanın veya bir PDF\'ye uzun basıp Paylaş/İçinde Aç\'ı seçin, ardından DartPDF\'yi seçin.',
        'other':
            'PDF belgelerini DartPDF ile ilişkilendirmek için sistem dosya işleyici ayarlarını kullanın.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR modeli indiriliyor…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Model indiriliyor %$percent';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR tamamlanıyor…';

  @override
  String get fileTypePdf => 'PDF belgeleri';

  @override
  String get fileTypeImages => 'Görseller';

  @override
  String get fileTypeStampBundle => 'DartPDF damgaları';

  @override
  String get appSigKeyFileType => 'RSA özel anahtarları';

  @override
  String get appSigCertificateFileType => 'X.509 sertifikaları';

  @override
  String get appSigErrorNoCertificateSelected =>
      'En az bir X.509 sertifikası seçin.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Sertifika $index geçerli X.509 değil.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Özel anahtar, seçilen hiçbir RSA sertifikasıyla eşleşmiyor.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Şifrelenmiş özel anahtarlar desteklenmiyor. Şifrelenmemiş bir RSA PKCS#1 veya PKCS#8 anahtarı seçin.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Özel anahtar, şifrelenmemiş bir RSA PKCS#1 veya PKCS#8 anahtarı değil.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Hiç X.509 sertifikası bulunamadı.';
}
