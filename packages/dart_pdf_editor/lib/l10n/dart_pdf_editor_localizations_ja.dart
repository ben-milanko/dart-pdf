// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class DartPdfEditorLocalizationsJa extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get add => '追加';

  @override
  String get annotCaret => 'カレット';

  @override
  String get annotCircle => '円';

  @override
  String get annotFileAttachment => 'ファイル添付';

  @override
  String get annotFreeText => 'テキストボックス';

  @override
  String get annotHighlight => 'ハイライト';

  @override
  String get annotInk => '手書き';

  @override
  String get annotLine => '直線';

  @override
  String get annotLink => 'リンク';

  @override
  String get annotPolygon => '多角形';

  @override
  String get annotPolyline => '折れ線';

  @override
  String get annotRedact => '墨消し';

  @override
  String get annotSquare => '四角形';

  @override
  String get annotSquiggly => '波線';

  @override
  String get annotStamp => 'スタンプ';

  @override
  String get annotStrikeOut => '取り消し線';

  @override
  String get annotText => 'ノート';

  @override
  String get annotUnderline => '下線';

  @override
  String get annotWidget => 'フォームフィールド';

  @override
  String get apply => '適用';

  @override
  String get bookmarkAdd => 'ブックマークを追加';

  @override
  String get bookmarkAddChild => '子ブックマークを追加';

  @override
  String get bookmarkCollapse => '折りたたむ';

  @override
  String get bookmarkDelete => 'ブックマークを削除';

  @override
  String get bookmarkEdit => 'ブックマークを編集';

  @override
  String get bookmarkEmpty => 'ブックマークがありません';

  @override
  String get bookmarkExpand => '展開';

  @override
  String get bookmarkExpandedByDefault => 'デフォルトで展開';

  @override
  String get bookmarkNoDestination => '移動先なし';

  @override
  String get bookmarkPageFieldLabel => 'ページ';

  @override
  String bookmarkPageLabel(int number) {
    return '$number ページ';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'ブックマーク';

  @override
  String get bookmarkTitleLabel => 'タイトル';

  @override
  String get bookmarkUntitled => '無題';

  @override
  String get cancel => 'キャンセル';

  @override
  String get clear => 'クリア';

  @override
  String get close => '閉じる';

  @override
  String get colorApplyingChanges => '色の変更を適用しています…';

  @override
  String get colorColorFormat => 'カラー形式';

  @override
  String get colorColorTitle => 'カラー';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 色を選択中',
      one: '$count 色を選択中',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'ドキュメントの色';

  @override
  String get colorFillColors => '塗りの色';

  @override
  String get colorFind => '検索';

  @override
  String get colorInDocument => 'ドキュメント内';

  @override
  String get colorNoColorsFound => 'まだ色が見つかりません';

  @override
  String get colorNoPageContentColors => 'ページコンテンツの色が見つかりません';

  @override
  String get colorPalette => 'パレット';

  @override
  String get colorPickColor => '色を選択';

  @override
  String get colorProcessingTitle => '色の処理';

  @override
  String get colorRecent => '最近使用';

  @override
  String get colorReplace => '置換';

  @override
  String get colorReplaceWithTransparent => '透明に置換';

  @override
  String get colorScanning => 'スキャン中…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'スキャン中 $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return '選択したページ ($count)';
  }

  @override
  String get colorStrokeColors => '線の色';

  @override
  String get colorTolerance => '許容差';

  @override
  String get colorTransparent => '透明';

  @override
  String get colorWholeDocument => 'ドキュメント全体';

  @override
  String get compareAfter => '変更後';

  @override
  String get compareBefore => '変更前';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の変更',
      one: '1 件の変更',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の変更',
      one: '1 件の変更',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(空)';

  @override
  String get compareNextChange => '次の変更';

  @override
  String get compareNoChanges => '変更なし';

  @override
  String get compareNoDifferences => '2 つのドキュメントに違いはありません';

  @override
  String get compareOverlay => 'オーバーレイ';

  @override
  String comparePageHeader(int page) {
    return '$page ページ';
  }

  @override
  String get comparePreviousChange => '前の変更';

  @override
  String get compareSideBySide => '並べて表示';

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
  String get editorViewAuthorNameTitle => '作成者名';

  @override
  String get lineStyleDashDot => '一点鎖線';

  @override
  String get lineStyleDashed => '破線';

  @override
  String get lineStyleDotted => '点線';

  @override
  String get lineStyleSolid => '実線';

  @override
  String get measCalibrate => '校正';

  @override
  String get measCalibrateScale => 'スケールを校正';

  @override
  String get measDepthLabel => '深さ: ';

  @override
  String get measKindAngle => '角度';

  @override
  String get measKindArc => '弧の長さ';

  @override
  String get measKindArea => '面積';

  @override
  String get measKindCount => 'カウント';

  @override
  String get measKindLength => '長さ';

  @override
  String get measKindNetArea => '正味面積';

  @override
  String get measKindPerimeter => '周囲長';

  @override
  String get measKindSlope => '勾配';

  @override
  String get measKindVolume => '体積';

  @override
  String get measLineRepresents => '描いた線が表す長さ:';

  @override
  String get measMeasure => '計測';

  @override
  String get measSetScale => '計測スケールを設定';

  @override
  String get measSetScaleButton => 'スケールを設定';

  @override
  String get measVolumeDepth => '体積の深さ';

  @override
  String get menuAddNode => '頂点を追加';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '注釈をページに適用',
      one: '注釈をページに適用',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'ページに適用…';

  @override
  String get menuBringToFront => '最前面へ移動';

  @override
  String get menuCheck => 'チェック';

  @override
  String get menuChooseValue => '値を選択…';

  @override
  String get menuClearCheck => 'チェックを解除';

  @override
  String get menuConvertToCheckBox => 'チェックボックスに変換';

  @override
  String get menuConvertToImageButton => '画像ボタンに変換';

  @override
  String get menuConvertToTextField => 'テキストフィールドに変換';

  @override
  String get menuDeleteField => 'フィールドを削除';

  @override
  String get menuEditValue => '値を編集…';

  @override
  String get menuFieldName => 'フィールド名';

  @override
  String get menuFieldValue => 'フィールドの値';

  @override
  String get menuFlattenForm => 'フォームを統合';

  @override
  String get menuLock => 'ロック';

  @override
  String get menuUnlock => 'ロック解除';

  @override
  String get menuRecolour => '色を変更…';

  @override
  String get menuRemoveNode => '頂点を削除';

  @override
  String get menuSetAsDefaultStyle => 'デフォルトのスタイルに設定';

  @override
  String get menuRename => '名前を変更…';

  @override
  String get menuSelectOption => 'オプションを選択';

  @override
  String get menuSendToBack => '最背面へ移動';

  @override
  String get menuSetImage => '画像を設定…';

  @override
  String get menuTextStyle => 'テキストスタイル…';

  @override
  String get none => 'なし';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'カラー';

  @override
  String get overlayEditText => 'テキストを編集';

  @override
  String get overlayFont => 'フォント';

  @override
  String get overlayLarger => '大きく';

  @override
  String get overlayMore => 'その他';

  @override
  String get overlayNote => 'ノート';

  @override
  String get overlaySmaller => '小さく';

  @override
  String get overlayStampText => 'スタンプのテキスト';

  @override
  String get linkDialogTitle => 'リンクを追加';

  @override
  String get linkKindWeb => 'ウェブアドレス';

  @override
  String get linkKindPage => 'ドキュメント内のページ';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'ページ番号';

  @override
  String get toolLink => 'リンク';

  @override
  String get overlayUnderline => '下線';

  @override
  String pageRangeErrorBounds(int count) {
    return '1 から $count までのページを入力してください。';
  }

  @override
  String get pageRangeErrorOrder => '最終ページは最初のページより前にできません。';

  @override
  String get pageRangeFrom => '開始';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページ',
      one: '1 ページ',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => '終了';

  @override
  String get panelDragToMovePanel => 'ドラッグしてパネルを移動';

  @override
  String get paste => '貼り付け';

  @override
  String get propAlign => '配置';

  @override
  String get propAlignCenter => '中央揃え';

  @override
  String get propAlignLeft => '左揃え';

  @override
  String get propAlignRight => '右揃え';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の注釈',
      one: '$count 件の注釈',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => '作成者';

  @override
  String get propAutoSize => '自動サイズ';

  @override
  String get propBold => '太字';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => '同梱フォント';

  @override
  String get propCallout => '引き出し';

  @override
  String get propCharSpacing => '文字間隔';

  @override
  String get propColor => 'カラー';

  @override
  String get propColour => 'カラー';

  @override
  String get propContents => '内容';

  @override
  String get propCornerRadius => '角の丸み';

  @override
  String get propEditsApplyToAll => '編集はすべての互換注釈に適用されます';

  @override
  String get propFieldName => 'フィールド名';

  @override
  String get propFieldTypeCheckBox => 'チェックボックス';

  @override
  String get propFieldTypeComboBox => 'コンボボックス';

  @override
  String get propFieldTypeImageButton => '画像ボタン';

  @override
  String get propFieldTypeListBox => 'リストボックス';

  @override
  String get propFieldTypeRadioGroup => 'ラジオグループ';

  @override
  String get propFieldTypeSignature => '署名';

  @override
  String get propFieldTypeText => 'テキストフィールド';

  @override
  String propFieldTypeTooltip(String type) {
    return 'フィールドの種類: $type';
  }

  @override
  String get propFieldTypeUnknown => '不明なフィールド';

  @override
  String get propFill => '塗り';

  @override
  String get propFont => 'フォント';

  @override
  String get propFontSubsetTooltip =>
      'このフォントはサブセット化されています。ドキュメントで既に使用されている文字のみ入力できます。';

  @override
  String get propFontWidth => 'フォント幅';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => '斜体';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => '文字が限定されています';

  @override
  String get propLineEnd => '線の終端';

  @override
  String get propLineEndingButt => 'バット';

  @override
  String get propLineEndingCircle => '円';

  @override
  String get propLineEndingClosedArrow => '閉じた矢印';

  @override
  String get propLineEndingClosedArrowRev => '閉じた矢印（逆）';

  @override
  String get propLineEndingDiamond => 'ひし形';

  @override
  String get propLineEndingOpenArrow => '開いた矢印';

  @override
  String get propLineEndingOpenArrowRev => '開いた矢印（逆）';

  @override
  String get propLineEndingSlash => 'スラッシュ';

  @override
  String get propLineEndingSquare => '四角形';

  @override
  String get propLineSpacing => '行間';

  @override
  String get propLineStart => '線の始端';

  @override
  String get propLineType => '線の種類';

  @override
  String get propLoadFont => 'フォントを読み込む…';

  @override
  String get propLoadFontSubtitle => 'TTF または OTF ファイル';

  @override
  String get propMoreColors => 'その他の色…';

  @override
  String get propMultiline => '複数行';

  @override
  String get propNoFill => '塗りなし';

  @override
  String get propNoFontsFound => 'フォントが見つかりません';

  @override
  String get propNoOutline => 'アウトラインなし';

  @override
  String get propOpacity => '不透明度';

  @override
  String get propOutline => 'アウトライン';

  @override
  String get propPageLabel => 'ページ';

  @override
  String propPageNumber(int number) {
    return '$number ページ';
  }

  @override
  String get propPropertiesTitle => 'プロパティ';

  @override
  String get propRecentlyUsed => '最近使用';

  @override
  String get propScale => '倍率';

  @override
  String get propSearchFonts => 'フォントを検索';

  @override
  String get propSectionAllFonts => 'すべてのフォント';

  @override
  String get propSectionAppearance => '外観';

  @override
  String get propSectionContent => '内容';

  @override
  String get propSectionFormField => 'フォームフィールド';

  @override
  String get propSectionInThisDocument => 'このドキュメント内';

  @override
  String get propSectionPositionSize => '位置とサイズ (pt)';

  @override
  String get propSectionSelection => '選択';

  @override
  String get propSectionText => 'テキスト';

  @override
  String get propSelectAnnotationPrompt => '注釈を選択するとプロパティが表示されます';

  @override
  String get propSize => 'サイズ';

  @override
  String get propStandardPdfFont => '標準 PDF フォント';

  @override
  String get propStroke => '線の太さ';

  @override
  String get propStyle => 'スタイル';

  @override
  String get propSystemFont => 'システムフォント';

  @override
  String get propType => '種類';

  @override
  String get propUnderline => '下線';

  @override
  String get propVaries => '複数の値';

  @override
  String get redo => 'やり直し';

  @override
  String get reflowNoContent => '抽出できるコンテンツがありません';

  @override
  String reflowPageLabel(int number) {
    return '$number ページ';
  }

  @override
  String get reflowSaveOrShare => '保存または共有';

  @override
  String get reflowViewFigure => '図を表示';

  @override
  String get remove => '削除';

  @override
  String get rename => '名前を変更';

  @override
  String get reset => 'リセット';

  @override
  String get save => '保存';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return '$page ページ';
  }

  @override
  String get sbarCallout => '引き出し';

  @override
  String get sbarFieldButton => 'ボタンフィールド';

  @override
  String get sbarFieldChoice => '選択フィールド';

  @override
  String get sbarFieldGeneric => 'フォームフィールド';

  @override
  String get sbarFieldSignature => '署名フィールド';

  @override
  String get sbarFieldText => 'テキストフィールド';

  @override
  String get sbarStateAccepted => '承認済み';

  @override
  String get sbarStateCancelled => '取り消し済み';

  @override
  String get sbarStateMarked => 'マーク済み';

  @override
  String get sbarStateRejected => '却下済み';

  @override
  String get sbarStateResolved => '解決済み';

  @override
  String get sbarStateUnmarked => 'マーク解除済み';

  @override
  String get searchAnnotations => '注釈を検索';

  @override
  String get searchClearSearch => '検索をクリア';

  @override
  String get searchEmptyHint => 'ドキュメントを検索すると、すべての一致がここに表示されます';

  @override
  String get searchMatchCase => '大文字と小文字を区別';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の一致',
      one: '1 件の一致',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => '次の一致';

  @override
  String searchNoMatches(String query) {
    return '「$query」に一致するものがありません';
  }

  @override
  String searchPageHeader(int page) {
    return '$page ページ';
  }

  @override
  String get searchPreviousMatch => '前の一致';

  @override
  String get searchRegex => '正規表現';

  @override
  String get searchResultsTitle => '検索結果';

  @override
  String get searchWholeWord => '単語単位';

  @override
  String get shellControls => 'コントロール';

  @override
  String get shellDefaultAuthor => 'デフォルトの作成者…';

  @override
  String get shellHighlightFormFields => 'フォームフィールドを強調表示';

  @override
  String get shellKeyboardShortcutsMenu => 'キーボードショートカット…';

  @override
  String get shellKeyboardShortcutsTitle => 'キーボードショートカット';

  @override
  String get shellShortcutsSearchHint => 'ショートカットを検索';

  @override
  String shellShortcutsNoMatches(String query) {
    return '「$query」に一致するショートカットがありません';
  }

  @override
  String get shellShortcutGroupSelect => '選択';

  @override
  String get shellShortcutGroupMarkup => 'マークアップ';

  @override
  String get shellShortcutGroupDraw => '描画';

  @override
  String get shellShortcutGroupShapes => '図形';

  @override
  String get shellShortcutGroupInsert => '挿入';

  @override
  String get shellShortcutGroupMeasure => '計測';

  @override
  String get shellShortcutGroupEdit => '編集';

  @override
  String get shellNotSet => '未設定';

  @override
  String get shellPageColor => 'ページの色…';

  @override
  String get shellPageGrid => 'ページグリッド';

  @override
  String get shellPanelAnnotations => '注釈';

  @override
  String get shellPanelBookmarks => 'ブックマーク';

  @override
  String get shellPanelPages => 'ページ';

  @override
  String get shellPanelProperties => 'プロパティ';

  @override
  String get shellPanelSearchResults => '検索結果';

  @override
  String get shellPanels => 'パネル';

  @override
  String get shellPressAKey => 'キーを押してください';

  @override
  String get shellPressLetterKeyHint => '文字キーを押すか、Delete でクリアします。';

  @override
  String get shellReflow => 'リフロー';

  @override
  String get shellReflowText => 'テキストをリフロー';

  @override
  String get shellResetZoom => 'ズームをリセット';

  @override
  String get shellSectionShell => 'シェル';

  @override
  String get shellSectionView => '表示';

  @override
  String get shellSettings => '設定';

  @override
  String get shellShowAnnotations => '注釈を表示';

  @override
  String get shellTabHere => 'ここにタブ';

  @override
  String get shellUnbound => '未割り当て';

  @override
  String get shellZoom => 'ズーム';

  @override
  String sidebarByAuthor(String author) {
    return '$author';
  }

  @override
  String get sidebarCancelSelection => '選択をキャンセル';

  @override
  String get sidebarClearSearch => '検索をクリア';

  @override
  String get sidebarDeleteSelected => '選択項目を削除';

  @override
  String get sidebarDeleteSignature => '署名を削除';

  @override
  String get sidebarLockAnnotation => 'ロック';

  @override
  String get sidebarUnlockAnnotation => 'ロック解除';

  @override
  String get sidebarMore => 'その他';

  @override
  String get sidebarNoAnnotations => '注釈がありません';

  @override
  String get sidebarNoMatchingAnnotations => '一致する注釈がありません';

  @override
  String sidebarPageHeader(int number) {
    return '$number ページ';
  }

  @override
  String get sidebarRemoveSignatureBody => 'ドキュメントからデジタル署名を削除します。この操作は元に戻せます。';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return '「$name」によるデジタル署名をドキュメントから削除します。この操作は元に戻せます。';
  }

  @override
  String get sidebarRemoveSignatureTitle => '署名を削除しますか?';

  @override
  String get sidebarReopen => '再開';

  @override
  String get sidebarReply => '返信';

  @override
  String get sidebarResolve => '解決';

  @override
  String get sidebarSearchHint => '注釈を検索';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件選択中',
      one: '$count 件選択中',
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
  String get sidebarWriteReplyHint => '返信を入力…';

  @override
  String get sigTitle => '署名';

  @override
  String get signIdCreate => '作成';

  @override
  String get signIdEmail => 'メール（任意）';

  @override
  String get signIdName => '名前';

  @override
  String get signIdNameHint => '署名に表示される名前';

  @override
  String get signIdNameRequired => '名前を入力してください';

  @override
  String get signIdOrganization => '組織（任意）';

  @override
  String get signIdSelfSignedInfo =>
      '自己署名 ID を作成します。Adobe Acrobat やその他のリーダーでは、署名は「署名済み、有効性不明」と表示されます。これは各リーダー独自の自己署名 ID と同じです。緑のチェックマークには、有料で公的に信頼された CA が必要です。';

  @override
  String get signIdTitle => '署名 ID を作成';

  @override
  String get stampBox => '四角形';

  @override
  String get stampCircle => '円';

  @override
  String get stampCustomCaption => 'カスタムスタンプ';

  @override
  String get stampDateFormat => '日付形式';

  @override
  String get stampDeleteComponent => '選択したコンポーネントを削除';

  @override
  String get stampDeleteStamp => 'スタンプを削除';

  @override
  String get stampEditStamp => 'スタンプを編集';

  @override
  String get stampExport => 'エクスポート…';

  @override
  String get stampFieldDate => '日付';

  @override
  String get stampFieldDateTime => '日付と時刻';

  @override
  String get stampFieldTime => '時刻';

  @override
  String get stampFieldUsername => 'ユーザー名';

  @override
  String get stampFont => 'フォント';

  @override
  String get stampFontBold => '太字';

  @override
  String get stampFontItalic => '斜体';

  @override
  String get stampHeight => '高さ';

  @override
  String get stampImage => '画像';

  @override
  String get stampImport => 'インポート…';

  @override
  String get stampInsertField => 'フィールドを挿入';

  @override
  String get stampMoreColors => 'その他の色…';

  @override
  String get stampNewStamp => '新規スタンプ…';

  @override
  String get stampNewStampTitle => '新規スタンプ';

  @override
  String get stampSelectTextToEdit => '編集するテキストを選択';

  @override
  String get stampSelectedText => '選択したテキスト';

  @override
  String get stampSignature => '署名';

  @override
  String get stampStamps => 'スタンプ';

  @override
  String get stampText => 'テキスト';

  @override
  String get stampTime12Hour => '12 時間';

  @override
  String get stampTime24Hour => '24 時間';

  @override
  String get stampTimeFormat => '時刻形式';

  @override
  String get stampWidth => '幅';

  @override
  String get takeoffArea => '面積';

  @override
  String get takeoffCount => 'カウント';

  @override
  String get takeoffEmpty => 'まだ計測がありません。';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count グループ',
      one: '$count グループ',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 項目',
      one: '$count 項目',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => '長さ';

  @override
  String get takeoffTitle => 'テイクオフ';

  @override
  String get tbAddInkAnnotation => '手書き注釈を追加';

  @override
  String get tbAlign => '配置';

  @override
  String get tbAlignBottom => '下揃え';

  @override
  String get tbAlignHorizontalCenters => '左右中央揃え';

  @override
  String get tbAlignLeft => '左揃え';

  @override
  String get tbAlignRight => '右揃え';

  @override
  String get tbAlignTop => '上揃え';

  @override
  String get tbAlignVerticalCenters => '上下中央揃え';

  @override
  String get tbAnnotationsFlattened => '注釈をページに統合しました';

  @override
  String get tbApplyRedactionsMessage =>
      'マークしたコンテンツはドキュメントから完全に削除されます。この操作は元に戻せません。';

  @override
  String get tbApplyRedactionsTitle => '墨消しを適用しますか?';

  @override
  String get tbApplyRedactionsTooltip => '墨消しを適用（元に戻せません）';

  @override
  String get tbAutosizeTextBox => 'テキストボックスを自動サイズ (Alt+Z)';

  @override
  String get tbCalibrateScaleHint => '既知の長さの線を描いてスケールを校正します。';

  @override
  String get tbCharSpacing => '文字間隔';

  @override
  String get tbCheckBoxOption => 'チェックボックス';

  @override
  String get tbCheckMarksOnDocument => 'ドキュメント上のチェックマーク';

  @override
  String get tbCropImage => '画像をトリミング';

  @override
  String get tbCroppingImage => '画像をトリミング中';

  @override
  String get tbCropApply => 'トリミングを適用';

  @override
  String get tbCropCancel => 'トリミングをキャンセル';

  @override
  String get tbCropReset => 'トリミングをリセット';

  @override
  String get tbColorLabel => 'カラー';

  @override
  String get tbColorProcessingTooltip => '色の処理 - ページコンテンツの色を検索して置換';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 色を置換しました',
      one: '1 色を置換しました',
      zero: '一致する色が見つかりません',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'チェックボックスに変換';

  @override
  String get tbConvertToImageButton => '画像ボタンに変換';

  @override
  String get tbConvertToTextField => 'テキストフィールドに変換';

  @override
  String get tbCornerRadius => '角の丸み';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の注釈を削除',
      one: '注釈を削除',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => '要素を削除';

  @override
  String get tbDeleteField => 'フィールドを削除';

  @override
  String get tbDiscardDrawing => '描画を破棄';

  @override
  String get tbDistributeHorizontally => '左右に均等配置';

  @override
  String get tbDistributeVertically => '上下に均等配置';

  @override
  String get tbDrawNewSignature => '新しい署名を描く…';

  @override
  String get tbEditAnnotationText => '注釈のテキストを編集';

  @override
  String get tbEditTextStyle => 'テキストとスタイルを編集';

  @override
  String get tbElement => '要素';

  @override
  String get tbEraserSize => '消しゴムのサイズ';

  @override
  String get tbFieldActions => 'フィールドの操作';

  @override
  String get tbFieldName => 'フィールド名';

  @override
  String tbFieldNamed(String name) {
    return 'フィールド: $name';
  }

  @override
  String get tbFieldValue => 'フィールドの値';

  @override
  String get tbFill => '塗り';

  @override
  String get tbFingerDraws => '指で描画中 - タップするとスクロールに切り替わります';

  @override
  String get tbFingerScrolls => '指でスクロール（ペンで描画） - タップすると描画に切り替わります';

  @override
  String get tbFlattenAnnotationsTooltip => '注釈をページに統合';

  @override
  String get tbFlattenForm => 'フォームを統合';

  @override
  String get tbFlattenFormBakeValues => 'フォームを統合 - 値をページに固定';

  @override
  String get tbFlattenLabel => '統合';

  @override
  String get tbFont => 'フォント';

  @override
  String get tbFontSize => 'フォントサイズ';

  @override
  String get tbFontWidth => 'フォント幅';

  @override
  String get tbFormFieldsFlattened => 'フォームフィールドをページに統合しました';

  @override
  String get tbGroupDraw => '描画';

  @override
  String get tbGroupEdit => '編集';

  @override
  String get tbGroupInsert => '挿入';

  @override
  String get tbGroupMarkup => 'マークアップ';

  @override
  String get tbGroupMeasure => '計測';

  @override
  String get tbGroupSelect => '選択';

  @override
  String get tbGroupShapes => '図形';

  @override
  String get tbImageButtonOption => '画像ボタン';

  @override
  String get tbLineEnd => '線の終端';

  @override
  String get tbLineSpacing => '行間';

  @override
  String get tbLineStart => '線の始端';

  @override
  String get tbLineType => '線の種類';

  @override
  String get tbManageStamps => 'スタンプを管理…';

  @override
  String get tbMarkupHighlight => 'ハイライト';

  @override
  String get tbMarkupHighlightTip => '選択範囲をハイライト';

  @override
  String get tbMarkupSquiggly => '波線下線';

  @override
  String get tbMarkupSquigglyTip => '選択範囲に波線下線';

  @override
  String get tbMarkupStrikeOut => '取り消し線';

  @override
  String get tbMarkupStrikeOutTip => '選択範囲に取り消し線';

  @override
  String get tbMarkupUnderline => '下線';

  @override
  String get tbMarkupUnderlineTip => '選択範囲に下線';

  @override
  String get tbMoreColors => 'その他の色…';

  @override
  String get tbNameArrow => '矢印';

  @override
  String get tbNameCallout => '引き出し';

  @override
  String get tbNameCloudPolygon => '雲形多角形';

  @override
  String get tbNameCount => 'カウント';

  @override
  String get tbNameDigitalSignature => 'デジタル署名';

  @override
  String get tbNameDraw => '描画';

  @override
  String get tbNameEllipse => '楕円';

  @override
  String get tbNameEraser => '手書きストロークを消去';

  @override
  String get tbNameHighlight => 'ハイライト';

  @override
  String get tbNameImage => '画像';

  @override
  String get tbNameLine => '直線';

  @override
  String get tbNameMeasureAngle => '角度を計測';

  @override
  String get tbNameMeasureArc => '弧の長さを計測';

  @override
  String get tbNameMeasureArea => '面積を計測';

  @override
  String get tbNameMeasureDistance => '距離を計測';

  @override
  String get tbNameMeasurePerimeter => '周囲長を計測';

  @override
  String get tbNameMeasureSlope => '勾配を計測（高さ/水平距離）';

  @override
  String get tbNameMeasureVolume => '体積を計測（面積 × 深さ）';

  @override
  String get tbNameNote => 'ノート';

  @override
  String get tbNamePolygon => '多角形';

  @override
  String get tbNamePolyline => '折れ線';

  @override
  String get tbNameRectangle => '四角形';

  @override
  String get tbNameSelect => '選択';

  @override
  String get tbNameSignature => '署名';

  @override
  String get tbNameStamp => 'スタンプ';

  @override
  String get tbNameTextBox => 'テキストボックス';

  @override
  String get tbNewFieldType => '新しいフィールドの種類 - ページ上でドラッグして追加';

  @override
  String get tbNoAnnotationsToFlatten => '統合する注釈がありません';

  @override
  String get tbNoCustomStamps => 'カスタムスタンプがありません';

  @override
  String get tbNoFormFieldsToFlatten => '統合するフォームフィールドがありません';

  @override
  String get tbNoRedactionsToApply => '適用する墨消しがありません';

  @override
  String get tbNoteTitle => 'ノート';

  @override
  String get tbOpacity => '不透明度';

  @override
  String get tbOutline => 'アウトライン';

  @override
  String get tbPatternScale => 'パターンの倍率';

  @override
  String get tbPickColorFromPage => 'ページから色を選択';

  @override
  String get tbRedactionsApplied => '墨消しを適用しました';

  @override
  String get tbRedoShortcut => 'やり直し (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'リフローできませんでした - このツールで再折り返しできる単一段組の段落ではありません。代わりにテキストの置換をお試しください。';

  @override
  String get tbReflowParagraph => '段落をリフロー';

  @override
  String get tbRenameField => 'フィールド名を変更';

  @override
  String get tbRenameFieldEllipsis => 'フィールド名を変更…';

  @override
  String get tbReplaceImage => '画像を置換';

  @override
  String get tbReplaceImageFailed => '画像を置換できませんでした';

  @override
  String get tbReplaceText => 'テキストを置換';

  @override
  String get tbSaveImage => '画像を保存';

  @override
  String get tbSaveShortcut => '保存… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'スケール';

  @override
  String get tbSelectTextForMarkup => 'マークアップするテキストを選択';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件選択中',
      one: '選択',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => '設定…';

  @override
  String get tbStamp => 'スタンプ';

  @override
  String get tbStampText => 'スタンプのテキスト';

  @override
  String get tbStrokeOpacityFont => '線、不透明度、フォント';

  @override
  String get tbStrokeWidthLabel => '線の太さ';

  @override
  String tbStrokeWidthPreset(String width) {
    return '線 $width';
  }

  @override
  String get tbStyle => 'スタイル';

  @override
  String get tbTakeoffTotals => 'テイクオフの合計';

  @override
  String get tbTextBorder => 'テキストの枠線';

  @override
  String get tbTextColour => 'テキストの色';

  @override
  String get tbTextFieldOption => 'テキストフィールド';

  @override
  String get tbTextFill => 'テキストの塗り';

  @override
  String get tbTextStyleEllipsis => 'テキストスタイル…';

  @override
  String get tbTextTitle => 'テキスト';

  @override
  String get tbTipCallout => '引き出し - 起点からボックスの位置までドラッグ';

  @override
  String get tbTipContent => 'ページコンテンツを編集';

  @override
  String get tbTipCount => 'カウント - タップしてチェックマークを置き、集計します';

  @override
  String get tbTipDigitalSignature => 'デジタル署名 - ボックスをドラッグして配置し署名';

  @override
  String get tbTipForm => 'フォームフィールド - タップで選択、ダブルタップで入力、ドラッグで追加';

  @override
  String get tbTipHighlightDraw => 'ハイライト - フリーハンドで描画';

  @override
  String get tbTipImage => '画像 - タップして配置、またはボックスをドラッグ';

  @override
  String get tbTipMeasureAngle => '角度を計測 - 3 点をクリック';

  @override
  String get tbTipMeasureArc => '弧の長さを計測 - 3 点をクリック';

  @override
  String get tbTipRedact => '墨消し - 領域をドラッグして適用';

  @override
  String get tbTipSignature => '署名 - ページをタップして配置';

  @override
  String get tbTipSnapshot => 'スナップショット - 領域をドラッグしてキャプチャ（ベクターとして貼り付け可能）';

  @override
  String get tbToolContent => 'コンテンツ';

  @override
  String get tbToolForm => 'フォーム';

  @override
  String get tbToolRedact => '墨消し';

  @override
  String get tbToolSnapshot => 'スナップショット';

  @override
  String get tbTools => 'ツール';

  @override
  String get tbTotals => '合計';

  @override
  String get tbTypeTextEachTime => '毎回テキストを入力';

  @override
  String get tbUnderline => '下線';

  @override
  String get tbUndoShortcut => '元に戻す (⌘Z)';

  @override
  String get textStyleFont => 'フォント';

  @override
  String get textStyleFontSize => 'フォントサイズ';

  @override
  String get textStyleKeep => '維持';

  @override
  String get textStyleStyle => 'スタイル';

  @override
  String get textStyleText => 'テキスト';

  @override
  String get textStyleTextFill => 'テキストの塗り';

  @override
  String get textStyleTitle => 'テキストとスタイルを編集';

  @override
  String get thumbAddPage => 'ページを追加';

  @override
  String get thumbClearSelection => '選択をクリア';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページをコピー',
      one: 'ページをコピー',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => '選択したページをコピー';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページを切り取り',
      one: 'ページを切り取り',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => '選択したページを切り取り';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページを削除',
      one: 'ページを削除',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => '選択したページを削除';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページを複製',
      one: 'ページを複製',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'ページをエクスポート…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページをエクスポート…',
      one: 'ページをエクスポート…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => '選択したページをエクスポート';

  @override
  String get thumbInsertBlankAfter => '後に空白ページを挿入';

  @override
  String get thumbInsertBlankBefore => '前に空白ページを挿入';

  @override
  String get thumbInsertFileFailed => 'そのファイルを挿入できませんでした。';

  @override
  String get thumbInsertPdf => 'PDF を挿入…';

  @override
  String get thumbPageActions => 'ページの操作';

  @override
  String thumbPageNumber(int number) {
    return '$number ページ';
  }

  @override
  String get thumbPages => 'ページ';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ページを貼り付け',
      one: 'ページを貼り付け',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '180° 回転';

  @override
  String get thumbRotateLeft => '左に回転';

  @override
  String get thumbRotatePageRight => 'ページを右に回転';

  @override
  String get thumbRotateRight => '右に回転';

  @override
  String get thumbRotateSelectedLeft => '選択したページを左に回転';

  @override
  String get thumbRotateSelectedRight => '選択したページを右に回転';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件選択中',
      one: '$count 件選択中',
    );
    return '$_temp0';
  }

  @override
  String get undo => '元に戻す';

  @override
  String get viewerEditFontUnsafe => 'この PDF フォントまたはエンコーディングは安全に編集できません。';

  @override
  String get viewerEditNeedsSinglePage => '編集するには 1 ページ内で選択する必要があります。';

  @override
  String get viewerEditNotEditableRun =>
      'この選択は 1 つの編集可能なページコンテンツのテキストランではありません。';

  @override
  String get viewerEditStyleUnchangeable =>
      'この PDF フォントは再入力できますが、スタイルは変更できません。';

  @override
  String get viewerEditTextStyle => 'テキストとスタイルを編集';

  @override
  String get viewerMarkup => 'マークアップ';

  @override
  String get viewerMarkupHighlight => 'ハイライト';

  @override
  String get viewerMarkupSquiggly => '波線';

  @override
  String get viewerMarkupStrikeOut => '取り消し線';

  @override
  String get viewerMarkupUnderline => '下線';

  @override
  String get viewerSelectAll => 'すべて選択';
}
