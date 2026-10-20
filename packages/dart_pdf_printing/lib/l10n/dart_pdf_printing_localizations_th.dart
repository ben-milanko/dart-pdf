// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class DartPdfPrintingLocalizationsTh extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get printDlgPreparing => 'กำลังเตรียม…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'กำลังเรนเดอร์หน้า $rendered จาก $total…';
  }

  @override
  String get printDlgTitle => 'กำลังพิมพ์';

  @override
  String get printPreviewAll => 'ทั้งหมด';

  @override
  String get printPreviewCurrent => 'ปัจจุบัน';

  @override
  String get printPreviewNextPage => 'หน้าถัดไป';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'หน้า $page จาก $total';
  }

  @override
  String get printPreviewPreviousPage => 'หน้าก่อนหน้า';

  @override
  String get printPreviewPrint => 'พิมพ์';

  @override
  String get printPreviewRange => 'ช่วง';

  @override
  String printPreviewRangeError(int total) {
    return 'ป้อนช่วงหน้าระหว่าง 1 ถึง $total';
  }

  @override
  String printPreviewSelection(int count) {
    return 'จำนวนหน้าที่จะพิมพ์: $count';
  }

  @override
  String get printPreviewTitle => 'ตัวอย่างก่อนพิมพ์';

  @override
  String get printPreviewUnavailable => 'ไม่มีตัวอย่าง';

  @override
  String get printOptionsPrinter => 'เครื่องพิมพ์';

  @override
  String get printOptionsNativePrinter =>
      'เลือกเครื่องพิมพ์ ถาดกระดาษ สี การพิมพ์สองหน้า และคุณสมบัติอุปกรณ์ในกล่องโต้ตอบการพิมพ์ของระบบที่จะแสดงถัดไป คงมาตราส่วนไว้ที่ 100% และจำนวนสำเนาไว้ที่ 1 เพื่อใช้เค้าโครงที่แสดงที่นี่';

  @override
  String get printOptionsPages => 'หน้า';

  @override
  String get printOptionsSelected => 'ที่เลือก';

  @override
  String get printOptionsPageRange => 'หน้า (ตัวอย่างเช่น 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'เพิ่มไฟล์…';

  @override
  String get printOptionsAddFailed => 'ไม่สามารถเพิ่มไฟล์ที่เลือกได้';

  @override
  String get printOptionsGetWindow => 'เลือกพื้นที่';

  @override
  String get printOptionsClearWindow => 'ล้างพื้นที่';

  @override
  String get printOptionsWindowHint =>
      'ลากกรอบสี่เหลี่ยมบนหน้าต้นฉบับนี้เพื่อเลือกพื้นที่ที่จะพิมพ์';

  @override
  String get printOptionsPaper => 'กระดาษ';

  @override
  String get printOptionsPaperSize => 'ขนาดกระดาษ';

  @override
  String get printOptionsPageSize => 'ใช้ขนาดหน้าของเอกสาร';

  @override
  String get printOptionsOrientation => 'การวางแนว';

  @override
  String get printOptionsAuto => 'อัตโนมัติ';

  @override
  String get printOptionsPortrait => 'แนวตั้ง';

  @override
  String get printOptionsLandscape => 'แนวนอน';

  @override
  String get printOptionsCopies => 'สำเนา';

  @override
  String get printOptionsCollate => 'เรียงชุดสำเนา';

  @override
  String get printOptionsReverse => 'ย้อนลำดับหน้า';

  @override
  String get printOptionsLayout => 'เค้าโครงหน้า';

  @override
  String get printOptionsScaling => 'การปรับขนาดหน้า';

  @override
  String get printOptionsScaleNone => 'ไม่ปรับ (ขนาดจริง)';

  @override
  String get printOptionsFitPaper => 'ปรับให้พอดีกระดาษ';

  @override
  String get printOptionsReducePaper => 'ย่อให้พอดีกระดาษ';

  @override
  String get printOptionsFitMargins => 'ปรับให้พอดีภายในระยะขอบ';

  @override
  String get printOptionsReduceMargins => 'ย่อให้พอดีภายในระยะขอบ';

  @override
  String get printOptionsCustomScale => 'มาตราส่วนกำหนดเอง';

  @override
  String get printOptionsMultiple => 'หลายหน้าต่อแผ่น';

  @override
  String get printOptionsScalePercent => 'มาตราส่วน (%)';

  @override
  String get printOptionsMargin => 'ระยะขอบ (pt)';

  @override
  String get printOptionsPagesPerSheet => 'จำนวนหน้าต่อแผ่น';

  @override
  String get printOptionsPageOrder => 'ลำดับหน้า';

  @override
  String get printOptionsHorizontal => 'แนวนอน';

  @override
  String get printOptionsHorizontalReverse => 'แนวนอนย้อนลำดับ';

  @override
  String get printOptionsVertical => 'แนวตั้ง';

  @override
  String get printOptionsVerticalReverse => 'แนวตั้งย้อนลำดับ';

  @override
  String get printOptionsBorder => 'พิมพ์กรอบหน้า';

  @override
  String get printOptionsRotation => 'การหมุน (ตามเข็มนาฬิกา)';

  @override
  String get printOptionsNoRotation => 'ไม่หมุน';

  @override
  String get printOptionsCenter => 'จัดกึ่งกลางกระดาษ';

  @override
  String get printOptionsOffsetX => 'เลื่อนไปทางขวา (pt)';

  @override
  String get printOptionsOffsetY => 'เลื่อนลง (pt)';

  @override
  String get printOptionsContents => 'เนื้อหาที่จะพิมพ์';

  @override
  String get printOptionsDocumentAndMarkups => 'เอกสารและคำอธิบายประกอบ';

  @override
  String get printOptionsDocumentOnly => 'เฉพาะเอกสาร';

  @override
  String get printOptionsMarkupsOnly => 'เฉพาะคำอธิบายประกอบ';

  @override
  String get printOptionsDimPage => 'พิมพ์เนื้อหาหน้าให้จางลง';

  @override
  String get printOptionsDimMarkups => 'พิมพ์คำอธิบายประกอบให้จางลง';

  @override
  String get printOptionsHyperlinks => 'พิมพ์ไฮเปอร์ลิงก์ที่มองเห็น';

  @override
  String get printOptionsDefaults => 'ค่าเริ่มต้น';

  @override
  String get printOptionsInvalidNumber => 'ป้อนตัวเลขที่ถูกต้องก่อนพิมพ์';

  @override
  String get printOptionsInvalidValue => 'ค่าไม่ถูกต้อง';

  @override
  String get printOptionsMarginGuide => 'เส้นสีแดงแสดงระยะขอบและจะไม่ถูกพิมพ์';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'พื้นที่: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'ต้นฉบับ: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'แผ่น: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'แผ่นที่ $sheet จาก $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'ไม่สามารถเตรียมเค้าโครงนี้ได้ โปรดตรวจสอบขนาดกระดาษ ระยะขอบ และมาตราส่วน';

  @override
  String get printOptionsChoosePrinter => 'เลือกเครื่องพิมพ์';

  @override
  String get printOptionsNoPrinters =>
      'ยังไม่ได้ติดตั้งเครื่องพิมพ์ เพิ่มเครื่องพิมพ์ในการตั้งค่า Windows แล้วลองอีกครั้ง';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'เครื่องพิมพ์ที่บันทึกไว้ “$printer” ไม่พร้อมใช้งาน เลือกเครื่องพิมพ์เพื่อดำเนินการต่อ';
  }

  @override
  String get printOptionsPrinterError =>
      'ไม่สามารถโหลดการตั้งค่าเครื่องพิมพ์ได้ ตรวจสอบการเชื่อมต่อเครื่องพิมพ์แล้วลองอีกครั้ง';

  @override
  String get printOptionsRetry => 'ลองอีกครั้ง';

  @override
  String get printOptionsColor => 'สี';

  @override
  String get printOptionsGrayscale => 'ขาวดำ';

  @override
  String get printOptionsDuplex => 'พิมพ์สองหน้า';

  @override
  String get printOptionsSimplex => 'หน้าเดียว';

  @override
  String get printOptionsLongEdge => 'พลิกด้านยาว';

  @override
  String get printOptionsShortEdge => 'พลิกด้านสั้น';

  @override
  String get printOptionsTray => 'ถาดกระดาษ';

  @override
  String get printOptionsDefaultTray => 'ค่าเริ่มต้นของเครื่องพิมพ์';

  @override
  String get printOptionsProperties => 'คุณสมบัติเครื่องพิมพ์…';

  @override
  String get printOptionsDirectPrinter =>
      'ปุ่มพิมพ์จะส่งงานนี้ไปยังเครื่องพิมพ์ที่เลือกโดยตรง';

  @override
  String get printOptionsPropertiesError =>
      'ไม่สามารถเปิดคุณสมบัติเครื่องพิมพ์ได้';

  @override
  String get printOptionsLoadingPrinters => 'กำลังโหลดเครื่องพิมพ์…';
}
