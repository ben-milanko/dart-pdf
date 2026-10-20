// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class DartPdfPrintingLocalizationsZh extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get printDlgPreparing => '正在准备…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '正在渲染第 $rendered 页，共 $total 页…';
  }

  @override
  String get printDlgTitle => '正在打印';

  @override
  String get printPreviewAll => '全部';

  @override
  String get printPreviewCurrent => '当前页';

  @override
  String get printPreviewNextPage => '下一页';

  @override
  String printPreviewPageOf(int page, int total) {
    return '第 $page 页，共 $total 页';
  }

  @override
  String get printPreviewPreviousPage => '上一页';

  @override
  String get printPreviewPrint => '打印';

  @override
  String get printPreviewRange => '范围';

  @override
  String printPreviewRangeError(int total) {
    return '请输入 1 到 $total 之间的页码范围。';
  }

  @override
  String printPreviewSelection(int count) {
    return '将打印的页数：$count';
  }

  @override
  String get printPreviewTitle => '打印预览';

  @override
  String get printPreviewUnavailable => '预览不可用';

  @override
  String get printOptionsPrinter => '打印机';

  @override
  String get printOptionsNativePrinter =>
      '在接下来的系统打印对话框中选择打印机、纸盒、颜色、双面打印及设备属性。请将缩放比例保持为 100%，份数保持为 1，以使用此处显示的布局。';

  @override
  String get printOptionsPages => '页面';

  @override
  String get printOptionsSelected => '所选页面';

  @override
  String get printOptionsPageRange => '页码（例如 1, 3-5）';

  @override
  String get printOptionsAddFiles => '添加文件…';

  @override
  String get printOptionsAddFailed => '无法添加所选文件。';

  @override
  String get printOptionsGetWindow => '选择区域';

  @override
  String get printOptionsClearWindow => '清除区域';

  @override
  String get printOptionsWindowHint => '在此源页面上拖出一个矩形，选择要打印的区域。';

  @override
  String get printOptionsPaper => '纸张';

  @override
  String get printOptionsPaperSize => '纸张大小';

  @override
  String get printOptionsPageSize => '使用文档页面大小';

  @override
  String get printOptionsOrientation => '方向';

  @override
  String get printOptionsAuto => '自动';

  @override
  String get printOptionsPortrait => '纵向';

  @override
  String get printOptionsLandscape => '横向';

  @override
  String get printOptionsCopies => '份数';

  @override
  String get printOptionsCollate => '逐份打印';

  @override
  String get printOptionsReverse => '反向页序';

  @override
  String get printOptionsLayout => '页面布局';

  @override
  String get printOptionsScaling => '页面缩放';

  @override
  String get printOptionsScaleNone => '无（实际大小）';

  @override
  String get printOptionsFitPaper => '适合纸张';

  @override
  String get printOptionsReducePaper => '缩小至纸张大小';

  @override
  String get printOptionsFitMargins => '适合页边距';

  @override
  String get printOptionsReduceMargins => '缩小至页边距内';

  @override
  String get printOptionsCustomScale => '自定义缩放';

  @override
  String get printOptionsMultiple => '每张纸打印多页';

  @override
  String get printOptionsScalePercent => '缩放比例（%）';

  @override
  String get printOptionsMargin => '页边距（磅）';

  @override
  String get printOptionsPagesPerSheet => '每张纸的页数';

  @override
  String get printOptionsPageOrder => '页面顺序';

  @override
  String get printOptionsHorizontal => '水平';

  @override
  String get printOptionsHorizontalReverse => '水平反向';

  @override
  String get printOptionsVertical => '垂直';

  @override
  String get printOptionsVerticalReverse => '垂直反向';

  @override
  String get printOptionsBorder => '打印页面边框';

  @override
  String get printOptionsRotation => '旋转（顺时针）';

  @override
  String get printOptionsNoRotation => '无';

  @override
  String get printOptionsCenter => '在纸张上居中';

  @override
  String get printOptionsOffsetX => '向右偏移（磅）';

  @override
  String get printOptionsOffsetY => '向下偏移（磅）';

  @override
  String get printOptionsContents => '打印内容';

  @override
  String get printOptionsDocumentAndMarkups => '文档和批注';

  @override
  String get printOptionsDocumentOnly => '仅文档';

  @override
  String get printOptionsMarkupsOnly => '仅批注';

  @override
  String get printOptionsDimPage => '淡化页面内容';

  @override
  String get printOptionsDimMarkups => '淡化批注';

  @override
  String get printOptionsHyperlinks => '打印可见超链接';

  @override
  String get printOptionsDefaults => '默认设置';

  @override
  String get printOptionsInvalidNumber => '请在打印前输入有效数字。';

  @override
  String get printOptionsInvalidValue => '无效值';

  @override
  String get printOptionsMarginGuide => '红线表示页边距，不会打印。';

  @override
  String printOptionsAreaSize(String width, String height) {
    return '区域：$width × $height 磅';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return '源页面：$width × $height 磅';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return '纸张：$width × $height 磅';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return '第 $sheet 张，共 $total 张';
  }

  @override
  String get printOptionsInvalidLayout => '无法生成此布局。请检查纸张大小、页边距和缩放比例。';

  @override
  String get printOptionsChoosePrinter => '选择打印机';

  @override
  String get printOptionsNoPrinters => '未安装打印机。请在 Windows 设置中添加打印机，然后重试。';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return '已保存的打印机“$printer”不可用。请选择打印机以继续。';
  }

  @override
  String get printOptionsPrinterError => '无法加载打印机设置。请检查打印机连接，然后重试。';

  @override
  String get printOptionsRetry => '重试';

  @override
  String get printOptionsColor => '彩色';

  @override
  String get printOptionsGrayscale => '黑白';

  @override
  String get printOptionsDuplex => '双面打印';

  @override
  String get printOptionsSimplex => '单面';

  @override
  String get printOptionsLongEdge => '长边翻转';

  @override
  String get printOptionsShortEdge => '短边翻转';

  @override
  String get printOptionsTray => '纸盒';

  @override
  String get printOptionsDefaultTray => '打印机默认值';

  @override
  String get printOptionsProperties => '打印机属性…';

  @override
  String get printOptionsDirectPrinter => '点击“打印”会将此任务直接发送到所选打印机。';

  @override
  String get printOptionsPropertiesError => '无法打开打印机属性。';

  @override
  String get printOptionsLoadingPrinters => '正在加载打印机…';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class DartPdfPrintingLocalizationsZhHant
    extends DartPdfPrintingLocalizationsZh {
  DartPdfPrintingLocalizationsZhHant() : super('zh_Hant');

  @override
  String get cancel => '取消';

  @override
  String get printDlgPreparing => '準備中…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '正在算繪第 $rendered 頁，共 $total 頁…';
  }

  @override
  String get printDlgTitle => '列印中';

  @override
  String get printPreviewAll => '全部';

  @override
  String get printPreviewCurrent => '目前頁面';

  @override
  String get printPreviewNextPage => '下一頁';

  @override
  String printPreviewPageOf(int page, int total) {
    return '第 $page 頁，共 $total 頁';
  }

  @override
  String get printPreviewPreviousPage => '上一頁';

  @override
  String get printPreviewPrint => '列印';

  @override
  String get printPreviewRange => '範圍';

  @override
  String printPreviewRangeError(int total) {
    return '請輸入 1 到 $total 之間的頁碼範圍。';
  }

  @override
  String printPreviewSelection(int count) {
    return '將列印的頁數：$count';
  }

  @override
  String get printPreviewTitle => '列印預覽';

  @override
  String get printPreviewUnavailable => '預覽無法使用';

  @override
  String get printOptionsPrinter => '印表機';

  @override
  String get printOptionsNativePrinter =>
      '在接下來的系統列印對話方塊中選擇印表機、紙匣、色彩、雙面列印及裝置屬性。請將縮放比例維持在 100%，份數維持為 1，以使用此處顯示的版面配置。';

  @override
  String get printOptionsPages => '頁面';

  @override
  String get printOptionsSelected => '所選頁面';

  @override
  String get printOptionsPageRange => '頁碼（例如 1, 3-5）';

  @override
  String get printOptionsAddFiles => '新增檔案…';

  @override
  String get printOptionsAddFailed => '無法新增所選檔案。';

  @override
  String get printOptionsGetWindow => '選取區域';

  @override
  String get printOptionsClearWindow => '清除區域';

  @override
  String get printOptionsWindowHint => '在此來源頁面上拖曳出一個矩形，選取要列印的區域。';

  @override
  String get printOptionsPaper => '紙張';

  @override
  String get printOptionsPaperSize => '紙張大小';

  @override
  String get printOptionsPageSize => '使用文件頁面大小';

  @override
  String get printOptionsOrientation => '方向';

  @override
  String get printOptionsAuto => '自動';

  @override
  String get printOptionsPortrait => '直向';

  @override
  String get printOptionsLandscape => '橫向';

  @override
  String get printOptionsCopies => '份數';

  @override
  String get printOptionsCollate => '逐份列印';

  @override
  String get printOptionsReverse => '反向頁序';

  @override
  String get printOptionsLayout => '頁面配置';

  @override
  String get printOptionsScaling => '頁面縮放';

  @override
  String get printOptionsScaleNone => '無（實際大小）';

  @override
  String get printOptionsFitPaper => '符合紙張大小';

  @override
  String get printOptionsReducePaper => '縮小至紙張大小';

  @override
  String get printOptionsFitMargins => '符合邊界';

  @override
  String get printOptionsReduceMargins => '縮小至邊界內';

  @override
  String get printOptionsCustomScale => '自訂縮放';

  @override
  String get printOptionsMultiple => '每張紙列印多頁';

  @override
  String get printOptionsScalePercent => '縮放比例（%）';

  @override
  String get printOptionsMargin => '邊界（點）';

  @override
  String get printOptionsPagesPerSheet => '每張紙的頁數';

  @override
  String get printOptionsPageOrder => '頁面順序';

  @override
  String get printOptionsHorizontal => '水平';

  @override
  String get printOptionsHorizontalReverse => '水平反向';

  @override
  String get printOptionsVertical => '垂直';

  @override
  String get printOptionsVerticalReverse => '垂直反向';

  @override
  String get printOptionsBorder => '列印頁面框線';

  @override
  String get printOptionsRotation => '旋轉（順時針）';

  @override
  String get printOptionsNoRotation => '無';

  @override
  String get printOptionsCenter => '在紙張上置中';

  @override
  String get printOptionsOffsetX => '向右位移（點）';

  @override
  String get printOptionsOffsetY => '向下位移（點）';

  @override
  String get printOptionsContents => '列印內容';

  @override
  String get printOptionsDocumentAndMarkups => '文件與註解';

  @override
  String get printOptionsDocumentOnly => '僅文件';

  @override
  String get printOptionsMarkupsOnly => '僅註解';

  @override
  String get printOptionsDimPage => '淡化頁面內容';

  @override
  String get printOptionsDimMarkups => '淡化註解';

  @override
  String get printOptionsHyperlinks => '列印可見的超連結';

  @override
  String get printOptionsDefaults => '預設值';

  @override
  String get printOptionsInvalidNumber => '請在列印前輸入有效數字。';

  @override
  String get printOptionsInvalidValue => '無效值';

  @override
  String get printOptionsMarginGuide => '紅線表示邊界，不會列印。';

  @override
  String printOptionsAreaSize(String width, String height) {
    return '區域：$width × $height 點';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return '來源：$width × $height 點';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return '紙張：$width × $height 點';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return '第 $sheet 張，共 $total 張';
  }

  @override
  String get printOptionsInvalidLayout => '無法產生此版面配置。請檢查紙張大小、邊界和縮放比例。';

  @override
  String get printOptionsChoosePrinter => '選擇印表機';

  @override
  String get printOptionsNoPrinters => '尚未安裝印表機。請在 Windows 設定中新增印表機，然後重試。';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return '已儲存的印表機「$printer」無法使用。請選擇印表機以繼續。';
  }

  @override
  String get printOptionsPrinterError => '無法載入印表機設定。請檢查印表機連線，然後重試。';

  @override
  String get printOptionsRetry => '重試';

  @override
  String get printOptionsColor => '彩色';

  @override
  String get printOptionsGrayscale => '黑白';

  @override
  String get printOptionsDuplex => '雙面列印';

  @override
  String get printOptionsSimplex => '單面';

  @override
  String get printOptionsLongEdge => '長邊翻轉';

  @override
  String get printOptionsShortEdge => '短邊翻轉';

  @override
  String get printOptionsTray => '紙匣';

  @override
  String get printOptionsDefaultTray => '印表機預設值';

  @override
  String get printOptionsProperties => '印表機內容…';

  @override
  String get printOptionsDirectPrinter => '按下「列印」會將此工作直接傳送至所選印表機。';

  @override
  String get printOptionsPropertiesError => '無法開啟印表機內容。';

  @override
  String get printOptionsLoadingPrinters => '正在載入印表機…';
}
