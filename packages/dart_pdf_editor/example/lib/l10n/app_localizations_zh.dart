// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get add => '添加';

  @override
  String get apply => '应用';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get close => '关闭';

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
  String exActionJavaScript(String script) {
    return '向应用公开的 JavaScript：$script';
  }

  @override
  String exActionLink(String uri) {
    return '链接：$uri';
  }

  @override
  String exActionNamed(String name) {
    return '命名动作：$name';
  }

  @override
  String exActionUnhandled(String type) {
    return '未处理的动作类型：$type';
  }

  @override
  String get exAnnotationTextCopied => '已复制注释文本';

  @override
  String get exApiKeyHelper => '以 Authorization: Bearer … 形式发送';

  @override
  String get exApiKeyLabel => 'API 密钥 / 令牌（可选）';

  @override
  String get exAppMenuTooltip => 'DartPDF 菜单';

  @override
  String get exClearRecentFiles => '清除最近文件';

  @override
  String get exCloseTab => '关闭标签页';

  @override
  String exCompareTabTitle(String before, String after) {
    return '比较：$before ↔ $after';
  }

  @override
  String get exCompareWithAnother => '与另一个 PDF 比较…';

  @override
  String get exCopiedToClipboard => '已复制到剪贴板';

  @override
  String get exCopySelectedText => '复制所选文本 (⌘C)';

  @override
  String get exCopyText => '复制文本';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '无法打开 $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '无法打开 $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '无法打开 $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '无法打开 $uri\n$error\n\n在网页上，这通常是 CORS 限制：服务器必须发送 Access-Control-Allow-Origin 并公开 Range 标头。';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '无法重新打开 $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '无法重新打开 $title - 其已保存的副本不再可用。';
  }

  @override
  String get exDemoNoteHint => '在此输入 - 此文本框浮动在页面上方';

  @override
  String get exDiagnosticsCopied => '诊断信息已复制到剪贴板';

  @override
  String exDownloaded(String name) {
    return '已下载 $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '已下载 $name - 使用 Ctrl+V 粘贴回 PDF 中';
  }

  @override
  String get exExport => '导出';

  @override
  String exExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get exExportPageImageMenu => '将页面导出为图像…';

  @override
  String get exExportPageImageTitle => '将页面导出为图像';

  @override
  String get exFeatureShowcase => '功能展示';

  @override
  String get exFormat => '格式';

  @override
  String get exHide => '隐藏';

  @override
  String get exHorizontalLayout => '水平页面布局';

  @override
  String get exHowToSetupOcr => '如何设置 OCR 服务器';

  @override
  String get exModelName => '模型名称';

  @override
  String get exNoMessage => '无消息';

  @override
  String get exNoRecentFiles => '无最近文件';

  @override
  String exNotAValidUrl(String url) {
    return '不是有效的 URL：\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR 添加了 $count 个文本段 - 现在可以选择页面文本了',
      one: 'OCR 添加了 1 个文本段 - 现在可以选择页面文本了',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      '使用您自行托管的视觉语言 OCR 模型（vLLM 上的 dots.ocr，或任何兼容 OpenAI 的 OCR 端点），在扫描页面上添加可选择、可搜索的文本层。';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title（OCR）';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR 失败：$error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => '打开';

  @override
  String get exOpenDocumentBeforeOcr => '运行 OCR 前请先打开文档';

  @override
  String get exOpenDocumentFirst => '请先打开文档';

  @override
  String get exOpenFromUrl => '从 URL 打开…';

  @override
  String get exOpenFromUrlTitle => '从 URL 打开';

  @override
  String get exOpenInNewTab => '在新标签页中打开 PDF';

  @override
  String get exOpenInteractiveDemo => '打开交互式演示';

  @override
  String get exOpenPdf => '打开 PDF…';

  @override
  String get exOpenPdfButton => '打开 PDF';

  @override
  String get exOpenRecent => '打开最近';

  @override
  String get exOpenUrlDescription =>
      '通过 PdfHttpByteSource 使用 HTTP Range 请求流式加载 PDF，仅获取解析器所需的内容；当服务器不支持范围请求时，回退到完整下载。';

  @override
  String get exOpeningDocument => '正在打开文档';

  @override
  String get exOpeningPdf => '正在打开 PDF…';

  @override
  String exOpeningTitle(String title) {
    return '正在打开 $title…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => '性能：自动';

  @override
  String get exPreparing => '正在准备…';

  @override
  String get exPubDevMenuItem => 'pub.dev 上的 dart_pdf_editor';

  @override
  String exRecognisingPage(int current, int count) {
    return '正在识别第 $current 页，共 $count 页…';
  }

  @override
  String get exResolution => '分辨率';

  @override
  String get exRunOcr => '运行 OCR';

  @override
  String get exSaveAs => '另存为…';

  @override
  String exSaveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String exSavedName(String name) {
    return '已保存 $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '已保存 $name - 使用 ⌘V 粘贴回 PDF 中';
  }

  @override
  String exSavedTo(String path) {
    return '已保存到 $path';
  }

  @override
  String get exScrollIndicatorDemo => '滚动指示器 API 演示';

  @override
  String get exServiceEndpoint => '服务端点';

  @override
  String get exShow => '显示';

  @override
  String get exSingleWorker => '单个工作线程';

  @override
  String get exSupplyFeedback => '提供反馈…';

  @override
  String get exSwitchToEdit => '切换到编辑模式';

  @override
  String get exSwitchToReadOnly => '切换到只读';

  @override
  String get exThemeDark => '主题：深色 - 切换到系统';

  @override
  String get exThemeLight => '主题：浅色 - 切换到深色';

  @override
  String get exThemeSystem => '主题：系统 - 切换到浅色';

  @override
  String get exTryDemo => '试用交互式演示';

  @override
  String get exUntitled => '无标题';

  @override
  String get exVerticalLayout => '垂直页面布局';

  @override
  String get exViewSource => '在 GitHub 上查看源代码';

  @override
  String get exWorkerAuto => '自动';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '性能：$count 个工作线程',
      one: '性能：单个工作线程',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count 个工作线程';
  }

  @override
  String get feedbackAttachDiagnostics => '将这些诊断信息附加到报告中';

  @override
  String get feedbackClearLog => '清除日志';

  @override
  String get feedbackCopyDiagnostics => '复制诊断信息';

  @override
  String get feedbackDiagnosticsNotice =>
      '反馈表单将在您的浏览器中打开。以下诊断信息仅在此设备上收集，并会附加上以帮助重现问题。请先查看这些信息 - 不要包含任何您希望保密的内容。';

  @override
  String get feedbackOpenForm => '打开反馈表单';

  @override
  String get feedbackTitle => '发送反馈';

  @override
  String get none => '无';

  @override
  String get ok => '确定';

  @override
  String get paste => '粘贴';

  @override
  String get redo => '重做';

  @override
  String get remove => '移除';

  @override
  String get rename => '重命名';

  @override
  String get reset => '重置';

  @override
  String get save => '保存';

  @override
  String get scrollDemoNextPage => '下一页';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return '第 $current / $count 页';
  }

  @override
  String get scrollDemoPreviousPage => '上一页';

  @override
  String get scrollDemoSwitchHorizontal => '切换到水平布局';

  @override
  String get scrollDemoSwitchVertical => '切换到垂直布局';

  @override
  String get scrollDemoTitle => '滚动指示器 API';

  @override
  String get undo => '撤销';

  @override
  String get exFileTypePdf => 'PDF 文档';

  @override
  String get exFileTypeImages => '图像';

  @override
  String get exFileTypeFonts => '字体';
}
