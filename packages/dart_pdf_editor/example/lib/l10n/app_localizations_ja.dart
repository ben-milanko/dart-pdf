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
  String exActionJavaScript(String script) {
    return 'アプリに渡された JavaScript: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'リンク: $uri';
  }

  @override
  String exActionNamed(String name) {
    return '名前付きアクション: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return '処理されないアクションの種類: $type';
  }

  @override
  String get exAnnotationTextCopied => '注釈のテキストをコピーしました';

  @override
  String get exApiKeyHelper => 'Authorization: Bearer … として送信されます';

  @override
  String get exApiKeyLabel => 'API キー / トークン（任意）';

  @override
  String get exAppMenuTooltip => 'DartPDF メニュー';

  @override
  String get exClearRecentFiles => '最近使用したファイルをクリア';

  @override
  String get exCloseTab => 'タブを閉じる';

  @override
  String exCompareTabTitle(String before, String after) {
    return '比較: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => '別の PDF と比較…';

  @override
  String get exCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get exCopySelectedText => '選択したテキストをコピー (⌘C)';

  @override
  String get exCopyText => 'テキストをコピー';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '$name を開けませんでした\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '$path を開けませんでした\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '$url を開けませんでした';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '$uri を開けませんでした\n$error\n\nウェブでは、これは多くの場合 CORS の制限です。サーバーは Access-Control-Allow-Origin を送信し、Range ヘッダーを公開する必要があります。';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '$title を再度開けませんでした\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '$title を再度開けませんでした - 保存されたコピーはもう利用できません。';
  }

  @override
  String get exDemoNoteHint => 'ここに入力 - このテキストボックスはページの上に浮かんでいます';

  @override
  String get exDiagnosticsCopied => '診断情報をクリップボードにコピーしました';

  @override
  String exDownloaded(String name) {
    return '$name をダウンロードしました';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name をダウンロードしました - Ctrl+V で PDF に貼り戻せます';
  }

  @override
  String get exExport => 'エクスポート';

  @override
  String exExportFailed(String error) {
    return 'エクスポートに失敗しました: $error';
  }

  @override
  String get exExportPageImageMenu => 'ページを画像としてエクスポート…';

  @override
  String get exExportPageImageTitle => 'ページを画像としてエクスポート';

  @override
  String get exFeatureShowcase => '機能ショーケース';

  @override
  String get exFormat => '形式';

  @override
  String get exHide => '非表示';

  @override
  String get exHorizontalLayout => '水平ページレイアウト';

  @override
  String get exHowToSetupOcr => 'OCR サーバーの設定方法';

  @override
  String get exModelName => 'モデル名';

  @override
  String get exNoMessage => 'メッセージなし';

  @override
  String get exNoRecentFiles => '最近使用したファイルはありません';

  @override
  String exNotAValidUrl(String url) {
    return '有効な URL ではありません:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR で $count 件のテキストスパンを追加しました - ページのテキストを選択できるようになりました',
      one: 'OCR で 1 件のテキストスパンを追加しました - ページのテキストを選択できるようになりました',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      '自分でホストするビジョン言語 OCR モデル（vLLM 上の dots.ocr、または OpenAI 互換の任意の OCR エンドポイント）を使用して、スキャンしたページに選択・検索可能なテキストレイヤーを追加します。';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR に失敗しました: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => '開く';

  @override
  String get exOpenDocumentBeforeOcr => 'OCR を実行する前にドキュメントを開いてください';

  @override
  String get exOpenDocumentFirst => '先にドキュメントを開いてください';

  @override
  String get exOpenFromUrl => 'URL から開く…';

  @override
  String get exOpenFromUrlTitle => 'URL から開く';

  @override
  String get exOpenInNewTab => 'PDF を新しいタブで開く';

  @override
  String get exOpenInteractiveDemo => 'インタラクティブデモを開く';

  @override
  String get exOpenPdf => 'PDF を開く…';

  @override
  String get exOpenPdfButton => 'PDF を開く';

  @override
  String get exOpenRecent => '最近使用したファイルを開く';

  @override
  String get exOpenUrlDescription =>
      'PdfHttpByteSource を介して HTTP Range リクエストで PDF をストリーミングし、パーサーが必要とする部分のみを取得します。サーバーが範囲リクエストに対応していない場合は、全体のダウンロードにフォールバックします。';

  @override
  String get exOpeningDocument => 'ドキュメントを開いています';

  @override
  String get exOpeningPdf => 'PDF を開いています…';

  @override
  String exOpeningTitle(String title) {
    return '$title を開いています…';
  }

  @override
  String get exPdfUrlLabel => 'PDF の URL';

  @override
  String get exPerformanceAuto => 'パフォーマンス: 自動';

  @override
  String get exPreparing => '準備中…';

  @override
  String get exPubDevMenuItem => 'pub.dev の dart_pdf_editor';

  @override
  String exRecognisingPage(int current, int count) {
    return 'ページ $current / $count を認識中…';
  }

  @override
  String get exResolution => '解像度';

  @override
  String get exRunOcr => 'OCR を実行';

  @override
  String get exSaveAs => '名前を付けて保存…';

  @override
  String exSaveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name を保存しました';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name を保存しました - ⌘V で PDF に貼り戻せます';
  }

  @override
  String exSavedTo(String path) {
    return '$path に保存しました';
  }

  @override
  String get exScrollIndicatorDemo => 'スクロールインジケーター API デモ';

  @override
  String get exServiceEndpoint => 'サービスエンドポイント';

  @override
  String get exShow => '表示';

  @override
  String get exSingleWorker => '単一ワーカー';

  @override
  String get exSupplyFeedback => 'フィードバックを送る…';

  @override
  String get exSwitchToEdit => '編集モードに切り替え';

  @override
  String get exSwitchToReadOnly => '読み取り専用に切り替え';

  @override
  String get exThemeDark => 'テーマ: ダーク - システムに切り替え';

  @override
  String get exThemeLight => 'テーマ: ライト - ダークに切り替え';

  @override
  String get exThemeSystem => 'テーマ: システム - ライトに切り替え';

  @override
  String get exTryDemo => 'インタラクティブデモを試す';

  @override
  String get exUntitled => '無題';

  @override
  String get exVerticalLayout => '垂直ページレイアウト';

  @override
  String get exViewSource => 'GitHub でソースを表示';

  @override
  String get exWorkerAuto => '自動';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'パフォーマンス: $count ワーカー',
      one: 'パフォーマンス: 単一ワーカー',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count ワーカー';
  }

  @override
  String get feedbackAttachDiagnostics => 'これらの診断情報をレポートに添付する';

  @override
  String get feedbackClearLog => 'ログをクリア';

  @override
  String get feedbackCopyDiagnostics => '診断情報をコピー';

  @override
  String get feedbackDiagnosticsNotice =>
      'フィードバックフォームはブラウザで開きます。以下の診断情報はこのデバイス上でのみ収集され、問題の再現に役立てるために添付されます。まず内容を確認し、非公開にしておきたいものは含めないでください。';

  @override
  String get feedbackOpenForm => 'フィードバックフォームを開く';

  @override
  String get feedbackTitle => 'フィードバックを送信';

  @override
  String get none => 'なし';

  @override
  String get ok => 'OK';

  @override
  String get paste => '貼り付け';

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
  String get scrollDemoNextPage => '次のページ';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'ページ $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => '前のページ';

  @override
  String get scrollDemoSwitchHorizontal => '水平レイアウトに切り替え';

  @override
  String get scrollDemoSwitchVertical => '垂直レイアウトに切り替え';

  @override
  String get scrollDemoTitle => 'スクロールインジケーター API';

  @override
  String get undo => '元に戻す';

  @override
  String get exFileTypePdf => 'PDF ドキュメント';

  @override
  String get exFileTypeImages => '画像';

  @override
  String get exFileTypeFonts => 'フォント';

  @override
  String exExtractedTitle(String title, int part) {
    return '$title - パート$part.pdf';
  }
}
