// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class DartPdfEditorLocalizationsZh extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get add => '添加';

  @override
  String get annotCaret => '插入符';

  @override
  String get annotCircle => '圆形';

  @override
  String get annotFileAttachment => '文件附件';

  @override
  String get annotFreeText => '文本框';

  @override
  String get annotHighlight => '高亮';

  @override
  String get annotInk => '手绘';

  @override
  String get annotLine => '直线';

  @override
  String get annotLink => '链接';

  @override
  String get annotPolygon => '多边形';

  @override
  String get annotPolyline => '折线';

  @override
  String get annotRedact => '密文遮盖';

  @override
  String get annotSquare => '方形';

  @override
  String get annotSquiggly => '波浪线';

  @override
  String get annotStamp => '图章';

  @override
  String get annotStrikeOut => '删除线';

  @override
  String get annotText => '便笺';

  @override
  String get annotUnderline => '下划线';

  @override
  String get annotWidget => '表单字段';

  @override
  String get apply => '应用';

  @override
  String get bookmarkAdd => '添加书签';

  @override
  String get bookmarkAddChild => '添加子书签';

  @override
  String get bookmarkCollapse => '折叠';

  @override
  String get bookmarkDelete => '删除书签';

  @override
  String get bookmarkEdit => '编辑书签';

  @override
  String get bookmarkEmpty => '无书签';

  @override
  String get bookmarkExpand => '展开';

  @override
  String get bookmarkExpandedByDefault => '默认展开';

  @override
  String get bookmarkNoDestination => '无目标位置';

  @override
  String get bookmarkPageFieldLabel => '页';

  @override
  String bookmarkPageLabel(int number) {
    return '第 $number 页';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => '书签';

  @override
  String get bookmarkTitleLabel => '标题';

  @override
  String get bookmarkUntitled => '无标题';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get close => '关闭';

  @override
  String get colorApplyingChanges => '正在应用颜色更改…';

  @override
  String get colorColorFormat => '颜色格式';

  @override
  String get colorColorTitle => '颜色';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择 $count 种颜色',
      one: '已选择 $count 种颜色',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => '文档颜色';

  @override
  String get colorFillColors => '填充颜色';

  @override
  String get colorFind => '查找';

  @override
  String get colorInDocument => '文档中';

  @override
  String get colorNoColorsFound => '尚未找到颜色';

  @override
  String get colorNoPageContentColors => '未找到页面内容颜色';

  @override
  String get colorPalette => '调色板';

  @override
  String get colorPickColor => '选取颜色';

  @override
  String get colorProcessingTitle => '颜色处理';

  @override
  String get colorRecent => '最近使用';

  @override
  String get colorReplace => '替换';

  @override
  String get colorReplaceWithTransparent => '替换为透明';

  @override
  String get colorScanning => '正在扫描…';

  @override
  String colorScanningProgress(int progress, int total) {
    return '正在扫描 $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return '所选页面（$count）';
  }

  @override
  String get colorStrokeColors => '描边颜色';

  @override
  String get colorTolerance => '容差';

  @override
  String get colorTransparent => '透明';

  @override
  String get colorWholeDocument => '整个文档';

  @override
  String get compareAfter => '之后';

  @override
  String get compareBefore => '之前';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 处更改',
      one: '1 处更改',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 处更改',
      one: '1 处更改',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '（空）';

  @override
  String get compareNextChange => '下一处更改';

  @override
  String get compareNoChanges => '无更改';

  @override
  String get compareNoDifferences => '两个文档之间没有差异';

  @override
  String get compareOverlay => '叠加';

  @override
  String comparePageHeader(int page) {
    return '第 $page 页';
  }

  @override
  String get comparePreviousChange => '上一处更改';

  @override
  String get compareSideBySide => '并排';

  @override
  String get copy => '复制';

  @override
  String get cut => '剪切';

  @override
  String get delete => '删除';

  @override
  String get done => '完成';

  @override
  String get edit => '编辑';

  @override
  String get editorViewAuthorNameTitle => '作者姓名';

  @override
  String get lineStyleDashDot => '点划线';

  @override
  String get lineStyleDashed => '虚线';

  @override
  String get lineStyleDotted => '点线';

  @override
  String get lineStyleSolid => '实线';

  @override
  String get measCalibrate => '校准';

  @override
  String get measCalibrateScale => '校准比例';

  @override
  String get measDepthLabel => '深度：';

  @override
  String get measKindAngle => '角度';

  @override
  String get measKindArc => '弧';

  @override
  String get measKindArea => '面积';

  @override
  String get measKindCount => '计数';

  @override
  String get measKindLength => '长度';

  @override
  String get measKindNetArea => '净面积';

  @override
  String get measKindPerimeter => '周长';

  @override
  String get measKindSlope => '坡度';

  @override
  String get measKindVolume => '体积';

  @override
  String get measLineRepresents => '您绘制的线段代表：';

  @override
  String get measMeasure => '测量';

  @override
  String get measSetScale => '设置测量比例';

  @override
  String get measSetScaleButton => '设置比例';

  @override
  String get measVolumeDepth => '体积深度';

  @override
  String get menuAddNode => '添加节点';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '将注释应用到多个页面',
      one: '将注释应用到多个页面',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => '应用到页面…';

  @override
  String get menuBringToFront => '移到最前';

  @override
  String get menuCheck => '勾选';

  @override
  String get menuChooseValue => '选择值…';

  @override
  String get menuClearCheck => '取消勾选';

  @override
  String get menuConvertToCheckBox => '转换为复选框';

  @override
  String get menuConvertToImageButton => '转换为图像按钮';

  @override
  String get menuConvertToTextField => '转换为文本字段';

  @override
  String get menuDeleteField => '删除字段';

  @override
  String get menuEditValue => '编辑值…';

  @override
  String get menuFieldName => '字段名称';

  @override
  String get menuFieldValue => '字段值';

  @override
  String get menuFlattenForm => '展平表单';

  @override
  String get menuLock => '锁定';

  @override
  String get menuUnlock => '解锁';

  @override
  String get menuRecolour => '重新着色…';

  @override
  String get menuRemoveNode => '移除节点';

  @override
  String get menuSetAsDefaultStyle => '设为默认样式';

  @override
  String get menuRename => '重命名…';

  @override
  String get menuSelectOption => '选择选项';

  @override
  String get menuSendToBack => '移到最后';

  @override
  String get menuSetImage => '设置图像…';

  @override
  String get menuTextStyle => '文本样式…';

  @override
  String get none => '无';

  @override
  String get ok => '确定';

  @override
  String get overlayColor => '颜色';

  @override
  String get overlayEditText => '编辑文本';

  @override
  String get overlayFont => '字体';

  @override
  String get overlayLarger => '增大';

  @override
  String get overlayMore => '更多';

  @override
  String get overlayNote => '便笺';

  @override
  String get overlaySmaller => '减小';

  @override
  String get overlayStampText => '图章文本';

  @override
  String get linkDialogTitle => '添加链接';

  @override
  String get linkKindWeb => '网址';

  @override
  String get linkKindPage => '文档中的页面';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => '页码';

  @override
  String get toolLink => '链接';

  @override
  String get overlayUnderline => '下划线';

  @override
  String pageRangeErrorBounds(int count) {
    return '请输入 1 到 $count 之间的页码。';
  }

  @override
  String get pageRangeErrorOrder => '末页不能早于首页。';

  @override
  String get pageRangeFrom => '从';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '1 页',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => '到';

  @override
  String get panelDragToMovePanel => '拖动以移动面板';

  @override
  String get paste => '粘贴';

  @override
  String get propAlign => '对齐';

  @override
  String get propAlignCenter => '居中对齐';

  @override
  String get propAlignLeft => '左对齐';

  @override
  String get propAlignRight => '右对齐';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个注释',
      one: '$count 个注释',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => '作者';

  @override
  String get propAutoSize => '自动调整大小';

  @override
  String get propBold => '粗体';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => '内置字体';

  @override
  String get propCallout => '标注';

  @override
  String get propCharSpacing => '字符间距';

  @override
  String get propColor => '颜色';

  @override
  String get propColour => '颜色';

  @override
  String get propContents => '内容';

  @override
  String get propEditsApplyToAll => '编辑将应用于所有兼容的注释';

  @override
  String get propFieldName => '字段名称';

  @override
  String get propFieldTypeCheckBox => '复选框';

  @override
  String get propFieldTypeComboBox => '组合框';

  @override
  String get propFieldTypeImageButton => '图像按钮';

  @override
  String get propFieldTypeListBox => '列表框';

  @override
  String get propFieldTypeRadioGroup => '单选按钮组';

  @override
  String get propFieldTypeSignature => '签名';

  @override
  String get propFieldTypeText => '文本字段';

  @override
  String propFieldTypeTooltip(String type) {
    return '字段类型：$type';
  }

  @override
  String get propFieldTypeUnknown => '未知字段';

  @override
  String get propFill => '填充';

  @override
  String get propFont => '字体';

  @override
  String get propFontSubsetTooltip => '此字体为子集 - 只能输入文档中已使用的字符。';

  @override
  String get propFontWidth => '字体宽度';

  @override
  String get propGeometryHeight => '高';

  @override
  String get propGeometryWidth => '宽';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => '斜体';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => '字符受限';

  @override
  String get propLineEnd => '线尾';

  @override
  String get propLineEndingButt => '平头';

  @override
  String get propLineEndingCircle => '圆形';

  @override
  String get propLineEndingClosedArrow => '实心箭头';

  @override
  String get propLineEndingClosedArrowRev => '实心箭头（反向）';

  @override
  String get propLineEndingDiamond => '菱形';

  @override
  String get propLineEndingOpenArrow => '空心箭头';

  @override
  String get propLineEndingOpenArrowRev => '空心箭头（反向）';

  @override
  String get propLineEndingSlash => '斜线';

  @override
  String get propLineEndingSquare => '方形';

  @override
  String get propLineSpacing => '行间距';

  @override
  String get propLineStart => '线首';

  @override
  String get propLineType => '线型';

  @override
  String get propLoadFont => '加载字体…';

  @override
  String get propLoadFontSubtitle => 'TTF 或 OTF 文件';

  @override
  String get propMoreColors => '更多颜色…';

  @override
  String get propMultiline => '多行';

  @override
  String get propNoFill => '无填充';

  @override
  String get propNoFontsFound => '未找到字体';

  @override
  String get propNoOutline => '无轮廓';

  @override
  String get propOpacity => '不透明度';

  @override
  String get propOutline => '轮廓';

  @override
  String get propPageLabel => '页';

  @override
  String propPageNumber(int number) {
    return '第 $number 页';
  }

  @override
  String get propPropertiesTitle => '属性';

  @override
  String get propRecentlyUsed => '最近使用';

  @override
  String get propScale => '缩放';

  @override
  String get propSearchFonts => '搜索字体';

  @override
  String get propSectionAllFonts => '所有字体';

  @override
  String get propSectionAppearance => '外观';

  @override
  String get propSectionContent => '内容';

  @override
  String get propSectionFormField => '表单字段';

  @override
  String get propSectionInThisDocument => '本文档中';

  @override
  String get propSectionPositionSize => '位置和大小（pt）';

  @override
  String get propSectionSelection => '选择';

  @override
  String get propSectionText => '文本';

  @override
  String get propSelectAnnotationPrompt => '选择一个注释以查看其属性';

  @override
  String get propSize => '大小';

  @override
  String get propStandardPdfFont => '标准 PDF 字体';

  @override
  String get propStroke => '描边';

  @override
  String get propStyle => '样式';

  @override
  String get propSystemFont => '系统字体';

  @override
  String get propType => '类型';

  @override
  String get propUnderline => '下划线';

  @override
  String get propVaries => '不一致';

  @override
  String get redo => '重做';

  @override
  String get reflowNoContent => '无可提取的内容';

  @override
  String reflowPageLabel(int number) {
    return '第 $number 页';
  }

  @override
  String get reflowSaveOrShare => '保存或分享';

  @override
  String get reflowViewFigure => '查看图片';

  @override
  String get remove => '移除';

  @override
  String get rename => '重命名';

  @override
  String get reset => '重置';

  @override
  String get save => '保存';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return '第 $page 页';
  }

  @override
  String get sbarCallout => '标注';

  @override
  String get sbarFieldButton => '按钮字段';

  @override
  String get sbarFieldChoice => '选择字段';

  @override
  String get sbarFieldGeneric => '表单字段';

  @override
  String get sbarFieldSignature => '签名字段';

  @override
  String get sbarFieldText => '文本字段';

  @override
  String get sbarStateAccepted => '已接受';

  @override
  String get sbarStateCancelled => '已取消';

  @override
  String get sbarStateMarked => '已标记';

  @override
  String get sbarStateRejected => '已拒绝';

  @override
  String get sbarStateResolved => '已解决';

  @override
  String get sbarStateUnmarked => '未标记';

  @override
  String get searchAnnotations => '搜索注释';

  @override
  String get searchClearSearch => '清除搜索';

  @override
  String get searchEmptyHint => '搜索文档，此处将列出所有匹配项';

  @override
  String get searchMatchCase => '区分大小写';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个匹配项',
      one: '1 个匹配项',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => '下一个匹配项';

  @override
  String searchNoMatches(String query) {
    return '没有与 “$query” 匹配的结果';
  }

  @override
  String searchPageHeader(int page) {
    return '第 $page 页';
  }

  @override
  String get searchPreviousMatch => '上一个匹配项';

  @override
  String get searchRegex => '正则表达式';

  @override
  String get searchResultsTitle => '搜索结果';

  @override
  String get searchWholeWord => '全字匹配';

  @override
  String get shellControls => '控件';

  @override
  String get shellDefaultAuthor => '默认作者…';

  @override
  String get shellHighlightFormFields => '高亮表单字段';

  @override
  String get shellKeyboardShortcutsMenu => '键盘快捷键…';

  @override
  String get shellKeyboardShortcutsTitle => '键盘快捷键';

  @override
  String get shellShortcutsSearchHint => '搜索快捷键';

  @override
  String shellShortcutsNoMatches(String query) {
    return '没有与 “$query” 匹配的快捷键';
  }

  @override
  String get shellShortcutGroupSelect => '选择';

  @override
  String get shellShortcutGroupMarkup => '标记';

  @override
  String get shellShortcutGroupDraw => '绘制';

  @override
  String get shellShortcutGroupShapes => '形状';

  @override
  String get shellShortcutGroupInsert => '插入';

  @override
  String get shellShortcutGroupMeasure => '测量';

  @override
  String get shellShortcutGroupEdit => '编辑';

  @override
  String get shellNotSet => '未设置';

  @override
  String get shellPageColor => '页面颜色…';

  @override
  String get shellPageGrid => '页面网格';

  @override
  String get shellPanelAnnotations => '注释';

  @override
  String get shellPanelBookmarks => '书签';

  @override
  String get shellPanelPages => '页面';

  @override
  String get shellPanelProperties => '属性';

  @override
  String get shellPanelSearchResults => '搜索结果';

  @override
  String get shellPanels => '面板';

  @override
  String get shellPressAKey => '按下一个键';

  @override
  String get shellPressLetterKeyHint => '按字母键，或按 Delete 清除。';

  @override
  String get shellReflow => '重排';

  @override
  String get shellReflowText => '文本重排';

  @override
  String get shellResetZoom => '重置缩放';

  @override
  String get shellSectionShell => '界面';

  @override
  String get shellSectionView => '视图';

  @override
  String get shellSettings => '设置';

  @override
  String get shellShowAnnotations => '显示注释';

  @override
  String get shellTabHere => '停靠为标签页';

  @override
  String get shellUnbound => '未绑定';

  @override
  String get shellZoom => '缩放';

  @override
  String sidebarByAuthor(String author) {
    return '由 $author';
  }

  @override
  String get sidebarCancelSelection => '取消选择';

  @override
  String get sidebarClearSearch => '清除搜索';

  @override
  String get sidebarDeleteSelected => '删除所选';

  @override
  String get sidebarDeleteSignature => '删除签名';

  @override
  String get sidebarLockAnnotation => '锁定';

  @override
  String get sidebarUnlockAnnotation => '解锁';

  @override
  String get sidebarMore => '更多';

  @override
  String get sidebarNoAnnotations => '无注释';

  @override
  String get sidebarNoMatchingAnnotations => '无匹配的注释';

  @override
  String sidebarPageHeader(int number) {
    return '第 $number 页';
  }

  @override
  String get sidebarRemoveSignatureBody => '这将从文档中移除数字签名。您可以撤销此操作。';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return '这将从文档中移除由 \"$name\" 添加的数字签名。您可以撤销此操作。';
  }

  @override
  String get sidebarRemoveSignatureTitle => '移除签名？';

  @override
  String get sidebarReopen => '重新打开';

  @override
  String get sidebarReply => '回复';

  @override
  String get sidebarResolve => '解决';

  @override
  String get sidebarSearchHint => '搜索注释';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 个',
      one: '已选 $count 个',
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
  String get sidebarWriteReplyHint => '写回复…';

  @override
  String get sigTitle => '签名';

  @override
  String get signIdCreate => '创建';

  @override
  String get signIdEmail => '电子邮件（可选）';

  @override
  String get signIdName => '姓名';

  @override
  String get signIdNameHint => '您的姓名，将显示在签名上';

  @override
  String get signIdNameRequired => '请输入姓名';

  @override
  String get signIdOrganization => '组织（可选）';

  @override
  String get signIdSelfSignedInfo =>
      '这将创建一个自签名身份。在 Adobe Acrobat 和其他阅读器中，签名会显示为“已签名，有效性未知”——与它们自己的自签名 ID 相同。绿色对勾需要付费的、受公开信任的 CA。';

  @override
  String get signIdTitle => '创建签名身份';

  @override
  String get stampBox => '方框';

  @override
  String get stampCircle => '圆形';

  @override
  String get stampCustomCaption => '自定义图章';

  @override
  String get stampDateFormat => '日期格式';

  @override
  String get stampDeleteComponent => '删除所选组件';

  @override
  String get stampDeleteStamp => '删除图章';

  @override
  String get stampEditStamp => '编辑图章';

  @override
  String get stampExport => '导出…';

  @override
  String get stampFieldDate => '日期';

  @override
  String get stampFieldDateTime => '日期和时间';

  @override
  String get stampFieldTime => '时间';

  @override
  String get stampFieldUsername => '用户名';

  @override
  String get stampFont => '字体';

  @override
  String get stampFontBold => '粗体';

  @override
  String get stampFontItalic => '斜体';

  @override
  String get stampHeight => '高度';

  @override
  String get stampImage => '图像';

  @override
  String get stampImport => '导入…';

  @override
  String get stampInsertField => '插入字段';

  @override
  String get stampMoreColors => '更多颜色…';

  @override
  String get stampNewStamp => '新建图章…';

  @override
  String get stampNewStampTitle => '新建图章';

  @override
  String get stampSelectTextToEdit => '选择要编辑的文本';

  @override
  String get stampSelectedText => '所选文本';

  @override
  String get stampSignature => '签名';

  @override
  String get stampStamps => '图章';

  @override
  String get stampText => '文本';

  @override
  String get stampTime12Hour => '12 小时';

  @override
  String get stampTime24Hour => '24 小时';

  @override
  String get stampTimeFormat => '时间格式';

  @override
  String get stampWidth => '宽度';

  @override
  String get takeoffArea => '面积';

  @override
  String get takeoffCount => '计数';

  @override
  String get takeoffEmpty => '尚无测量。';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个分组',
      one: '$count 个分组',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个项目',
      one: '$count 个项目',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => '长度';

  @override
  String get takeoffTitle => '工程量统计';

  @override
  String get tbAddInkAnnotation => '添加手绘注释';

  @override
  String get tbAlign => '对齐';

  @override
  String get tbAlignBottom => '底端对齐';

  @override
  String get tbAlignHorizontalCenters => '水平居中对齐';

  @override
  String get tbAlignLeft => '左对齐';

  @override
  String get tbAlignRight => '右对齐';

  @override
  String get tbAlignTop => '顶端对齐';

  @override
  String get tbAlignVerticalCenters => '垂直居中对齐';

  @override
  String get tbAnnotationsFlattened => '注释已展平到页面中';

  @override
  String get tbApplyRedactionsMessage => '标记的内容将从文档中永久移除。此操作无法撤销。';

  @override
  String get tbApplyRedactionsTitle => '应用密文遮盖？';

  @override
  String get tbApplyRedactionsTooltip => '应用密文遮盖（不可逆）';

  @override
  String get tbAutosizeTextBox => '自动调整文本框大小 (Alt+Z)';

  @override
  String get tbCalibrateScaleHint => '绘制一条已知长度的线段以校准比例。';

  @override
  String get tbCharSpacing => '字符间距';

  @override
  String get tbCheckBoxOption => '复选框';

  @override
  String get tbCheckMarksOnDocument => '文档上的勾选标记';

  @override
  String get tbCropImage => '裁剪图像';

  @override
  String get tbCroppingImage => '正在裁剪图像';

  @override
  String get tbCropApply => '应用裁剪';

  @override
  String get tbCropCancel => '取消裁剪';

  @override
  String get tbCropReset => '重置裁剪';

  @override
  String get tbColorLabel => '颜色';

  @override
  String get tbColorProcessingTooltip => '颜色处理 - 查找并替换页面内容颜色';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已替换 $count 种颜色',
      one: '已替换 1 种颜色',
      zero: '未找到匹配的颜色',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => '转换为复选框';

  @override
  String get tbConvertToImageButton => '转换为图像按钮';

  @override
  String get tbConvertToTextField => '转换为文本字段';

  @override
  String get tbCornerRadius => '圆角半径';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除 $count 个注释',
      one: '删除注释',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => '删除元素';

  @override
  String get tbDeleteField => '删除字段';

  @override
  String get tbDiscardDrawing => '放弃绘制';

  @override
  String get tbDistributeHorizontally => '水平分布';

  @override
  String get tbDistributeVertically => '垂直分布';

  @override
  String get tbDrawNewSignature => '绘制新签名…';

  @override
  String get tbEditAnnotationText => '编辑注释文本';

  @override
  String get tbEditTextStyle => '编辑文本和样式';

  @override
  String get tbElement => '元素';

  @override
  String get tbEraserSize => '橡皮擦大小';

  @override
  String get tbFieldActions => '字段操作';

  @override
  String get tbFieldName => '字段名称';

  @override
  String tbFieldNamed(String name) {
    return '字段：$name';
  }

  @override
  String get tbFieldValue => '字段值';

  @override
  String get tbFill => '填充';

  @override
  String get tbFingerDraws => '手指绘制 - 点按可改为滚动';

  @override
  String get tbFingerScrolls => '手指滚动（触控笔绘制）- 点按可改为绘制';

  @override
  String get tbFlattenAnnotationsTooltip => '将注释展平到页面中';

  @override
  String get tbFlattenForm => '展平表单';

  @override
  String get tbFlattenFormBakeValues => '展平表单 - 将值固化到页面中';

  @override
  String get tbFlattenLabel => '展平';

  @override
  String get tbFont => '字体';

  @override
  String get tbFontSize => '字号';

  @override
  String get tbFontWidth => '字体宽度';

  @override
  String get tbFormFieldsFlattened => '表单字段已展平到页面中';

  @override
  String get tbGroupDraw => '绘制';

  @override
  String get tbGroupEdit => '编辑';

  @override
  String get tbGroupInsert => '插入';

  @override
  String get tbGroupMarkup => '标记';

  @override
  String get tbGroupMeasure => '测量';

  @override
  String get tbGroupSelect => '选择';

  @override
  String get tbGroupShapes => '形状';

  @override
  String get tbImageButtonOption => '图像按钮';

  @override
  String get tbLineEnd => '线尾';

  @override
  String get tbLineSpacing => '行间距';

  @override
  String get tbLineStart => '线首';

  @override
  String get tbLineType => '线型';

  @override
  String get tbManageStamps => '管理图章…';

  @override
  String get tbMarkupHighlight => '高亮';

  @override
  String get tbMarkupHighlightTip => '高亮所选内容';

  @override
  String get tbMarkupSquiggly => '波浪下划线';

  @override
  String get tbMarkupSquigglyTip => '为所选内容添加波浪下划线';

  @override
  String get tbMarkupStrikeOut => '删除线';

  @override
  String get tbMarkupStrikeOutTip => '为所选内容添加删除线';

  @override
  String get tbMarkupUnderline => '下划线';

  @override
  String get tbMarkupUnderlineTip => '为所选内容添加下划线';

  @override
  String get tbMoreColors => '更多颜色…';

  @override
  String get tbNameArrow => '箭头';

  @override
  String get tbNameCallout => '标注';

  @override
  String get tbNameCloudPolygon => '云形多边形';

  @override
  String get tbNameCount => '计数';

  @override
  String get tbNameDigitalSignature => '数字签名';

  @override
  String get tbNameDraw => '绘制';

  @override
  String get tbNameEllipse => '椭圆';

  @override
  String get tbNameEraser => '擦除手绘笔迹';

  @override
  String get tbNameHighlight => '高亮';

  @override
  String get tbNameImage => '图像';

  @override
  String get tbNameLine => '直线';

  @override
  String get tbNameMeasureAngle => '测量角度';

  @override
  String get tbNameMeasureArc => '测量弧长';

  @override
  String get tbNameMeasureArea => '测量面积';

  @override
  String get tbNameMeasureDistance => '测量距离';

  @override
  String get tbNameMeasurePerimeter => '测量周长';

  @override
  String get tbNameMeasureSlope => '测量坡度（垂直/水平）';

  @override
  String get tbNameMeasureVolume => '测量体积（面积 × 深度）';

  @override
  String get tbNameNote => '便笺';

  @override
  String get tbNamePolygon => '多边形';

  @override
  String get tbNamePolyline => '折线';

  @override
  String get tbNameRectangle => '矩形';

  @override
  String get tbNameSelect => '选择';

  @override
  String get tbNameSignature => '签名';

  @override
  String get tbNameStamp => '图章';

  @override
  String get tbNameTextBox => '文本框';

  @override
  String get tbNewFieldType => '新建字段类型 - 在页面上拖动以添加';

  @override
  String get tbNoAnnotationsToFlatten => '没有可展平的注释';

  @override
  String get tbNoCustomStamps => '无自定义图章';

  @override
  String get tbNoFormFieldsToFlatten => '没有可展平的表单字段';

  @override
  String get tbNoRedactionsToApply => '没有可应用的密文遮盖';

  @override
  String get tbNoteTitle => '便笺';

  @override
  String get tbOpacity => '不透明度';

  @override
  String get tbOutline => '轮廓';

  @override
  String get tbPatternScale => '图案缩放';

  @override
  String get tbPickColorFromPage => '从页面选取颜色';

  @override
  String get tbRedactionsApplied => '已应用密文遮盖';

  @override
  String get tbRedoShortcut => '重做 (⇧⌘Z)';

  @override
  String get tbReflowFailed => '无法重排 - 这不是此工具可重新排版的单栏段落。请改用“替换文本”。';

  @override
  String get tbReflowParagraph => '重排段落';

  @override
  String get tbRenameField => '重命名字段';

  @override
  String get tbRenameFieldEllipsis => '重命名字段…';

  @override
  String get tbReplaceImage => '替换图像';

  @override
  String get tbReplaceImageFailed => '无法替换图像';

  @override
  String get tbReplaceText => '替换文本';

  @override
  String get tbSaveImage => '保存图像';

  @override
  String get tbSaveShortcut => '保存… (⌘S / Ctrl+S)';

  @override
  String get tbScale => '比例';

  @override
  String get tbSelectTextForMarkup => '选择文本以使用标记';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 个',
      one: '选择',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => '设置…';

  @override
  String get tbStamp => '图章';

  @override
  String get tbStampText => '图章文本';

  @override
  String get tbStrokeOpacityFont => '描边、不透明度、字体';

  @override
  String get tbStrokeWidthLabel => '描边宽度';

  @override
  String tbStrokeWidthPreset(String width) {
    return '描边 $width';
  }

  @override
  String get tbStyle => '样式';

  @override
  String get tbTakeoffTotals => '工程量合计';

  @override
  String get tbTextBorder => '文本边框';

  @override
  String get tbTextColour => '文本颜色';

  @override
  String get tbTextFieldOption => '文本字段';

  @override
  String get tbTextFill => '文本填充';

  @override
  String get tbTextStyleEllipsis => '文本样式…';

  @override
  String get tbTextTitle => '文本';

  @override
  String get tbTipCallout => '标注 - 从指示点拖动到文本框的位置';

  @override
  String get tbTipContent => '编辑页面内容';

  @override
  String get tbTipCount => '计数 - 点按以放置勾选标记并统计';

  @override
  String get tbTipDigitalSignature => '数字签名 - 拖出一个框以放置并签名';

  @override
  String get tbTipForm => '表单字段 - 点按选择，双击填写，拖动添加';

  @override
  String get tbTipHighlightDraw => '高亮 - 手绘';

  @override
  String get tbTipImage => '图像 - 点按放置，或拖出一个框';

  @override
  String get tbTipMeasureAngle => '测量角度 - 点击三个点';

  @override
  String get tbTipMeasureArc => '测量弧长 - 点击三个点';

  @override
  String get tbTipRedact => '密文遮盖 - 拖出一个区域，然后应用';

  @override
  String get tbTipSignature => '签名 - 点按页面以放置';

  @override
  String get tbTipSnapshot => '快照 - 拖出一个区域以捕获（可作为矢量粘贴回去）';

  @override
  String get tbToolContent => '内容';

  @override
  String get tbToolForm => '表单';

  @override
  String get tbToolRedact => '密文遮盖';

  @override
  String get tbToolSnapshot => '快照';

  @override
  String get tbTools => '工具';

  @override
  String get tbTotals => '合计';

  @override
  String get tbTypeTextEachTime => '每次输入文本';

  @override
  String get tbUnderline => '下划线';

  @override
  String get tbUndoShortcut => '撤销 (⌘Z)';

  @override
  String get textStyleFont => '字体';

  @override
  String get textStyleFontSize => '字号';

  @override
  String get textStyleKeep => '保持';

  @override
  String get textStyleStyle => '样式';

  @override
  String get textStyleText => '文本';

  @override
  String get textStyleTextFill => '文本填充';

  @override
  String get textStyleTitle => '编辑文本和样式';

  @override
  String get thumbAddPage => '添加页面';

  @override
  String get thumbClearSelection => '清除选择';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '复制 $count 页',
      one: '复制页面',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => '复制所选页面';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '剪切 $count 页',
      one: '剪切页面',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => '剪切所选页面';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除 $count 页',
      one: '删除页面',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => '删除所选页面';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '生成 $count 页副本',
      one: '生成页面副本',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => '导出页面…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '导出 $count 页…',
      one: '导出页面…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => '导出所选页面';

  @override
  String get thumbInsertBlankAfter => '在之后插入空白页';

  @override
  String get thumbInsertBlankBefore => '在之前插入空白页';

  @override
  String get thumbInsertFileFailed => '无法插入该文件。';

  @override
  String get thumbInsertPdf => '插入 PDF…';

  @override
  String get thumbPageActions => '页面操作';

  @override
  String thumbPageNumber(int number) {
    return '第 $number 页';
  }

  @override
  String get thumbPages => '页面';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '粘贴 $count 页',
      one: '粘贴页面',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '旋转 180°';

  @override
  String get thumbRotateLeft => '向左旋转';

  @override
  String get thumbRotatePageRight => '向右旋转页面';

  @override
  String get thumbRotateRight => '向右旋转';

  @override
  String get thumbRotateSelectedLeft => '向左旋转所选页面';

  @override
  String get thumbRotateSelectedRight => '向右旋转所选页面';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选 $count 个',
      one: '已选 $count 个',
    );
    return '$_temp0';
  }

  @override
  String get undo => '撤销';

  @override
  String get viewerEditFontUnsafe => '无法安全地编辑此 PDF 字体或编码。';

  @override
  String get viewerEditNeedsSinglePage => '编辑要求所选内容在同一页面上。';

  @override
  String get viewerEditNotEditableRun => '此选择不是单个可编辑的页面内容文本段。';

  @override
  String get viewerEditStyleUnchangeable => '此 PDF 字体可重新输入，但无法更改其样式。';

  @override
  String get viewerEditTextStyle => '编辑文本和样式';

  @override
  String get viewerMarkup => '标记';

  @override
  String get viewerMarkupHighlight => '高亮';

  @override
  String get viewerMarkupSquiggly => '波浪线';

  @override
  String get viewerMarkupStrikeOut => '删除线';

  @override
  String get viewerMarkupUnderline => '下划线';

  @override
  String get viewerSelectAll => '全选';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class DartPdfEditorLocalizationsZhHant extends DartPdfEditorLocalizationsZh {
  DartPdfEditorLocalizationsZhHant() : super('zh_Hant');

  @override
  String get add => '新增';

  @override
  String get annotCaret => '插入符號';

  @override
  String get annotCircle => '圓形';

  @override
  String get annotFileAttachment => '檔案附件';

  @override
  String get annotFreeText => '文字方塊';

  @override
  String get annotHighlight => '醒目提示';

  @override
  String get annotInk => '手繪';

  @override
  String get annotLine => '線條';

  @override
  String get annotLink => '連結';

  @override
  String get annotPolygon => '多邊形';

  @override
  String get annotPolyline => '折線';

  @override
  String get annotRedact => '塗黑';

  @override
  String get annotSquare => '方形';

  @override
  String get annotSquiggly => '波浪線';

  @override
  String get annotStamp => '戳記';

  @override
  String get annotStrikeOut => '刪除線';

  @override
  String get annotText => '便箋';

  @override
  String get annotUnderline => '底線';

  @override
  String get annotWidget => '表單欄位';

  @override
  String get apply => '套用';

  @override
  String get bookmarkAdd => '新增書籤';

  @override
  String get bookmarkAddChild => '新增子書籤';

  @override
  String get bookmarkCollapse => '收合';

  @override
  String get bookmarkDelete => '刪除書籤';

  @override
  String get bookmarkEdit => '編輯書籤';

  @override
  String get bookmarkEmpty => '沒有書籤';

  @override
  String get bookmarkExpand => '展開';

  @override
  String get bookmarkExpandedByDefault => '預設展開';

  @override
  String get bookmarkNoDestination => '沒有目的地';

  @override
  String get bookmarkPageFieldLabel => '頁面';

  @override
  String bookmarkPageLabel(int number) {
    return '第 $number 頁';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => '書籤';

  @override
  String get bookmarkTitleLabel => '標題';

  @override
  String get bookmarkUntitled => '未命名';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get close => '關閉';

  @override
  String get colorApplyingChanges => '正在套用顏色變更…';

  @override
  String get colorColorFormat => '顏色格式';

  @override
  String get colorColorTitle => '顏色';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 個顏色',
      one: '已選取 $count 個顏色',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => '文件顏色';

  @override
  String get colorFillColors => '填滿顏色';

  @override
  String get colorFind => '尋找';

  @override
  String get colorInDocument => '文件中';

  @override
  String get colorNoColorsFound => '尚未找到顏色';

  @override
  String get colorNoPageContentColors => '找不到頁面內容顏色';

  @override
  String get colorPalette => '調色盤';

  @override
  String get colorPickColor => '挑選顏色';

  @override
  String get colorProcessingTitle => '顏色處理';

  @override
  String get colorRecent => '最近使用';

  @override
  String get colorReplace => '取代';

  @override
  String get colorReplaceWithTransparent => '取代為透明';

  @override
  String get colorScanning => '掃描中…';

  @override
  String colorScanningProgress(int progress, int total) {
    return '掃描 $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return '選取的頁面 ($count)';
  }

  @override
  String get colorStrokeColors => '線條顏色';

  @override
  String get colorTolerance => '容許度';

  @override
  String get colorTransparent => '透明';

  @override
  String get colorWholeDocument => '整份文件';

  @override
  String get compareAfter => '之後';

  @override
  String get compareBefore => '之前';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項變更',
      one: '1 項變更',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項變更',
      one: '1 項變更',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '（空白）';

  @override
  String get compareNextChange => '下一項變更';

  @override
  String get compareNoChanges => '沒有變更';

  @override
  String get compareNoDifferences => '兩份文件之間沒有差異';

  @override
  String get compareOverlay => '疊加';

  @override
  String comparePageHeader(int page) {
    return '第 $page 頁';
  }

  @override
  String get comparePreviousChange => '上一項變更';

  @override
  String get compareSideBySide => '並排';

  @override
  String get copy => '複製';

  @override
  String get cut => '剪下';

  @override
  String get delete => '刪除';

  @override
  String get done => '完成';

  @override
  String get edit => '編輯';

  @override
  String get editorViewAuthorNameTitle => '作者名稱';

  @override
  String get lineStyleDashDot => '點虛線';

  @override
  String get lineStyleDashed => '虛線';

  @override
  String get lineStyleDotted => '點線';

  @override
  String get lineStyleSolid => '實線';

  @override
  String get measCalibrate => '校準';

  @override
  String get measCalibrateScale => '校準比例';

  @override
  String get measDepthLabel => '深度： ';

  @override
  String get measKindAngle => '角度';

  @override
  String get measKindArc => '弧';

  @override
  String get measKindArea => '面積';

  @override
  String get measKindCount => '計數';

  @override
  String get measKindLength => '長度';

  @override
  String get measKindNetArea => '淨面積';

  @override
  String get measKindPerimeter => '周長';

  @override
  String get measKindSlope => '坡度';

  @override
  String get measKindVolume => '體積';

  @override
  String get measLineRepresents => '您繪製的線條代表：';

  @override
  String get measMeasure => '測量';

  @override
  String get measSetScale => '設定測量比例';

  @override
  String get measSetScaleButton => '設定比例';

  @override
  String get measVolumeDepth => '體積深度';

  @override
  String get menuAddNode => '新增節點';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '將註解套用至頁面',
      one: '將註解套用至頁面',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => '套用至頁面…';

  @override
  String get menuBringToFront => '移至最上層';

  @override
  String get menuCheck => '勾選';

  @override
  String get menuChooseValue => '選擇值…';

  @override
  String get menuClearCheck => '清除勾選';

  @override
  String get menuConvertToCheckBox => '轉換為核取方塊';

  @override
  String get menuConvertToImageButton => '轉換為影像按鈕';

  @override
  String get menuConvertToTextField => '轉換為文字欄位';

  @override
  String get menuDeleteField => '刪除欄位';

  @override
  String get menuEditValue => '編輯值…';

  @override
  String get menuFieldName => '欄位名稱';

  @override
  String get menuFieldValue => '欄位值';

  @override
  String get menuFlattenForm => '平面化表單';

  @override
  String get menuLock => '鎖定';

  @override
  String get menuUnlock => '解鎖';

  @override
  String get menuRecolour => '重新上色…';

  @override
  String get menuRemoveNode => '移除節點';

  @override
  String get menuSetAsDefaultStyle => '設為預設樣式';

  @override
  String get menuRename => '重新命名…';

  @override
  String get menuSelectOption => '選取選項';

  @override
  String get menuSendToBack => '移至最下層';

  @override
  String get menuSetImage => '設定影像…';

  @override
  String get menuTextStyle => '文字樣式…';

  @override
  String get none => '無';

  @override
  String get ok => '確定';

  @override
  String get overlayColor => '顏色';

  @override
  String get overlayEditText => '編輯文字';

  @override
  String get overlayFont => '字型';

  @override
  String get overlayLarger => '放大';

  @override
  String get overlayMore => '更多';

  @override
  String get overlayNote => '便箋';

  @override
  String get overlaySmaller => '縮小';

  @override
  String get overlayStampText => '戳記文字';

  @override
  String get linkDialogTitle => '新增連結';

  @override
  String get linkKindWeb => '網址';

  @override
  String get linkKindPage => '文件中的頁面';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => '頁碼';

  @override
  String get toolLink => '連結';

  @override
  String get overlayUnderline => '底線';

  @override
  String pageRangeErrorBounds(int count) {
    return '請輸入 1 到 $count 之間的頁碼。';
  }

  @override
  String get pageRangeErrorOrder => '最後一頁不得早於第一頁。';

  @override
  String get pageRangeFrom => '從';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 頁',
      one: '1 頁',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => '至';

  @override
  String get panelDragToMovePanel => '拖曳以移動面板';

  @override
  String get paste => '貼上';

  @override
  String get propAlign => '對齊';

  @override
  String get propAlignCenter => '置中對齊';

  @override
  String get propAlignLeft => '靠左對齊';

  @override
  String get propAlignRight => '靠右對齊';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個註解',
      one: '$count 個註解',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => '作者';

  @override
  String get propAutoSize => '自動調整大小';

  @override
  String get propBold => '粗體';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => '隨附字型';

  @override
  String get propCallout => '圖說文字';

  @override
  String get propCharSpacing => '字元間距';

  @override
  String get propColor => '顏色';

  @override
  String get propColour => '顏色';

  @override
  String get propContents => '內容';

  @override
  String get propEditsApplyToAll => '編輯會套用至所有相容的註解';

  @override
  String get propFieldName => '欄位名稱';

  @override
  String get propFieldTypeCheckBox => '核取方塊';

  @override
  String get propFieldTypeComboBox => '下拉式方塊';

  @override
  String get propFieldTypeImageButton => '影像按鈕';

  @override
  String get propFieldTypeListBox => '清單方塊';

  @override
  String get propFieldTypeRadioGroup => '選項按鈕群組';

  @override
  String get propFieldTypeSignature => '簽章';

  @override
  String get propFieldTypeText => '文字欄位';

  @override
  String propFieldTypeTooltip(String type) {
    return '欄位類型：$type';
  }

  @override
  String get propFieldTypeUnknown => '未知欄位';

  @override
  String get propFill => '填滿';

  @override
  String get propFont => '字型';

  @override
  String get propFontSubsetTooltip => '此字型為子集 - 只能輸入文件中已使用的字元。';

  @override
  String get propFontWidth => '字型寬度';

  @override
  String get propGeometryHeight => '高';

  @override
  String get propGeometryWidth => '寬';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => '斜體';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => '字元受限';

  @override
  String get propLineEnd => '線條終點';

  @override
  String get propLineEndingButt => '平端';

  @override
  String get propLineEndingCircle => '圓形';

  @override
  String get propLineEndingClosedArrow => '實心箭頭';

  @override
  String get propLineEndingClosedArrowRev => '實心箭頭（反向）';

  @override
  String get propLineEndingDiamond => '菱形';

  @override
  String get propLineEndingOpenArrow => '開口箭頭';

  @override
  String get propLineEndingOpenArrowRev => '開口箭頭（反向）';

  @override
  String get propLineEndingSlash => '斜線';

  @override
  String get propLineEndingSquare => '方形';

  @override
  String get propLineSpacing => '行距';

  @override
  String get propLineStart => '線條起點';

  @override
  String get propLineType => '線條類型';

  @override
  String get propLoadFont => '載入字型…';

  @override
  String get propLoadFontSubtitle => 'TTF 或 OTF 檔案';

  @override
  String get propMoreColors => '更多顏色…';

  @override
  String get propMultiline => '多行';

  @override
  String get propNoFill => '無填滿';

  @override
  String get propNoFontsFound => '找不到字型';

  @override
  String get propNoOutline => '無外框';

  @override
  String get propOpacity => '不透明度';

  @override
  String get propOutline => '外框';

  @override
  String get propPageLabel => '頁面';

  @override
  String propPageNumber(int number) {
    return '第 $number 頁';
  }

  @override
  String get propPropertiesTitle => '屬性';

  @override
  String get propRecentlyUsed => '最近使用';

  @override
  String get propScale => '縮放';

  @override
  String get propSearchFonts => '搜尋字型';

  @override
  String get propSectionAllFonts => '所有字型';

  @override
  String get propSectionAppearance => '外觀';

  @override
  String get propSectionContent => '內容';

  @override
  String get propSectionFormField => '表單欄位';

  @override
  String get propSectionInThisDocument => '此文件中';

  @override
  String get propSectionPositionSize => '位置與大小 (pt)';

  @override
  String get propSectionSelection => '選取範圍';

  @override
  String get propSectionText => '文字';

  @override
  String get propSelectAnnotationPrompt => '選取註解以查看其屬性';

  @override
  String get propSize => '大小';

  @override
  String get propStandardPdfFont => '標準 PDF 字型';

  @override
  String get propStroke => '筆畫寬度';

  @override
  String get propStyle => '樣式';

  @override
  String get propSystemFont => '系統字型';

  @override
  String get propType => '類型';

  @override
  String get propUnderline => '底線';

  @override
  String get propVaries => '不一';

  @override
  String get redo => '重做';

  @override
  String get reflowNoContent => '沒有可擷取的內容';

  @override
  String reflowPageLabel(int number) {
    return '第 $number 頁';
  }

  @override
  String get reflowSaveOrShare => '儲存或分享';

  @override
  String get reflowViewFigure => '檢視圖片';

  @override
  String get remove => '移除';

  @override
  String get rename => '重新命名';

  @override
  String get reset => '重設';

  @override
  String get save => '儲存';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return '第 $page 頁';
  }

  @override
  String get sbarCallout => '圖說文字';

  @override
  String get sbarFieldButton => '按鈕欄位';

  @override
  String get sbarFieldChoice => '選擇欄位';

  @override
  String get sbarFieldGeneric => '表單欄位';

  @override
  String get sbarFieldSignature => '簽章欄位';

  @override
  String get sbarFieldText => '文字欄位';

  @override
  String get sbarStateAccepted => '已接受';

  @override
  String get sbarStateCancelled => '已取消';

  @override
  String get sbarStateMarked => '已標記';

  @override
  String get sbarStateRejected => '已拒絕';

  @override
  String get sbarStateResolved => '已解決';

  @override
  String get sbarStateUnmarked => '未標記';

  @override
  String get searchAnnotations => '搜尋註解';

  @override
  String get searchClearSearch => '清除搜尋';

  @override
  String get searchEmptyHint => '搜尋文件以在此列出所有相符項目';

  @override
  String get searchMatchCase => '大小寫相符';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個相符項目',
      one: '1 個相符項目',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => '下一個相符項目';

  @override
  String searchNoMatches(String query) {
    return '找不到「$query」的相符項目';
  }

  @override
  String searchPageHeader(int page) {
    return '第 $page 頁';
  }

  @override
  String get searchPreviousMatch => '上一個相符項目';

  @override
  String get searchRegex => '正規表示式';

  @override
  String get searchResultsTitle => '搜尋結果';

  @override
  String get searchWholeWord => '全字相符';

  @override
  String get shellControls => '控制項';

  @override
  String get shellDefaultAuthor => '預設作者…';

  @override
  String get shellHighlightFormFields => '標示表單欄位';

  @override
  String get shellKeyboardShortcutsMenu => '鍵盤快速鍵…';

  @override
  String get shellKeyboardShortcutsTitle => '鍵盤快速鍵';

  @override
  String get shellShortcutsSearchHint => '搜尋快速鍵';

  @override
  String shellShortcutsNoMatches(String query) {
    return '沒有符合「$query」的快速鍵';
  }

  @override
  String get shellShortcutGroupSelect => '選取';

  @override
  String get shellShortcutGroupMarkup => '標記';

  @override
  String get shellShortcutGroupDraw => '繪製';

  @override
  String get shellShortcutGroupShapes => '形狀';

  @override
  String get shellShortcutGroupInsert => '插入';

  @override
  String get shellShortcutGroupMeasure => '測量';

  @override
  String get shellShortcutGroupEdit => '編輯';

  @override
  String get shellNotSet => '未設定';

  @override
  String get shellPageColor => '頁面顏色…';

  @override
  String get shellPageGrid => '頁面網格';

  @override
  String get shellPanelAnnotations => '註解';

  @override
  String get shellPanelBookmarks => '書籤';

  @override
  String get shellPanelPages => '頁面';

  @override
  String get shellPanelProperties => '屬性';

  @override
  String get shellPanelSearchResults => '搜尋結果';

  @override
  String get shellPanels => '面板';

  @override
  String get shellPressAKey => '按下按鍵';

  @override
  String get shellPressLetterKeyHint => '按下字母鍵，或按 Delete 清除。';

  @override
  String get shellReflow => '重排';

  @override
  String get shellReflowText => '文字重排';

  @override
  String get shellResetZoom => '重設縮放';

  @override
  String get shellSectionShell => '外殼';

  @override
  String get shellSectionView => '檢視';

  @override
  String get shellSettings => '設定';

  @override
  String get shellShowAnnotations => '顯示註解';

  @override
  String get shellTabHere => '在此建立分頁';

  @override
  String get shellUnbound => '未綁定';

  @override
  String get shellZoom => '縮放';

  @override
  String sidebarByAuthor(String author) {
    return '由 $author';
  }

  @override
  String get sidebarCancelSelection => '取消選取';

  @override
  String get sidebarClearSearch => '清除搜尋';

  @override
  String get sidebarDeleteSelected => '刪除選取項目';

  @override
  String get sidebarDeleteSignature => '刪除簽章';

  @override
  String get sidebarLockAnnotation => '鎖定';

  @override
  String get sidebarUnlockAnnotation => '解鎖';

  @override
  String get sidebarMore => '更多';

  @override
  String get sidebarNoAnnotations => '沒有註解';

  @override
  String get sidebarNoMatchingAnnotations => '沒有相符的註解';

  @override
  String sidebarPageHeader(int number) {
    return '第 $number 頁';
  }

  @override
  String get sidebarRemoveSignatureBody => '這會從文件中移除數位簽章。您可以復原此操作。';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return '這會從文件中移除由「$name」建立的數位簽章。您可以復原此操作。';
  }

  @override
  String get sidebarRemoveSignatureTitle => '移除簽章？';

  @override
  String get sidebarReopen => '重新開啟';

  @override
  String get sidebarReply => '回覆';

  @override
  String get sidebarResolve => '解決';

  @override
  String get sidebarSearchHint => '搜尋註解';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 個',
      one: '已選取 $count 個',
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
  String get sidebarWriteReplyHint => '撰寫回覆…';

  @override
  String get sigTitle => '簽名';

  @override
  String get signIdCreate => '建立';

  @override
  String get signIdEmail => '電子郵件（選填）';

  @override
  String get signIdName => '名稱';

  @override
  String get signIdNameHint => '您的名稱，會顯示在簽名上';

  @override
  String get signIdNameRequired => '請輸入名稱';

  @override
  String get signIdOrganization => '組織（選填）';

  @override
  String get signIdSelfSignedInfo =>
      '這會建立自我簽署的身分。在 Adobe Acrobat 及其他閱讀器中，簽章會顯示為「已簽署，有效性未知」- 與它們自己的自我簽署 ID 相同。綠色勾號需要付費且受公開信任的 CA。';

  @override
  String get signIdTitle => '建立簽署身分';

  @override
  String get stampBox => '方框';

  @override
  String get stampCircle => '圓形';

  @override
  String get stampCustomCaption => '自訂戳記';

  @override
  String get stampDateFormat => '日期格式';

  @override
  String get stampDeleteComponent => '刪除選取的元件';

  @override
  String get stampDeleteStamp => '刪除戳記';

  @override
  String get stampEditStamp => '編輯戳記';

  @override
  String get stampExport => '匯出…';

  @override
  String get stampFieldDate => '日期';

  @override
  String get stampFieldDateTime => '日期與時間';

  @override
  String get stampFieldTime => '時間';

  @override
  String get stampFieldUsername => '使用者名稱';

  @override
  String get stampFont => '字型';

  @override
  String get stampFontBold => '粗體';

  @override
  String get stampFontItalic => '斜體';

  @override
  String get stampHeight => '高度';

  @override
  String get stampImage => '影像';

  @override
  String get stampImport => '匯入…';

  @override
  String get stampInsertField => '插入欄位';

  @override
  String get stampMoreColors => '更多顏色…';

  @override
  String get stampNewStamp => '新增戳記…';

  @override
  String get stampNewStampTitle => '新增戳記';

  @override
  String get stampSelectTextToEdit => '選取文字以編輯';

  @override
  String get stampSelectedText => '選取的文字';

  @override
  String get stampSignature => '簽名';

  @override
  String get stampStamps => '戳記';

  @override
  String get stampText => '文字';

  @override
  String get stampTime12Hour => '12 小時';

  @override
  String get stampTime24Hour => '24 小時';

  @override
  String get stampTimeFormat => '時間格式';

  @override
  String get stampWidth => '寬度';

  @override
  String get takeoffArea => '面積';

  @override
  String get takeoffCount => '計數';

  @override
  String get takeoffEmpty => '尚無測量。';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個群組',
      one: '$count 個群組',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個項目',
      one: '$count 個項目',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => '長度';

  @override
  String get takeoffTitle => '估算';

  @override
  String get tbAddInkAnnotation => '新增手繪註解';

  @override
  String get tbAlign => '對齊';

  @override
  String get tbAlignBottom => '靠下對齊';

  @override
  String get tbAlignHorizontalCenters => '水平置中對齊';

  @override
  String get tbAlignLeft => '靠左對齊';

  @override
  String get tbAlignRight => '靠右對齊';

  @override
  String get tbAlignTop => '靠上對齊';

  @override
  String get tbAlignVerticalCenters => '垂直置中對齊';

  @override
  String get tbAnnotationsFlattened => '已將註解平面化至頁面';

  @override
  String get tbApplyRedactionsMessage => '標記的內容將從文件中永久移除。此操作無法復原。';

  @override
  String get tbApplyRedactionsTitle => '套用塗黑？';

  @override
  String get tbApplyRedactionsTooltip => '套用塗黑（無法復原）';

  @override
  String get tbAutosizeTextBox => '自動調整文字方塊大小 (Alt+Z)';

  @override
  String get tbCalibrateScaleHint => '繪製一條已知長度的線條以校準比例。';

  @override
  String get tbCharSpacing => '字元間距';

  @override
  String get tbCheckBoxOption => '核取方塊';

  @override
  String get tbCheckMarksOnDocument => '文件上的勾選標記';

  @override
  String get tbCropImage => '裁剪影像';

  @override
  String get tbCroppingImage => '正在裁剪影像';

  @override
  String get tbCropApply => '套用裁剪';

  @override
  String get tbCropCancel => '取消裁剪';

  @override
  String get tbCropReset => '重設裁剪';

  @override
  String get tbColorLabel => '顏色';

  @override
  String get tbColorProcessingTooltip => '顏色處理 - 尋找並取代頁面內容顏色';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已取代 $count 個顏色',
      one: '已取代 1 個顏色',
      zero: '找不到相符的顏色',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => '轉換為核取方塊';

  @override
  String get tbConvertToImageButton => '轉換為影像按鈕';

  @override
  String get tbConvertToTextField => '轉換為文字欄位';

  @override
  String get tbCornerRadius => '圓角半徑';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '刪除 $count 個註解',
      one: '刪除註解',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => '刪除元素';

  @override
  String get tbDeleteField => '刪除欄位';

  @override
  String get tbDiscardDrawing => '捨棄繪圖';

  @override
  String get tbDistributeHorizontally => '水平均分';

  @override
  String get tbDistributeVertically => '垂直均分';

  @override
  String get tbDrawNewSignature => '繪製新簽名…';

  @override
  String get tbEditAnnotationText => '編輯註解文字';

  @override
  String get tbEditTextStyle => '編輯文字與樣式';

  @override
  String get tbElement => '元素';

  @override
  String get tbEraserSize => '橡皮擦大小';

  @override
  String get tbFieldActions => '欄位動作';

  @override
  String get tbFieldName => '欄位名稱';

  @override
  String tbFieldNamed(String name) {
    return '欄位：$name';
  }

  @override
  String get tbFieldValue => '欄位值';

  @override
  String get tbFill => '填滿';

  @override
  String get tbFingerDraws => '手指繪圖 - 點一下改為捲動';

  @override
  String get tbFingerScrolls => '手指捲動（觸控筆繪圖）- 點一下改為繪圖';

  @override
  String get tbFlattenAnnotationsTooltip => '將註解平面化至頁面';

  @override
  String get tbFlattenForm => '平面化表單';

  @override
  String get tbFlattenFormBakeValues => '平面化表單 - 將值烙印至頁面';

  @override
  String get tbFlattenLabel => '平面化';

  @override
  String get tbFont => '字型';

  @override
  String get tbFontSize => '字型大小';

  @override
  String get tbFontWidth => '字型寬度';

  @override
  String get tbFormFieldsFlattened => '已將表單欄位平面化至頁面';

  @override
  String get tbGroupDraw => '繪製';

  @override
  String get tbGroupEdit => '編輯';

  @override
  String get tbGroupInsert => '插入';

  @override
  String get tbGroupMarkup => '標記';

  @override
  String get tbGroupMeasure => '測量';

  @override
  String get tbGroupSelect => '選取';

  @override
  String get tbGroupShapes => '形狀';

  @override
  String get tbImageButtonOption => '影像按鈕';

  @override
  String get tbLineEnd => '線條終點';

  @override
  String get tbLineSpacing => '行距';

  @override
  String get tbLineStart => '線條起點';

  @override
  String get tbLineType => '線條類型';

  @override
  String get tbManageStamps => '管理戳記…';

  @override
  String get tbMarkupHighlight => '醒目提示';

  @override
  String get tbMarkupHighlightTip => '醒目提示選取範圍';

  @override
  String get tbMarkupSquiggly => '波浪底線';

  @override
  String get tbMarkupSquigglyTip => '為選取範圍加上波浪底線';

  @override
  String get tbMarkupStrikeOut => '刪除線';

  @override
  String get tbMarkupStrikeOutTip => '為選取範圍加上刪除線';

  @override
  String get tbMarkupUnderline => '底線';

  @override
  String get tbMarkupUnderlineTip => '為選取範圍加上底線';

  @override
  String get tbMoreColors => '更多顏色…';

  @override
  String get tbNameArrow => '箭頭';

  @override
  String get tbNameCallout => '圖說文字';

  @override
  String get tbNameCloudPolygon => '雲形多邊形';

  @override
  String get tbNameCount => '計數';

  @override
  String get tbNameDigitalSignature => '數位簽章';

  @override
  String get tbNameDraw => '繪製';

  @override
  String get tbNameEllipse => '橢圓形';

  @override
  String get tbNameEraser => '擦除手繪筆畫';

  @override
  String get tbNameHighlight => '醒目提示';

  @override
  String get tbNameImage => '影像';

  @override
  String get tbNameLine => '線條';

  @override
  String get tbNameMeasureAngle => '測量角度';

  @override
  String get tbNameMeasureArc => '測量弧長';

  @override
  String get tbNameMeasureArea => '測量面積';

  @override
  String get tbNameMeasureDistance => '測量距離';

  @override
  String get tbNameMeasurePerimeter => '測量周長';

  @override
  String get tbNameMeasureSlope => '測量坡度（垂直/水平）';

  @override
  String get tbNameMeasureVolume => '測量體積（面積 × 深度）';

  @override
  String get tbNameNote => '便箋';

  @override
  String get tbNamePolygon => '多邊形';

  @override
  String get tbNamePolyline => '折線';

  @override
  String get tbNameRectangle => '矩形';

  @override
  String get tbNameSelect => '選取';

  @override
  String get tbNameSignature => '簽名';

  @override
  String get tbNameStamp => '戳記';

  @override
  String get tbNameTextBox => '文字方塊';

  @override
  String get tbNewFieldType => '新欄位類型 - 在頁面上拖曳以新增';

  @override
  String get tbNoAnnotationsToFlatten => '沒有可平面化的註解';

  @override
  String get tbNoCustomStamps => '沒有自訂戳記';

  @override
  String get tbNoFormFieldsToFlatten => '沒有可平面化的表單欄位';

  @override
  String get tbNoRedactionsToApply => '沒有可套用的塗黑';

  @override
  String get tbNoteTitle => '便箋';

  @override
  String get tbOpacity => '不透明度';

  @override
  String get tbOutline => '外框';

  @override
  String get tbPatternScale => '圖樣縮放';

  @override
  String get tbPickColorFromPage => '從頁面挑選顏色';

  @override
  String get tbRedactionsApplied => '已套用塗黑';

  @override
  String get tbRedoShortcut => '重做 (⇧⌘Z)';

  @override
  String get tbReflowFailed => '無法重排 - 這不是此工具可重新換行的單欄段落。請改用「取代文字」。';

  @override
  String get tbReflowParagraph => '重排段落';

  @override
  String get tbRenameField => '重新命名欄位';

  @override
  String get tbRenameFieldEllipsis => '重新命名欄位…';

  @override
  String get tbReplaceImage => '取代影像';

  @override
  String get tbReplaceImageFailed => '無法取代影像';

  @override
  String get tbReplaceText => '取代文字';

  @override
  String get tbSaveImage => '儲存影像';

  @override
  String get tbSaveShortcut => '儲存… (⌘S / Ctrl+S)';

  @override
  String get tbScale => '比例';

  @override
  String get tbSelectTextForMarkup => '選取文字以使用標記';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 個',
      one: '選取範圍',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => '設定…';

  @override
  String get tbStamp => '戳記';

  @override
  String get tbStampText => '戳記文字';

  @override
  String get tbStrokeOpacityFont => '筆畫、不透明度、字型';

  @override
  String get tbStrokeWidthLabel => '筆畫寬度';

  @override
  String tbStrokeWidthPreset(String width) {
    return '筆畫 $width';
  }

  @override
  String get tbStyle => '樣式';

  @override
  String get tbTakeoffTotals => '估算總計';

  @override
  String get tbTextBorder => '文字邊框';

  @override
  String get tbTextColour => '文字顏色';

  @override
  String get tbTextFieldOption => '文字欄位';

  @override
  String get tbTextFill => '文字填滿';

  @override
  String get tbTextStyleEllipsis => '文字樣式…';

  @override
  String get tbTextTitle => '文字';

  @override
  String get tbTipCallout => '圖說文字 - 從點拖曳至方塊要放置的位置';

  @override
  String get tbTipContent => '編輯頁面內容';

  @override
  String get tbTipCount => '計數 - 點一下放置勾選標記並計數';

  @override
  String get tbTipDigitalSignature => '數位簽章 - 拖曳方塊以放置並簽署';

  @override
  String get tbTipForm => '表單欄位 - 點一下選取，點兩下填寫，拖曳以新增';

  @override
  String get tbTipHighlightDraw => '醒目提示 - 手繪';

  @override
  String get tbTipImage => '影像 - 點一下放置，或拖曳出方塊';

  @override
  String get tbTipMeasureAngle => '測量角度 - 點三個點';

  @override
  String get tbTipMeasureArc => '測量弧長 - 點三個點';

  @override
  String get tbTipRedact => '塗黑 - 拖曳出區域，然後套用';

  @override
  String get tbTipSignature => '簽名 - 點一下頁面以放置';

  @override
  String get tbTipSnapshot => '快照 - 拖曳出區域以擷取（以向量貼回）';

  @override
  String get tbToolContent => '內容';

  @override
  String get tbToolForm => '表單';

  @override
  String get tbToolRedact => '塗黑';

  @override
  String get tbToolSnapshot => '快照';

  @override
  String get tbTools => '工具';

  @override
  String get tbTotals => '總計';

  @override
  String get tbTypeTextEachTime => '每次輸入文字';

  @override
  String get tbUnderline => '底線';

  @override
  String get tbUndoShortcut => '復原 (⌘Z)';

  @override
  String get textStyleFont => '字型';

  @override
  String get textStyleFontSize => '字型大小';

  @override
  String get textStyleKeep => '保留';

  @override
  String get textStyleStyle => '樣式';

  @override
  String get textStyleText => '文字';

  @override
  String get textStyleTextFill => '文字填滿';

  @override
  String get textStyleTitle => '編輯文字與樣式';

  @override
  String get thumbAddPage => '新增頁面';

  @override
  String get thumbClearSelection => '清除選取';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '複製 $count 頁',
      one: '複製頁面',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => '複製選取的頁面';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '剪下 $count 頁',
      one: '剪下頁面',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => '剪下選取的頁面';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '刪除 $count 頁',
      one: '刪除頁面',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => '刪除選取的頁面';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '再製 $count 頁',
      one: '再製頁面',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => '匯出頁面…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '匯出 $count 頁…',
      one: '匯出頁面…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => '匯出選取的頁面';

  @override
  String get thumbInsertBlankAfter => '在後方插入空白頁';

  @override
  String get thumbInsertBlankBefore => '在前方插入空白頁';

  @override
  String get thumbInsertFileFailed => '無法插入該檔案。';

  @override
  String get thumbInsertPdf => '插入 PDF…';

  @override
  String get thumbPageActions => '頁面動作';

  @override
  String thumbPageNumber(int number) {
    return '第 $number 頁';
  }

  @override
  String get thumbPages => '頁面';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '貼上 $count 頁',
      one: '貼上頁面',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '旋轉 180°';

  @override
  String get thumbRotateLeft => '向左旋轉';

  @override
  String get thumbRotatePageRight => '向右旋轉頁面';

  @override
  String get thumbRotateRight => '向右旋轉';

  @override
  String get thumbRotateSelectedLeft => '向左旋轉選取的頁面';

  @override
  String get thumbRotateSelectedRight => '向右旋轉選取的頁面';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已選取 $count 個',
      one: '已選取 $count 個',
    );
    return '$_temp0';
  }

  @override
  String get undo => '復原';

  @override
  String get viewerEditFontUnsafe => '無法安全地編輯此 PDF 字型或編碼。';

  @override
  String get viewerEditNeedsSinglePage => '編輯需要在單一頁面上選取。';

  @override
  String get viewerEditNotEditableRun => '此選取範圍不是單一可編輯的頁面內容文字段。';

  @override
  String get viewerEditStyleUnchangeable => '此 PDF 字型可重新輸入，但無法變更其樣式。';

  @override
  String get viewerEditTextStyle => '編輯文字與樣式';

  @override
  String get viewerMarkup => '標記';

  @override
  String get viewerMarkupHighlight => '醒目提示';

  @override
  String get viewerMarkupSquiggly => '波浪線';

  @override
  String get viewerMarkupStrikeOut => '刪除線';

  @override
  String get viewerMarkupUnderline => '底線';

  @override
  String get viewerSelectAll => '全選';
}
