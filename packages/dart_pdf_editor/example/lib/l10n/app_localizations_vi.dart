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
  String exActionJavaScript(String script) {
    return 'JavaScript được chuyển tới ứng dụng: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Liên kết: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Hành động có tên: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Loại hành động không được xử lý: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Đã sao chép văn bản chú thích';

  @override
  String get exApiKeyHelper => 'Được gửi dưới dạng Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Khóa API / mã thông báo (tùy chọn)';

  @override
  String get exAppMenuTooltip => 'Menu DartPDF';

  @override
  String get exClearRecentFiles => 'Xóa tệp gần đây';

  @override
  String get exCloseTab => 'Đóng thẻ';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'So sánh: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'So sánh với PDF khác…';

  @override
  String get exCopiedToClipboard => 'Đã sao chép vào bảng nhớ tạm';

  @override
  String get exCopySelectedText => 'Sao chép văn bản đã chọn (⌘C)';

  @override
  String get exCopyText => 'Sao chép văn bản';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Không thể mở $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Không thể mở $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Không thể mở $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Không thể mở $uri\n$error\n\nTrên web, đây thường là hạn chế CORS: máy chủ phải gửi Access-Control-Allow-Origin và hiển thị các tiêu đề Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Không thể mở lại $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Không thể mở lại $title - bản sao đã lưu không còn khả dụng.';
  }

  @override
  String get exDemoNoteHint =>
      'Nhập vào đây - hộp văn bản này nổi phía trên trang';

  @override
  String get exDiagnosticsCopied =>
      'Đã sao chép thông tin chẩn đoán vào bảng nhớ tạm';

  @override
  String exDownloaded(String name) {
    return 'Đã tải xuống $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Đã tải xuống $name - dán lại vào PDF bằng Ctrl+V';
  }

  @override
  String get exExport => 'Xuất';

  @override
  String exExportFailed(String error) {
    return 'Xuất không thành công: $error';
  }

  @override
  String get exExportPageImageMenu => 'Xuất trang dưới dạng hình ảnh…';

  @override
  String get exExportPageImageTitle => 'Xuất trang dưới dạng hình ảnh';

  @override
  String get exFeatureShowcase => 'Trình diễn tính năng';

  @override
  String get exFormat => 'Định dạng';

  @override
  String get exHide => 'Ẩn';

  @override
  String get exHorizontalLayout => 'Bố cục trang ngang';

  @override
  String get exHowToSetupOcr => 'Cách thiết lập máy chủ OCR';

  @override
  String get exModelName => 'Tên mô hình';

  @override
  String get exNoMessage => 'Không có thông báo';

  @override
  String get exNoRecentFiles => 'Không có tệp gần đây';

  @override
  String exNotAValidUrl(String url) {
    return 'URL không hợp lệ:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR đã thêm $count đoạn văn bản - văn bản trang giờ có thể chọn được',
      one: 'OCR đã thêm 1 đoạn văn bản - văn bản trang giờ có thể chọn được',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Thêm một lớp văn bản có thể chọn và tìm kiếm lên các trang được quét bằng mô hình OCR ngôn ngữ-thị giác do bạn tự lưu trữ (dots.ocr trên vLLM, hoặc bất kỳ điểm cuối OCR nào tương thích với OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR không thành công: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Mở';

  @override
  String get exOpenDocumentBeforeOcr => 'Mở một tài liệu trước khi chạy OCR';

  @override
  String get exOpenDocumentFirst => 'Mở một tài liệu trước';

  @override
  String get exOpenFromUrl => 'Mở từ URL…';

  @override
  String get exOpenFromUrlTitle => 'Mở từ URL';

  @override
  String get exOpenInNewTab => 'Mở PDF trong thẻ mới';

  @override
  String get exOpenInteractiveDemo => 'Mở bản demo tương tác';

  @override
  String get exOpenPdf => 'Mở một PDF…';

  @override
  String get exOpenPdfButton => 'Mở một PDF';

  @override
  String get exOpenRecent => 'Mở gần đây';

  @override
  String get exOpenUrlDescription =>
      'Truyền phát PDF qua các yêu cầu HTTP Range thông qua PdfHttpByteSource, chỉ tải những gì trình phân tích cần và chuyển sang tải xuống toàn bộ khi máy chủ không hỗ trợ range.';

  @override
  String get exOpeningDocument => 'Đang mở tài liệu';

  @override
  String get exOpeningPdf => 'Đang mở PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Đang mở $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL PDF';

  @override
  String get exPerformanceAuto => 'Hiệu suất: Tự động';

  @override
  String get exPreparing => 'Đang chuẩn bị…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor trên pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Đang nhận dạng trang $current trên $count…';
  }

  @override
  String get exResolution => 'Độ phân giải';

  @override
  String get exRunOcr => 'Chạy OCR';

  @override
  String get exSaveAs => 'Lưu thành…';

  @override
  String exSaveFailed(String error) {
    return 'Lưu không thành công: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Đã lưu $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Đã lưu $name - dán lại vào PDF bằng ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Đã lưu vào $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Bản demo API chỉ báo cuộn';

  @override
  String get exServiceEndpoint => 'Điểm cuối dịch vụ';

  @override
  String get exShow => 'Hiện';

  @override
  String get exSingleWorker => 'Một worker';

  @override
  String get exSupplyFeedback => 'Gửi phản hồi…';

  @override
  String get exSwitchToEdit => 'Chuyển sang chế độ chỉnh sửa';

  @override
  String get exSwitchToReadOnly => 'Chuyển sang chỉ đọc';

  @override
  String get exThemeDark => 'Giao diện: tối - chuyển sang hệ thống';

  @override
  String get exThemeLight => 'Giao diện: sáng - chuyển sang tối';

  @override
  String get exThemeSystem => 'Giao diện: hệ thống - chuyển sang sáng';

  @override
  String get exTryDemo => 'Thử bản demo tương tác';

  @override
  String get exWelcomeScreen => 'Màn hình chào mừng';

  @override
  String get exUntitled => 'Không có tiêu đề';

  @override
  String get exVerticalLayout => 'Bố cục trang dọc';

  @override
  String get exViewSource => 'Xem mã nguồn trên GitHub';

  @override
  String get exWorkerAuto => 'Tự động';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hiệu suất: $count worker',
      one: 'Hiệu suất: một worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count worker';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Đính kèm thông tin chẩn đoán này vào báo cáo';

  @override
  String get feedbackClearLog => 'Xóa nhật ký';

  @override
  String get feedbackCopyDiagnostics => 'Sao chép thông tin chẩn đoán';

  @override
  String get feedbackDiagnosticsNotice =>
      'Biểu mẫu phản hồi sẽ mở trong trình duyệt của bạn. Thông tin chẩn đoán bên dưới chỉ được thu thập trên thiết bị này và được đính kèm để giúp tái hiện sự cố. Hãy xem lại trước - đừng bao gồm bất kỳ điều gì bạn muốn giữ riêng tư.';

  @override
  String get feedbackOpenForm => 'Mở biểu mẫu phản hồi';

  @override
  String get feedbackTitle => 'Gửi phản hồi';

  @override
  String get none => 'Không có';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Dán';

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
  String get scrollDemoNextPage => 'Trang tiếp theo';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Trang $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Trang trước';

  @override
  String get scrollDemoSwitchHorizontal => 'Chuyển sang bố cục ngang';

  @override
  String get scrollDemoSwitchVertical => 'Chuyển sang bố cục dọc';

  @override
  String get scrollDemoTitle => 'API chỉ báo cuộn';

  @override
  String get undo => 'Hoàn tác';

  @override
  String get exFileTypePdf => 'Tài liệu PDF';

  @override
  String get exFileTypeImages => 'Hình ảnh';

  @override
  String get exFileTypeFonts => 'Phông chữ';
}
