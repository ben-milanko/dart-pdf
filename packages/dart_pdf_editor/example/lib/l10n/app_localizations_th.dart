// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get add => 'เพิ่ม';

  @override
  String get apply => 'ใช้';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get clear => 'ล้าง';

  @override
  String get close => 'ปิด';

  @override
  String get copy => 'คัดลอก';

  @override
  String get cut => 'ตัด';

  @override
  String get delete => 'ลบ';

  @override
  String get done => 'เสร็จสิ้น';

  @override
  String get edit => 'แก้ไข';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript ที่ส่งไปยังแอป: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'ลิงก์: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'การกระทำที่มีชื่อ: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'ประเภทการกระทำที่ไม่ได้จัดการ: $type';
  }

  @override
  String get exAnnotationTextCopied => 'คัดลอกข้อความคำอธิบายประกอบแล้ว';

  @override
  String get exApiKeyHelper => 'ส่งเป็น Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'คีย์ API / โทเค็น (ไม่บังคับ)';

  @override
  String get exAppMenuTooltip => 'เมนู DartPDF';

  @override
  String get exClearRecentFiles => 'ล้างไฟล์ล่าสุด';

  @override
  String get exCloseTab => 'ปิดแท็บ';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'เปรียบเทียบ: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'เปรียบเทียบกับ PDF อื่น…';

  @override
  String get exCopiedToClipboard => 'คัดลอกไปยังคลิปบอร์ดแล้ว';

  @override
  String get exCopySelectedText => 'คัดลอกข้อความที่เลือก (⌘C)';

  @override
  String get exCopyText => 'คัดลอกข้อความ';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'ไม่สามารถเปิด $name ได้\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'ไม่สามารถเปิด $path ได้\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'ไม่สามารถเปิด $url ได้';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'ไม่สามารถเปิด $uri ได้\n$error\n\nบนเว็บมักเป็นข้อจำกัด CORS: เซิร์ฟเวอร์ต้องส่ง Access-Control-Allow-Origin และเปิดเผยส่วนหัว Range';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'ไม่สามารถเปิด $title อีกครั้งได้\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'ไม่สามารถเปิด $title อีกครั้งได้ - สำเนาที่บันทึกไว้ไม่พร้อมใช้งานอีกต่อไป';
  }

  @override
  String get exDemoNoteHint => 'พิมพ์ที่นี่ - กล่องข้อความนี้ลอยอยู่เหนือหน้า';

  @override
  String get exDiagnosticsCopied => 'คัดลอกข้อมูลวินิจฉัยไปยังคลิปบอร์ดแล้ว';

  @override
  String exDownloaded(String name) {
    return 'ดาวน์โหลด $name แล้ว';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'ดาวน์โหลด $name แล้ว - วางกลับลงใน PDF ด้วย Ctrl+V';
  }

  @override
  String get exExport => 'ส่งออก';

  @override
  String exExportFailed(String error) {
    return 'การส่งออกล้มเหลว: $error';
  }

  @override
  String get exExportPageImageMenu => 'ส่งออกหน้าเป็นรูปภาพ…';

  @override
  String get exExportPageImageTitle => 'ส่งออกหน้าเป็นรูปภาพ';

  @override
  String get exFeatureShowcase => 'แสดงคุณสมบัติ';

  @override
  String get exFormat => 'รูปแบบ';

  @override
  String get exHide => 'ซ่อน';

  @override
  String get exHorizontalLayout => 'เค้าโครงหน้าแนวนอน';

  @override
  String get exHowToSetupOcr => 'วิธีตั้งค่าเซิร์ฟเวอร์ OCR';

  @override
  String get exModelName => 'ชื่อโมเดล';

  @override
  String get exNoMessage => 'ไม่มีข้อความ';

  @override
  String get exNoRecentFiles => 'ไม่มีไฟล์ล่าสุด';

  @override
  String exNotAValidUrl(String url) {
    return 'ไม่ใช่ URL ที่ถูกต้อง:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR เพิ่ม $count ช่วงข้อความ - ตอนนี้ข้อความในหน้าเลือกได้แล้ว',
      one: 'OCR เพิ่ม 1 ช่วงข้อความ - ตอนนี้ข้อความในหน้าเลือกได้แล้ว',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'เพิ่มชั้นข้อความที่เลือกและค้นหาได้ทับหน้าที่สแกนโดยใช้โมเดล OCR ภาษาภาพที่คุณโฮสต์เอง (dots.ocr บน vLLM หรือปลายทาง OCR ที่เข้ากันได้กับ OpenAI ใด ๆ)';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR ล้มเหลว: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'เปิด';

  @override
  String get exOpenDocumentBeforeOcr => 'เปิดเอกสารก่อนรัน OCR';

  @override
  String get exOpenDocumentFirst => 'เปิดเอกสารก่อน';

  @override
  String get exOpenFromUrl => 'เปิดจาก URL…';

  @override
  String get exOpenFromUrlTitle => 'เปิดจาก URL';

  @override
  String get exOpenInNewTab => 'เปิด PDF ในแท็บใหม่';

  @override
  String get exOpenInteractiveDemo => 'เปิดการสาธิตแบบโต้ตอบ';

  @override
  String get exOpenPdf => 'เปิด PDF…';

  @override
  String get exOpenPdfButton => 'เปิด PDF';

  @override
  String get exOpenRecent => 'เปิดล่าสุด';

  @override
  String get exRecentFiles => 'ไฟล์ล่าสุด';

  @override
  String get exViewAllRecentFiles => 'ดูไฟล์ล่าสุดทั้งหมด…';

  @override
  String get exSearchRecentFiles => 'ค้นหาไฟล์ล่าสุด';

  @override
  String get exNoMatchingRecentFiles => 'ไม่มีไฟล์ล่าสุดที่ตรงกับการค้นหา';

  @override
  String get exGridView => 'มุมมองตาราง';

  @override
  String get exListView => 'มุมมองรายการ';

  @override
  String get exOpenUrlDescription =>
      'สตรีม PDF ผ่านคำขอ HTTP Range ด้วย PdfHttpByteSource ดึงเฉพาะสิ่งที่ตัวแยกวิเคราะห์ต้องการ และกลับไปดาวน์โหลดทั้งหมดเมื่อเซิร์ฟเวอร์ไม่รองรับ range';

  @override
  String get exOpeningDocument => 'กำลังเปิดเอกสาร';

  @override
  String get exOpeningPdf => 'กำลังเปิด PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'กำลังเปิด $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL ของ PDF';

  @override
  String get exPerformanceAuto => 'ประสิทธิภาพ: อัตโนมัติ';

  @override
  String get exPreparing => 'กำลังเตรียม…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor บน pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'กำลังจดจำหน้า $current จาก $count…';
  }

  @override
  String get exResolution => 'ความละเอียด';

  @override
  String get exRunOcr => 'รัน OCR';

  @override
  String get exSaveAs => 'บันทึกเป็น…';

  @override
  String exSaveFailed(String error) {
    return 'การบันทึกล้มเหลว: $error';
  }

  @override
  String exSavedName(String name) {
    return 'บันทึก $name แล้ว';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'บันทึก $name แล้ว - วางกลับลงใน PDF ด้วย ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'บันทึกไปยัง $path แล้ว';
  }

  @override
  String get exScrollIndicatorDemo => 'การสาธิต API ตัวบ่งชี้การเลื่อน';

  @override
  String get exServiceEndpoint => 'ปลายทางบริการ';

  @override
  String get exShow => 'แสดง';

  @override
  String get exSingleWorker => 'เวิร์กเกอร์เดียว';

  @override
  String get exSupplyFeedback => 'ส่งความคิดเห็น…';

  @override
  String get exSwitchToEdit => 'สลับเป็นโหมดแก้ไข';

  @override
  String get exSwitchToReadOnly => 'สลับเป็นอ่านอย่างเดียว';

  @override
  String get exThemeDark => 'ธีม: มืด - สลับเป็นระบบ';

  @override
  String get exThemeLight => 'ธีม: สว่าง - สลับเป็นมืด';

  @override
  String get exThemeSystem => 'ธีม: ระบบ - สลับเป็นสว่าง';

  @override
  String get exTryDemo => 'ลองการสาธิตแบบโต้ตอบ';

  @override
  String get exUntitled => 'ไม่มีชื่อ';

  @override
  String get exVerticalLayout => 'เค้าโครงหน้าแนวตั้ง';

  @override
  String get exViewSource => 'ดูซอร์สโค้ดบน GitHub';

  @override
  String get exWorkerAuto => 'อัตโนมัติ';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ประสิทธิภาพ: $count เวิร์กเกอร์',
      one: 'ประสิทธิภาพ: เวิร์กเกอร์เดียว',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count เวิร์กเกอร์';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'แนบข้อมูลวินิจฉัยเหล่านี้ไปกับรายงาน';

  @override
  String get feedbackClearLog => 'ล้างบันทึก';

  @override
  String get feedbackCopyDiagnostics => 'คัดลอกข้อมูลวินิจฉัย';

  @override
  String get feedbackDiagnosticsNotice =>
      'แบบฟอร์มความคิดเห็นจะเปิดในเบราว์เซอร์ของคุณ ข้อมูลวินิจฉัยด้านล่างถูกรวบรวมบนอุปกรณ์นี้เท่านั้นและแนบมาเพื่อช่วยทำซ้ำปัญหา ตรวจสอบก่อน - อย่าใส่สิ่งที่คุณต้องการเก็บเป็นส่วนตัว';

  @override
  String get feedbackOpenForm => 'เปิดแบบฟอร์มความคิดเห็น';

  @override
  String get feedbackTitle => 'ส่งความคิดเห็น';

  @override
  String get none => 'ไม่มี';

  @override
  String get ok => 'ตกลง';

  @override
  String get paste => 'วาง';

  @override
  String get redo => 'ทำซ้ำ';

  @override
  String get remove => 'นำออก';

  @override
  String get rename => 'เปลี่ยนชื่อ';

  @override
  String get reset => 'รีเซ็ต';

  @override
  String get save => 'บันทึก';

  @override
  String get scrollDemoNextPage => 'หน้าถัดไป';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'หน้า $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'หน้าก่อนหน้า';

  @override
  String get scrollDemoSwitchHorizontal => 'สลับเป็นเค้าโครงแนวนอน';

  @override
  String get scrollDemoSwitchVertical => 'สลับเป็นเค้าโครงแนวตั้ง';

  @override
  String get scrollDemoTitle => 'API ตัวบ่งชี้การเลื่อน';

  @override
  String get undo => 'เลิกทำ';

  @override
  String get exFileTypePdf => 'เอกสาร PDF';

  @override
  String get exFileTypeImages => 'รูปภาพ';

  @override
  String get exFileTypeFonts => 'ฟอนต์';
}
