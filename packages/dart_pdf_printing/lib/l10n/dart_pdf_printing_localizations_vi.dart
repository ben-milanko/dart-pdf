// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class DartPdfPrintingLocalizationsVi extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get cancel => 'Hủy';

  @override
  String get printDlgPreparing => 'Đang chuẩn bị…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Đang kết xuất trang $rendered trên $total…';
  }

  @override
  String get printDlgTitle => 'Đang in';

  @override
  String get printPreviewAll => 'Tất cả';

  @override
  String get printPreviewCurrent => 'Hiện tại';

  @override
  String get printPreviewNextPage => 'Trang tiếp theo';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Trang $page trên $total';
  }

  @override
  String get printPreviewPreviousPage => 'Trang trước';

  @override
  String get printPreviewPrint => 'In';

  @override
  String get printPreviewRange => 'Phạm vi';

  @override
  String printPreviewRangeError(int total) {
    return 'Nhập phạm vi trang từ 1 đến $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Số trang sẽ in: $count';
  }

  @override
  String get printPreviewTitle => 'Xem trước khi in';

  @override
  String get printPreviewUnavailable => 'Không có bản xem trước';

  @override
  String get printOptionsPrinter => 'Máy in';

  @override
  String get printOptionsNativePrinter =>
      'Trong hộp thoại in của hệ thống tiếp theo, hãy chọn máy in, khay giấy, màu, chế độ in hai mặt và thuộc tính thiết bị. Giữ tỷ lệ ở 100% và số bản sao là 1 để sử dụng bố cục hiển thị ở đây.';

  @override
  String get printOptionsPages => 'Trang';

  @override
  String get printOptionsSelected => 'Đã chọn';

  @override
  String get printOptionsPageRange => 'Trang (ví dụ: 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Thêm tệp…';

  @override
  String get printOptionsAddFailed => 'Không thể thêm các tệp đã chọn.';

  @override
  String get printOptionsGetWindow => 'Chọn vùng';

  @override
  String get printOptionsClearWindow => 'Xóa vùng chọn';

  @override
  String get printOptionsWindowHint =>
      'Kéo một hình chữ nhật trên trang gốc này để chọn vùng cần in.';

  @override
  String get printOptionsPaper => 'Giấy';

  @override
  String get printOptionsPaperSize => 'Khổ giấy';

  @override
  String get printOptionsPageSize => 'Dùng kích thước trang của tài liệu';

  @override
  String get printOptionsOrientation => 'Hướng giấy';

  @override
  String get printOptionsAuto => 'Tự động';

  @override
  String get printOptionsPortrait => 'Dọc';

  @override
  String get printOptionsLandscape => 'Ngang';

  @override
  String get printOptionsCopies => 'Bản sao';

  @override
  String get printOptionsCollate => 'In từng bộ';

  @override
  String get printOptionsReverse => 'Đảo thứ tự trang';

  @override
  String get printOptionsLayout => 'Bố cục trang';

  @override
  String get printOptionsScaling => 'Co giãn trang';

  @override
  String get printOptionsScaleNone => 'Không (kích thước thực)';

  @override
  String get printOptionsFitPaper => 'Vừa khổ giấy';

  @override
  String get printOptionsReducePaper => 'Thu nhỏ cho vừa khổ giấy';

  @override
  String get printOptionsFitMargins => 'Vừa trong lề';

  @override
  String get printOptionsReduceMargins => 'Thu nhỏ cho vừa trong lề';

  @override
  String get printOptionsCustomScale => 'Tỷ lệ tùy chỉnh';

  @override
  String get printOptionsMultiple => 'Nhiều trang trên một tờ';

  @override
  String get printOptionsScalePercent => 'Tỷ lệ (%)';

  @override
  String get printOptionsMargin => 'Lề (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Số trang mỗi tờ';

  @override
  String get printOptionsPageOrder => 'Thứ tự trang';

  @override
  String get printOptionsHorizontal => 'Theo chiều ngang';

  @override
  String get printOptionsHorizontalReverse => 'Theo chiều ngang đảo ngược';

  @override
  String get printOptionsVertical => 'Theo chiều dọc';

  @override
  String get printOptionsVerticalReverse => 'Theo chiều dọc đảo ngược';

  @override
  String get printOptionsBorder => 'In viền trang';

  @override
  String get printOptionsRotation => 'Xoay (theo chiều kim đồng hồ)';

  @override
  String get printOptionsNoRotation => 'Không';

  @override
  String get printOptionsCenter => 'Căn giữa trên giấy';

  @override
  String get printOptionsOffsetX => 'Dịch sang phải (pt)';

  @override
  String get printOptionsOffsetY => 'Dịch xuống (pt)';

  @override
  String get printOptionsContents => 'Nội dung cần in';

  @override
  String get printOptionsDocumentAndMarkups => 'Tài liệu và chú thích';

  @override
  String get printOptionsDocumentOnly => 'Chỉ tài liệu';

  @override
  String get printOptionsMarkupsOnly => 'Chỉ chú thích';

  @override
  String get printOptionsDimPage => 'Làm nhạt nội dung trang';

  @override
  String get printOptionsDimMarkups => 'Làm nhạt chú thích';

  @override
  String get printOptionsHyperlinks => 'In siêu liên kết hiển thị';

  @override
  String get printOptionsDefaults => 'Mặc định';

  @override
  String get printOptionsInvalidNumber => 'Nhập số hợp lệ trước khi in.';

  @override
  String get printOptionsInvalidValue => 'Giá trị không hợp lệ';

  @override
  String get printOptionsMarginGuide =>
      'Các đường màu đỏ thể hiện lề và sẽ không được in.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Vùng: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Trang gốc: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Tờ: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Tờ $sheet / $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Không thể chuẩn bị bố cục này. Hãy kiểm tra khổ giấy, lề và tỷ lệ.';

  @override
  String get printOptionsChoosePrinter => 'Chọn máy in';

  @override
  String get printOptionsNoPrinters =>
      'Chưa cài đặt máy in nào. Thêm máy in trong Cài đặt Windows rồi thử lại.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Máy in đã lưu “$printer” không khả dụng. Chọn máy in để tiếp tục.';
  }

  @override
  String get printOptionsPrinterError =>
      'Không thể tải cài đặt máy in. Kiểm tra kết nối máy in rồi thử lại.';

  @override
  String get printOptionsRetry => 'Thử lại';

  @override
  String get printOptionsColor => 'Màu';

  @override
  String get printOptionsGrayscale => 'Đen trắng';

  @override
  String get printOptionsDuplex => 'In hai mặt';

  @override
  String get printOptionsSimplex => 'Một mặt';

  @override
  String get printOptionsLongEdge => 'Lật theo cạnh dài';

  @override
  String get printOptionsShortEdge => 'Lật theo cạnh ngắn';

  @override
  String get printOptionsTray => 'Khay giấy';

  @override
  String get printOptionsDefaultTray => 'Mặc định của máy in';

  @override
  String get printOptionsProperties => 'Thuộc tính máy in…';

  @override
  String get printOptionsDirectPrinter =>
      'In sẽ gửi lệnh in này trực tiếp đến máy in đã chọn.';

  @override
  String get printOptionsPropertiesError => 'Không thể mở thuộc tính máy in.';

  @override
  String get printOptionsLoadingPrinters => 'Đang tải máy in…';
}
