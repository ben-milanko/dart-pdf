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
  String get appSigAddLogo => '添加徽标…';

  @override
  String appSigAllPages(int pageCount) {
    return '全部 $pageCount 页';
  }

  @override
  String get appSigAppearance => '外观';

  @override
  String get appSigAppearanceDescription =>
      '签名将绘制在您放置的位置。签名者姓名和详细信息始终显示；您可以添加手绘签名和徽标背景。';

  @override
  String appSigApplyTo(String label) {
    return '应用到：$label';
  }

  @override
  String get appSigApplyToPages => '应用到页面…';

  @override
  String get appSigChooseCertificate => '选择证书文件…';

  @override
  String get appSigChooseKeyDescription =>
      '选择您的私钥（RSA、PEM 或 DER）及其证书文件。密钥仅用于签名，绝不会被保存。';

  @override
  String get appSigChoosePngOrJpeg => '请选择 PNG 或 JPEG 图像。';

  @override
  String get appSigChoosePrivateKey => '选择私钥…';

  @override
  String get appSigContactInfo => '联系信息';

  @override
  String get appSigCouldNotCaptureSignature => '无法捕获签名。';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return '无法读取证书：$error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return '无法读取密钥：$error';
  }

  @override
  String get appSigCreateOnDevice => '在此设备上创建签名';

  @override
  String appSigDate(String date) {
    return '日期：$date';
  }

  @override
  String get appSigDigitallySign => '数字签名';

  @override
  String get appSigDrawSignature => '绘制签名…';

  @override
  String get appSigFieldHelper => '留空以创建新的签名字段。';

  @override
  String get appSigFieldLabel => '现有签名字段（可选）';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个证书',
      one: '1 个证书',
    );
    return '$_temp0 · 有效期 $validFrom 至 $validUntil';
  }

  @override
  String get appSigIntro => '数字签名可证明您签署了此文档，且此后未被更改。请选择您的签名方式。';

  @override
  String get appSigKeyOrCertUnreadable => '无法读取所选的密钥或证书。';

  @override
  String get appSigKeylessDescription =>
      '最简单。我们通过电子邮件确认您的身份并为您签名，并附带受信任的时间戳。无需安装或设置。';

  @override
  String get appSigKeylessIdentity => '无密钥身份';

  @override
  String get appSigKeylessSignInExpired => '您的无密钥登录已过期。请重新登录。';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return '无密钥登录失败：$failure';
  }

  @override
  String get appSigKeylessSubtitle => '无密钥 · 已加时间戳 · 有效性未知';

  @override
  String get appSigKeylessWebNote =>
      '使用电子邮件登录是最简单的签名方式——它在 DartPDF 桌面和移动应用中可用。出于安全原因，它无法在网页浏览器中运行。';

  @override
  String get appSigLocation => '位置';

  @override
  String get appSigLogoAdded => '已添加徽标 ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return '第 $start–$end 页';
  }

  @override
  String get appSigPreviewNote => '预览 - 签名后的签名框可能略有不同。';

  @override
  String get appSigReason => '原因';

  @override
  String appSigReasonLine(String reason) {
    return '原因：$reason';
  }

  @override
  String get appSigRefreshingSignIn => '正在刷新登录…';

  @override
  String get appSigRemoveLogo => '移除徽标';

  @override
  String get appSigRemoveSignature => '移除签名';

  @override
  String get appSigSelfSignedDescription =>
      '无需登录或文件。最适合个人使用——它会保存在此设备上以备下次使用。某些 PDF 阅读器会将其显示为“已签名，有效性未知”，对于您自己创建的签名，这是正常现象。';

  @override
  String get appSigSelfSignedIdentity => '自签名身份';

  @override
  String get appSigSelfSignedSubtitle => '自签名 · 有效性未知';

  @override
  String get appSigShowSignatureOnPages => '在页面上显示签名';

  @override
  String get appSigSign => '签名';

  @override
  String get appSigSignInWithEmail => '使用您的电子邮件登录';

  @override
  String get appSigSignatureAdded => '已添加签名 ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '由 $signerName 数字签名';
  }

  @override
  String get appSigSigner => '签名者';

  @override
  String get appSigSigningYouIn => '正在为您登录…';

  @override
  String get appSigThisPageOnly => '仅此页面';

  @override
  String get appSigUseOwnCertificate => '使用您自己的证书';

  @override
  String get appSigUseOwnCertificateSubtitle => '适用于来自您组织的签名证书';

  @override
  String get appSigX509Signer => 'X.509 签名者';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在新标签页中打开这 $count 个 PDF，还是将它们的页面插入到“$title”中？',
      one: '在新标签页中打开此 PDF，还是将其页面插入到“$title”中？',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '添加拖入的 PDF',
      one: '添加拖入的 PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => '已复制注释文本';

  @override
  String get editorAppMenuTooltip => 'DartPDF 菜单';

  @override
  String get editorCancelOcr => '取消 OCR';

  @override
  String get editorClearRecentFiles => '清除最近文件';

  @override
  String get editorCloseAll => '全部关闭';

  @override
  String get editorCloseOthers => '关闭其他';

  @override
  String get editorCloseTab => '关闭标签页';

  @override
  String get editorCloseTabsToRight => '关闭右侧标签页';

  @override
  String get editorCompareFailedTitle => '比较失败';

  @override
  String editorCompareTitle(String title) {
    return '比较：$title';
  }

  @override
  String get editorCopiedToClipboard => '已复制到剪贴板';

  @override
  String get editorCopySelectedTextTooltip => '复制所选文本 (⌘C)';

  @override
  String get editorCopyText => '复制文本';

  @override
  String editorCouldNotExport(String title) {
    return '无法导出 $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return '无法导入图章：$error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '无法插入拖入的 PDF',
      one: '无法插入拖入的 PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '无法打开 $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => '无法打开所在文件夹';

  @override
  String editorCouldNotOpenSecond(String error) {
    return '无法打开第二个文件\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return '无法打开所选文件\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '无法打开 $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '无法打印 $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '无法重新打开 $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return '无法进行数字签名：$error';
  }

  @override
  String get editorDiscard => '放弃';

  @override
  String get editorDiscardChangesTitle => '放弃更改？';

  @override
  String get editorDocumentSigned => '文档已进行数字签名';

  @override
  String get editorDownload => '下载';

  @override
  String get editorDropToOpen => '拖放 PDF 以打开';

  @override
  String get editorDropToOpenOrInsert => '拖放 PDF 以打开或插入';

  @override
  String get editorInsertPages => '插入页面';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '已插入 $count 个；无法读取 $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已将 $count 个 PDF 插入到 $title',
      one: '已将页面插入到 $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return '无效链接：$uri';
  }

  @override
  String get editorJavaScriptIgnored => '此文档尝试运行 JavaScript（已忽略）';

  @override
  String get editorLoadingFullDocument => '正在加载完整文档';

  @override
  String get editorMenuCompareWith => '与…比较';

  @override
  String get editorMenuDigitallySign => '数字签名…';

  @override
  String get editorMenuDigitallySigning => '正在数字签名…';

  @override
  String get editorMenuExportImage => '将页面导出为图像…';

  @override
  String get editorMenuNewDocument => '新建文档…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => '打开 PDF…';

  @override
  String get editorMenuPrint => '打印…';

  @override
  String get editorMenuSaveAs => '另存为…';

  @override
  String get editorMenuScanDocument => '扫描为新文档…';

  @override
  String get editorMenuInsertScan => '插入扫描件…';

  @override
  String get editorScanFailed => '无法扫描文档。';

  @override
  String get editorInsertedScan => '已插入扫描的页面。';

  @override
  String get editorMenuSettings => '设置';

  @override
  String get editorMenuSwitchToEdit => '切换到编辑模式';

  @override
  String get editorMenuSwitchToReadOnly => '切换到只读';

  @override
  String editorNamedAction(String name) {
    return '命名动作：$name';
  }

  @override
  String get editorNoRecentFiles => '无最近文件';

  @override
  String editorOcrTitle(String title) {
    return '$title（OCR）';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => '运行 OCR 前请先打开文档';

  @override
  String get editorOpenFailedTitle => '打开失败';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在新标签页中打开',
      one: '在新标签页中打开',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => '在新标签页中打开 PDF';

  @override
  String get editorOpenRecent => '打开最近';

  @override
  String get editorOpenTabs => '打开的标签页';

  @override
  String get editorOpeningDocumentSemantic => '正在打开文档';

  @override
  String get editorOpeningPdf => '正在打开 PDF…';

  @override
  String editorOpeningTitle(String title) {
    return '正在打开 $title…';
  }

  @override
  String editorPageNumber(int number) {
    return '第 $number 页';
  }

  @override
  String get editorPreviewComparison => '比较';

  @override
  String get editorPreviewCouldNotOpen => '无法打开';

  @override
  String get editorPreviewOpening => '正在打开';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => '已移除签名';

  @override
  String get editorSnapshotCopied => '快照已复制到剪贴板';

  @override
  String get editorSnapshotCopyFailed => '无法将快照复制到剪贴板';

  @override
  String get editorTabs => '标签页';

  @override
  String editorTabsOpenCount(int count) {
    return '$count 个已打开';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文档有未保存的更改。',
      one: '一个文档有未保存的更改。',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return '不支持的动作：$type';
  }

  @override
  String get editorUntitled => '无标题';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version 已可用。';
  }

  @override
  String get editorUpdateLater => '稍后';

  @override
  String get editorViewAllTabs => '查看所有标签页';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => '导出';

  @override
  String get imgExportFormat => '格式';

  @override
  String get imgExportResolution => '分辨率';

  @override
  String get imgExportTitle => '将页面导出为图像';

  @override
  String get newDocCreate => '创建';

  @override
  String get newDocLandscape => '横向';

  @override
  String get newDocOrientation => '方向';

  @override
  String get newDocPageSize => '页面大小';

  @override
  String get newDocPortrait => '纵向';

  @override
  String get newDocTitle => '新建文档';

  @override
  String get none => '无';

  @override
  String get ocrAlreadyRunning => 'OCR 正在运行 - 请等待其完成或取消';

  @override
  String get ocrBrowserInitFailed => '浏览器 OCR 初始化失败';

  @override
  String get ocrCancelled => 'OCR 已取消';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在处理 $count 个文本段后取消了 OCR',
      one: '在处理 1 个文本段后取消了 OCR',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => '下载';

  @override
  String ocrDownloadFailed(String error) {
    return '无法下载 OCR 模型：$error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return '添加可选文本层需要设备端 OCR 模型$size。它只需下载一次，之后即可离线运行。\n\n模型：$model';
  }

  @override
  String get ocrDownloadPromptTitle => '下载 OCR 模型？';

  @override
  String ocrFailed(String error) {
    return 'OCR 失败：$error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable => '此平台不支持设备端 OCR';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR 添加了 $count 个文本段 - 现在可以选择页面文本了',
      one: 'OCR 添加了 1 个文本段 - 现在可以选择页面文本了',
      zero: 'OCR 未在这些页面上找到文本',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      '网页 OCR 会下载一个 Florence-2 视觉语言模型，并通过 Transformers.js 使用 WebGPU/WASM 在本地运行。PDF 页面会保留在此浏览器中；仅在首次使用时获取模型文件。';

  @override
  String get ocrWebPromptTitle => '在此浏览器中运行 AI OCR？';

  @override
  String get ocrWebStart => '开始 OCR';

  @override
  String get ok => '确定';

  @override
  String get paste => '粘贴';

  @override
  String get printDlgPreparing => '正在准备…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '正在渲染第 $rendered 页，共 $total 页…';
  }

  @override
  String get printDlgTitle => '正在打印';

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
  String get settingsAbout => '关于';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsCheckNow => '立即检查';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '系统默认';

  @override
  String get settingsCheckingForUpdates => '正在检查更新…';

  @override
  String get settingsCouldNotOpenDownload => '无法打开下载';

  @override
  String get settingsCouldNotOpenSystemSettings => '无法打开系统设置';

  @override
  String get settingsDeveloperTools => '开发者工具';

  @override
  String get settingsDeveloperToolsSubtitle => '指标、日志、渲染模式 (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '下载 $version';
  }

  @override
  String get settingsOpenSettings => '打开设置';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已记住 $count 个',
      one: '已记住 1 个',
      zero: '无最近文件',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => '最近文件';

  @override
  String get settingsSetUpAsDefault => '设为默认应用';

  @override
  String get settingsSystem => '系统';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeSystem => '系统';

  @override
  String get settingsTitle => '设置';

  @override
  String settingsUpToDate(String version) {
    return '您使用的是最新版本（$version）。';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return '版本 $version 已可用（您当前为 $currentVersion）。';
  }

  @override
  String get settingsUpdateFailed => '无法检查更新。请稍后再试。';

  @override
  String settingsUpdateIdle(String name, String version) {
    return '您当前使用 $name $version。';
  }

  @override
  String get settingsUpdates => '更新';

  @override
  String get settingsViewSource => '在 GitHub 上查看源代码';

  @override
  String get undo => '撤销';

  @override
  String get welcomeOpenPdf => '打开 PDF';

  @override
  String get welcomePickAgainToReopen => '重新选择以打开';

  @override
  String get welcomeRecent => '最近';

  @override
  String get welcomeRemoveFromRecent => '从最近中移除';

  @override
  String get welcomeTapToReopen => '点按以重新打开';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': '安装网页应用，然后将其选为 PDF 文件的打开方式。',
        'windows': '打开 Windows 的 PDF 默认应用设置。',
        'macos': '按照访达的“始终打开方式”步骤操作。',
        'linux': '使用桌面环境的默认应用程序设置。',
        'android': '打开 PDF 时选择 DartPDF，然后点按“始终”。',
        'ios': '在“文件”中使用“共享”或“打开方式”将 PDF 发送到此处。',
        'other': '配置系统的 PDF 文件处理程序。',
      },
    );
    return '$_temp0';
  }

  @override
  String settingsDefaultAppInstructions(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': '请先从浏览器安装 DartPDF。然后使用浏览器或操作系统的文件处理程序设置，将 PDF 文件关联到已安装的应用。',
        'windows':
            'Windows 设置将打开到“默认应用”。搜索“.pdf”或“PDF”，选择当前的 PDF 应用，然后选择 DartPDF。',
        'macos': '在访达中，选择任意 PDF，选择“文件”>“显示简介”，展开“打开方式”，选择 DartPDF，然后点按“全部更改…”。',
        'linux':
            '打开桌面环境的“默认应用程序”设置，或在“文件”中右键单击某个 PDF，选择“属性”，并将 DartPDF 设为 PDF 文档的默认应用。',
        'android':
            '从“文件”或“下载”中打开 PDF，在应用选择器中选择 DartPDF，然后选择“始终”。如果已有其他应用打开 PDF，请先在 Android 设置中清除该应用的默认设置。',
        'ios':
            'iOS 不提供全局默认 PDF 编辑器。请使用“文件”>“共享”，或长按 PDF 并选择“共享/打开方式”，然后选择 DartPDF。',
        'other': '使用系统的文件处理程序设置，将 PDF 文档关联到 DartPDF。',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => '正在下载 OCR 模型…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return '正在下载模型 $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => '正在完成 OCR…';

  @override
  String get fileTypePdf => 'PDF 文档';

  @override
  String get fileTypeImages => '图像';

  @override
  String get fileTypeStampBundle => 'DartPDF 图章';

  @override
  String get appSigKeyFileType => 'RSA 私钥';

  @override
  String get appSigCertificateFileType => 'X.509 证书';

  @override
  String get appSigErrorNoCertificateSelected => '请至少选择一个 X.509 证书。';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return '证书 $index 不是有效的 X.509。';
  }

  @override
  String get appSigErrorKeyCertificateMismatch => '私钥与所选的任何 RSA 证书都不匹配。';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      '不支持加密的私钥。请选择未加密的 RSA PKCS#1 或 PKCS#8 密钥。';

  @override
  String get appSigErrorKeyNotRsa => '私钥不是未加密的 RSA PKCS#1 或 PKCS#8 密钥。';

  @override
  String get appSigErrorNoCertificateFound => '未找到 X.509 证书。';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get add => '新增';

  @override
  String get appSigAddLogo => '新增標誌…';

  @override
  String appSigAllPages(int pageCount) {
    return '全部 $pageCount 頁';
  }

  @override
  String get appSigAppearance => '外觀';

  @override
  String get appSigAppearanceDescription =>
      '簽名會繪製在您放置的位置。簽署者名稱與詳細資料一律顯示；您可以加上手繪標記與標誌背景。';

  @override
  String appSigApplyTo(String label) {
    return '套用至：$label';
  }

  @override
  String get appSigApplyToPages => '套用至頁面…';

  @override
  String get appSigChooseCertificate => '選擇憑證檔案…';

  @override
  String get appSigChooseKeyDescription =>
      '選擇您的私密金鑰（RSA、PEM 或 DER）及其憑證檔案。金鑰僅用於簽署，絕不會儲存。';

  @override
  String get appSigChoosePngOrJpeg => '請選擇 PNG 或 JPEG 影像。';

  @override
  String get appSigChoosePrivateKey => '選擇私密金鑰…';

  @override
  String get appSigContactInfo => '聯絡資訊';

  @override
  String get appSigCouldNotCaptureSignature => '無法擷取簽名。';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return '無法讀取憑證：$error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return '無法讀取金鑰：$error';
  }

  @override
  String get appSigCreateOnDevice => '在此裝置上建立簽名';

  @override
  String appSigDate(String date) {
    return '日期：$date';
  }

  @override
  String get appSigDigitallySign => '數位簽署';

  @override
  String get appSigDrawSignature => '繪製簽名…';

  @override
  String get appSigFieldHelper => '留空以建立新的簽章欄位。';

  @override
  String get appSigFieldLabel => '現有的簽章欄位（選填）';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 個憑證',
      one: '1 個憑證',
    );
    return '$_temp0 · 有效期 $validFrom 至 $validUntil';
  }

  @override
  String get appSigIntro => '數位簽章證明您簽署了此文件，且文件自簽署後未經變更。請選擇您想要的簽署方式。';

  @override
  String get appSigKeyOrCertUnreadable => '無法讀取所選的金鑰或憑證。';

  @override
  String get appSigKeylessDescription =>
      '最簡單。我們透過電子郵件確認您的身分並為您簽署，附上受信任的時間戳記。無需安裝或設定。';

  @override
  String get appSigKeylessIdentity => '無金鑰身分';

  @override
  String get appSigKeylessSignInExpired => '您的無金鑰登入已過期。請重新登入。';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return '無金鑰登入失敗：$failure';
  }

  @override
  String get appSigKeylessSubtitle => '無金鑰 · 已加時間戳記 · 有效性未知';

  @override
  String get appSigKeylessWebNote =>
      '使用電子郵件登入是最簡單的方式 — 可在 DartPDF 桌面版與行動版應用程式中使用。基於安全考量，它無法在網頁瀏覽器中執行。';

  @override
  String get appSigLocation => '位置';

  @override
  String get appSigLogoAdded => '已新增標誌 ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return '第 $start–$end 頁';
  }

  @override
  String get appSigPreviewNote => '預覽 - 簽署後的方塊可能略有不同。';

  @override
  String get appSigReason => '原因';

  @override
  String appSigReasonLine(String reason) {
    return '原因：$reason';
  }

  @override
  String get appSigRefreshingSignIn => '正在重新整理登入…';

  @override
  String get appSigRemoveLogo => '移除標誌';

  @override
  String get appSigRemoveSignature => '移除簽名';

  @override
  String get appSigSelfSignedDescription =>
      '無需登入或檔案。最適合個人使用 — 會儲存在此裝置上供下次使用。某些 PDF 閱讀器會顯示為「已簽署，有效性未知」，這對於您自己建立的簽章是正常的。';

  @override
  String get appSigSelfSignedIdentity => '自我簽署身分';

  @override
  String get appSigSelfSignedSubtitle => '自我簽署 · 有效性未知';

  @override
  String get appSigShowSignatureOnPages => '在頁面上顯示簽名';

  @override
  String get appSigSign => '簽署';

  @override
  String get appSigSignInWithEmail => '使用電子郵件登入';

  @override
  String get appSigSignatureAdded => '已新增簽名 ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '由 $signerName 數位簽署';
  }

  @override
  String get appSigSigner => '簽署者';

  @override
  String get appSigSigningYouIn => '正在為您登入…';

  @override
  String get appSigThisPageOnly => '僅此頁面';

  @override
  String get appSigUseOwnCertificate => '使用您自己的憑證';

  @override
  String get appSigUseOwnCertificateSubtitle => '適用於來自您組織的簽署憑證';

  @override
  String get appSigX509Signer => 'X.509 簽署者';

  @override
  String get apply => '套用';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get close => '關閉';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在新分頁中開啟這 $count 個 PDF，或將它們的頁面插入「$title」？',
      one: '在新分頁中開啟此 PDF，或將其頁面插入「$title」？',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新增拖放的 PDF',
      one: '新增拖放的 PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => '已複製註解文字';

  @override
  String get editorAppMenuTooltip => 'DartPDF 選單';

  @override
  String get editorCancelOcr => '取消 OCR';

  @override
  String get editorClearRecentFiles => '清除最近使用的檔案';

  @override
  String get editorCloseAll => '全部關閉';

  @override
  String get editorCloseOthers => '關閉其他';

  @override
  String get editorCloseTab => '關閉分頁';

  @override
  String get editorCloseTabsToRight => '關閉右側分頁';

  @override
  String get editorCompareFailedTitle => '比較失敗';

  @override
  String editorCompareTitle(String title) {
    return '比較：$title';
  }

  @override
  String get editorCopiedToClipboard => '已複製到剪貼簿';

  @override
  String get editorCopySelectedTextTooltip => '複製選取的文字 (⌘C)';

  @override
  String get editorCopyText => '複製文字';

  @override
  String editorCouldNotExport(String title) {
    return '無法匯出 $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return '無法匯入戳記：$error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '無法插入拖放的 PDF',
      one: '無法插入拖放的 PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '無法開啟 $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => '無法開啟所在資料夾';

  @override
  String editorCouldNotOpenSecond(String error) {
    return '無法開啟第二個檔案\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return '無法開啟選取的檔案\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '無法開啟 $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '無法列印 $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '無法重新開啟 $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return '無法數位簽署：$error';
  }

  @override
  String get editorDiscard => '捨棄';

  @override
  String get editorDiscardChangesTitle => '捨棄變更？';

  @override
  String get editorDocumentSigned => '文件已數位簽署';

  @override
  String get editorDownload => '下載';

  @override
  String get editorDropToOpen => '拖放 PDF 以開啟';

  @override
  String get editorDropToOpenOrInsert => '拖放 PDF 以開啟或插入';

  @override
  String get editorInsertPages => '插入頁面';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '已插入 $count；無法讀取 $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已將 $count 個 PDF 插入 $title',
      one: '已將頁面插入 $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return '無效的連結：$uri';
  }

  @override
  String get editorJavaScriptIgnored => '此文件嘗試執行 JavaScript（已忽略）';

  @override
  String get editorLoadingFullDocument => '正在載入完整文件';

  @override
  String get editorMenuCompareWith => '與…比較';

  @override
  String get editorMenuDigitallySign => '數位簽署…';

  @override
  String get editorMenuDigitallySigning => '正在數位簽署…';

  @override
  String get editorMenuExportImage => '將頁面匯出為影像…';

  @override
  String get editorMenuNewDocument => '新文件…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => '開啟 PDF…';

  @override
  String get editorMenuPrint => '列印…';

  @override
  String get editorMenuSaveAs => '另存新檔…';

  @override
  String get editorMenuScanDocument => '掃描為新文件…';

  @override
  String get editorMenuInsertScan => '插入掃描件…';

  @override
  String get editorScanFailed => '無法掃描文件。';

  @override
  String get editorInsertedScan => '已插入掃描的頁面。';

  @override
  String get editorMenuSettings => '設定';

  @override
  String get editorMenuSwitchToEdit => '切換至編輯模式';

  @override
  String get editorMenuSwitchToReadOnly => '切換至唯讀';

  @override
  String editorNamedAction(String name) {
    return '具名動作：$name';
  }

  @override
  String get editorNoRecentFiles => '沒有最近使用的檔案';

  @override
  String editorOcrTitle(String title) {
    return '$title（OCR）';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => '執行 OCR 前請先開啟文件';

  @override
  String get editorOpenFailedTitle => '開啟失敗';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在新分頁中開啟',
      one: '在新分頁中開啟',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => '在新分頁中開啟 PDF';

  @override
  String get editorOpenRecent => '開啟最近使用';

  @override
  String get editorOpenTabs => '開啟的分頁';

  @override
  String get editorOpeningDocumentSemantic => '正在開啟文件';

  @override
  String get editorOpeningPdf => '正在開啟 PDF…';

  @override
  String editorOpeningTitle(String title) {
    return '正在開啟 $title…';
  }

  @override
  String editorPageNumber(int number) {
    return '第 $number 頁';
  }

  @override
  String get editorPreviewComparison => '比較';

  @override
  String get editorPreviewCouldNotOpen => '無法開啟';

  @override
  String get editorPreviewOpening => '正在開啟';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => '已移除簽名';

  @override
  String get editorSnapshotCopied => '已將快照複製到剪貼簿';

  @override
  String get editorSnapshotCopyFailed => '無法將快照複製到剪貼簿';

  @override
  String get editorTabs => '分頁';

  @override
  String editorTabsOpenCount(int count) {
    return '已開啟 $count 個';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 份文件有未儲存的變更。',
      one: '有一份文件有未儲存的變更。',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return '不支援的動作：$type';
  }

  @override
  String get editorUntitled => '未命名';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version 已可使用。';
  }

  @override
  String get editorUpdateLater => '稍後';

  @override
  String get editorViewAllTabs => '檢視所有分頁';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => '匯出';

  @override
  String get imgExportFormat => '格式';

  @override
  String get imgExportResolution => '解析度';

  @override
  String get imgExportTitle => '將頁面匯出為影像';

  @override
  String get newDocCreate => '建立';

  @override
  String get newDocLandscape => '橫向';

  @override
  String get newDocOrientation => '方向';

  @override
  String get newDocPageSize => '頁面大小';

  @override
  String get newDocPortrait => '直向';

  @override
  String get newDocTitle => '新文件';

  @override
  String get none => '無';

  @override
  String get ocrAlreadyRunning => 'OCR 已在執行中 - 請等待其完成或取消它';

  @override
  String get ocrBrowserInitFailed => '瀏覽器 OCR 初始化失敗';

  @override
  String get ocrCancelled => '已取消 OCR';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已在 $count 個文字範圍後取消 OCR',
      one: '已在 1 個文字範圍後取消 OCR',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => '下載';

  @override
  String ocrDownloadFailed(String error) {
    return '無法下載 OCR 模型：$error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return '新增可選取的文字圖層需要裝置端 OCR 模型$size。它只會下載一次，之後便可離線執行。\n\n模型：$model';
  }

  @override
  String get ocrDownloadPromptTitle => '下載 OCR 模型？';

  @override
  String ocrFailed(String error) {
    return 'OCR 失敗：$error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable => '此平台不支援裝置端 OCR';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR 新增了 $count 個文字範圍 - 現在可選取頁面文字',
      one: 'OCR 新增了 1 個文字範圍 - 現在可選取頁面文字',
      zero: 'OCR 在這些頁面上找不到文字',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      '網頁 OCR 會下載 Florence-2 視覺語言模型，並透過 Transformers.js 以 WebGPU/WASM 在本機執行。PDF 頁面會保留在此瀏覽器中；只有模型檔案會在首次使用時擷取。';

  @override
  String get ocrWebPromptTitle => '在此瀏覽器中執行 AI OCR？';

  @override
  String get ocrWebStart => '開始 OCR';

  @override
  String get ok => '確定';

  @override
  String get paste => '貼上';

  @override
  String get printDlgPreparing => '準備中…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '正在算繪第 $rendered 頁，共 $total 頁…';
  }

  @override
  String get printDlgTitle => '列印中';

  @override
  String get redo => '重做';

  @override
  String get remove => '移除';

  @override
  String get rename => '重新命名';

  @override
  String get reset => '重設';

  @override
  String get save => '儲存';

  @override
  String get settingsAbout => '關於';

  @override
  String get settingsAppearance => '外觀';

  @override
  String get settingsCheckNow => '立即檢查';

  @override
  String get settingsLanguage => '語言';

  @override
  String get settingsLanguageSystem => '系統預設';

  @override
  String get settingsCheckingForUpdates => '正在檢查更新…';

  @override
  String get settingsCouldNotOpenDownload => '無法開啟下載';

  @override
  String get settingsCouldNotOpenSystemSettings => '無法開啟系統設定';

  @override
  String get settingsDeveloperTools => '開發者工具';

  @override
  String get settingsDeveloperToolsSubtitle => '指標、記錄、算繪模式 (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '下載 $version';
  }

  @override
  String get settingsOpenSettings => '開啟設定';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已記住 $count 個',
      one: '已記住 1 個',
      zero: '沒有最近使用的檔案',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => '最近使用的檔案';

  @override
  String get settingsSetUpAsDefault => '設定為預設應用程式';

  @override
  String get settingsSystem => '系統';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeLight => '淺色';

  @override
  String get settingsThemeSystem => '系統';

  @override
  String get settingsTitle => '設定';

  @override
  String settingsUpToDate(String version) {
    return '您使用的是最新版本 ($version)。';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return '版本 $version 已可使用（您目前為 $currentVersion）。';
  }

  @override
  String get settingsUpdateFailed => '無法檢查更新。請稍後再試。';

  @override
  String settingsUpdateIdle(String name, String version) {
    return '您使用的是 $name $version。';
  }

  @override
  String get settingsUpdates => '更新';

  @override
  String get settingsViewSource => '在 GitHub 上檢視原始碼';

  @override
  String get undo => '復原';

  @override
  String get welcomeOpenPdf => '開啟 PDF';

  @override
  String get welcomePickAgainToReopen => '再次選取以重新開啟';

  @override
  String get welcomeRecent => '最近使用';

  @override
  String get welcomeRemoveFromRecent => '從最近使用中移除';

  @override
  String get welcomeTapToReopen => '點一下以重新開啟';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': '安裝網頁應用程式，然後將其選為 PDF 檔案的開啟方式。',
        'windows': '開啟 Windows 的 PDF 預設應用程式設定。',
        'macos': '依照 Finder 的「永遠以此開啟」步驟操作。',
        'linux': '使用您桌面環境的預設應用程式設定。',
        'android': '開啟 PDF 時選擇 DartPDF，然後點選「一律」。',
        'ios': '使用「檔案」中的「分享」或「開啟方式」將 PDF 傳送至此。',
        'other': '設定您系統的 PDF 檔案處理程式。',
      },
    );
    return '$_temp0';
  }

  @override
  String settingsDefaultAppInstructions(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': '先從瀏覽器安裝 DartPDF。然後使用瀏覽器或作業系統的檔案處理程式設定，將 PDF 檔案關聯至已安裝的應用程式。',
        'windows':
            'Windows 設定會開啟至「預設應用程式」。搜尋「.pdf」或「PDF」，選擇目前的 PDF 應用程式，然後選取 DartPDF。',
        'macos':
            '在 Finder 中選取任一 PDF，選擇「檔案」>「取得資訊」，展開「打開檔案的應用程式」，選擇 DartPDF，然後按一下「全部更改…」。',
        'linux':
            '開啟桌面環境的「預設應用程式」設定，或在「檔案」中的 PDF 上按一下右鍵，選擇「內容」，並將 DartPDF 設為 PDF 文件的預設值。',
        'android':
            '從「檔案」或「下載」開啟 PDF，在應用程式選擇器中選擇 DartPDF，然後選取「一律」。如果已有其他應用程式開啟 PDF，請先在 Android 設定中清除該應用程式的預設值。',
        'ios':
            'iOS 不提供全域預設 PDF 編輯器。請使用「檔案」>「分享」，或長按 PDF 並選擇「分享/開啟方式」，然後選擇 DartPDF。',
        'other': '使用系統的檔案處理程式設定，將 PDF 文件關聯至 DartPDF。',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => '正在下載 OCR 模型…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return '正在下載模型 $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => '正在完成 OCR…';

  @override
  String get fileTypePdf => 'PDF 文件';

  @override
  String get fileTypeImages => '影像';

  @override
  String get fileTypeStampBundle => 'DartPDF 戳記';

  @override
  String get appSigKeyFileType => 'RSA 私密金鑰';

  @override
  String get appSigCertificateFileType => 'X.509 憑證';

  @override
  String get appSigErrorNoCertificateSelected => '請至少選擇一個 X.509 憑證。';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return '憑證 $index 不是有效的 X.509。';
  }

  @override
  String get appSigErrorKeyCertificateMismatch => '私密金鑰與任何選取的 RSA 憑證都不相符。';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      '不支援加密的私密金鑰。請選擇未加密的 RSA PKCS#1 或 PKCS#8 金鑰。';

  @override
  String get appSigErrorKeyNotRsa => '私密金鑰不是未加密的 RSA PKCS#1 或 PKCS#8 金鑰。';

  @override
  String get appSigErrorNoCertificateFound => '找不到 X.509 憑證。';
}
