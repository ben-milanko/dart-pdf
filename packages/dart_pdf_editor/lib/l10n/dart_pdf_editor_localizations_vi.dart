// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class DartPdfEditorLocalizationsVi extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get add => 'Thêm';

  @override
  String get annotCaret => 'Dấu chèn';

  @override
  String get annotCircle => 'Hình tròn';

  @override
  String get annotFileAttachment => 'Tệp đính kèm';

  @override
  String get annotFreeText => 'Hộp văn bản';

  @override
  String get annotHighlight => 'Tô sáng';

  @override
  String get annotInk => 'Nét mực';

  @override
  String get annotLine => 'Đường thẳng';

  @override
  String get annotLink => 'Liên kết';

  @override
  String get annotPolygon => 'Đa giác';

  @override
  String get annotPolyline => 'Đường gấp khúc';

  @override
  String get annotRedact => 'Che thông tin';

  @override
  String get annotSquare => 'Hình vuông';

  @override
  String get annotSquiggly => 'Gạch lượn sóng';

  @override
  String get annotStamp => 'Con dấu';

  @override
  String get annotStrikeOut => 'Gạch ngang';

  @override
  String get annotText => 'Ghi chú';

  @override
  String get annotUnderline => 'Gạch chân';

  @override
  String get annotWidget => 'Trường biểu mẫu';

  @override
  String get apply => 'Áp dụng';

  @override
  String get bookmarkAdd => 'Thêm dấu trang';

  @override
  String get bookmarkAddChild => 'Thêm dấu trang con';

  @override
  String get bookmarkCollapse => 'Thu gọn';

  @override
  String get bookmarkDelete => 'Xóa dấu trang';

  @override
  String get bookmarkEdit => 'Chỉnh sửa dấu trang';

  @override
  String get bookmarkEmpty => 'Không có dấu trang';

  @override
  String get bookmarkExpand => 'Mở rộng';

  @override
  String get bookmarkExpandedByDefault => 'Mở rộng theo mặc định';

  @override
  String get bookmarkNoDestination => 'Không có đích đến';

  @override
  String get bookmarkPageFieldLabel => 'Trang';

  @override
  String bookmarkPageLabel(int number) {
    return 'Trang $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Dấu trang';

  @override
  String get bookmarkTitleLabel => 'Tiêu đề';

  @override
  String get bookmarkUntitled => 'Không có tiêu đề';

  @override
  String get cancel => 'Hủy';

  @override
  String get clear => 'Xóa';

  @override
  String get close => 'Đóng';

  @override
  String get colorApplyingChanges => 'Đang áp dụng các thay đổi màu…';

  @override
  String get colorColorFormat => 'Định dạng màu';

  @override
  String get colorColorTitle => 'Màu';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã chọn $count màu',
      one: 'Đã chọn $count màu',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Màu của tài liệu';

  @override
  String get colorFillColors => 'Màu tô';

  @override
  String get colorFind => 'Tìm';

  @override
  String get colorInDocument => 'Trong tài liệu';

  @override
  String get colorNoColorsFound => 'Chưa tìm thấy màu nào';

  @override
  String get colorNoPageContentColors =>
      'Không tìm thấy màu nội dung trang nào';

  @override
  String get colorPalette => 'Bảng màu';

  @override
  String get colorPickColor => 'Chọn màu';

  @override
  String get colorProcessingTitle => 'Xử lý màu';

  @override
  String get colorRecent => 'Gần đây';

  @override
  String get colorReplace => 'Thay thế';

  @override
  String get colorReplaceWithTransparent => 'Thay bằng trong suốt';

  @override
  String get colorScanning => 'Đang quét…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Đang quét $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Các trang đã chọn ($count)';
  }

  @override
  String get colorStrokeColors => 'Màu nét';

  @override
  String get colorTolerance => 'Dung sai';

  @override
  String get colorTransparent => 'Trong suốt';

  @override
  String get colorWholeDocument => 'Toàn bộ tài liệu';

  @override
  String get compareAfter => 'Sau';

  @override
  String get compareBefore => 'Trước';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thay đổi',
      one: '1 thay đổi',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thay đổi',
      one: '1 thay đổi',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(trống)';

  @override
  String get compareNextChange => 'Thay đổi tiếp theo';

  @override
  String get compareNoChanges => 'Không có thay đổi';

  @override
  String get compareNoDifferences => 'Không có khác biệt giữa hai tài liệu';

  @override
  String get compareOverlay => 'Lớp phủ';

  @override
  String comparePageHeader(int page) {
    return 'Trang $page';
  }

  @override
  String get comparePreviousChange => 'Thay đổi trước';

  @override
  String get compareSideBySide => 'Cạnh nhau';

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
  String get editorViewAuthorNameTitle => 'Tên tác giả';

  @override
  String get lineStyleDashDot => 'Gạch-chấm';

  @override
  String get lineStyleDashed => 'Gạch đứt';

  @override
  String get lineStyleDotted => 'Chấm';

  @override
  String get lineStyleSolid => 'Liền';

  @override
  String get measCalibrate => 'Hiệu chỉnh';

  @override
  String get measCalibrateScale => 'Hiệu chỉnh tỷ lệ';

  @override
  String get measDepthLabel => 'Độ sâu: ';

  @override
  String get measKindAngle => 'Góc';

  @override
  String get measKindArc => 'Cung';

  @override
  String get measKindArea => 'Diện tích';

  @override
  String get measKindCount => 'Đếm';

  @override
  String get measKindLength => 'Chiều dài';

  @override
  String get measKindNetArea => 'Diện tích thực';

  @override
  String get measKindPerimeter => 'Chu vi';

  @override
  String get measKindSlope => 'Độ dốc';

  @override
  String get measKindVolume => 'Thể tích';

  @override
  String get measLineRepresents => 'Đường bạn vẽ đại diện cho:';

  @override
  String get measMeasure => 'Đo';

  @override
  String get measSetScale => 'Đặt tỷ lệ đo';

  @override
  String get measSetScaleButton => 'Đặt tỷ lệ';

  @override
  String get measVolumeDepth => 'Độ sâu thể tích';

  @override
  String get menuAddNode => 'Thêm nút';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Áp dụng các chú thích vào các trang',
      one: 'Áp dụng chú thích vào các trang',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Áp dụng cho các trang…';

  @override
  String get menuBringToFront => 'Đưa lên trước';

  @override
  String get menuCheck => 'Đánh dấu chọn';

  @override
  String get menuChooseValue => 'Chọn giá trị…';

  @override
  String get menuClearCheck => 'Bỏ đánh dấu chọn';

  @override
  String get menuConvertToCheckBox => 'Chuyển thành hộp kiểm';

  @override
  String get menuConvertToImageButton => 'Chuyển thành nút hình ảnh';

  @override
  String get menuConvertToTextField => 'Chuyển thành trường văn bản';

  @override
  String get menuDeleteField => 'Xóa trường';

  @override
  String get menuEditValue => 'Chỉnh sửa giá trị…';

  @override
  String get menuFieldName => 'Tên trường';

  @override
  String get menuFieldValue => 'Giá trị trường';

  @override
  String get menuFlattenForm => 'Làm phẳng biểu mẫu';

  @override
  String get menuLock => 'Lock';

  @override
  String get menuUnlock => 'Unlock';

  @override
  String get menuRecolour => 'Đổi màu…';

  @override
  String get menuRemoveNode => 'Xóa nút';

  @override
  String get menuSetAsDefaultStyle => 'Đặt làm kiểu mặc định';

  @override
  String get menuRename => 'Đổi tên…';

  @override
  String get menuSelectOption => 'Chọn tùy chọn';

  @override
  String get menuSendToBack => 'Đưa xuống dưới';

  @override
  String get menuSetImage => 'Đặt hình ảnh…';

  @override
  String get menuTextStyle => 'Kiểu văn bản…';

  @override
  String get none => 'Không có';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Màu';

  @override
  String get overlayEditText => 'Chỉnh sửa văn bản';

  @override
  String get overlayFont => 'Phông chữ';

  @override
  String get overlayLarger => 'Lớn hơn';

  @override
  String get overlayMore => 'Thêm';

  @override
  String get overlayNote => 'Ghi chú';

  @override
  String get overlaySmaller => 'Nhỏ hơn';

  @override
  String get overlayStampText => 'Văn bản con dấu';

  @override
  String get overlayUnderline => 'Gạch chân';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Nhập các trang từ 1 đến $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Trang cuối không được đứng trước trang đầu.';

  @override
  String get pageRangeFrom => 'Từ';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trang',
      one: '1 trang',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Đến';

  @override
  String get panelDragToMovePanel => 'Kéo để di chuyển bảng';

  @override
  String get paste => 'Dán';

  @override
  String get propAlign => 'Căn lề';

  @override
  String get propAlignCenter => 'Căn giữa';

  @override
  String get propAlignLeft => 'Căn trái';

  @override
  String get propAlignRight => 'Căn phải';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chú thích',
      one: '$count chú thích',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Tác giả';

  @override
  String get propAutoSize => 'Tự động cỡ';

  @override
  String get propBold => 'Đậm';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Phông chữ đi kèm';

  @override
  String get propCallout => 'Chú dẫn';

  @override
  String get propCharSpacing => 'Giãn ký tự';

  @override
  String get propColor => 'Màu';

  @override
  String get propColour => 'Màu sắc';

  @override
  String get propContents => 'Nội dung';

  @override
  String get propEditsApplyToAll =>
      'Các chỉnh sửa áp dụng cho tất cả chú thích tương thích';

  @override
  String get propFieldName => 'Tên trường';

  @override
  String get propFieldTypeCheckBox => 'Hộp kiểm';

  @override
  String get propFieldTypeComboBox => 'Hộp tổ hợp';

  @override
  String get propFieldTypeImageButton => 'Nút hình ảnh';

  @override
  String get propFieldTypeListBox => 'Hộp danh sách';

  @override
  String get propFieldTypeRadioGroup => 'Nhóm nút chọn';

  @override
  String get propFieldTypeSignature => 'Chữ ký';

  @override
  String get propFieldTypeText => 'Trường văn bản';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Loại trường: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Trường không xác định';

  @override
  String get propFill => 'Tô';

  @override
  String get propFont => 'Phông chữ';

  @override
  String get propFontSubsetTooltip =>
      'Phông chữ này là tập con - chỉ có thể nhập các ký tự đã được dùng trong tài liệu.';

  @override
  String get propFontWidth => 'Chiều rộng phông chữ';

  @override
  String get propGeometryHeight => 'C';

  @override
  String get propGeometryWidth => 'R';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Nghiêng';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Ký tự hạn chế';

  @override
  String get propLineEnd => 'Đầu cuối';

  @override
  String get propLineEndingButt => 'Bằng';

  @override
  String get propLineEndingCircle => 'Hình tròn';

  @override
  String get propLineEndingClosedArrow => 'Mũi tên đặc';

  @override
  String get propLineEndingClosedArrowRev => 'Mũi tên đặc (ngược)';

  @override
  String get propLineEndingDiamond => 'Hình thoi';

  @override
  String get propLineEndingOpenArrow => 'Mũi tên hở';

  @override
  String get propLineEndingOpenArrowRev => 'Mũi tên hở (ngược)';

  @override
  String get propLineEndingSlash => 'Gạch chéo';

  @override
  String get propLineEndingSquare => 'Hình vuông';

  @override
  String get propLineSpacing => 'Giãn dòng';

  @override
  String get propLineStart => 'Đầu bắt đầu';

  @override
  String get propLineType => 'Kiểu đường';

  @override
  String get propLoadFont => 'Tải phông chữ…';

  @override
  String get propLoadFontSubtitle => 'Tệp TTF hoặc OTF';

  @override
  String get propMoreColors => 'Thêm màu…';

  @override
  String get propMultiline => 'Nhiều dòng';

  @override
  String get propNoFill => 'Không tô';

  @override
  String get propNoFontsFound => 'Không tìm thấy phông chữ';

  @override
  String get propNoOutline => 'Không viền';

  @override
  String get propOpacity => 'Độ mờ';

  @override
  String get propOutline => 'Viền';

  @override
  String get propPageLabel => 'Trang';

  @override
  String propPageNumber(int number) {
    return 'Trang $number';
  }

  @override
  String get propPropertiesTitle => 'Thuộc tính';

  @override
  String get propRecentlyUsed => 'Dùng gần đây';

  @override
  String get propScale => 'Tỷ lệ';

  @override
  String get propSearchFonts => 'Tìm phông chữ';

  @override
  String get propSectionAllFonts => 'Tất cả phông chữ';

  @override
  String get propSectionAppearance => 'Giao diện';

  @override
  String get propSectionContent => 'Nội dung';

  @override
  String get propSectionFormField => 'Trường biểu mẫu';

  @override
  String get propSectionInThisDocument => 'Trong tài liệu này';

  @override
  String get propSectionPositionSize => 'Vị trí & kích thước (pt)';

  @override
  String get propSectionSelection => 'Lựa chọn';

  @override
  String get propSectionText => 'Văn bản';

  @override
  String get propSelectAnnotationPrompt =>
      'Chọn một chú thích để xem thuộc tính của nó';

  @override
  String get propSize => 'Cỡ';

  @override
  String get propStandardPdfFont => 'Phông chữ PDF chuẩn';

  @override
  String get propStroke => 'Nét';

  @override
  String get propStyle => 'Kiểu';

  @override
  String get propSystemFont => 'Phông chữ hệ thống';

  @override
  String get propType => 'Loại';

  @override
  String get propUnderline => 'Gạch chân';

  @override
  String get propVaries => 'Khác nhau';

  @override
  String get redo => 'Làm lại';

  @override
  String get reflowNoContent => 'Không có nội dung trích xuất được';

  @override
  String reflowPageLabel(int number) {
    return 'Trang $number';
  }

  @override
  String get reflowSaveOrShare => 'Lưu hoặc chia sẻ';

  @override
  String get reflowViewFigure => 'Xem hình';

  @override
  String get remove => 'Gỡ bỏ';

  @override
  String get rename => 'Đổi tên';

  @override
  String get reset => 'Đặt lại';

  @override
  String get save => 'Lưu';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Trang $page';
  }

  @override
  String get sbarCallout => 'Chú dẫn';

  @override
  String get sbarFieldButton => 'Trường nút';

  @override
  String get sbarFieldChoice => 'Trường lựa chọn';

  @override
  String get sbarFieldGeneric => 'Trường biểu mẫu';

  @override
  String get sbarFieldSignature => 'Trường chữ ký';

  @override
  String get sbarFieldText => 'Trường văn bản';

  @override
  String get sbarStateAccepted => 'Đã chấp nhận';

  @override
  String get sbarStateCancelled => 'Đã hủy';

  @override
  String get sbarStateMarked => 'Đã đánh dấu';

  @override
  String get sbarStateRejected => 'Đã từ chối';

  @override
  String get sbarStateResolved => 'Đã giải quyết';

  @override
  String get sbarStateUnmarked => 'Chưa đánh dấu';

  @override
  String get searchAnnotations => 'Search annotations';

  @override
  String get searchClearSearch => 'Xóa tìm kiếm';

  @override
  String get searchEmptyHint =>
      'Tìm kiếm trong tài liệu để liệt kê mọi kết quả khớp tại đây';

  @override
  String get searchMatchCase => 'Khớp chữ hoa/thường';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kết quả khớp',
      one: '1 kết quả khớp',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Kết quả tiếp theo';

  @override
  String searchNoMatches(String query) {
    return 'Không có kết quả khớp cho “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Trang $page';
  }

  @override
  String get searchPreviousMatch => 'Kết quả trước';

  @override
  String get searchRegex => 'Biểu thức chính quy';

  @override
  String get searchResultsTitle => 'Kết quả tìm kiếm';

  @override
  String get searchWholeWord => 'Toàn bộ từ';

  @override
  String get shellControls => 'Điều khiển';

  @override
  String get shellDefaultAuthor => 'Tác giả mặc định…';

  @override
  String get shellHighlightFormFields => 'Làm nổi bật các trường biểu mẫu';

  @override
  String get shellKeyboardShortcutsMenu => 'Phím tắt…';

  @override
  String get shellKeyboardShortcutsTitle => 'Phím tắt';

  @override
  String get shellShortcutsSearchHint => 'Tìm phím tắt';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Không có phím tắt nào khớp “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Chọn';

  @override
  String get shellShortcutGroupMarkup => 'Đánh dấu';

  @override
  String get shellShortcutGroupDraw => 'Vẽ';

  @override
  String get shellShortcutGroupShapes => 'Hình khối';

  @override
  String get shellShortcutGroupInsert => 'Chèn';

  @override
  String get shellShortcutGroupMeasure => 'Đo';

  @override
  String get shellShortcutGroupEdit => 'Chỉnh sửa';

  @override
  String get shellNotSet => 'Chưa đặt';

  @override
  String get shellPageColor => 'Màu trang…';

  @override
  String get shellPageGrid => 'Lưới trang';

  @override
  String get shellPanelAnnotations => 'Chú thích';

  @override
  String get shellPanelBookmarks => 'Dấu trang';

  @override
  String get shellPanelPages => 'Trang';

  @override
  String get shellPanelProperties => 'Thuộc tính';

  @override
  String get shellPanelSearchResults => 'Kết quả tìm kiếm';

  @override
  String get shellPanels => 'Bảng';

  @override
  String get shellPressAKey => 'Nhấn một phím';

  @override
  String get shellPressLetterKeyHint =>
      'Nhấn một phím chữ cái, hoặc Delete để xóa.';

  @override
  String get shellReflow => 'Sắp xếp lại';

  @override
  String get shellReflowText => 'Sắp xếp lại văn bản';

  @override
  String get shellResetZoom => 'Đặt lại thu phóng';

  @override
  String get shellSectionShell => 'Khung';

  @override
  String get shellSectionView => 'Xem';

  @override
  String get shellSettings => 'Cài đặt';

  @override
  String get shellShowAnnotations => 'Hiện chú thích';

  @override
  String get shellTabHere => 'Ghép thẻ tại đây';

  @override
  String get shellUnbound => 'Chưa gán';

  @override
  String get shellZoom => 'Thu phóng';

  @override
  String sidebarByAuthor(String author) {
    return 'bởi $author';
  }

  @override
  String get sidebarCancelSelection => 'Hủy lựa chọn';

  @override
  String get sidebarClearSearch => 'Xóa tìm kiếm';

  @override
  String get sidebarDeleteSelected => 'Xóa mục đã chọn';

  @override
  String get sidebarDeleteSignature => 'Xóa chữ ký';

  @override
  String get sidebarLockAnnotation => 'Lock';

  @override
  String get sidebarUnlockAnnotation => 'Unlock';

  @override
  String get sidebarMore => 'Thêm';

  @override
  String get sidebarNoAnnotations => 'Không có chú thích';

  @override
  String get sidebarNoMatchingAnnotations => 'Không có chú thích khớp';

  @override
  String sidebarPageHeader(int number) {
    return 'Trang $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Thao tác này gỡ chữ ký số khỏi tài liệu. Bạn có thể hoàn tác việc này.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Thao tác này gỡ chữ ký số của \"$name\" khỏi tài liệu. Bạn có thể hoàn tác việc này.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Gỡ chữ ký?';

  @override
  String get sidebarReopen => 'Mở lại';

  @override
  String get sidebarReply => 'Trả lời';

  @override
  String get sidebarResolve => 'Giải quyết';

  @override
  String get sidebarSearchHint => 'Tìm chú thích';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã chọn $count',
      one: 'Đã chọn $count',
    );
    return '$_temp0';
  }

  @override
  String get sidebarSignatureChecking => 'Checking…';

  @override
  String get sidebarSignatureTrusted => 'Valid — trusted';

  @override
  String get sidebarSignatureUnverified => 'Valid — unverified';

  @override
  String get sidebarSignatureInvalid => 'Invalid';

  @override
  String sidebarSignatureSignedBy(String name) {
    return 'Signed by $name';
  }

  @override
  String sidebarSignatureSignedAt(String time) {
    return 'Signed $time';
  }

  @override
  String sidebarSignatureTrustedVia(String authority) {
    return 'Trusted via $authority';
  }

  @override
  String get sidebarSignatureUntrustedDetail =>
      'Signer is not from a trusted authority';

  @override
  String get sidebarSignatureNoAnchors =>
      'No trusted authorities are configured';

  @override
  String get sidebarSignatureModified => 'Document was changed after signing';

  @override
  String get sidebarSignatureRevoked => 'The signer\'s certificate was revoked';

  @override
  String sidebarSignatureTimestamped(String time) {
    return 'Timestamped $time';
  }

  @override
  String sidebarSignatureLevel(String level) {
    return 'PAdES $level';
  }

  @override
  String get sidebarWriteReplyHint => 'Viết câu trả lời…';

  @override
  String get sigTitle => 'Chữ ký';

  @override
  String get signIdCreate => 'Tạo';

  @override
  String get signIdEmail => 'Email (tùy chọn)';

  @override
  String get signIdName => 'Tên';

  @override
  String get signIdNameHint => 'Tên của bạn, như sẽ hiển thị trên chữ ký';

  @override
  String get signIdNameRequired => 'Nhập một tên';

  @override
  String get signIdOrganization => 'Tổ chức (tùy chọn)';

  @override
  String get signIdSelfSignedInfo =>
      'Thao tác này tạo một danh tính tự ký. Chữ ký sẽ hiển thị là \"đã ký, không rõ hiệu lực\" trong Adobe Acrobat và các trình đọc khác - giống như các ID tự ký của chính họ. Dấu tích xanh yêu cầu một CA được tin cậy công khai, có trả phí.';

  @override
  String get signIdTitle => 'Tạo danh tính ký';

  @override
  String get stampBox => 'Hộp';

  @override
  String get stampCircle => 'Hình tròn';

  @override
  String get stampCustomCaption => 'Con dấu tùy chỉnh';

  @override
  String get stampDateFormat => 'Định dạng ngày';

  @override
  String get stampDeleteComponent => 'Xóa thành phần đã chọn';

  @override
  String get stampDeleteStamp => 'Xóa con dấu';

  @override
  String get stampEditStamp => 'Chỉnh sửa con dấu';

  @override
  String get stampExport => 'Xuất…';

  @override
  String get stampFieldDate => 'Ngày';

  @override
  String get stampFieldDateTime => 'Ngày & giờ';

  @override
  String get stampFieldTime => 'Giờ';

  @override
  String get stampFieldUsername => 'Tên người dùng';

  @override
  String get stampFont => 'Phông chữ';

  @override
  String get stampFontBold => 'Đậm';

  @override
  String get stampFontItalic => 'Nghiêng';

  @override
  String get stampHeight => 'Chiều cao';

  @override
  String get stampImage => 'Hình ảnh';

  @override
  String get stampImport => 'Nhập…';

  @override
  String get stampInsertField => 'Chèn trường';

  @override
  String get stampMoreColors => 'Thêm màu…';

  @override
  String get stampNewStamp => 'Con dấu mới…';

  @override
  String get stampNewStampTitle => 'Con dấu mới';

  @override
  String get stampSelectTextToEdit => 'Chọn văn bản để chỉnh sửa';

  @override
  String get stampSelectedText => 'Văn bản đã chọn';

  @override
  String get stampSignature => 'Chữ ký';

  @override
  String get stampStamps => 'Con dấu';

  @override
  String get stampText => 'Văn bản';

  @override
  String get stampTime12Hour => '12 giờ';

  @override
  String get stampTime24Hour => '24 giờ';

  @override
  String get stampTimeFormat => 'Định dạng giờ';

  @override
  String get stampWidth => 'Chiều rộng';

  @override
  String get takeoffArea => 'Diện tích';

  @override
  String get takeoffCount => 'Đếm';

  @override
  String get takeoffEmpty => 'Chưa có phép đo nào.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nhóm',
      one: '$count nhóm',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mục',
      one: '$count mục',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Chiều dài';

  @override
  String get takeoffTitle => 'Bóc tách';

  @override
  String get tbAddInkAnnotation => 'Thêm chú thích nét mực';

  @override
  String get tbAlign => 'Căn lề';

  @override
  String get tbAlignBottom => 'Căn dưới';

  @override
  String get tbAlignHorizontalCenters => 'Căn giữa theo chiều ngang';

  @override
  String get tbAlignLeft => 'Căn trái';

  @override
  String get tbAlignRight => 'Căn phải';

  @override
  String get tbAlignTop => 'Căn trên';

  @override
  String get tbAlignVerticalCenters => 'Căn giữa theo chiều dọc';

  @override
  String get tbAnnotationsFlattened => 'Đã làm phẳng chú thích vào các trang';

  @override
  String get tbApplyRedactionsMessage =>
      'Nội dung được đánh dấu sẽ bị xóa vĩnh viễn khỏi tài liệu. Không thể hoàn tác việc này.';

  @override
  String get tbApplyRedactionsTitle => 'Áp dụng che thông tin?';

  @override
  String get tbApplyRedactionsTooltip =>
      'Áp dụng che thông tin (không thể đảo ngược)';

  @override
  String get tbAutosizeTextBox => 'Tự động cỡ hộp văn bản (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Vẽ một đường có độ dài đã biết để hiệu chỉnh tỷ lệ.';

  @override
  String get tbCharSpacing => 'Giãn ký tự';

  @override
  String get tbCheckBoxOption => 'Hộp kiểm';

  @override
  String get tbCheckMarksOnDocument => 'Dấu kiểm trên tài liệu';

  @override
  String get tbCropImage => 'Crop image';

  @override
  String get tbCroppingImage => 'Cropping image';

  @override
  String get tbCropApply => 'Apply crop';

  @override
  String get tbCropCancel => 'Cancel crop';

  @override
  String get tbCropReset => 'Reset crop';

  @override
  String get tbColorLabel => 'Màu';

  @override
  String get tbColorProcessingTooltip =>
      'Xử lý màu - tìm và thay thế màu nội dung trang';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã thay thế $count màu',
      one: 'Đã thay thế 1 màu',
      zero: 'Không tìm thấy màu khớp nào',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Chuyển thành hộp kiểm';

  @override
  String get tbConvertToImageButton => 'Chuyển thành nút hình ảnh';

  @override
  String get tbConvertToTextField => 'Chuyển thành trường văn bản';

  @override
  String get tbCornerRadius => 'Bán kính góc';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Xóa $count chú thích',
      one: 'Xóa chú thích',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Xóa phần tử';

  @override
  String get tbDeleteField => 'Xóa trường';

  @override
  String get tbDiscardDrawing => 'Bỏ bản vẽ';

  @override
  String get tbDistributeHorizontally => 'Phân bố theo chiều ngang';

  @override
  String get tbDistributeVertically => 'Phân bố theo chiều dọc';

  @override
  String get tbDrawNewSignature => 'Vẽ chữ ký mới…';

  @override
  String get tbEditAnnotationText => 'Chỉnh sửa văn bản chú thích';

  @override
  String get tbEditTextStyle => 'Chỉnh sửa văn bản & kiểu';

  @override
  String get tbElement => 'Phần tử';

  @override
  String get tbEraserSize => 'Cỡ tẩy';

  @override
  String get tbFieldActions => 'Hành động trường';

  @override
  String get tbFieldName => 'Tên trường';

  @override
  String tbFieldNamed(String name) {
    return 'Trường: $name';
  }

  @override
  String get tbFieldValue => 'Giá trị trường';

  @override
  String get tbFill => 'Tô';

  @override
  String get tbFingerDraws => 'Ngón tay vẽ - nhấn để nó cuộn thay vào đó';

  @override
  String get tbFingerScrolls => 'Ngón tay cuộn (bút vẽ) - nhấn để nó vẽ';

  @override
  String get tbFlattenAnnotationsTooltip => 'Làm phẳng chú thích vào các trang';

  @override
  String get tbFlattenForm => 'Làm phẳng biểu mẫu';

  @override
  String get tbFlattenFormBakeValues =>
      'Làm phẳng biểu mẫu - đưa giá trị vào các trang';

  @override
  String get tbFlattenLabel => 'Làm phẳng';

  @override
  String get tbFont => 'Phông chữ';

  @override
  String get tbFontSize => 'Cỡ phông chữ';

  @override
  String get tbFontWidth => 'Chiều rộng phông chữ';

  @override
  String get tbFormFieldsFlattened =>
      'Đã làm phẳng các trường biểu mẫu vào các trang';

  @override
  String get tbGroupDraw => 'Vẽ';

  @override
  String get tbGroupEdit => 'Chỉnh sửa';

  @override
  String get tbGroupInsert => 'Chèn';

  @override
  String get tbGroupMarkup => 'Đánh dấu';

  @override
  String get tbGroupMeasure => 'Đo';

  @override
  String get tbGroupSelect => 'Chọn';

  @override
  String get tbGroupShapes => 'Hình khối';

  @override
  String get tbImageButtonOption => 'Nút hình ảnh';

  @override
  String get tbLineEnd => 'Đầu cuối';

  @override
  String get tbLineSpacing => 'Giãn dòng';

  @override
  String get tbLineStart => 'Đầu bắt đầu';

  @override
  String get tbLineType => 'Kiểu đường';

  @override
  String get tbManageStamps => 'Quản lý con dấu…';

  @override
  String get tbMarkupHighlight => 'Tô sáng';

  @override
  String get tbMarkupHighlightTip => 'Tô sáng vùng chọn';

  @override
  String get tbMarkupSquiggly => 'Gạch lượn sóng';

  @override
  String get tbMarkupSquigglyTip => 'Gạch lượn sóng vùng chọn';

  @override
  String get tbMarkupStrikeOut => 'Gạch ngang';

  @override
  String get tbMarkupStrikeOutTip => 'Gạch ngang vùng chọn';

  @override
  String get tbMarkupUnderline => 'Gạch chân';

  @override
  String get tbMarkupUnderlineTip => 'Gạch chân vùng chọn';

  @override
  String get tbMoreColors => 'Thêm màu…';

  @override
  String get tbNameArrow => 'Mũi tên';

  @override
  String get tbNameCallout => 'Chú dẫn';

  @override
  String get tbNameCloudPolygon => 'Đa giác đám mây';

  @override
  String get tbNameCount => 'Đếm';

  @override
  String get tbNameDigitalSignature => 'Chữ ký số';

  @override
  String get tbNameDraw => 'Vẽ';

  @override
  String get tbNameEllipse => 'Hình elip';

  @override
  String get tbNameEraser => 'Tẩy nét mực';

  @override
  String get tbNameHighlight => 'Tô sáng';

  @override
  String get tbNameImage => 'Hình ảnh';

  @override
  String get tbNameLine => 'Đường thẳng';

  @override
  String get tbNameMeasureAngle => 'Đo góc';

  @override
  String get tbNameMeasureArc => 'Đo chiều dài cung';

  @override
  String get tbNameMeasureArea => 'Đo diện tích';

  @override
  String get tbNameMeasureDistance => 'Đo khoảng cách';

  @override
  String get tbNameMeasurePerimeter => 'Đo chu vi';

  @override
  String get tbNameMeasureSlope => 'Đo độ dốc (lên/ngang)';

  @override
  String get tbNameMeasureVolume => 'Đo thể tích (diện tích × độ sâu)';

  @override
  String get tbNameNote => 'Ghi chú';

  @override
  String get tbNamePolygon => 'Đa giác';

  @override
  String get tbNamePolyline => 'Đường gấp khúc';

  @override
  String get tbNameRectangle => 'Hình chữ nhật';

  @override
  String get tbNameSelect => 'Chọn';

  @override
  String get tbNameSignature => 'Chữ ký';

  @override
  String get tbNameStamp => 'Con dấu';

  @override
  String get tbNameTextBox => 'Hộp văn bản';

  @override
  String get tbNewFieldType => 'Loại trường mới - kéo trên một trang để thêm';

  @override
  String get tbNoAnnotationsToFlatten => 'Không có chú thích nào để làm phẳng';

  @override
  String get tbNoCustomStamps => 'Không có con dấu tùy chỉnh';

  @override
  String get tbNoFormFieldsToFlatten =>
      'Không có trường biểu mẫu nào để làm phẳng';

  @override
  String get tbNoRedactionsToApply => 'Không có che thông tin nào để áp dụng';

  @override
  String get tbNoteTitle => 'Ghi chú';

  @override
  String get tbOpacity => 'Độ mờ';

  @override
  String get tbOutline => 'Viền';

  @override
  String get tbPatternScale => 'Tỷ lệ mẫu';

  @override
  String get tbPickColorFromPage => 'Chọn màu từ trang';

  @override
  String get tbRedactionsApplied => 'Đã áp dụng che thông tin';

  @override
  String get tbRedoShortcut => 'Làm lại (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Không thể sắp xếp lại - đây không phải là đoạn văn một cột mà công cụ này có thể dàn lại. Hãy thử Thay thế văn bản.';

  @override
  String get tbReflowParagraph => 'Sắp xếp lại đoạn văn';

  @override
  String get tbRenameField => 'Đổi tên trường';

  @override
  String get tbRenameFieldEllipsis => 'Đổi tên trường…';

  @override
  String get tbReplaceImage => 'Thay thế hình ảnh';

  @override
  String get tbReplaceImageFailed => 'Không thể thay thế hình ảnh';

  @override
  String get tbReplaceText => 'Thay thế văn bản';

  @override
  String get tbSaveImage => 'Lưu hình ảnh';

  @override
  String get tbSaveShortcut => 'Lưu… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Tỷ lệ';

  @override
  String get tbSelectTextForMarkup => 'Chọn văn bản để dùng đánh dấu';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã chọn $count',
      one: 'Lựa chọn',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Đặt…';

  @override
  String get tbStamp => 'Con dấu';

  @override
  String get tbStampText => 'Văn bản con dấu';

  @override
  String get tbStrokeOpacityFont => 'Nét, độ mờ, phông chữ';

  @override
  String get tbStrokeWidthLabel => 'Độ rộng nét';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Nét $width';
  }

  @override
  String get tbStyle => 'Kiểu';

  @override
  String get tbTakeoffTotals => 'Tổng bóc tách';

  @override
  String get tbTextBorder => 'Viền văn bản';

  @override
  String get tbTextColour => 'Màu văn bản';

  @override
  String get tbTextFieldOption => 'Trường văn bản';

  @override
  String get tbTextFill => 'Tô văn bản';

  @override
  String get tbTextStyleEllipsis => 'Kiểu văn bản…';

  @override
  String get tbTextTitle => 'Văn bản';

  @override
  String get tbTipCallout => 'Chú dẫn - kéo từ điểm đến nơi đặt hộp';

  @override
  String get tbTipContent => 'Chỉnh sửa nội dung trang';

  @override
  String get tbTipCount => 'Đếm - nhấn để thả dấu kiểm và đếm chúng';

  @override
  String get tbTipDigitalSignature => 'Chữ ký số - kéo một hộp để đặt và ký';

  @override
  String get tbTipForm =>
      'Trường biểu mẫu - nhấn để chọn, nhấn đúp để điền, kéo để thêm';

  @override
  String get tbTipHighlightDraw => 'Tô sáng - vẽ tự do';

  @override
  String get tbTipImage => 'Hình ảnh - nhấn để đặt, hoặc kéo ra một hộp';

  @override
  String get tbTipMeasureAngle => 'Đo góc - nhấp ba điểm';

  @override
  String get tbTipMeasureArc => 'Đo chiều dài cung - nhấp ba điểm';

  @override
  String get tbTipRedact => 'Che thông tin - kéo một vùng, rồi áp dụng';

  @override
  String get tbTipSignature => 'Chữ ký - nhấn một trang để đặt nó';

  @override
  String get tbTipSnapshot =>
      'Ảnh chụp - kéo một vùng để chụp (dán lại dưới dạng vector)';

  @override
  String get tbToolContent => 'Nội dung';

  @override
  String get tbToolForm => 'Biểu mẫu';

  @override
  String get tbToolRedact => 'Che thông tin';

  @override
  String get tbToolSnapshot => 'Ảnh chụp';

  @override
  String get tbTools => 'Công cụ';

  @override
  String get tbTotals => 'Tổng';

  @override
  String get tbTypeTextEachTime => 'Nhập văn bản mỗi lần';

  @override
  String get tbUnderline => 'Gạch chân';

  @override
  String get tbUndoShortcut => 'Hoàn tác (⌘Z)';

  @override
  String get textStyleFont => 'Phông chữ';

  @override
  String get textStyleFontSize => 'Cỡ phông chữ';

  @override
  String get textStyleKeep => 'giữ';

  @override
  String get textStyleStyle => 'Kiểu';

  @override
  String get textStyleText => 'Văn bản';

  @override
  String get textStyleTextFill => 'Tô văn bản';

  @override
  String get textStyleTitle => 'Chỉnh sửa văn bản & kiểu';

  @override
  String get thumbAddPage => 'Thêm trang';

  @override
  String get thumbClearSelection => 'Xóa lựa chọn';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sao chép $count trang',
      one: 'Sao chép trang',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Sao chép các trang đã chọn';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cắt $count trang',
      one: 'Cắt trang',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Cắt các trang đã chọn';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Xóa $count trang',
      one: 'Xóa trang',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Xóa các trang đã chọn';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nhân bản $count trang',
      one: 'Nhân bản trang',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Xuất các trang…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Xuất $count trang…',
      one: 'Xuất trang…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Xuất các trang đã chọn';

  @override
  String get thumbInsertBlankAfter => 'Chèn trang trống sau';

  @override
  String get thumbInsertBlankBefore => 'Chèn trang trống trước';

  @override
  String get thumbInsertFileFailed => 'Không thể chèn tệp đó.';

  @override
  String get thumbInsertPdf => 'Chèn PDF…';

  @override
  String get thumbPageActions => 'Hành động trang';

  @override
  String thumbPageNumber(int number) {
    return 'Trang $number';
  }

  @override
  String get thumbPages => 'Trang';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dán $count trang',
      one: 'Dán trang',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Xoay 180°';

  @override
  String get thumbRotateLeft => 'Xoay trái';

  @override
  String get thumbRotatePageRight => 'Xoay trang phải';

  @override
  String get thumbRotateRight => 'Xoay phải';

  @override
  String get thumbRotateSelectedLeft => 'Xoay các trang đã chọn sang trái';

  @override
  String get thumbRotateSelectedRight => 'Xoay các trang đã chọn sang phải';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Đã chọn $count',
      one: 'Đã chọn $count',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Hoàn tác';

  @override
  String get viewerEditFontUnsafe =>
      'Không thể chỉnh sửa an toàn phông chữ hoặc mã hóa của PDF này.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Việc chỉnh sửa yêu cầu một lựa chọn trên một trang.';

  @override
  String get viewerEditNotEditableRun =>
      'Lựa chọn này không phải là một chuỗi văn bản nội dung trang có thể chỉnh sửa.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Phông chữ PDF này có thể nhập lại, nhưng không thể thay đổi kiểu của nó.';

  @override
  String get viewerEditTextStyle => 'Chỉnh sửa văn bản & kiểu';

  @override
  String get viewerMarkup => 'Đánh dấu';

  @override
  String get viewerMarkupHighlight => 'Tô sáng';

  @override
  String get viewerMarkupSquiggly => 'Gạch lượn sóng';

  @override
  String get viewerMarkupStrikeOut => 'Gạch ngang';

  @override
  String get viewerMarkupUnderline => 'Gạch chân';

  @override
  String get viewerSelectAll => 'Chọn tất cả';
}
