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
