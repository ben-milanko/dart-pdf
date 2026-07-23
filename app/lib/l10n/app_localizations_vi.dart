// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get add => 'Thêm';

  @override
  String get appSigAddLogo => 'Thêm biểu trưng…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Tất cả $pageCount trang';
  }

  @override
  String get appSigAppearance => 'Giao diện';

  @override
  String get appSigAppearanceDescription =>
      'Chữ ký được vẽ ở nơi bạn đặt nó. Tên và thông tin người ký luôn được hiển thị; bạn có thể thêm dấu vẽ tay và nền biểu trưng.';

  @override
  String appSigApplyTo(String label) {
    return 'Áp dụng cho: $label';
  }

  @override
  String get appSigApplyToPages => 'Áp dụng cho các trang…';

  @override
  String get appSigChooseCertificate => 'Chọn tệp chứng chỉ…';

  @override
  String get appSigChooseKeyDescription =>
      'Chọn khóa riêng tư của bạn (RSA, PEM hoặc DER) và tệp chứng chỉ của nó. Khóa chỉ được dùng để ký và không bao giờ được lưu.';

  @override
  String get appSigChoosePngOrJpeg => 'Chọn một hình ảnh PNG hoặc JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Chọn khóa riêng tư…';

  @override
  String get appSigContactInfo => 'Thông tin liên hệ';

  @override
  String get appSigCouldNotCaptureSignature => 'Không thể ghi lại chữ ký.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Không thể đọc chứng chỉ: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Không thể đọc khóa: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Tạo chữ ký trên thiết bị này';

  @override
  String appSigDate(String date) {
    return 'Ngày: $date';
  }

  @override
  String get appSigDigitallySign => 'Ký số';

  @override
  String get appSigDrawSignature => 'Vẽ chữ ký…';

  @override
  String get appSigFieldHelper => 'Để trống để tạo trường chữ ký mới.';

  @override
  String get appSigFieldLabel => 'Trường chữ ký hiện có (tùy chọn)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chứng chỉ',
      one: '1 chứng chỉ',
    );
    return '$_temp0 · hợp lệ từ $validFrom đến $validUntil';
  }

  @override
  String get appSigIntro =>
      'Chữ ký số chứng minh rằng bạn đã ký tài liệu này và nó chưa bị thay đổi kể từ đó. Chọn cách bạn muốn ký.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Không thể đọc khóa hoặc chứng chỉ đã chọn.';

  @override
  String get appSigKeylessDescription =>
      'Dễ nhất. Chúng tôi xác nhận đó là bạn qua email và ký thay bạn, với dấu thời gian đáng tin cậy. Không cần cài đặt hay thiết lập gì.';

  @override
  String get appSigKeylessIdentity => 'Danh tính không khóa';

  @override
  String get appSigKeylessSignInExpired =>
      'Đăng nhập không khóa của bạn đã hết hạn. Vui lòng đăng nhập lại.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Đăng nhập không khóa không thành công: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Không khóa · có dấu thời gian · không rõ hiệu lực';

  @override
  String get appSigKeylessWebNote =>
      'Đăng nhập bằng email là cách dễ nhất — nó có sẵn trong ứng dụng máy tính và di động của DartPDF. Vì lý do bảo mật, nó không thể chạy trong trình duyệt web.';

  @override
  String get appSigLocation => 'Vị trí';

  @override
  String get appSigLogoAdded => 'Đã thêm biểu trưng ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Trang $start–$end';
  }

  @override
  String get appSigPreviewNote => 'Xem trước - hộp đã ký có thể khác đôi chút.';

  @override
  String get appSigReason => 'Lý do';

  @override
  String appSigReasonLine(String reason) {
    return 'Lý do: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Đang làm mới đăng nhập…';

  @override
  String get appSigRemoveLogo => 'Gỡ biểu trưng';

  @override
  String get appSigRemoveSignature => 'Gỡ chữ ký';

  @override
  String get appSigSelfSignedDescription =>
      'Không cần đăng nhập hay tệp nào. Tốt nhất cho mục đích cá nhân — nó được lưu trên thiết bị này cho lần sau. Một số trình đọc PDF sẽ hiển thị nó là \"đã ký, không rõ hiệu lực\", điều này là bình thường đối với chữ ký do chính bạn tạo.';

  @override
  String get appSigSelfSignedIdentity => 'Danh tính tự ký';

  @override
  String get appSigSelfSignedSubtitle => 'Tự ký · không rõ hiệu lực';

  @override
  String get appSigShowSignatureOnPages => 'Hiển thị chữ ký trên các trang';

  @override
  String get appSigSign => 'Ký';

  @override
  String get appSigSignInWithEmail => 'Đăng nhập bằng email của bạn';

  @override
  String get appSigSignatureAdded => 'Đã thêm chữ ký ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Được ký số bởi $signerName';
  }

  @override
  String get appSigSigner => 'Người ký';

  @override
  String get appSigSigningYouIn => 'Đang đăng nhập cho bạn…';

  @override
  String get appSigThisPageOnly => 'Chỉ trang này';

  @override
  String get appSigUseOwnCertificate => 'Sử dụng chứng chỉ của riêng bạn';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Dành cho chứng chỉ ký từ tổ chức của bạn';

  @override
  String get appSigX509Signer => 'Người ký X.509';

  @override
  String get apply => 'Áp dụng';

  @override
  String get cancel => 'Hủy';

  @override
  String get clear => 'Xóa';

  @override
  String get close => 'Đóng';

  @override
  String get copy => 'Sao chép';

  @override
  String get cut => 'Cắt';

  @override
  String get delete => 'Xóa';

  @override
  String get done => 'Xong';

  @override
  String get edit => 'Chỉnh sửa';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Mở $count PDF này trong thẻ mới, hay chèn các trang của chúng vào \"$title\"?',
      one:
          'Mở PDF này trong thẻ mới, hay chèn các trang của nó vào \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Thêm các PDF đã thả',
      one: 'Thêm PDF đã thả',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Đã sao chép văn bản chú thích';

  @override
  String get editorAppMenuTooltip => 'Menu DartPDF';

  @override
  String get editorCancelOcr => 'Hủy OCR';

  @override
  String get editorClearRecentFiles => 'Xóa tệp gần đây';

  @override
  String get editorCloseAll => 'Đóng tất cả';

  @override
  String get editorCloseOthers => 'Đóng các thẻ khác';

  @override
  String get editorCloseTab => 'Đóng thẻ';

  @override
  String get editorCloseTabsToRight => 'Đóng các thẻ bên phải';

  @override
  String get editorCompareFailedTitle => 'So sánh không thành công';

  @override
  String editorCompareTitle(String title) {
    return 'So sánh: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Đã sao chép vào bảng nhớ tạm';

  @override
  String get editorCopySelectedTextTooltip => 'Sao chép văn bản đã chọn (⌘C)';

  @override
  String get editorCopyText => 'Sao chép văn bản';

  @override
  String editorCouldNotExport(String title) {
    return 'Không thể xuất $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Không thể nhập con dấu: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Không thể chèn các PDF đã thả',
      one: 'Không thể chèn PDF đã thả',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Không thể mở $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Không thể mở thư mục chứa tệp';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Không thể mở tệp thứ hai\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Không thể mở tệp đã chọn\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Không thể mở $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Không thể in $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Không thể mở lại $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Không thể ký số: $error';
  }

  @override
  String get editorDiscard => 'Bỏ';

  @override
  String get editorDiscardChangesTitle => 'Bỏ các thay đổi?';

  @override
  String get editorDocumentSigned => 'Tài liệu đã được ký số';

  @override
  String get editorDownload => 'Tải xuống';

  @override
  String get editorDropToOpen => 'Thả PDF để mở';

  @override
  String get editorDropToOpenOrInsert => 'Thả PDF để mở hoặc chèn';

  @override
  String get editorInsertPages => 'Chèn trang';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Đã chèn $count; không thể đọc $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã chèn $count PDF vào $title',
      one: 'Đã chèn các trang vào $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Liên kết không hợp lệ: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Tài liệu này đã cố chạy JavaScript (đã bỏ qua)';

  @override
  String get editorLoadingFullDocument => 'Đang tải toàn bộ tài liệu';

  @override
  String get editorMenuCompareWith => 'So sánh với…';

  @override
  String get editorMenuDigitallySign => 'Ký số…';

  @override
  String get editorMenuDigitallySigning => 'Đang ký số…';

  @override
  String get editorMenuExportImage => 'Xuất trang dưới dạng hình ảnh…';

  @override
  String get editorMenuNewDocument => 'Tài liệu mới…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Mở một PDF…';

  @override
  String get editorMenuPrint => 'In…';

  @override
  String get editorMenuSaveAs => 'Lưu thành…';

  @override
  String get editorMenuSettings => 'Cài đặt';

  @override
  String get editorMenuSwitchToEdit => 'Chuyển sang chế độ chỉnh sửa';

  @override
  String get editorMenuSwitchToReadOnly => 'Chuyển sang chỉ đọc';

  @override
  String editorNamedAction(String name) {
    return 'Hành động có tên: $name';
  }

  @override
  String get editorNoRecentFiles => 'Không có tệp gần đây';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Mở một tài liệu trước khi chạy OCR';

  @override
  String get editorOpenFailedTitle => 'Mở không thành công';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mở trong các thẻ mới',
      one: 'Mở trong thẻ mới',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Mở PDF trong thẻ mới';

  @override
  String get editorOpenRecent => 'Mở gần đây';

  @override
  String get editorOpenTabs => 'Các thẻ đang mở';

  @override
  String get editorOpeningDocumentSemantic => 'Đang mở tài liệu';

  @override
  String get editorOpeningPdf => 'Đang mở PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Đang mở $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Trang $number';
  }

  @override
  String get editorPreviewComparison => 'So sánh';

  @override
  String get editorPreviewCouldNotOpen => 'Không thể mở';

  @override
  String get editorPreviewOpening => 'Đang mở';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Đã gỡ chữ ký';

  @override
  String get editorSnapshotCopied => 'Đã sao chép ảnh chụp vào bảng nhớ tạm';

  @override
  String get editorSnapshotCopyFailed =>
      'Không thể sao chép ảnh chụp vào bảng nhớ tạm';

  @override
  String get editorTabs => 'Thẻ';

  @override
  String editorTabsOpenCount(int count) {
    return '$count đang mở';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tài liệu có các thay đổi chưa lưu.',
      one: 'Một tài liệu có các thay đổi chưa lưu.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Hành động không được hỗ trợ: $type';
  }

  @override
  String get editorUntitled => 'Không có tiêu đề';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version đã có sẵn.';
  }

  @override
  String get editorUpdateLater => 'Để sau';

  @override
  String get updateInstallNow => 'Update now';

  @override
  String get updateDownloadingTitle => 'Downloading update';

  @override
  String get updatePreparing => 'Preparing…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateRestarting => 'Restarting to finish the update…';

  @override
  String get updateHandedOff => 'Update downloaded. Opening the installer…';

  @override
  String updateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get editorViewAllTabs => 'Xem tất cả các thẻ';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Xuất';

  @override
  String get imgExportFormat => 'Định dạng';

  @override
  String get imgExportResolution => 'Độ phân giải';

  @override
  String get imgExportTitle => 'Xuất trang dưới dạng hình ảnh';

  @override
  String get newDocCreate => 'Tạo';

  @override
  String get newDocLandscape => 'Ngang';

  @override
  String get newDocOrientation => 'Hướng';

  @override
  String get newDocPageSize => 'Kích thước trang';

  @override
  String get newDocPortrait => 'Dọc';

  @override
  String get newDocTitle => 'Tài liệu mới';

  @override
  String get none => 'Không có';

  @override
  String get ocrAlreadyRunning =>
      'OCR đang chạy - hãy đợi nó hoàn tất hoặc hủy nó';

  @override
  String get ocrBrowserInitFailed =>
      'OCR trên trình duyệt khởi tạo không thành công';

  @override
  String get ocrCancelled => 'Đã hủy OCR';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã hủy OCR sau $count đoạn văn bản',
      one: 'Đã hủy OCR sau 1 đoạn văn bản',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Tải xuống';

  @override
  String ocrDownloadFailed(String error) {
    return 'Không thể tải xuống mô hình OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Việc thêm lớp văn bản có thể chọn cần mô hình OCR trên thiết bị$size. Nó tải xuống một lần rồi chạy ngoại tuyến.\n\nMô hình: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Tải xuống mô hình OCR?';

  @override
  String ocrFailed(String error) {
    return 'OCR không thành công: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'OCR trên thiết bị không khả dụng trên nền tảng này';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR đã thêm $count đoạn văn bản - văn bản trang giờ có thể chọn được',
      one: 'OCR đã thêm 1 đoạn văn bản - văn bản trang giờ có thể chọn được',
      zero: 'OCR không tìm thấy văn bản nào trên các trang này',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'OCR web tải xuống mô hình ngôn ngữ-thị giác Florence-2 và chạy nó cục bộ bằng WebGPU/WASM thông qua Transformers.js. Các trang PDF vẫn ở trong trình duyệt này; chỉ các tệp mô hình được tải về khi dùng lần đầu.';

  @override
  String get ocrWebPromptTitle => 'Chạy AI OCR trong trình duyệt này?';

  @override
  String get ocrWebStart => 'Bắt đầu OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Dán';

  @override
  String get printDlgPreparing => 'Đang chuẩn bị…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Đang kết xuất trang $rendered trên $total…';
  }

  @override
  String get printDlgTitle => 'Đang in';

  @override
  String get redo => 'Làm lại';

  @override
  String get remove => 'Gỡ bỏ';

  @override
  String get rename => 'Đổi tên';

  @override
  String get reset => 'Đặt lại';

  @override
  String get save => 'Lưu';

  @override
  String get settingsAbout => 'Giới thiệu';

  @override
  String get settingsAppearance => 'Giao diện';

  @override
  String get settingsCheckNow => 'Kiểm tra ngay';

  @override
  String get settingsLanguage => 'Ngôn ngữ';

  @override
  String get settingsLanguageSystem => 'Mặc định của hệ thống';

  @override
  String get settingsCheckingForUpdates => 'Đang kiểm tra cập nhật…';

  @override
  String get settingsCouldNotOpenDownload => 'Không thể mở bản tải xuống';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Không thể mở cài đặt hệ thống';

  @override
  String get settingsDeveloperTools => 'Công cụ nhà phát triển';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Số liệu, nhật ký, chế độ kết xuất (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Tải xuống $version';
  }

  @override
  String get settingsOpenSettings => 'Mở Cài đặt';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã ghi nhớ $count',
      one: 'Đã ghi nhớ 1',
      zero: 'Không có tệp gần đây',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Tệp gần đây';

  @override
  String get settingsSetUpAsDefault => 'Thiết lập làm ứng dụng mặc định';

  @override
  String get settingsSystem => 'Hệ thống';

  @override
  String get settingsThemeDark => 'Tối';

  @override
  String get settingsThemeLight => 'Sáng';

  @override
  String get settingsThemeSystem => 'Hệ thống';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String settingsUpToDate(String version) {
    return 'Bạn đang dùng phiên bản mới nhất ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Phiên bản $version đã có sẵn (bạn đang có $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Không thể kiểm tra cập nhật. Hãy thử lại sau.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Bạn đang có $name $version.';
  }

  @override
  String get settingsUpdates => 'Cập nhật';

  @override
  String get settingsViewSource => 'Xem mã nguồn trên GitHub';

  @override
  String get undo => 'Hoàn tác';

  @override
  String get welcomeOpenPdf => 'Mở một PDF';

  @override
  String get welcomePickAgainToReopen => 'Chọn lại để mở lại';

  @override
  String get welcomeRecent => 'Gần đây';

  @override
  String get welcomeRemoveFromRecent => 'Gỡ khỏi danh sách gần đây';

  @override
  String get welcomeTapToReopen => 'Nhấn để mở lại';

  @override
  String get welcomeViewAsGrid => 'Xem dạng lưới';

  @override
  String get welcomeViewAsList => 'Xem dạng danh sách';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Cài đặt ứng dụng web, sau đó chọn nó cho các tệp PDF.',
        'windows': 'Mở cài đặt ứng dụng mặc định của Windows cho PDF.',
        'macos': 'Làm theo các bước “Always Open With” của Finder.',
        'linux':
            'Sử dụng cài đặt ứng dụng mặc định của môi trường máy tính để bàn của bạn.',
        'android': 'Chọn DartPDF khi mở PDF, sau đó nhấn Luôn luôn.',
        'ios': 'Dùng Chia sẻ hoặc Mở Trong từ Tệp để gửi PDF vào đây.',
        'other': 'Định cấu hình trình xử lý tệp PDF của hệ thống của bạn.',
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
            'Cài đặt DartPDF từ trình duyệt của bạn trước. Sau đó dùng cài đặt trình xử lý tệp của trình duyệt hoặc hệ điều hành để liên kết các tệp PDF với ứng dụng đã cài đặt.',
        'windows':
            'Cài đặt Windows sẽ mở đến Ứng dụng mặc định. Tìm kiếm “.pdf” hoặc “PDF”, chọn ứng dụng PDF hiện tại, sau đó chọn DartPDF.',
        'macos':
            'Trong Finder, chọn bất kỳ PDF nào, chọn File > Get Info, mở rộng “Open with”, chọn DartPDF, sau đó nhấp “Change All…”.',
        'linux':
            'Mở cài đặt máy tính để bàn cho Ứng dụng mặc định, hoặc nhấp chuột phải vào một PDF trong Tệp, chọn Thuộc tính, và đặt DartPDF làm mặc định cho tài liệu PDF.',
        'android':
            'Mở một PDF từ Tệp hoặc Tải xuống, chọn DartPDF trong bộ chọn ứng dụng, sau đó chọn Luôn luôn. Nếu một ứng dụng khác đã mở PDF, hãy xóa mặc định của ứng dụng đó trong Cài đặt Android trước.',
        'ios':
            'iOS không cung cấp trình chỉnh sửa PDF mặc định toàn cục. Dùng Tệp > Chia sẻ, hoặc nhấn giữ một PDF và chọn Chia sẻ/Mở Trong, sau đó chọn DartPDF.',
        'other':
            'Dùng cài đặt hệ thống cho trình xử lý tệp để liên kết tài liệu PDF với DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Đang tải xuống mô hình OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Đang tải xuống mô hình $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Đang hoàn tất OCR…';

  @override
  String get fileTypePdf => 'Tài liệu PDF';

  @override
  String get fileTypeImages => 'Hình ảnh';

  @override
  String get fileTypeStampBundle => 'Con dấu DartPDF';

  @override
  String get appSigKeyFileType => 'Khóa riêng tư RSA';

  @override
  String get appSigCertificateFileType => 'Chứng chỉ X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Chọn ít nhất một chứng chỉ X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Chứng chỉ $index không phải X.509 hợp lệ.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Khóa riêng tư không khớp với bất kỳ chứng chỉ RSA nào đã chọn.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Không hỗ trợ khóa riêng tư được mã hóa. Hãy chọn khóa RSA PKCS#1 hoặc PKCS#8 chưa mã hóa.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Khóa riêng tư không phải là khóa RSA PKCS#1 hoặc PKCS#8 chưa mã hóa.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Không tìm thấy chứng chỉ X.509 nào.';
}
