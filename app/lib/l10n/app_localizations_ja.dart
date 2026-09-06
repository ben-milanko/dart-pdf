// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get add => '追加';

  @override
  String get appSigAddLogo => 'ロゴを追加…';

  @override
  String appSigAllPages(int pageCount) {
    return '全 $pageCount ページ';
  }

  @override
  String get appSigAppearance => '外観';

  @override
  String get appSigAppearanceDescription =>
      '署名は配置した場所に描画されます。署名者名と詳細は常に表示されます。手書きのマークやロゴの背景を追加できます。';

  @override
  String appSigApplyTo(String label) {
    return '適用先: $label';
  }

  @override
  String get appSigApplyToPages => 'ページに適用…';

  @override
  String get appSigChooseCertificate => '証明書ファイルを選択…';

  @override
  String get appSigChooseKeyDescription =>
      '秘密鍵（RSA、PEM または DER）とその証明書ファイルを選択してください。鍵は署名にのみ使用され、保存されることはありません。';

  @override
  String get appSigChoosePngOrJpeg => 'PNG または JPEG 画像を選択してください。';

  @override
  String get appSigChoosePrivateKey => '秘密鍵を選択…';

  @override
  String get appSigContactInfo => '連絡先情報';

  @override
  String get appSigCouldNotCaptureSignature => '署名をキャプチャできませんでした。';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return '証明書を読み取れませんでした: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return '鍵を読み取れませんでした: $error';
  }

  @override
  String get appSigCreateOnDevice => 'このデバイスで署名を作成';

  @override
  String appSigDate(String date) {
    return '日付: $date';
  }

  @override
  String get appSigDigitallySign => 'デジタル署名';

  @override
  String get appSigDrawSignature => '署名を描く…';

  @override
  String get appSigFieldHelper => '空欄のままにすると新しい署名フィールドを作成します。';

  @override
  String get appSigFieldLabel => '既存の署名フィールド（任意）';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の証明書',
      one: '1 件の証明書',
    );
    return '$_temp0 · 有効期間 $validFrom 〜 $validUntil';
  }

  @override
  String get appSigIntro =>
      'デジタル署名は、あなたがこのドキュメントに署名し、それ以降変更されていないことを証明します。署名方法を選択してください。';

  @override
  String get appSigKeyOrCertUnreadable => '選択した鍵または証明書を読み取れませんでした。';

  @override
  String get appSigKeylessDescription =>
      '最も簡単な方法です。メールで本人確認を行い、信頼できるタイムスタンプ付きで署名を代行します。インストールや設定は不要です。';

  @override
  String get appSigKeylessIdentity => 'キーレス ID';

  @override
  String get appSigKeylessSignInExpired =>
      'キーレスサインインの有効期限が切れました。もう一度サインインしてください。';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'キーレスサインインに失敗しました: $failure';
  }

  @override
  String get appSigKeylessSubtitle => 'キーレス · タイムスタンプ付き · 有効性不明';

  @override
  String get appSigKeylessWebNote =>
      'メールでのサインインが最も簡単な方法で、DartPDF のデスクトップ版とモバイル版で利用できます。セキュリティ上の理由により、ウェブブラウザでは動作しません。';

  @override
  String get appSigLocation => '場所';

  @override
  String get appSigLogoAdded => 'ロゴを追加しました ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return '$start〜$end ページ';
  }

  @override
  String get appSigPreviewNote => 'プレビュー - 署名後のボックスは若干異なる場合があります。';

  @override
  String get appSigReason => '理由';

  @override
  String appSigReasonLine(String reason) {
    return '理由: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'サインインを更新中…';

  @override
  String get appSigRemoveLogo => 'ロゴを削除';

  @override
  String get appSigRemoveSignature => '署名を削除';

  @override
  String get appSigSelfSignedDescription =>
      'サインインやファイルは不要です。個人利用に最適で、次回のためにこのデバイスに保存されます。一部の PDF リーダーでは「署名済み、有効性不明」と表示されますが、自分で作成した署名では通常の動作です。';

  @override
  String get appSigSelfSignedIdentity => '自己署名 ID';

  @override
  String get appSigSelfSignedSubtitle => '自己署名 · 有効性不明';

  @override
  String get appSigShowSignatureOnPages => '署名を表示するページ';

  @override
  String get appSigSign => '署名';

  @override
  String get appSigSignInWithEmail => 'メールでサインイン';

  @override
  String get appSigSignatureAdded => '署名を追加しました ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '$signerName によりデジタル署名';
  }

  @override
  String get appSigSigner => '署名者';

  @override
  String get appSigSigningYouIn => 'サインイン中…';

  @override
  String get appSigThisPageOnly => 'このページのみ';

  @override
  String get appSigUseOwnCertificate => '自分の証明書を使用';

  @override
  String get appSigUseOwnCertificateSubtitle => '組織発行の署名証明書を使う場合';

  @override
  String get appSigX509Signer => 'X.509 署名者';

  @override
  String get apply => '適用';

  @override
  String get cancel => 'キャンセル';

  @override
  String get clear => 'クリア';

  @override
  String get close => '閉じる';

  @override
  String get copy => 'コピー';

  @override
  String get cut => '切り取り';

  @override
  String get delete => '削除';

  @override
  String get done => '完了';

  @override
  String get edit => '編集';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'これら $count 件の PDF を新しいタブで開きますか、それともそのページを「$title」に挿入しますか?',
      one: 'この PDF を新しいタブで開きますか、それともそのページを「$title」に挿入しますか?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ドロップした PDF を追加',
      one: 'ドロップした PDF を追加',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => '注釈のテキストをコピーしました';

  @override
  String get editorAppMenuTooltip => 'DartPDF メニュー';

  @override
  String get editorCancelOcr => 'OCR をキャンセル';

  @override
  String get editorClearRecentFiles => '最近使用したファイルをクリア';

  @override
  String get editorCloseAll => 'すべて閉じる';

  @override
  String get editorCloseOthers => '他を閉じる';

  @override
  String get editorCloseTab => 'タブを閉じる';

  @override
  String get editorCloseTabsToRight => '右側のタブを閉じる';

  @override
  String get editorCompareFailedTitle => '比較に失敗しました';

  @override
  String editorCompareTitle(String title) {
    return '比較: $title';
  }

  @override
  String get editorCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get editorCopySelectedTextTooltip => '選択したテキストをコピー (⌘C)';

  @override
  String get editorCopyText => 'テキストをコピー';

  @override
  String editorCouldNotExport(String title) {
    return '$title をエクスポートできませんでした';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'スタンプをインポートできませんでした: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ドロップした PDF を挿入できませんでした',
      one: 'ドロップした PDF を挿入できませんでした',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '$title を開けませんでした\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => '含まれるフォルダを開けませんでした';

  @override
  String editorCouldNotOpenSecond(String error) {
    return '2 つ目のファイルを開けませんでした\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return '選択したファイルを開けませんでした\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '$url を開けませんでした';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '$title を印刷できませんでした';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '$title を再度開けませんでした';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'デジタル署名できませんでした: $error';
  }

  @override
  String get editorDiscard => '破棄';

  @override
  String get editorDiscardChangesTitle => '変更を破棄しますか?';

  @override
  String get editorDocumentSigned => 'ドキュメントにデジタル署名しました';

  @override
  String get editorDownload => 'ダウンロード';

  @override
  String get editorDropToOpen => 'PDF をドロップして開く';

  @override
  String get editorDropToOpenOrInsert => 'PDF をドロップして開くか挿入';

  @override
  String get editorInsertPages => 'ページを挿入';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count 件を挿入しました。$files は読み取れませんでした';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の PDF を $title に挿入しました',
      one: 'ページを $title に挿入しました',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return '無効なリンク: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'このドキュメントは JavaScript を実行しようとしました（無視されました）';

  @override
  String get editorLoadingFullDocument => 'ドキュメント全体を読み込み中';

  @override
  String get editorMenuCompareWith => '比較する…';

  @override
  String get editorMenuDigitallySign => 'デジタル署名…';

  @override
  String get editorMenuDigitallySigning => 'デジタル署名中…';

  @override
  String get editorMenuExportImage => 'ページを画像としてエクスポート…';

  @override
  String get editorMenuNewDocument => '新規ドキュメント…';

  @override
  String get editorMenuNewWindow => '新しいウィンドウ';

  @override
  String get editorMoveToNewWindow => '新しいウィンドウに移動';

  @override
  String get editorUnableToOpenNewWindow => '新しいウィンドウを開けませんでした';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'PDF を開く…';

  @override
  String get editorMenuPrint => '印刷…';

  @override
  String get editorMenuSaveAs => '名前を付けて保存…';

  @override
  String get editorMenuScanDocument => '新しいドキュメントにスキャン…';

  @override
  String get editorMenuInsertDocument => 'ドキュメントを挿入…';

  @override
  String get editorMenuInsertScan => 'スキャンを挿入…';

  @override
  String get editorScanFailed => 'ドキュメントをスキャンできませんでした。';

  @override
  String get editorInsertedScan => 'スキャンしたページを挿入しました。';

  @override
  String get editorMenuSettings => '設定';

  @override
  String get editorMenuSectionFile => 'ファイル';

  @override
  String get editorMenuSectionDocument => 'このドキュメント';

  @override
  String get editorMenuSectionApp => 'アプリ';

  @override
  String get editorMenuReadOnly => '読み取り専用';

  @override
  String get editorMenuSearchActions => '操作を検索…';

  @override
  String get paletteHint => '操作・ツール・パネルを検索';

  @override
  String get paletteNoMatch => '一致するコマンドがありません';

  @override
  String get paletteKeyHints => '↑↓ 移動 · ⏎ 実行 · esc 閉じる';

  @override
  String paletteCount(int count) {
    return '$count 件のコマンド';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$total 件中 $count 件';
  }

  @override
  String get paletteSourceMenu => 'メニュー';

  @override
  String get paletteSourcePanel => 'パネル';

  @override
  String get paletteSourceView => '表示';

  @override
  String get paletteSourceFile => 'ファイル';

  @override
  String paletteSourceTool(String group) {
    return '$groupツール';
  }

  @override
  String get paletteNeedsDocument => 'ドキュメントを開いてください';

  @override
  String editorNamedAction(String name) {
    return '名前付きアクション: $name';
  }

  @override
  String get editorNoRecentFiles => '最近使用したファイルはありません';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'OCR を実行する前にドキュメントを開いてください';

  @override
  String get editorOpenFailedTitle => '開けませんでした';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新しいタブで開く',
      one: '新しいタブで開く',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'PDF を新しいタブで開く';

  @override
  String get editorOpenRecent => '最近使用したファイルを開く';

  @override
  String get editorViewAllRecentFiles => '最近使用したファイルをすべて表示…';

  @override
  String get editorOpenTabs => '開いているタブ';

  @override
  String get editorOpeningDocumentSemantic => 'ドキュメントを開いています';

  @override
  String get editorOpeningPdf => 'PDF を開いています…';

  @override
  String editorOpeningTitle(String title) {
    return '$title を開いています…';
  }

  @override
  String editorPageNumber(int number) {
    return '$number ページ';
  }

  @override
  String get editorPreviewComparison => '比較';

  @override
  String get editorPreviewCouldNotOpen => '開けませんでした';

  @override
  String get editorPreviewOpening => '開いています';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '前回のセッションの $count 件のドキュメントの未保存の変更を復元しました。',
      one: '前回のセッションの未保存の変更を復元しました。',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => '署名を削除しました';

  @override
  String get editorSnapshotCopied => 'スナップショットをクリップボードにコピーしました';

  @override
  String get editorSnapshotCopyFailed => 'スナップショットをクリップボードにコピーできませんでした';

  @override
  String get editorTabs => 'タブ';

  @override
  String editorTabsOpenCount(int count) {
    return '$count 件開いています';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のドキュメントに未保存の変更があります。',
      one: 'ドキュメントに未保存の変更があります。',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'サポートされていないアクション: $type';
  }

  @override
  String get editorUntitled => '無題';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version が利用可能です。';
  }

  @override
  String get editorUpdateLater => '後で';

  @override
  String get updateInstallNow => '今すぐ更新';

  @override
  String get updateDownloadingTitle => '更新をダウンロード中';

  @override
  String get updatePreparing => '準備中…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get updateRestarting => '更新を完了するために再起動しています…';

  @override
  String get updateHandedOff => '更新をダウンロードしました。インストーラーを開いています…';

  @override
  String updateFailed(String error) {
    return '更新に失敗しました: $error';
  }

  @override
  String get editorViewAllTabs => 'すべてのタブを表示';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'エクスポート';

  @override
  String get imgExportFormat => '形式';

  @override
  String get imgExportResolution => '解像度';

  @override
  String get imgExportTitle => 'ページを画像としてエクスポート';

  @override
  String get newDocCreate => '作成';

  @override
  String get newDocLandscape => '横向き';

  @override
  String get newDocOrientation => '向き';

  @override
  String get newDocPageSize => 'ページサイズ';

  @override
  String get newDocPortrait => '縦向き';

  @override
  String get newDocTitle => '新規ドキュメント';

  @override
  String get none => 'なし';

  @override
  String get ocrAlreadyRunning => 'OCR は既に実行中です - 完了を待つかキャンセルしてください';

  @override
  String get ocrBrowserInitFailed => 'ブラウザ OCR の初期化に失敗しました';

  @override
  String get ocrCancelled => 'OCR をキャンセルしました';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のテキストスパンの後で OCR をキャンセルしました',
      one: '1 件のテキストスパンの後で OCR をキャンセルしました',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'ダウンロード';

  @override
  String ocrDownloadFailed(String error) {
    return 'OCR モデルをダウンロードできませんでした: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return '選択可能なテキストレイヤーを追加するには、オンデバイス OCR モデル$sizeが必要です。一度ダウンロードすれば、その後はオフラインで動作します。\n\nモデル: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR モデルをダウンロードしますか?';

  @override
  String ocrFailed(String error) {
    return 'OCR に失敗しました: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(約 $mb MB)';
  }

  @override
  String get ocrNotAvailable => 'このプラットフォームではオンデバイス OCR を利用できません';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR で $count 件のテキストスパンを追加しました - ページのテキストを選択できるようになりました',
      one: 'OCR で 1 件のテキストスパンを追加しました - ページのテキストを選択できるようになりました',
      zero: 'これらのページにテキストは見つかりませんでした',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'ウェブ OCR は Florence-2 のビジョン言語モデルをダウンロードし、Transformers.js を通じて WebGPU/WASM でローカルに実行します。PDF ページはこのブラウザ内に留まり、初回使用時にモデルファイルのみが取得されます。';

  @override
  String get ocrWebPromptTitle => 'このブラウザで AI OCR を実行しますか?';

  @override
  String get ocrWebStart => 'OCR を開始';

  @override
  String get ok => 'OK';

  @override
  String get paste => '貼り付け';

  @override
  String get printDlgPreparing => '準備中…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'ページ $rendered / $total をレンダリング中…';
  }

  @override
  String get printDlgTitle => '印刷中';

  @override
  String get printPreviewAll => 'すべて';

  @override
  String get printPreviewCurrent => '現在のページ';

  @override
  String get printPreviewFrom => '開始';

  @override
  String get printPreviewNextPage => '次のページ';

  @override
  String printPreviewPageOf(int page, int total) {
    return '$total ページ中 $page ページ';
  }

  @override
  String get printPreviewPreviousPage => '前のページ';

  @override
  String get printPreviewPrint => '印刷';

  @override
  String get printPreviewRange => '範囲';

  @override
  String printPreviewRangeError(int total) {
    return '1 〜 $total の範囲でページを入力してください。';
  }

  @override
  String printPreviewSelection(int count) {
    return '印刷するページ数: $count';
  }

  @override
  String get printPreviewTitle => '印刷プレビュー';

  @override
  String get printPreviewTo => '終了';

  @override
  String get printPreviewUnavailable => 'プレビューを利用できません';

  @override
  String get redo => 'やり直し';

  @override
  String get remove => '削除';

  @override
  String get rename => '名前を変更';

  @override
  String get reset => 'リセット';

  @override
  String get save => '保存';

  @override
  String get settingsAbout => 'バージョン情報';

  @override
  String get settingsAppearance => '外観';

  @override
  String get settingsCheckNow => '今すぐ確認';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageSystem => 'システムのデフォルト';

  @override
  String get settingsCheckingForUpdates => 'アップデートを確認中…';

  @override
  String get settingsCouldNotOpenDownload => 'ダウンロードを開けませんでした';

  @override
  String get settingsCouldNotOpenSystemSettings => 'システム設定を開けませんでした';

  @override
  String get settingsDeveloperTools => '開発者ツール';

  @override
  String get settingsDeveloperToolsSubtitle => 'メトリクス、ログ、レンダリングモード (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version をダウンロード';
  }

  @override
  String get settingsOpenSettings => '設定を開く';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件を記憶',
      one: '1 件を記憶',
      zero: '最近使用したファイルはありません',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => '最近使用したファイル';

  @override
  String get settingsSetUpAsDefault => '既定のアプリケーションとして設定';

  @override
  String get settingsSystem => 'システム';

  @override
  String get settingsThemeDark => 'ダーク';

  @override
  String get settingsThemeLight => 'ライト';

  @override
  String get settingsThemeSystem => 'システム';

  @override
  String get settingsTitle => '設定';

  @override
  String settingsUpToDate(String version) {
    return '最新バージョン ($version) を使用しています。';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'バージョン $version が利用可能です（現在は $currentVersion）。';
  }

  @override
  String get settingsUpdateFailed => 'アップデートを確認できませんでした。後でもう一度お試しください。';

  @override
  String settingsUpdateIdle(String name, String version) {
    return '$name $version を使用しています。';
  }

  @override
  String get settingsNightlyUpdates => 'ナイトリーアップデート';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'main の署名なし Windows テストビルドの更新通知を自動で受け取ります。';

  @override
  String get settingsUpdates => 'アップデート';

  @override
  String get settingsViewSource => 'GitHub でソースを表示';

  @override
  String get undo => '元に戻す';

  @override
  String get welcomeOpenPdf => 'PDF を開く';

  @override
  String get welcomePickAgainToReopen => '再度開くにはもう一度選択してください';

  @override
  String get welcomeRecent => '最近使用';

  @override
  String get welcomeSearchRecentFiles => '最近使用したファイルを検索';

  @override
  String get welcomeNoMatchingRecentFiles => '検索に一致する最近使用したファイルはありません';

  @override
  String get welcomeRemoveFromRecent => '最近使用したファイルから削除';

  @override
  String get welcomeTapToReopen => 'タップして再度開く';

  @override
  String get welcomeViewAsGrid => 'グリッド表示';

  @override
  String get welcomeViewAsList => 'リスト表示';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'ウェブアプリをインストールし、PDF ファイルの既定アプリに選択してください。',
        'windows': 'PDF の Windows 既定アプリ設定を開きます。',
        'macos': 'Finder の「常にこのアプリで開く」の手順に従ってください。',
        'linux': 'デスクトップの既定アプリケーション設定を使用してください。',
        'android': 'PDF を開くときに DartPDF を選び、「常時」をタップしてください。',
        'ios': 'ファイルアプリの共有または「このアプリで開く」で PDF をここに送信してください。',
        'other': 'システムの PDF ファイルハンドラを設定してください。',
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
            'まずブラウザから DartPDF をインストールしてください。次に、ブラウザまたはオペレーティングシステムのファイルハンドラ設定で、PDF ファイルをインストールしたアプリに関連付けます。',
        'windows':
            'Windows の設定が「既定のアプリ」に開きます。「.pdf」または「PDF」を検索し、現在の PDF アプリを選択して DartPDF を選びます。',
        'macos':
            'Finder で任意の PDF を選択し、「ファイル」>「情報を見る」を選択して「このアプリケーションで開く」を展開し、DartPDF を選んで「すべてを変更…」をクリックします。',
        'linux':
            'デスクトップの既定のアプリケーション設定を開くか、ファイルアプリで PDF を右クリックして「プロパティ」を選び、DartPDF を PDF ドキュメントの既定に設定します。',
        'android':
            'ファイルまたはダウンロードから PDF を開き、アプリ選択画面で DartPDF を選んで「常時」を選択します。他のアプリが既に PDF を開く場合は、まず Android の設定でそのアプリの既定をクリアしてください。',
        'ios':
            'iOS にはグローバルな既定の PDF エディタはありません。「ファイル」>「共有」を使うか、PDF を長押しして「共有」/「このアプリで開く」を選び、DartPDF を選択してください。',
        'other': 'システムのファイルハンドラ設定を使い、PDF ドキュメントを DartPDF に関連付けてください。',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR モデルをダウンロード中…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'モデルをダウンロード中 $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR を完了中…';

  @override
  String get fileTypePdf => 'PDF ドキュメント';

  @override
  String get fileTypeImages => '画像';

  @override
  String get fileTypeStampBundle => 'DartPDF スタンプ';

  @override
  String get appSigKeyFileType => 'RSA 秘密鍵';

  @override
  String get appSigCertificateFileType => 'X.509 証明書';

  @override
  String get appSigErrorNoCertificateSelected => 'X.509 証明書を 1 つ以上選択してください。';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return '証明書 $index は有効な X.509 ではありません。';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      '秘密鍵が、選択したどの RSA 証明書とも一致しません。';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      '暗号化された秘密鍵はサポートされていません。暗号化されていない RSA PKCS#1 または PKCS#8 鍵を選択してください。';

  @override
  String get appSigErrorKeyNotRsa =>
      '秘密鍵は暗号化されていない RSA PKCS#1 または PKCS#8 鍵ではありません。';

  @override
  String get appSigErrorNoCertificateFound => 'X.509 証明書が見つかりませんでした。';

  @override
  String get imageSourceTakePhoto => '写真を撮る';

  @override
  String get imageSourceChooseFile => 'ファイルを選択';

  @override
  String get imageSourceCameraFailed => '写真を撮影できませんでした';

  @override
  String get settingsCachedDocuments => 'キャッシュされたドキュメント';

  @override
  String settingsCacheUsage(String used, String limit) {
    return '$limit MiB 中 $used MiB 使用';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return '$limit MiB を超えるファイルはキャッシュされません。削除しても最近使ったファイルの一覧、開いているドキュメント、未保存の変更は保持されます。キャッシュされたファイルを再度開くには、ファイルを選び直す必要があります。';
  }

  @override
  String get settingsClearCachedDocuments => 'ドキュメントのキャッシュを削除';

  @override
  String get settingsCacheUnavailable => 'キャッシュサイズを取得できません';

  @override
  String get settingsCacheClearFailed => 'ドキュメントのキャッシュを削除できませんでした。再試行してください。';

  @override
  String get printOptionsPrinter => 'プリンター';

  @override
  String get printOptionsNativePrinter =>
      '次に表示されるシステムの印刷ダイアログで、プリンター、給紙トレイ、カラー、両面印刷、プリンターのプロパティを選択します。ここに表示されているレイアウトを使用するには、倍率を100%、部数を1のままにしてください。';

  @override
  String get printOptionsPages => 'ページ';

  @override
  String get printOptionsSelected => '選択したページ';

  @override
  String get printOptionsPageRange => 'ページ（例: 1, 3-5）';

  @override
  String get printOptionsAddFiles => 'ファイルを追加…';

  @override
  String get printOptionsAddFailed => '選択したファイルを追加できませんでした。';

  @override
  String get printOptionsGetWindow => '範囲を選択';

  @override
  String get printOptionsClearWindow => '範囲を解除';

  @override
  String get printOptionsWindowHint => '元のページ上でドラッグして長方形を描き、印刷する範囲を選択してください。';

  @override
  String get printOptionsPaper => '用紙';

  @override
  String get printOptionsPaperSize => '用紙サイズ';

  @override
  String get printOptionsPageSize => '文書のページサイズを使用';

  @override
  String get printOptionsOrientation => '用紙の向き';

  @override
  String get printOptionsAuto => '自動';

  @override
  String get printOptionsPortrait => '縦';

  @override
  String get printOptionsLandscape => '横';

  @override
  String get printOptionsCopies => '部数';

  @override
  String get printOptionsCollate => '部単位で印刷';

  @override
  String get printOptionsReverse => 'ページの順序を逆にする';

  @override
  String get printOptionsLayout => 'ページレイアウト';

  @override
  String get printOptionsScaling => 'ページの拡大・縮小';

  @override
  String get printOptionsScaleNone => 'なし（実際のサイズ）';

  @override
  String get printOptionsFitPaper => '用紙に合わせる';

  @override
  String get printOptionsReducePaper => '用紙に収まるよう縮小';

  @override
  String get printOptionsFitMargins => '余白内に合わせる';

  @override
  String get printOptionsReduceMargins => '余白内に収まるよう縮小';

  @override
  String get printOptionsCustomScale => '倍率を指定';

  @override
  String get printOptionsMultiple => '1枚に複数ページを印刷';

  @override
  String get printOptionsScalePercent => '倍率（%）';

  @override
  String get printOptionsMargin => '余白（pt）';

  @override
  String get printOptionsPagesPerSheet => '1枚あたりのページ数';

  @override
  String get printOptionsPageOrder => 'ページの順序';

  @override
  String get printOptionsHorizontal => '横方向';

  @override
  String get printOptionsHorizontalReverse => '横方向（右から左）';

  @override
  String get printOptionsVertical => '縦方向';

  @override
  String get printOptionsVerticalReverse => '縦方向（列を右から左）';

  @override
  String get printOptionsBorder => 'ページの枠線を印刷';

  @override
  String get printOptionsRotation => '回転（時計回り）';

  @override
  String get printOptionsNoRotation => 'なし';

  @override
  String get printOptionsCenter => '用紙の中央に配置';

  @override
  String get printOptionsOffsetX => '右への移動量（pt）';

  @override
  String get printOptionsOffsetY => '下への移動量（pt）';

  @override
  String get printOptionsContents => '印刷する内容';

  @override
  String get printOptionsDocumentAndMarkups => '文書と注釈';

  @override
  String get printOptionsDocumentOnly => '文書のみ';

  @override
  String get printOptionsMarkupsOnly => '注釈のみ';

  @override
  String get printOptionsDimPage => 'ページの内容を薄く印刷';

  @override
  String get printOptionsDimMarkups => '注釈を薄く印刷';

  @override
  String get printOptionsHyperlinks => '表示されているハイパーリンクを印刷';

  @override
  String get printOptionsDefaults => '既定値に戻す';

  @override
  String get printOptionsInvalidNumber => '印刷する前に有効な数値を入力してください。';

  @override
  String get printOptionsInvalidValue => '無効な値です';

  @override
  String get printOptionsMarginGuide => '赤い線は余白を示しています。印刷はされません。';

  @override
  String printOptionsAreaSize(String width, String height) {
    return '範囲: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return '元のページ: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return '用紙: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return '$total枚中$sheet枚目';
  }

  @override
  String get printOptionsInvalidLayout =>
      'このレイアウトを準備できませんでした。用紙サイズ、余白、倍率を確認してください。';
}
