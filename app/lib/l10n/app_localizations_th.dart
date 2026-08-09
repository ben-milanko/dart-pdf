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
  String get appSigAddLogo => 'เพิ่มโลโก้…';

  @override
  String appSigAllPages(int pageCount) {
    return 'ทั้งหมด $pageCount หน้า';
  }

  @override
  String get appSigAppearance => 'ลักษณะที่ปรากฏ';

  @override
  String get appSigAppearanceDescription =>
      'ลายเซ็นจะถูกวาดในตำแหน่งที่คุณวางไว้ ชื่อผู้ลงนามและรายละเอียดจะแสดงเสมอ คุณสามารถเพิ่มลายเซ็นที่วาดด้วยมือและพื้นหลังโลโก้ได้';

  @override
  String appSigApplyTo(String label) {
    return 'ใช้กับ: $label';
  }

  @override
  String get appSigApplyToPages => 'ใช้กับหน้า…';

  @override
  String get appSigChooseCertificate => 'เลือกไฟล์ใบรับรอง…';

  @override
  String get appSigChooseKeyDescription =>
      'เลือกคีย์ส่วนตัวของคุณ (RSA, PEM หรือ DER) และไฟล์ใบรับรอง คีย์ใช้สำหรับลงนามเท่านั้นและจะไม่ถูกบันทึกไว้';

  @override
  String get appSigChoosePngOrJpeg => 'เลือกรูปภาพ PNG หรือ JPEG';

  @override
  String get appSigChoosePrivateKey => 'เลือกคีย์ส่วนตัว…';

  @override
  String get appSigContactInfo => 'ข้อมูลติดต่อ';

  @override
  String get appSigCouldNotCaptureSignature => 'ไม่สามารถจับภาพลายเซ็นได้';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'ไม่สามารถอ่านใบรับรองได้: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'ไม่สามารถอ่านคีย์ได้: $error';
  }

  @override
  String get appSigCreateOnDevice => 'สร้างลายเซ็นบนอุปกรณ์นี้';

  @override
  String appSigDate(String date) {
    return 'วันที่: $date';
  }

  @override
  String get appSigDigitallySign => 'ลงนามดิจิทัล';

  @override
  String get appSigDrawSignature => 'วาดลายเซ็น…';

  @override
  String get appSigFieldHelper => 'เว้นว่างไว้เพื่อสร้างช่องลายเซ็นใหม่';

  @override
  String get appSigFieldLabel => 'ช่องลายเซ็นที่มีอยู่ (ไม่บังคับ)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ใบรับรอง',
      one: '1 ใบรับรอง',
    );
    return '$_temp0 · ใช้ได้ $validFrom ถึง $validUntil';
  }

  @override
  String get appSigIntro =>
      'ลายเซ็นดิจิทัลพิสูจน์ว่าคุณลงนามในเอกสารนี้และไม่มีการเปลี่ยนแปลงตั้งแต่นั้นมา เลือกวิธีที่คุณต้องการลงนาม';

  @override
  String get appSigKeyOrCertUnreadable =>
      'ไม่สามารถอ่านคีย์หรือใบรับรองที่เลือกได้';

  @override
  String get appSigKeylessDescription =>
      'ง่ายที่สุด เรายืนยันว่าเป็นคุณผ่านอีเมลและลงนามให้คุณ พร้อมการประทับเวลาที่เชื่อถือได้ ไม่ต้องติดตั้งหรือตั้งค่าใด ๆ';

  @override
  String get appSigKeylessIdentity => 'ข้อมูลระบุตัวตนแบบไร้คีย์';

  @override
  String get appSigKeylessSignInExpired =>
      'การลงชื่อเข้าใช้แบบไร้คีย์ของคุณหมดอายุแล้ว โปรดลงชื่อเข้าใช้อีกครั้ง';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'การลงชื่อเข้าใช้แบบไร้คีย์ล้มเหลว: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'ไร้คีย์ · ประทับเวลาแล้ว · ไม่ทราบความถูกต้อง';

  @override
  String get appSigKeylessWebNote =>
      'การลงชื่อเข้าใช้ด้วยอีเมลเป็นวิธีที่ง่ายที่สุด — มีให้บริการในแอป DartPDF สำหรับเดสก์ท็อปและมือถือ ด้วยเหตุผลด้านความปลอดภัยจึงไม่สามารถทำงานในเว็บเบราว์เซอร์ได้';

  @override
  String get appSigLocation => 'ตำแหน่งที่ตั้ง';

  @override
  String get appSigLogoAdded => 'เพิ่มโลโก้แล้ว ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'หน้า $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'ตัวอย่าง - กล่องที่ลงนามแล้วอาจแตกต่างเล็กน้อย';

  @override
  String get appSigReason => 'เหตุผล';

  @override
  String appSigReasonLine(String reason) {
    return 'เหตุผล: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'กำลังรีเฟรชการลงชื่อเข้าใช้…';

  @override
  String get appSigRemoveLogo => 'นำโลโก้ออก';

  @override
  String get appSigRemoveSignature => 'นำลายเซ็นออก';

  @override
  String get appSigSelfSignedDescription =>
      'ไม่ต้องลงชื่อเข้าใช้หรือใช้ไฟล์ เหมาะที่สุดสำหรับการใช้งานส่วนตัว — จะถูกบันทึกไว้บนอุปกรณ์นี้สำหรับครั้งต่อไป โปรแกรมอ่าน PDF บางตัวจะแสดงเป็น \"ลงนามแล้ว ไม่ทราบความถูกต้อง\" ซึ่งเป็นเรื่องปกติสำหรับลายเซ็นที่คุณสร้างเอง';

  @override
  String get appSigSelfSignedIdentity => 'ข้อมูลระบุตัวตนที่ลงนามด้วยตนเอง';

  @override
  String get appSigSelfSignedSubtitle => 'ลงนามด้วยตนเอง · ไม่ทราบความถูกต้อง';

  @override
  String get appSigShowSignatureOnPages => 'แสดงลายเซ็นบนหน้า';

  @override
  String get appSigSign => 'ลงนาม';

  @override
  String get appSigSignInWithEmail => 'ลงชื่อเข้าใช้ด้วยอีเมลของคุณ';

  @override
  String get appSigSignatureAdded => 'เพิ่มลายเซ็นแล้ว ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'ลงนามดิจิทัลโดย $signerName';
  }

  @override
  String get appSigSigner => 'ผู้ลงนาม';

  @override
  String get appSigSigningYouIn => 'กำลังลงชื่อเข้าใช้ให้คุณ…';

  @override
  String get appSigThisPageOnly => 'หน้านี้เท่านั้น';

  @override
  String get appSigUseOwnCertificate => 'ใช้ใบรับรองของคุณเอง';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'สำหรับใบรับรองการลงนามจากองค์กรของคุณ';

  @override
  String get appSigX509Signer => 'ผู้ลงนาม X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'เปิด PDF จำนวน $count ไฟล์นี้ในแท็บใหม่ หรือแทรกหน้าลงใน \"$title\"?',
      one: 'เปิด PDF นี้ในแท็บใหม่ หรือแทรกหน้าลงใน \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เพิ่ม PDF ที่ลากวาง',
      one: 'เพิ่ม PDF ที่ลากวาง',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'คัดลอกข้อความคำอธิบายประกอบแล้ว';

  @override
  String get editorAppMenuTooltip => 'เมนู DartPDF';

  @override
  String get editorCancelOcr => 'ยกเลิก OCR';

  @override
  String get editorClearRecentFiles => 'ล้างไฟล์ล่าสุด';

  @override
  String get editorCloseAll => 'ปิดทั้งหมด';

  @override
  String get editorCloseOthers => 'ปิดอันอื่น';

  @override
  String get editorCloseTab => 'ปิดแท็บ';

  @override
  String get editorCloseTabsToRight => 'ปิดแท็บทางขวา';

  @override
  String get editorCompareFailedTitle => 'การเปรียบเทียบล้มเหลว';

  @override
  String editorCompareTitle(String title) {
    return 'เปรียบเทียบ: $title';
  }

  @override
  String get editorCopiedToClipboard => 'คัดลอกไปยังคลิปบอร์ดแล้ว';

  @override
  String get editorCopySelectedTextTooltip => 'คัดลอกข้อความที่เลือก (⌘C)';

  @override
  String get editorCopyText => 'คัดลอกข้อความ';

  @override
  String editorCouldNotExport(String title) {
    return 'ไม่สามารถส่งออก $title ได้';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'ไม่สามารถนำเข้าตราประทับได้: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ไม่สามารถแทรก PDF ที่ลากวางได้',
      one: 'ไม่สามารถแทรก PDF ที่ลากวางได้',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'ไม่สามารถเปิด $title ได้\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'ไม่สามารถเปิดโฟลเดอร์ที่บรรจุไฟล์ได้';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'ไม่สามารถเปิดไฟล์ที่สองได้\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'ไม่สามารถเปิดไฟล์ที่เลือกได้\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'ไม่สามารถเปิด $url ได้';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'ไม่สามารถพิมพ์ $title ได้';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'ไม่สามารถเปิด $title อีกครั้งได้';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'ไม่สามารถลงนามดิจิทัลได้: $error';
  }

  @override
  String get editorDiscard => 'ทิ้ง';

  @override
  String get editorDiscardChangesTitle => 'ทิ้งการเปลี่ยนแปลงหรือไม่';

  @override
  String get editorDocumentSigned => 'ลงนามดิจิทัลในเอกสารแล้ว';

  @override
  String get editorDownload => 'ดาวน์โหลด';

  @override
  String get editorDropToOpen => 'วาง PDF เพื่อเปิด';

  @override
  String get editorDropToOpenOrInsert => 'วาง PDF เพื่อเปิดหรือแทรก';

  @override
  String get editorInsertPages => 'แทรกหน้า';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'แทรกแล้ว $count; ไม่สามารถอ่าน $files ได้';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'แทรก PDF จำนวน $count ไฟล์ลงใน $title แล้ว',
      one: 'แทรกหน้าลงใน $title แล้ว',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'ลิงก์ไม่ถูกต้อง: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'เอกสารนี้พยายามรัน JavaScript (ถูกละเว้น)';

  @override
  String get editorLoadingFullDocument => 'กำลังโหลดเอกสารทั้งหมด';

  @override
  String get editorMenuCompareWith => 'เปรียบเทียบกับ…';

  @override
  String get editorMenuDigitallySign => 'ลงนามดิจิทัล…';

  @override
  String get editorMenuDigitallySigning => 'กำลังลงนามดิจิทัล…';

  @override
  String get editorMenuExportImage => 'ส่งออกหน้าเป็นรูปภาพ…';

  @override
  String get editorMenuNewDocument => 'เอกสารใหม่…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'เปิด PDF…';

  @override
  String get editorMenuPrint => 'พิมพ์…';

  @override
  String get editorMenuSaveAs => 'บันทึกเป็น…';

  @override
  String get editorMenuScanDocument => 'สแกนเป็นเอกสารใหม่…';

  @override
  String get editorMenuInsertScan => 'แทรกสแกน…';

  @override
  String get editorScanFailed => 'ไม่สามารถสแกนเอกสารได้';

  @override
  String get editorInsertedScan => 'แทรกหน้าที่สแกนแล้ว';

  @override
  String get editorMenuSettings => 'การตั้งค่า';

  @override
  String get editorMenuSwitchToEdit => 'สลับเป็นโหมดแก้ไข';

  @override
  String get editorMenuSwitchToReadOnly => 'สลับเป็นอ่านอย่างเดียว';

  @override
  String editorNamedAction(String name) {
    return 'การกระทำที่มีชื่อ: $name';
  }

  @override
  String get editorNoRecentFiles => 'ไม่มีไฟล์ล่าสุด';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'เปิดเอกสารก่อนรัน OCR';

  @override
  String get editorOpenFailedTitle => 'เปิดไม่สำเร็จ';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เปิดในแท็บใหม่',
      one: 'เปิดในแท็บใหม่',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'เปิด PDF ในแท็บใหม่';

  @override
  String get editorOpenRecent => 'เปิดล่าสุด';

  @override
  String get editorOpenTabs => 'แท็บที่เปิด';

  @override
  String get editorOpeningDocumentSemantic => 'กำลังเปิดเอกสาร';

  @override
  String get editorOpeningPdf => 'กำลังเปิด PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'กำลังเปิด $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'หน้า $number';
  }

  @override
  String get editorPreviewComparison => 'การเปรียบเทียบ';

  @override
  String get editorPreviewCouldNotOpen => 'ไม่สามารถเปิดได้';

  @override
  String get editorPreviewOpening => 'กำลังเปิด';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'กู้คืนการเปลี่ยนแปลงที่ยังไม่ได้บันทึกใน $count เอกสารจากเซสชันล่าสุดแล้ว',
      one: 'กู้คืนการเปลี่ยนแปลงที่ยังไม่ได้บันทึกจากเซสชันล่าสุดแล้ว',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'นำลายเซ็นออกแล้ว';

  @override
  String get editorSnapshotCopied => 'คัดลอกสแนปช็อตไปยังคลิปบอร์ดแล้ว';

  @override
  String get editorSnapshotCopyFailed =>
      'ไม่สามารถคัดลอกสแนปช็อตไปยังคลิปบอร์ดได้';

  @override
  String get editorTabs => 'แท็บ';

  @override
  String editorTabsOpenCount(int count) {
    return 'เปิดอยู่ $count';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เอกสาร $count รายการมีการเปลี่ยนแปลงที่ยังไม่ได้บันทึก',
      one: 'เอกสารมีการเปลี่ยนแปลงที่ยังไม่ได้บันทึก',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'การกระทำที่ไม่รองรับ: $type';
  }

  @override
  String get editorUntitled => 'ไม่มีชื่อ';

  @override
  String editorUpdateAvailable(String version) {
    return 'มี DartPDF $version ให้ใช้งาน';
  }

  @override
  String get editorUpdateLater => 'ภายหลัง';

  @override
  String get updateInstallNow => 'อัปเดตทันที';

  @override
  String get updateDownloadingTitle => 'กำลังดาวน์โหลดการอัปเดต';

  @override
  String get updatePreparing => 'กำลังเตรียม…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'กำลังดาวน์โหลด… $percent%';
  }

  @override
  String get updateRestarting => 'กำลังรีสตาร์ทเพื่อสิ้นสุดการอัปเดต…';

  @override
  String get updateHandedOff => 'ดาวน์โหลดการอัปเดตแล้ว กำลังเปิดตัวติดตั้ง…';

  @override
  String updateFailed(String error) {
    return 'การอัปเดตล้มเหลว: $error';
  }

  @override
  String get editorViewAllTabs => 'ดูแท็บทั้งหมด';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'ส่งออก';

  @override
  String get imgExportFormat => 'รูปแบบ';

  @override
  String get imgExportResolution => 'ความละเอียด';

  @override
  String get imgExportTitle => 'ส่งออกหน้าเป็นรูปภาพ';

  @override
  String get newDocCreate => 'สร้าง';

  @override
  String get newDocLandscape => 'แนวนอน';

  @override
  String get newDocOrientation => 'การวางแนว';

  @override
  String get newDocPageSize => 'ขนาดหน้า';

  @override
  String get newDocPortrait => 'แนวตั้ง';

  @override
  String get newDocTitle => 'เอกสารใหม่';

  @override
  String get none => 'ไม่มี';

  @override
  String get ocrAlreadyRunning =>
      'OCR กำลังทำงานอยู่แล้ว - รอให้เสร็จหรือยกเลิก';

  @override
  String get ocrBrowserInitFailed => 'OCR ในเบราว์เซอร์เริ่มต้นไม่สำเร็จ';

  @override
  String get ocrCancelled => 'ยกเลิก OCR แล้ว';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ยกเลิก OCR หลังจาก $count ช่วงข้อความ',
      one: 'ยกเลิก OCR หลังจาก 1 ช่วงข้อความ',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'ดาวน์โหลด';

  @override
  String ocrDownloadFailed(String error) {
    return 'ไม่สามารถดาวน์โหลดโมเดล OCR ได้: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'การเพิ่มชั้นข้อความที่เลือกได้ต้องใช้โมเดล OCR บนอุปกรณ์$size ดาวน์โหลดเพียงครั้งเดียวแล้วทำงานแบบออฟไลน์\n\nโมเดล: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'ดาวน์โหลดโมเดล OCR หรือไม่';

  @override
  String ocrFailed(String error) {
    return 'OCR ล้มเหลว: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable => 'OCR บนอุปกรณ์ไม่พร้อมใช้งานบนแพลตฟอร์มนี้';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR เพิ่ม $count ช่วงข้อความ - ตอนนี้ข้อความในหน้าเลือกได้แล้ว',
      one: 'OCR เพิ่ม 1 ช่วงข้อความ - ตอนนี้ข้อความในหน้าเลือกได้แล้ว',
      zero: 'OCR ไม่พบข้อความในหน้าเหล่านี้',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'OCR บนเว็บจะดาวน์โหลดโมเดลภาษาภาพ Florence-2 และรันในเครื่องด้วย WebGPU/WASM ผ่าน Transformers.js หน้า PDF จะยังคงอยู่ในเบราว์เซอร์นี้ มีเพียงไฟล์โมเดลเท่านั้นที่ดึงมาเมื่อใช้งานครั้งแรก';

  @override
  String get ocrWebPromptTitle => 'รัน AI OCR ในเบราว์เซอร์นี้หรือไม่';

  @override
  String get ocrWebStart => 'เริ่ม OCR';

  @override
  String get ok => 'ตกลง';

  @override
  String get paste => 'วาง';

  @override
  String get printDlgPreparing => 'กำลังเตรียม…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'กำลังเรนเดอร์หน้า $rendered จาก $total…';
  }

  @override
  String get printDlgTitle => 'กำลังพิมพ์';

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
  String get settingsAbout => 'เกี่ยวกับ';

  @override
  String get settingsAppearance => 'ลักษณะที่ปรากฏ';

  @override
  String get settingsCheckNow => 'ตรวจสอบตอนนี้';

  @override
  String get settingsLanguage => 'ภาษา';

  @override
  String get settingsLanguageSystem => 'ค่าเริ่มต้นของระบบ';

  @override
  String get settingsCheckingForUpdates => 'กำลังตรวจสอบการอัปเดต…';

  @override
  String get settingsCouldNotOpenDownload => 'ไม่สามารถเปิดการดาวน์โหลดได้';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'ไม่สามารถเปิดการตั้งค่าระบบได้';

  @override
  String get settingsDeveloperTools => 'เครื่องมือนักพัฒนา';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'เมตริก บันทึก โหมดเรนเดอร์ (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'ดาวน์โหลด $version';
  }

  @override
  String get settingsOpenSettings => 'เปิดการตั้งค่า';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'จดจำไว้ $count ไฟล์',
      one: 'จดจำไว้ 1 ไฟล์',
      zero: 'ไม่มีไฟล์ล่าสุด',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'ไฟล์ล่าสุด';

  @override
  String get settingsSetUpAsDefault => 'ตั้งค่าเป็นแอปพลิเคชันเริ่มต้น';

  @override
  String get settingsSystem => 'ระบบ';

  @override
  String get settingsThemeDark => 'มืด';

  @override
  String get settingsThemeLight => 'สว่าง';

  @override
  String get settingsThemeSystem => 'ระบบ';

  @override
  String get settingsTitle => 'การตั้งค่า';

  @override
  String settingsUpToDate(String version) {
    return 'คุณใช้เวอร์ชันล่าสุดแล้ว ($version)';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'มีเวอร์ชัน $version ให้ใช้งาน (คุณมี $currentVersion)';
  }

  @override
  String get settingsUpdateFailed =>
      'ตรวจสอบการอัปเดตไม่ได้ ลองอีกครั้งภายหลัง';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'คุณมี $name $version';
  }

  @override
  String get settingsNightlyUpdates => 'การอัปเดตแบบ Nightly';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'รับการแจ้งเตือนอัปเดตอัตโนมัติสำหรับบิลด์ทดสอบ Windows ที่ไม่ได้ลงนามจาก main';

  @override
  String get settingsUpdates => 'การอัปเดต';

  @override
  String get settingsViewSource => 'ดูซอร์สโค้ดบน GitHub';

  @override
  String get undo => 'เลิกทำ';

  @override
  String get welcomeOpenPdf => 'เปิด PDF';

  @override
  String get welcomePickAgainToReopen => 'เลือกอีกครั้งเพื่อเปิดใหม่';

  @override
  String get welcomeRecent => 'ล่าสุด';

  @override
  String get welcomeRemoveFromRecent => 'นำออกจากรายการล่าสุด';

  @override
  String get welcomeTapToReopen => 'แตะเพื่อเปิดใหม่';

  @override
  String get welcomeViewAsGrid => 'มุมมองตาราง';

  @override
  String get welcomeViewAsList => 'มุมมองรายการ';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'ติดตั้งเว็บแอป แล้วเลือกให้เปิดไฟล์ PDF',
        'windows': 'เปิดการตั้งค่าแอปเริ่มต้นของ Windows สำหรับ PDF',
        'macos': 'ทำตามขั้นตอน “Always Open With” ของ Finder',
        'linux': 'ใช้การตั้งค่าแอปพลิเคชันเริ่มต้นของเดสก์ท็อปคุณ',
        'android': 'เลือก DartPDF เมื่อเปิด PDF แล้วแตะเสมอ',
        'ios': 'ใช้แชร์หรือเปิดในจาก Files เพื่อส่ง PDF มาที่นี่',
        'other': 'กำหนดค่าตัวจัดการไฟล์ PDF ของระบบคุณ',
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
            'ติดตั้ง DartPDF จากเบราว์เซอร์ของคุณก่อน จากนั้นใช้การตั้งค่าตัวจัดการไฟล์ของเบราว์เซอร์หรือระบบปฏิบัติการเพื่อเชื่อมโยงไฟล์ PDF กับแอปที่ติดตั้ง',
        'windows':
            'การตั้งค่า Windows จะเปิดไปที่แอปเริ่มต้น ค้นหา “.pdf” หรือ “PDF” เลือกแอป PDF ปัจจุบัน แล้วเลือก DartPDF',
        'macos':
            'ใน Finder เลือก PDF ใดก็ได้ เลือก File > Get Info ขยาย “Open with” เลือก DartPDF แล้วคลิก “Change All…”',
        'linux':
            'เปิดการตั้งค่าเดสก์ท็อปสำหรับแอปพลิเคชันเริ่มต้น หรือคลิกขวาที่ PDF ใน Files เลือก Properties แล้วตั้ง DartPDF เป็นค่าเริ่มต้นสำหรับเอกสาร PDF',
        'android':
            'เปิด PDF จาก Files หรือ Downloads เลือก DartPDF ในตัวเลือกแอป แล้วเลือกเสมอ หากมีแอปอื่นเปิด PDF อยู่แล้ว ให้ล้างค่าเริ่มต้นของแอปนั้นในการตั้งค่า Android ก่อน',
        'ios':
            'iOS ไม่มีตัวแก้ไข PDF เริ่มต้นแบบทั่วทั้งระบบ ใช้ Files > Share หรือกดค้างที่ PDF แล้วเลือก Share/Open In จากนั้นเลือก DartPDF',
        'other':
            'ใช้การตั้งค่าระบบสำหรับตัวจัดการไฟล์เพื่อเชื่อมโยงเอกสาร PDF กับ DartPDF',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'กำลังดาวน์โหลดโมเดล OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'กำลังดาวน์โหลดโมเดล $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'กำลังเสร็จสิ้น OCR…';

  @override
  String get fileTypePdf => 'เอกสาร PDF';

  @override
  String get fileTypeImages => 'รูปภาพ';

  @override
  String get fileTypeStampBundle => 'ตราประทับ DartPDF';

  @override
  String get appSigKeyFileType => 'คีย์ส่วนตัว RSA';

  @override
  String get appSigCertificateFileType => 'ใบรับรอง X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'เลือกใบรับรอง X.509 อย่างน้อยหนึ่งใบ';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'ใบรับรอง $index ไม่ใช่ X.509 ที่ถูกต้อง';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'คีย์ส่วนตัวไม่ตรงกับใบรับรอง RSA ที่เลือกใด ๆ';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'ไม่รองรับคีย์ส่วนตัวที่เข้ารหัส เลือกคีย์ RSA PKCS#1 หรือ PKCS#8 ที่ไม่ได้เข้ารหัส';

  @override
  String get appSigErrorKeyNotRsa =>
      'คีย์ส่วนตัวไม่ใช่คีย์ RSA PKCS#1 หรือ PKCS#8 ที่ไม่ได้เข้ารหัส';

  @override
  String get appSigErrorNoCertificateFound => 'ไม่พบใบรับรอง X.509';

  @override
  String get imageSourceTakePhoto => 'ถ่ายภาพ';

  @override
  String get imageSourceChooseFile => 'เลือกไฟล์';

  @override
  String get imageSourceCameraFailed => 'ถ่ายภาพไม่สำเร็จ';
}
