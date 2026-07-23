// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class DartPdfEditorLocalizationsTh extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get tbCropApply => 'ใช้การครอบตัด';

  @override
  String get tbCropCancel => 'ยกเลิกการครอบตัด';

  @override
  String get tbCropImage => 'ครอบตัดรูปภาพ';

  @override
  String get tbCropReset => 'รีเซ็ตการครอบตัด';

  @override
  String get tbCroppingImage => 'กำลังครอบตัดรูปภาพ';

  @override
  String get menuLock => 'ล็อก';

  @override
  String get menuUnlock => 'ปลดล็อก';

  @override
  String get sidebarLockAnnotation => 'ล็อก';

  @override
  String get sidebarUnlockAnnotation => 'ปลดล็อก';

  @override
  String get searchAnnotations => 'ค้นหาคำอธิบายประกอบ';

  @override
  String get add => 'เพิ่ม';

  @override
  String get annotCaret => 'เครื่องหมายแทรก';

  @override
  String get annotCircle => 'วงกลม';

  @override
  String get annotFileAttachment => 'ไฟล์แนบ';

  @override
  String get annotFreeText => 'กล่องข้อความ';

  @override
  String get annotHighlight => 'ไฮไลต์';

  @override
  String get annotInk => 'หมึกวาด';

  @override
  String get annotLine => 'เส้น';

  @override
  String get annotLink => 'ลิงก์';

  @override
  String get annotPolygon => 'รูปหลายเหลี่ยม';

  @override
  String get annotPolyline => 'เส้นหลายส่วน';

  @override
  String get annotRedact => 'การปิดบังข้อมูล';

  @override
  String get annotSquare => 'สี่เหลี่ยม';

  @override
  String get annotSquiggly => 'เส้นหยัก';

  @override
  String get annotStamp => 'ตราประทับ';

  @override
  String get annotStrikeOut => 'ขีดฆ่า';

  @override
  String get annotText => 'โน้ต';

  @override
  String get annotUnderline => 'ขีดเส้นใต้';

  @override
  String get annotWidget => 'ช่องแบบฟอร์ม';

  @override
  String get apply => 'ใช้';

  @override
  String get bookmarkAdd => 'เพิ่มบุ๊กมาร์ก';

  @override
  String get bookmarkAddChild => 'เพิ่มบุ๊กมาร์กย่อย';

  @override
  String get bookmarkCollapse => 'ยุบ';

  @override
  String get bookmarkDelete => 'ลบบุ๊กมาร์ก';

  @override
  String get bookmarkEdit => 'แก้ไขบุ๊กมาร์ก';

  @override
  String get bookmarkEmpty => 'ไม่มีบุ๊กมาร์ก';

  @override
  String get bookmarkExpand => 'ขยาย';

  @override
  String get bookmarkExpandedByDefault => 'ขยายไว้ตามค่าเริ่มต้น';

  @override
  String get bookmarkNoDestination => 'ไม่มีปลายทาง';

  @override
  String get bookmarkPageFieldLabel => 'หน้า';

  @override
  String bookmarkPageLabel(int number) {
    return 'หน้า $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'บุ๊กมาร์ก';

  @override
  String get bookmarkTitleLabel => 'ชื่อ';

  @override
  String get bookmarkUntitled => 'ไม่มีชื่อ';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get clear => 'ล้าง';

  @override
  String get close => 'ปิด';

  @override
  String get colorApplyingChanges => 'กำลังปรับใช้การเปลี่ยนสี…';

  @override
  String get colorColorFormat => 'รูปแบบสี';

  @override
  String get colorColorTitle => 'สี';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เลือก $count สี',
      one: 'เลือก $count สี',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'สีในเอกสาร';

  @override
  String get colorFillColors => 'สีเติม';

  @override
  String get colorFind => 'ค้นหา';

  @override
  String get colorInDocument => 'ในเอกสาร';

  @override
  String get colorNoColorsFound => 'ยังไม่พบสี';

  @override
  String get colorNoPageContentColors => 'ไม่พบสีในเนื้อหาหน้า';

  @override
  String get colorPalette => 'จานสี';

  @override
  String get colorPickColor => 'เลือกสี';

  @override
  String get colorProcessingTitle => 'การประมวลผลสี';

  @override
  String get colorRecent => 'ล่าสุด';

  @override
  String get colorReplace => 'แทนที่';

  @override
  String get colorReplaceWithTransparent => 'แทนที่ด้วยความโปร่งใส';

  @override
  String get colorScanning => 'กำลังสแกน…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'กำลังสแกน $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'หน้าที่เลือก ($count)';
  }

  @override
  String get colorStrokeColors => 'สีเส้น';

  @override
  String get colorTolerance => 'ความคลาดเคลื่อน';

  @override
  String get colorTransparent => 'โปร่งใส';

  @override
  String get colorWholeDocument => 'ทั้งเอกสาร';

  @override
  String get compareAfter => 'หลัง';

  @override
  String get compareBefore => 'ก่อน';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count การเปลี่ยนแปลง',
      one: '1 การเปลี่ยนแปลง',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count การเปลี่ยนแปลง',
      one: '1 การเปลี่ยนแปลง',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(ว่าง)';

  @override
  String get compareNextChange => 'การเปลี่ยนแปลงถัดไป';

  @override
  String get compareNoChanges => 'ไม่มีการเปลี่ยนแปลง';

  @override
  String get compareNoDifferences => 'ไม่มีความแตกต่างระหว่างเอกสารทั้งสอง';

  @override
  String get compareOverlay => 'ซ้อนทับ';

  @override
  String comparePageHeader(int page) {
    return 'หน้า $page';
  }

  @override
  String get comparePreviousChange => 'การเปลี่ยนแปลงก่อนหน้า';

  @override
  String get compareSideBySide => 'เทียบเคียงกัน';

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
  String get editorViewAuthorNameTitle => 'ชื่อผู้เขียน';

  @override
  String get lineStyleDashDot => 'เส้นประจุด';

  @override
  String get lineStyleDashed => 'เส้นประ';

  @override
  String get lineStyleDotted => 'เส้นจุด';

  @override
  String get lineStyleSolid => 'เส้นทึบ';

  @override
  String get measCalibrate => 'ปรับเทียบ';

  @override
  String get measCalibrateScale => 'ปรับเทียบมาตราส่วน';

  @override
  String get measDepthLabel => 'ความลึก: ';

  @override
  String get measKindAngle => 'มุม';

  @override
  String get measKindArc => 'ส่วนโค้ง';

  @override
  String get measKindArea => 'พื้นที่';

  @override
  String get measKindCount => 'จำนวน';

  @override
  String get measKindLength => 'ความยาว';

  @override
  String get measKindNetArea => 'พื้นที่สุทธิ';

  @override
  String get measKindPerimeter => 'เส้นรอบรูป';

  @override
  String get measKindSlope => 'ความชัน';

  @override
  String get measKindVolume => 'ปริมาตร';

  @override
  String get measLineRepresents => 'เส้นที่คุณวาดแทน:';

  @override
  String get measMeasure => 'วัด';

  @override
  String get measSetScale => 'ตั้งมาตราส่วนการวัด';

  @override
  String get measSetScaleButton => 'ตั้งมาตราส่วน';

  @override
  String get measVolumeDepth => 'ความลึกของปริมาตร';

  @override
  String get menuAddNode => 'เพิ่มจุด';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ใช้คำอธิบายประกอบกับหน้า',
      one: 'ใช้คำอธิบายประกอบกับหน้า',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'ใช้กับหน้า…';

  @override
  String get menuBringToFront => 'นำมาไว้ด้านหน้า';

  @override
  String get menuCheck => 'ทำเครื่องหมาย';

  @override
  String get menuChooseValue => 'เลือกค่า…';

  @override
  String get menuClearCheck => 'ล้างเครื่องหมาย';

  @override
  String get menuConvertToCheckBox => 'แปลงเป็นช่องทำเครื่องหมาย';

  @override
  String get menuConvertToImageButton => 'แปลงเป็นปุ่มรูปภาพ';

  @override
  String get menuConvertToTextField => 'แปลงเป็นช่องข้อความ';

  @override
  String get menuDeleteField => 'ลบช่อง';

  @override
  String get menuEditValue => 'แก้ไขค่า…';

  @override
  String get menuFieldName => 'ชื่อช่อง';

  @override
  String get menuFieldValue => 'ค่าของช่อง';

  @override
  String get menuFlattenForm => 'รวมแบบฟอร์ม';

  @override
  String get menuRecolour => 'เปลี่ยนสี…';

  @override
  String get menuRemoveNode => 'นำจุดออก';

  @override
  String get menuSetAsDefaultStyle => 'ตั้งเป็นสไตล์เริ่มต้น';

  @override
  String get menuRename => 'เปลี่ยนชื่อ…';

  @override
  String get menuSelectOption => 'เลือกตัวเลือก';

  @override
  String get menuSendToBack => 'ส่งไปไว้ด้านหลัง';

  @override
  String get menuSetImage => 'ตั้งรูปภาพ…';

  @override
  String get menuTextStyle => 'สไตล์ข้อความ…';

  @override
  String get none => 'ไม่มี';

  @override
  String get ok => 'ตกลง';

  @override
  String get overlayColor => 'สี';

  @override
  String get overlayEditText => 'แก้ไขข้อความ';

  @override
  String get overlayFont => 'ฟอนต์';

  @override
  String get overlayLarger => 'ใหญ่ขึ้น';

  @override
  String get overlayMore => 'เพิ่มเติม';

  @override
  String get overlayNote => 'โน้ต';

  @override
  String get overlaySmaller => 'เล็กลง';

  @override
  String get overlayStampText => 'ข้อความตราประทับ';

  @override
  String get overlayUnderline => 'ขีดเส้นใต้';

  @override
  String pageRangeErrorBounds(int count) {
    return 'ป้อนหน้าระหว่าง 1 ถึง $count';
  }

  @override
  String get pageRangeErrorOrder => 'หน้าสุดท้ายต้องไม่อยู่ก่อนหน้าแรก';

  @override
  String get pageRangeFrom => 'จาก';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count หน้า',
      one: '1 หน้า',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'ถึง';

  @override
  String get panelDragToMovePanel => 'ลากเพื่อย้ายแผง';

  @override
  String get paste => 'วาง';

  @override
  String get propAlign => 'จัดแนว';

  @override
  String get propAlignCenter => 'จัดกึ่งกลาง';

  @override
  String get propAlignLeft => 'จัดชิดซ้าย';

  @override
  String get propAlignRight => 'จัดชิดขวา';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count คำอธิบายประกอบ',
      one: '$count คำอธิบายประกอบ',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'ผู้เขียน';

  @override
  String get propAutoSize => 'ปรับขนาดอัตโนมัติ';

  @override
  String get propBold => 'ตัวหนา';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'ฟอนต์ที่มาพร้อมกัน';

  @override
  String get propCallout => 'คำบรรยาย';

  @override
  String get propCharSpacing => 'ระยะห่างอักขระ';

  @override
  String get propColor => 'สี';

  @override
  String get propColour => 'สี';

  @override
  String get propContents => 'เนื้อหา';

  @override
  String get propEditsApplyToAll =>
      'การแก้ไขมีผลกับคำอธิบายประกอบที่เข้ากันได้ทั้งหมด';

  @override
  String get propFieldName => 'ชื่อช่อง';

  @override
  String get propFieldTypeCheckBox => 'ช่องทำเครื่องหมาย';

  @override
  String get propFieldTypeComboBox => 'กล่องคอมโบ';

  @override
  String get propFieldTypeImageButton => 'ปุ่มรูปภาพ';

  @override
  String get propFieldTypeListBox => 'กล่องรายการ';

  @override
  String get propFieldTypeRadioGroup => 'กลุ่มปุ่มตัวเลือก';

  @override
  String get propFieldTypeSignature => 'ลายเซ็น';

  @override
  String get propFieldTypeText => 'ช่องข้อความ';

  @override
  String propFieldTypeTooltip(String type) {
    return 'ประเภทช่อง: $type';
  }

  @override
  String get propFieldTypeUnknown => 'ช่องที่ไม่รู้จัก';

  @override
  String get propFill => 'สีเติม';

  @override
  String get propFont => 'ฟอนต์';

  @override
  String get propFontSubsetTooltip =>
      'ฟอนต์นี้เป็นชุดย่อย - พิมพ์ได้เฉพาะอักขระที่ใช้อยู่แล้วในเอกสารเท่านั้น';

  @override
  String get propFontWidth => 'ความกว้างฟอนต์';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'ตัวเอียง';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'อักขระจำกัด';

  @override
  String get propLineEnd => 'ปลายเส้น';

  @override
  String get propLineEndingButt => 'ตัดตรง';

  @override
  String get propLineEndingCircle => 'วงกลม';

  @override
  String get propLineEndingClosedArrow => 'ลูกศรทึบ';

  @override
  String get propLineEndingClosedArrowRev => 'ลูกศรทึบ (กลับด้าน)';

  @override
  String get propLineEndingDiamond => 'สี่เหลี่ยมข้าวหลามตัด';

  @override
  String get propLineEndingOpenArrow => 'ลูกศรเปิด';

  @override
  String get propLineEndingOpenArrowRev => 'ลูกศรเปิด (กลับด้าน)';

  @override
  String get propLineEndingSlash => 'ขีดเฉียง';

  @override
  String get propLineEndingSquare => 'สี่เหลี่ยม';

  @override
  String get propLineSpacing => 'ระยะห่างบรรทัด';

  @override
  String get propLineStart => 'ต้นเส้น';

  @override
  String get propLineType => 'ชนิดเส้น';

  @override
  String get propLoadFont => 'โหลดฟอนต์…';

  @override
  String get propLoadFontSubtitle => 'ไฟล์ TTF หรือ OTF';

  @override
  String get propMoreColors => 'สีเพิ่มเติม…';

  @override
  String get propMultiline => 'หลายบรรทัด';

  @override
  String get propNoFill => 'ไม่มีสีเติม';

  @override
  String get propNoFontsFound => 'ไม่พบฟอนต์';

  @override
  String get propNoOutline => 'ไม่มีเส้นขอบ';

  @override
  String get propOpacity => 'ความทึบแสง';

  @override
  String get propOutline => 'เส้นขอบ';

  @override
  String get propPageLabel => 'หน้า';

  @override
  String propPageNumber(int number) {
    return 'หน้า $number';
  }

  @override
  String get propPropertiesTitle => 'คุณสมบัติ';

  @override
  String get propRecentlyUsed => 'ใช้ล่าสุด';

  @override
  String get propScale => 'มาตราส่วน';

  @override
  String get propSearchFonts => 'ค้นหาฟอนต์';

  @override
  String get propSectionAllFonts => 'ฟอนต์ทั้งหมด';

  @override
  String get propSectionAppearance => 'ลักษณะที่ปรากฏ';

  @override
  String get propSectionContent => 'เนื้อหา';

  @override
  String get propSectionFormField => 'ช่องแบบฟอร์ม';

  @override
  String get propSectionInThisDocument => 'ในเอกสารนี้';

  @override
  String get propSectionPositionSize => 'ตำแหน่งและขนาด (pt)';

  @override
  String get propSectionSelection => 'การเลือก';

  @override
  String get propSectionText => 'ข้อความ';

  @override
  String get propSelectAnnotationPrompt =>
      'เลือกคำอธิบายประกอบเพื่อดูคุณสมบัติ';

  @override
  String get propSize => 'ขนาด';

  @override
  String get propStandardPdfFont => 'ฟอนต์ PDF มาตรฐาน';

  @override
  String get propStroke => 'เส้น';

  @override
  String get propStyle => 'สไตล์';

  @override
  String get propSystemFont => 'ฟอนต์ระบบ';

  @override
  String get propType => 'ประเภท';

  @override
  String get propUnderline => 'ขีดเส้นใต้';

  @override
  String get propVaries => 'แตกต่างกัน';

  @override
  String get redo => 'ทำซ้ำ';

  @override
  String get reflowNoContent => 'ไม่มีเนื้อหาที่ดึงได้';

  @override
  String reflowPageLabel(int number) {
    return 'หน้า $number';
  }

  @override
  String get reflowSaveOrShare => 'บันทึกหรือแชร์';

  @override
  String get reflowViewFigure => 'ดูรูปภาพ';

  @override
  String get remove => 'นำออก';

  @override
  String get rename => 'เปลี่ยนชื่อ';

  @override
  String get reset => 'รีเซ็ต';

  @override
  String get save => 'บันทึก';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'หน้า $page';
  }

  @override
  String get sbarCallout => 'คำบรรยาย';

  @override
  String get sbarFieldButton => 'ช่องปุ่ม';

  @override
  String get sbarFieldChoice => 'ช่องตัวเลือก';

  @override
  String get sbarFieldGeneric => 'ช่องแบบฟอร์ม';

  @override
  String get sbarFieldSignature => 'ช่องลายเซ็น';

  @override
  String get sbarFieldText => 'ช่องข้อความ';

  @override
  String get sbarStateAccepted => 'ยอมรับแล้ว';

  @override
  String get sbarStateCancelled => 'ยกเลิกแล้ว';

  @override
  String get sbarStateMarked => 'ทำเครื่องหมายแล้ว';

  @override
  String get sbarStateRejected => 'ปฏิเสธแล้ว';

  @override
  String get sbarStateResolved => 'แก้ไขแล้ว';

  @override
  String get sbarStateUnmarked => 'ยกเลิกเครื่องหมายแล้ว';

  @override
  String get searchClearSearch => 'ล้างการค้นหา';

  @override
  String get searchEmptyHint =>
      'ค้นหาในเอกสารเพื่อแสดงรายการที่ตรงกันทั้งหมดที่นี่';

  @override
  String get searchMatchCase => 'ตรงตามตัวพิมพ์';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count รายการที่ตรงกัน',
      one: '1 รายการที่ตรงกัน',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'รายการถัดไป';

  @override
  String searchNoMatches(String query) {
    return 'ไม่มีรายการที่ตรงกับ “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'หน้า $page';
  }

  @override
  String get searchPreviousMatch => 'รายการก่อนหน้า';

  @override
  String get searchRegex => 'นิพจน์ทั่วไป';

  @override
  String get searchResultsTitle => 'ผลการค้นหา';

  @override
  String get searchWholeWord => 'ทั้งคำ';

  @override
  String get shellControls => 'การควบคุม';

  @override
  String get shellDefaultAuthor => 'ผู้เขียนเริ่มต้น…';

  @override
  String get shellHighlightFormFields => 'ไฮไลต์ช่องแบบฟอร์ม';

  @override
  String get shellKeyboardShortcutsMenu => 'แป้นพิมพ์ลัด…';

  @override
  String get shellKeyboardShortcutsTitle => 'แป้นพิมพ์ลัด';

  @override
  String get shellShortcutsSearchHint => 'ค้นหาแป้นพิมพ์ลัด';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'ไม่มีแป้นพิมพ์ลัดที่ตรงกับ “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'เลือก';

  @override
  String get shellShortcutGroupMarkup => 'มาร์กอัป';

  @override
  String get shellShortcutGroupDraw => 'วาด';

  @override
  String get shellShortcutGroupShapes => 'รูปทรง';

  @override
  String get shellShortcutGroupInsert => 'แทรก';

  @override
  String get shellShortcutGroupMeasure => 'วัด';

  @override
  String get shellShortcutGroupEdit => 'แก้ไข';

  @override
  String get shellNotSet => 'ไม่ได้ตั้งค่า';

  @override
  String get shellPageColor => 'สีหน้า…';

  @override
  String get shellPageGrid => 'ตารางหน้า';

  @override
  String get shellPanelAnnotations => 'คำอธิบายประกอบ';

  @override
  String get shellPanelBookmarks => 'บุ๊กมาร์ก';

  @override
  String get shellPanelPages => 'หน้า';

  @override
  String get shellPanelProperties => 'คุณสมบัติ';

  @override
  String get shellPanelSearchResults => 'ผลการค้นหา';

  @override
  String get shellPanels => 'แผง';

  @override
  String get shellPressAKey => 'กดปุ่ม';

  @override
  String get shellPressLetterKeyHint => 'กดปุ่มตัวอักษร หรือ Delete เพื่อล้าง';

  @override
  String get shellReflow => 'จัดเรียงใหม่';

  @override
  String get shellReflowText => 'จัดเรียงข้อความใหม่';

  @override
  String get shellResetZoom => 'รีเซ็ตการซูม';

  @override
  String get shellSectionShell => 'เชลล์';

  @override
  String get shellSectionView => 'มุมมอง';

  @override
  String get shellSettings => 'การตั้งค่า';

  @override
  String get shellShowAnnotations => 'แสดงคำอธิบายประกอบ';

  @override
  String get shellTabHere => 'แท็บที่นี่';

  @override
  String get shellUnbound => 'ไม่ได้กำหนด';

  @override
  String get shellZoom => 'ซูม';

  @override
  String sidebarByAuthor(String author) {
    return 'โดย $author';
  }

  @override
  String get sidebarCancelSelection => 'ยกเลิกการเลือก';

  @override
  String get sidebarClearSearch => 'ล้างการค้นหา';

  @override
  String get sidebarDeleteSelected => 'ลบที่เลือก';

  @override
  String get sidebarDeleteSignature => 'ลบลายเซ็น';

  @override
  String get sidebarMore => 'เพิ่มเติม';

  @override
  String get sidebarNoAnnotations => 'ไม่มีคำอธิบายประกอบ';

  @override
  String get sidebarNoMatchingAnnotations => 'ไม่มีคำอธิบายประกอบที่ตรงกัน';

  @override
  String sidebarPageHeader(int number) {
    return 'หน้า $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'การดำเนินการนี้จะนำลายเซ็นดิจิทัลออกจากเอกสาร คุณสามารถเลิกทำได้';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'การดำเนินการนี้จะนำลายเซ็นดิจิทัลโดย \"$name\" ออกจากเอกสาร คุณสามารถเลิกทำได้';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'นำลายเซ็นออกหรือไม่';

  @override
  String get sidebarReopen => 'เปิดใหม่';

  @override
  String get sidebarReply => 'ตอบกลับ';

  @override
  String get sidebarResolve => 'แก้ไข';

  @override
  String get sidebarSearchHint => 'ค้นหาคำอธิบายประกอบ';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เลือก $count รายการ',
      one: 'เลือก $count รายการ',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'เขียนคำตอบ…';

  @override
  String get sigTitle => 'ลายเซ็น';

  @override
  String get signIdCreate => 'สร้าง';

  @override
  String get signIdEmail => 'อีเมล (ไม่บังคับ)';

  @override
  String get signIdName => 'ชื่อ';

  @override
  String get signIdNameHint => 'ชื่อของคุณตามที่ควรปรากฏบนลายเซ็น';

  @override
  String get signIdNameRequired => 'ป้อนชื่อ';

  @override
  String get signIdOrganization => 'องค์กร (ไม่บังคับ)';

  @override
  String get signIdSelfSignedInfo =>
      'การดำเนินการนี้จะสร้างข้อมูลระบุตัวตนที่ลงนามด้วยตนเอง ลายเซ็นจะแสดงเป็น \"ลงนามแล้ว ไม่ทราบความถูกต้อง\" ใน Adobe Acrobat และโปรแกรมอ่านอื่น ๆ - เหมือนกับ ID ที่ลงนามด้วยตนเองของโปรแกรมเหล่านั้น เครื่องหมายถูกสีเขียวต้องใช้ CA ที่ได้รับความไว้วางใจแบบสาธารณะและเสียค่าใช้จ่าย';

  @override
  String get signIdTitle => 'สร้างข้อมูลระบุตัวตนสำหรับลงนาม';

  @override
  String get stampBox => 'กล่อง';

  @override
  String get stampCircle => 'วงกลม';

  @override
  String get stampCustomCaption => 'ตราประทับกำหนดเอง';

  @override
  String get stampDateFormat => 'รูปแบบวันที่';

  @override
  String get stampDeleteComponent => 'ลบส่วนประกอบที่เลือก';

  @override
  String get stampDeleteStamp => 'ลบตราประทับ';

  @override
  String get stampEditStamp => 'แก้ไขตราประทับ';

  @override
  String get stampExport => 'ส่งออก…';

  @override
  String get stampFieldDate => 'วันที่';

  @override
  String get stampFieldDateTime => 'วันที่และเวลา';

  @override
  String get stampFieldTime => 'เวลา';

  @override
  String get stampFieldUsername => 'ชื่อผู้ใช้';

  @override
  String get stampFont => 'ฟอนต์';

  @override
  String get stampFontBold => 'ตัวหนา';

  @override
  String get stampFontItalic => 'ตัวเอียง';

  @override
  String get stampHeight => 'ความสูง';

  @override
  String get stampImage => 'รูปภาพ';

  @override
  String get stampImport => 'นำเข้า…';

  @override
  String get stampInsertField => 'แทรกช่อง';

  @override
  String get stampMoreColors => 'สีเพิ่มเติม…';

  @override
  String get stampNewStamp => 'ตราประทับใหม่…';

  @override
  String get stampNewStampTitle => 'ตราประทับใหม่';

  @override
  String get stampSelectTextToEdit => 'เลือกข้อความเพื่อแก้ไข';

  @override
  String get stampSelectedText => 'ข้อความที่เลือก';

  @override
  String get stampSignature => 'ลายเซ็น';

  @override
  String get stampStamps => 'ตราประทับ';

  @override
  String get stampText => 'ข้อความ';

  @override
  String get stampTime12Hour => '12 ชม.';

  @override
  String get stampTime24Hour => '24 ชม.';

  @override
  String get stampTimeFormat => 'รูปแบบเวลา';

  @override
  String get stampWidth => 'ความกว้าง';

  @override
  String get takeoffArea => 'พื้นที่';

  @override
  String get takeoffCount => 'จำนวน';

  @override
  String get takeoffEmpty => 'ยังไม่มีการวัด';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count กลุ่ม',
      one: '$count กลุ่ม',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count รายการ',
      one: '$count รายการ',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'ความยาว';

  @override
  String get takeoffTitle => 'การถอดปริมาณ';

  @override
  String get tbAddInkAnnotation => 'เพิ่มคำอธิบายประกอบหมึกวาด';

  @override
  String get tbAlign => 'จัดแนว';

  @override
  String get tbAlignBottom => 'จัดชิดล่าง';

  @override
  String get tbAlignHorizontalCenters => 'จัดกึ่งกลางแนวนอน';

  @override
  String get tbAlignLeft => 'จัดชิดซ้าย';

  @override
  String get tbAlignRight => 'จัดชิดขวา';

  @override
  String get tbAlignTop => 'จัดชิดบน';

  @override
  String get tbAlignVerticalCenters => 'จัดกึ่งกลางแนวตั้ง';

  @override
  String get tbAnnotationsFlattened => 'รวมคำอธิบายประกอบเข้ากับหน้าแล้ว';

  @override
  String get tbApplyRedactionsMessage =>
      'เนื้อหาที่ทำเครื่องหมายไว้จะถูกลบออกจากเอกสารอย่างถาวร การดำเนินการนี้ไม่สามารถเลิกทำได้';

  @override
  String get tbApplyRedactionsTitle => 'ใช้การปิดบังข้อมูลหรือไม่';

  @override
  String get tbApplyRedactionsTooltip =>
      'ใช้การปิดบังข้อมูล (ไม่สามารถย้อนกลับได้)';

  @override
  String get tbAutosizeTextBox => 'ปรับขนาดกล่องข้อความอัตโนมัติ (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'วาดเส้นที่ทราบความยาวเพื่อปรับเทียบมาตราส่วน';

  @override
  String get tbCharSpacing => 'ระยะห่างอักขระ';

  @override
  String get tbCheckBoxOption => 'ช่องทำเครื่องหมาย';

  @override
  String get tbCheckMarksOnDocument => 'เครื่องหมายถูกบนเอกสาร';

  @override
  String get tbColorLabel => 'สี';

  @override
  String get tbColorProcessingTooltip =>
      'การประมวลผลสี - ค้นหาและแทนที่สีในเนื้อหาหน้า';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'แทนที่ $count สีแล้ว',
      one: 'แทนที่ 1 สีแล้ว',
      zero: 'ไม่พบสีที่ตรงกัน',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'แปลงเป็นช่องทำเครื่องหมาย';

  @override
  String get tbConvertToImageButton => 'แปลงเป็นปุ่มรูปภาพ';

  @override
  String get tbConvertToTextField => 'แปลงเป็นช่องข้อความ';

  @override
  String get tbCornerRadius => 'รัศมีมุม';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ลบคำอธิบายประกอบ $count รายการ',
      one: 'ลบคำอธิบายประกอบ',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'ลบองค์ประกอบ';

  @override
  String get tbDeleteField => 'ลบช่อง';

  @override
  String get tbDiscardDrawing => 'ทิ้งภาพวาด';

  @override
  String get tbDistributeHorizontally => 'กระจายในแนวนอน';

  @override
  String get tbDistributeVertically => 'กระจายในแนวตั้ง';

  @override
  String get tbDrawNewSignature => 'วาดลายเซ็นใหม่…';

  @override
  String get tbEditAnnotationText => 'แก้ไขข้อความคำอธิบายประกอบ';

  @override
  String get tbEditTextStyle => 'แก้ไขข้อความและสไตล์';

  @override
  String get tbElement => 'องค์ประกอบ';

  @override
  String get tbEraserSize => 'ขนาดยางลบ';

  @override
  String get tbFieldActions => 'การกระทำของช่อง';

  @override
  String get tbFieldName => 'ชื่อช่อง';

  @override
  String tbFieldNamed(String name) {
    return 'ช่อง: $name';
  }

  @override
  String get tbFieldValue => 'ค่าของช่อง';

  @override
  String get tbFill => 'สีเติม';

  @override
  String get tbFingerDraws => 'นิ้ววาด - แตะเพื่อให้เลื่อนแทน';

  @override
  String get tbFingerScrolls => 'นิ้วเลื่อน (ปากกาวาด) - แตะเพื่อให้วาด';

  @override
  String get tbFlattenAnnotationsTooltip => 'รวมคำอธิบายประกอบเข้ากับหน้า';

  @override
  String get tbFlattenForm => 'รวมแบบฟอร์ม';

  @override
  String get tbFlattenFormBakeValues => 'รวมแบบฟอร์ม - ฝังค่าลงในหน้า';

  @override
  String get tbFlattenLabel => 'รวม';

  @override
  String get tbFont => 'ฟอนต์';

  @override
  String get tbFontSize => 'ขนาดฟอนต์';

  @override
  String get tbFontWidth => 'ความกว้างฟอนต์';

  @override
  String get tbFormFieldsFlattened => 'รวมช่องแบบฟอร์มเข้ากับหน้าแล้ว';

  @override
  String get tbGroupDraw => 'วาด';

  @override
  String get tbGroupEdit => 'แก้ไข';

  @override
  String get tbGroupInsert => 'แทรก';

  @override
  String get tbGroupMarkup => 'มาร์กอัป';

  @override
  String get tbGroupMeasure => 'วัด';

  @override
  String get tbGroupSelect => 'เลือก';

  @override
  String get tbGroupShapes => 'รูปทรง';

  @override
  String get tbImageButtonOption => 'ปุ่มรูปภาพ';

  @override
  String get tbLineEnd => 'ปลายเส้น';

  @override
  String get tbLineSpacing => 'ระยะห่างบรรทัด';

  @override
  String get tbLineStart => 'ต้นเส้น';

  @override
  String get tbLineType => 'ชนิดเส้น';

  @override
  String get tbManageStamps => 'จัดการตราประทับ…';

  @override
  String get tbMarkupHighlight => 'ไฮไลต์';

  @override
  String get tbMarkupHighlightTip => 'ไฮไลต์ส่วนที่เลือก';

  @override
  String get tbMarkupSquiggly => 'เส้นหยักใต้ข้อความ';

  @override
  String get tbMarkupSquigglyTip => 'เส้นหยักใต้ส่วนที่เลือก';

  @override
  String get tbMarkupStrikeOut => 'ขีดฆ่า';

  @override
  String get tbMarkupStrikeOutTip => 'ขีดฆ่าส่วนที่เลือก';

  @override
  String get tbMarkupUnderline => 'ขีดเส้นใต้';

  @override
  String get tbMarkupUnderlineTip => 'ขีดเส้นใต้ส่วนที่เลือก';

  @override
  String get tbMoreColors => 'สีเพิ่มเติม…';

  @override
  String get tbNameArrow => 'ลูกศร';

  @override
  String get tbNameCallout => 'คำบรรยาย';

  @override
  String get tbNameCloudPolygon => 'รูปหลายเหลี่ยมแบบก้อนเมฆ';

  @override
  String get tbNameCount => 'นับ';

  @override
  String get tbNameDigitalSignature => 'ลายเซ็นดิจิทัล';

  @override
  String get tbNameDraw => 'วาด';

  @override
  String get tbNameEllipse => 'วงรี';

  @override
  String get tbNameEraser => 'ลบเส้นหมึก';

  @override
  String get tbNameHighlight => 'ไฮไลต์';

  @override
  String get tbNameImage => 'รูปภาพ';

  @override
  String get tbNameLine => 'เส้น';

  @override
  String get tbNameMeasureAngle => 'วัดมุม';

  @override
  String get tbNameMeasureArc => 'วัดความยาวส่วนโค้ง';

  @override
  String get tbNameMeasureArea => 'วัดพื้นที่';

  @override
  String get tbNameMeasureDistance => 'วัดระยะทาง';

  @override
  String get tbNameMeasurePerimeter => 'วัดเส้นรอบรูป';

  @override
  String get tbNameMeasureSlope => 'วัดความชัน (สูง/ราบ)';

  @override
  String get tbNameMeasureVolume => 'วัดปริมาตร (พื้นที่ × ความลึก)';

  @override
  String get tbNameNote => 'โน้ต';

  @override
  String get tbNamePolygon => 'รูปหลายเหลี่ยม';

  @override
  String get tbNamePolyline => 'เส้นหลายส่วน';

  @override
  String get tbNameRectangle => 'สี่เหลี่ยมผืนผ้า';

  @override
  String get tbNameSelect => 'เลือก';

  @override
  String get tbNameSignature => 'ลายเซ็น';

  @override
  String get tbNameStamp => 'ตราประทับ';

  @override
  String get tbNameTextBox => 'กล่องข้อความ';

  @override
  String get tbNewFieldType => 'ประเภทช่องใหม่ - ลากบนหน้าเพื่อเพิ่ม';

  @override
  String get tbNoAnnotationsToFlatten => 'ไม่มีคำอธิบายประกอบให้รวม';

  @override
  String get tbNoCustomStamps => 'ไม่มีตราประทับกำหนดเอง';

  @override
  String get tbNoFormFieldsToFlatten => 'ไม่มีช่องแบบฟอร์มให้รวม';

  @override
  String get tbNoRedactionsToApply => 'ไม่มีการปิดบังข้อมูลให้ใช้';

  @override
  String get tbNoteTitle => 'โน้ต';

  @override
  String get tbOpacity => 'ความทึบแสง';

  @override
  String get tbOutline => 'เส้นขอบ';

  @override
  String get tbPatternScale => 'มาตราส่วนลวดลาย';

  @override
  String get tbPickColorFromPage => 'เลือกสีจากหน้า';

  @override
  String get tbRedactionsApplied => 'ใช้การปิดบังข้อมูลแล้ว';

  @override
  String get tbRedoShortcut => 'ทำซ้ำ (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'ไม่สามารถจัดเรียงใหม่ได้ - นี่ไม่ใช่ย่อหน้าคอลัมน์เดียวที่เครื่องมือนี้จัดเรียงใหม่ได้ ลองใช้แทนที่ข้อความแทน';

  @override
  String get tbReflowParagraph => 'จัดเรียงย่อหน้าใหม่';

  @override
  String get tbRenameField => 'เปลี่ยนชื่อช่อง';

  @override
  String get tbRenameFieldEllipsis => 'เปลี่ยนชื่อช่อง…';

  @override
  String get tbReplaceImage => 'แทนที่รูปภาพ';

  @override
  String get tbReplaceImageFailed => 'ไม่สามารถแทนที่รูปภาพได้';

  @override
  String get tbReplaceText => 'แทนที่ข้อความ';

  @override
  String get tbSaveImage => 'บันทึกรูปภาพ';

  @override
  String get tbSaveShortcut => 'บันทึก… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'มาตราส่วน';

  @override
  String get tbSelectTextForMarkup => 'เลือกข้อความเพื่อใช้มาร์กอัป';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เลือก $count รายการ',
      one: 'การเลือก',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'ตั้ง…';

  @override
  String get tbStamp => 'ตราประทับ';

  @override
  String get tbStampText => 'ข้อความตราประทับ';

  @override
  String get tbStrokeOpacityFont => 'เส้น ความทึบแสง ฟอนต์';

  @override
  String get tbStrokeWidthLabel => 'ความหนาเส้น';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'เส้น $width';
  }

  @override
  String get tbStyle => 'สไตล์';

  @override
  String get tbTakeoffTotals => 'ยอดรวมการถอดปริมาณ';

  @override
  String get tbTextBorder => 'เส้นขอบข้อความ';

  @override
  String get tbTextColour => 'สีข้อความ';

  @override
  String get tbTextFieldOption => 'ช่องข้อความ';

  @override
  String get tbTextFill => 'สีเติมข้อความ';

  @override
  String get tbTextStyleEllipsis => 'สไตล์ข้อความ…';

  @override
  String get tbTextTitle => 'ข้อความ';

  @override
  String get tbTipCallout => 'คำบรรยาย - ลากจากจุดไปยังตำแหน่งที่กล่องจะไป';

  @override
  String get tbTipContent => 'แก้ไขเนื้อหาหน้า';

  @override
  String get tbTipCount => 'นับ - แตะเพื่อวางเครื่องหมายถูกและนับ';

  @override
  String get tbTipDigitalSignature =>
      'ลายเซ็นดิจิทัล - ลากกล่องเพื่อวางและลงนาม';

  @override
  String get tbTipForm =>
      'ช่องแบบฟอร์ม - แตะเพื่อเลือก แตะสองครั้งเพื่อกรอก ลากเพื่อเพิ่ม';

  @override
  String get tbTipHighlightDraw => 'ไฮไลต์ - วาดอิสระ';

  @override
  String get tbTipImage => 'รูปภาพ - แตะเพื่อวาง หรือลากออกเป็นกล่อง';

  @override
  String get tbTipMeasureAngle => 'วัดมุม - คลิกสามจุด';

  @override
  String get tbTipMeasureArc => 'วัดความยาวส่วนโค้ง - คลิกสามจุด';

  @override
  String get tbTipRedact => 'ปิดบังข้อมูล - ลากบริเวณ แล้วใช้งาน';

  @override
  String get tbTipSignature => 'ลายเซ็น - แตะหน้าเพื่อวาง';

  @override
  String get tbTipSnapshot =>
      'สแนปช็อต - ลากบริเวณเพื่อจับภาพ (วางกลับเป็นเวกเตอร์)';

  @override
  String get tbToolContent => 'เนื้อหา';

  @override
  String get tbToolForm => 'แบบฟอร์ม';

  @override
  String get tbToolRedact => 'ปิดบังข้อมูล';

  @override
  String get tbToolSnapshot => 'สแนปช็อต';

  @override
  String get tbTools => 'เครื่องมือ';

  @override
  String get tbTotals => 'ยอดรวม';

  @override
  String get tbTypeTextEachTime => 'พิมพ์ข้อความทุกครั้ง';

  @override
  String get tbUnderline => 'ขีดเส้นใต้';

  @override
  String get tbUndoShortcut => 'เลิกทำ (⌘Z)';

  @override
  String get textStyleFont => 'ฟอนต์';

  @override
  String get textStyleFontSize => 'ขนาดฟอนต์';

  @override
  String get textStyleKeep => 'คงเดิม';

  @override
  String get textStyleStyle => 'สไตล์';

  @override
  String get textStyleText => 'ข้อความ';

  @override
  String get textStyleTextFill => 'สีเติมข้อความ';

  @override
  String get textStyleTitle => 'แก้ไขข้อความและสไตล์';

  @override
  String get thumbAddPage => 'เพิ่มหน้า';

  @override
  String get thumbClearSelection => 'ล้างการเลือก';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'คัดลอก $count หน้า',
      one: 'คัดลอกหน้า',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'คัดลอกหน้าที่เลือก';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ตัด $count หน้า',
      one: 'ตัดหน้า',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'ตัดหน้าที่เลือก';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ลบ $count หน้า',
      one: 'ลบหน้า',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'ลบหน้าที่เลือก';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ทำสำเนา $count หน้า',
      one: 'ทำสำเนาหน้า',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'ส่งออกหน้า…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ส่งออก $count หน้า…',
      one: 'ส่งออกหน้า…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'ส่งออกหน้าที่เลือก';

  @override
  String get thumbInsertBlankAfter => 'แทรกหน้าว่างหลังจาก';

  @override
  String get thumbInsertBlankBefore => 'แทรกหน้าว่างก่อน';

  @override
  String get thumbInsertFileFailed => 'ไม่สามารถแทรกไฟล์นั้นได้';

  @override
  String get thumbInsertPdf => 'แทรก PDF…';

  @override
  String get thumbPageActions => 'การกระทำของหน้า';

  @override
  String thumbPageNumber(int number) {
    return 'หน้า $number';
  }

  @override
  String get thumbPages => 'หน้า';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'วาง $count หน้า',
      one: 'วางหน้า',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'หมุน 180°';

  @override
  String get thumbRotateLeft => 'หมุนซ้าย';

  @override
  String get thumbRotatePageRight => 'หมุนหน้าไปทางขวา';

  @override
  String get thumbRotateRight => 'หมุนขวา';

  @override
  String get thumbRotateSelectedLeft => 'หมุนหน้าที่เลือกไปทางซ้าย';

  @override
  String get thumbRotateSelectedRight => 'หมุนหน้าที่เลือกไปทางขวา';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'เลือก $count รายการ',
      one: 'เลือก $count รายการ',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'เลิกทำ';

  @override
  String get viewerEditFontUnsafe =>
      'ฟอนต์หรือการเข้ารหัสของ PDF นี้ไม่สามารถแก้ไขได้อย่างปลอดภัย';

  @override
  String get viewerEditNeedsSinglePage => 'การแก้ไขต้องเลือกในหน้าเดียว';

  @override
  String get viewerEditNotEditableRun =>
      'ส่วนที่เลือกนี้ไม่ใช่ข้อความเนื้อหาหน้าที่แก้ไขได้เพียงส่วนเดียว';

  @override
  String get viewerEditStyleUnchangeable =>
      'ฟอนต์ PDF นี้สามารถพิมพ์ใหม่ได้ แต่ไม่สามารถเปลี่ยนสไตล์ได้';

  @override
  String get viewerEditTextStyle => 'แก้ไขข้อความและสไตล์';

  @override
  String get viewerMarkup => 'มาร์กอัป';

  @override
  String get viewerMarkupHighlight => 'ไฮไลต์';

  @override
  String get viewerMarkupSquiggly => 'เส้นหยัก';

  @override
  String get viewerMarkupStrikeOut => 'ขีดฆ่า';

  @override
  String get viewerMarkupUnderline => 'ขีดเส้นใต้';

  @override
  String get viewerSelectAll => 'เลือกทั้งหมด';
}
