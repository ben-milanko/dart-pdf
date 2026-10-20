// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class DartPdfPrintingLocalizationsJa extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get cancel => 'キャンセル';

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
  String get printPreviewUnavailable => 'プレビューを利用できません';

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

  @override
  String get printOptionsChoosePrinter => 'プリンターを選択';

  @override
  String get printOptionsNoPrinters =>
      'プリンターがインストールされていません。Windows の設定でプリンターを追加してから、再試行してください。';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return '保存されたプリンター「$printer」は利用できません。続行するにはプリンターを選択してください。';
  }

  @override
  String get printOptionsPrinterError =>
      'プリンターの設定を読み込めませんでした。プリンターの接続を確認して再試行してください。';

  @override
  String get printOptionsRetry => '再試行';

  @override
  String get printOptionsColor => 'カラー';

  @override
  String get printOptionsGrayscale => '白黒';

  @override
  String get printOptionsDuplex => '両面印刷';

  @override
  String get printOptionsSimplex => '片面';

  @override
  String get printOptionsLongEdge => '長辺とじ';

  @override
  String get printOptionsShortEdge => '短辺とじ';

  @override
  String get printOptionsTray => '給紙トレイ';

  @override
  String get printOptionsDefaultTray => 'プリンターの既定値';

  @override
  String get printOptionsProperties => 'プリンターのプロパティ…';

  @override
  String get printOptionsDirectPrinter => '「印刷」を押すと、選択したプリンターにこのジョブが直接送信されます。';

  @override
  String get printOptionsPropertiesError => 'プリンターのプロパティを開けませんでした。';

  @override
  String get printOptionsLoadingPrinters => 'プリンターを読み込み中…';
}
