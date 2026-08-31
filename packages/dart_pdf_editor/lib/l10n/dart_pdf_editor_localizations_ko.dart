// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class DartPdfEditorLocalizationsKo extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get add => '추가';

  @override
  String get annotCaret => '캐럿';

  @override
  String get annotCircle => '원';

  @override
  String get annotFileAttachment => '파일 첨부';

  @override
  String get annotFreeText => '텍스트 상자';

  @override
  String get annotHighlight => '형광펜';

  @override
  String get annotInk => '잉크';

  @override
  String get annotLine => '선';

  @override
  String get annotLink => '링크';

  @override
  String get annotPolygon => '다각형';

  @override
  String get annotPolyline => '폴리라인';

  @override
  String get annotRedact => '교정';

  @override
  String get annotSquare => '사각형';

  @override
  String get annotSquiggly => '물결 밑줄';

  @override
  String get annotStamp => '스탬프';

  @override
  String get annotStrikeOut => '취소선';

  @override
  String get annotText => '메모';

  @override
  String get annotUnderline => '밑줄';

  @override
  String get annotWidget => '양식 필드';

  @override
  String get apply => '적용';

  @override
  String get bookmarkAdd => '책갈피 추가';

  @override
  String get bookmarkAddChild => '하위 책갈피 추가';

  @override
  String get bookmarkCollapse => '접기';

  @override
  String get bookmarkDelete => '책갈피 삭제';

  @override
  String get bookmarkEdit => '책갈피 편집';

  @override
  String get bookmarkEmpty => '책갈피 없음';

  @override
  String get bookmarkExpand => '펼치기';

  @override
  String get bookmarkExpandedByDefault => '기본적으로 펼침';

  @override
  String get bookmarkNoDestination => '대상 없음';

  @override
  String get bookmarkPageFieldLabel => '페이지';

  @override
  String bookmarkPageLabel(int number) {
    return '$number페이지';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => '책갈피';

  @override
  String get bookmarkTitleLabel => '제목';

  @override
  String get bookmarkUntitled => '제목 없음';

  @override
  String get cancel => '취소';

  @override
  String get clear => '지우기';

  @override
  String get close => '닫기';

  @override
  String get colorApplyingChanges => '색상 변경 사항 적용 중…';

  @override
  String get colorColorFormat => '색상 형식';

  @override
  String get colorColorTitle => '색상';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '색상 $count개 선택됨',
      one: '색상 $count개 선택됨',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => '문서 색상';

  @override
  String get colorFillColors => '채우기 색상';

  @override
  String get colorFind => '찾기';

  @override
  String get colorInDocument => '문서 내';

  @override
  String get colorNoColorsFound => '아직 발견된 색상 없음';

  @override
  String get colorNoPageContentColors => '페이지 콘텐츠 색상을 찾을 수 없음';

  @override
  String get colorPalette => '팔레트';

  @override
  String get colorPickColor => '색상 선택';

  @override
  String get colorProcessingTitle => '색상 처리';

  @override
  String get colorRecent => '최근';

  @override
  String get colorReplace => '바꾸기';

  @override
  String get colorReplaceWithTransparent => '투명으로 바꾸기';

  @override
  String get colorScanning => '스캔 중…';

  @override
  String colorScanningProgress(int progress, int total) {
    return '스캔 중 $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return '선택한 페이지 ($count)';
  }

  @override
  String get colorStrokeColors => '선 색상';

  @override
  String get colorTolerance => '허용 오차';

  @override
  String get colorTransparent => '투명';

  @override
  String get colorWholeDocument => '문서 전체';

  @override
  String get compareAfter => '이후';

  @override
  String get compareBefore => '이전';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '변경 $count개',
      one: '변경 1개',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '변경 $count개',
      one: '변경 1개',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(비어 있음)';

  @override
  String get compareNextChange => '다음 변경';

  @override
  String get compareNoChanges => '변경 없음';

  @override
  String get compareNoDifferences => '두 문서 간 차이 없음';

  @override
  String get compareOverlay => '오버레이';

  @override
  String comparePageHeader(int page) {
    return '$page페이지';
  }

  @override
  String get comparePreviousChange => '이전 변경';

  @override
  String get compareSideBySide => '나란히 보기';

  @override
  String get copy => '복사';

  @override
  String get cut => '잘라내기';

  @override
  String get delete => '삭제';

  @override
  String get done => '완료';

  @override
  String get edit => '편집';

  @override
  String get editorViewAuthorNameTitle => '작성자 이름';

  @override
  String get lineStyleDashDot => '일점쇄선';

  @override
  String get lineStyleDashed => '파선';

  @override
  String get lineStyleDotted => '점선';

  @override
  String get lineStyleSolid => '실선';

  @override
  String get measCalibrate => '보정';

  @override
  String get measCalibrateScale => '축척 보정';

  @override
  String get measDepthLabel => '깊이: ';

  @override
  String get measKindAngle => '각도';

  @override
  String get measKindArc => '호';

  @override
  String get measKindArea => '면적';

  @override
  String get measKindCount => '개수';

  @override
  String get measKindLength => '길이';

  @override
  String get measKindNetArea => '순면적';

  @override
  String get measKindPerimeter => '둘레';

  @override
  String get measKindSlope => '기울기';

  @override
  String get measKindVolume => '부피';

  @override
  String get measLineRepresents => '그린 선이 나타내는 값:';

  @override
  String get measMeasure => '측정';

  @override
  String get measSetScale => '측정 축척 설정';

  @override
  String get measSetScaleButton => '축척 설정';

  @override
  String get measVolumeDepth => '부피 깊이';

  @override
  String get menuAddNode => '노드 추가';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '페이지에 주석 적용',
      one: '페이지에 주석 적용',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => '페이지에 적용…';

  @override
  String get menuBringToFront => '맨 앞으로 가져오기';

  @override
  String get menuCheck => '체크';

  @override
  String get menuChooseValue => '값 선택…';

  @override
  String get menuClearCheck => '체크 해제';

  @override
  String get menuConvertToCheckBox => '확인란으로 변환';

  @override
  String get menuConvertToImageButton => '이미지 버튼으로 변환';

  @override
  String get menuConvertToTextField => '텍스트 필드로 변환';

  @override
  String get menuDeleteField => '필드 삭제';

  @override
  String get menuEditValue => '값 편집…';

  @override
  String get menuFieldName => '필드 이름';

  @override
  String get menuFieldValue => '필드 값';

  @override
  String get menuFlattenForm => '양식 병합';

  @override
  String get menuLock => '잠금';

  @override
  String get menuUnlock => '잠금 해제';

  @override
  String get menuRecolour => '색상 변경…';

  @override
  String get menuRemoveNode => '노드 제거';

  @override
  String get menuSaveToStamps => '스탬프에 저장';

  @override
  String get menuSetAsDefaultStyle => '기본 스타일로 설정';

  @override
  String get menuRename => '이름 바꾸기…';

  @override
  String get menuSelectOption => '옵션 선택';

  @override
  String get menuSendToBack => '맨 뒤로 보내기';

  @override
  String get menuSetImage => '이미지 설정…';

  @override
  String get menuTextStyle => '텍스트 스타일…';

  @override
  String get none => '없음';

  @override
  String get ok => '확인';

  @override
  String get overlayColor => '색상';

  @override
  String get overlayEditText => '텍스트 편집';

  @override
  String get overlayFont => '글꼴';

  @override
  String get overlayLarger => '크게';

  @override
  String get overlayMore => '더 보기';

  @override
  String get overlayNote => '메모';

  @override
  String get overlaySmaller => '작게';

  @override
  String get overlayStampText => '스탬프 텍스트';

  @override
  String get linkDialogTitle => '링크 추가';

  @override
  String get linkKindWeb => '웹 주소';

  @override
  String get linkKindPage => '문서 내 페이지';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => '페이지 번호';

  @override
  String get toolLink => '링크';

  @override
  String get overlayUnderline => '밑줄';

  @override
  String pageRangeErrorBounds(int count) {
    return '1과 $count 사이의 페이지를 입력하세요.';
  }

  @override
  String get pageRangeErrorOrder => '마지막 페이지는 첫 페이지보다 앞설 수 없습니다.';

  @override
  String get pageRangeFrom => '시작';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count페이지',
      one: '1페이지',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => '끝';

  @override
  String get panelDragToMovePanel => '패널을 옮기려면 드래그하세요';

  @override
  String get paste => '붙여넣기';

  @override
  String get propAlign => '정렬';

  @override
  String get propAlignCenter => '가운데 정렬';

  @override
  String get propAlignLeft => '왼쪽 정렬';

  @override
  String get propAlignRight => '오른쪽 정렬';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '주석 $count개',
      one: '주석 $count개',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => '작성자';

  @override
  String get propAutoSize => '자동 크기';

  @override
  String get propBold => '굵게';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => '번들 글꼴';

  @override
  String get propCallout => '콜아웃';

  @override
  String get propCharSpacing => '자간';

  @override
  String get propColor => '색상';

  @override
  String get propColour => '색상';

  @override
  String get propContents => '내용';

  @override
  String get propCornerRadius => '모서리 반경';

  @override
  String get propEditsApplyToAll => '편집 내용이 호환되는 모든 주석에 적용됩니다';

  @override
  String get propFieldName => '필드 이름';

  @override
  String get propFieldTypeCheckBox => '확인란';

  @override
  String get propFieldTypeComboBox => '콤보 상자';

  @override
  String get propFieldTypeImageButton => '이미지 버튼';

  @override
  String get propFieldTypeListBox => '목록 상자';

  @override
  String get propFieldTypeRadioGroup => '라디오 그룹';

  @override
  String get propFieldTypeSignature => '서명';

  @override
  String get propFieldTypeText => '텍스트 필드';

  @override
  String propFieldTypeTooltip(String type) {
    return '필드 유형: $type';
  }

  @override
  String get propFieldTypeUnknown => '알 수 없는 필드';

  @override
  String get propFill => '채우기';

  @override
  String get propFont => '글꼴';

  @override
  String get propFontSubsetTooltip =>
      '이 글꼴은 서브셋입니다 - 문서에서 이미 사용된 문자만 입력할 수 있습니다.';

  @override
  String get propFontWidth => '글꼴 너비';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => '기울임꼴';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => '제한된 문자';

  @override
  String get propLineEnd => '선 끝';

  @override
  String get propLineEndingButt => '평면';

  @override
  String get propLineEndingCircle => '원';

  @override
  String get propLineEndingClosedArrow => '닫힌 화살표';

  @override
  String get propLineEndingClosedArrowRev => '닫힌 화살표(반전)';

  @override
  String get propLineEndingDiamond => '다이아몬드';

  @override
  String get propLineEndingOpenArrow => '열린 화살표';

  @override
  String get propLineEndingOpenArrowRev => '열린 화살표(반전)';

  @override
  String get propLineEndingSlash => '슬래시';

  @override
  String get propLineEndingSquare => '사각형';

  @override
  String get propLineSpacing => '줄 간격';

  @override
  String get propLineStart => '선 시작';

  @override
  String get propLineType => '선 유형';

  @override
  String get propLoadFont => '글꼴 불러오기…';

  @override
  String get propLoadFontSubtitle => 'TTF 또는 OTF 파일';

  @override
  String get propMoreColors => '더 많은 색상…';

  @override
  String get propMultiline => '여러 줄';

  @override
  String get propNoFill => '채우기 없음';

  @override
  String get propNoFontsFound => '글꼴을 찾을 수 없음';

  @override
  String get propNoOutline => '윤곽선 없음';

  @override
  String get propOpacity => '불투명도';

  @override
  String get propOutline => '윤곽선';

  @override
  String get propPageLabel => '페이지';

  @override
  String propPageNumber(int number) {
    return '$number페이지';
  }

  @override
  String get propPropertiesTitle => '속성';

  @override
  String get propRecentlyUsed => '최근 사용';

  @override
  String get propScale => '배율';

  @override
  String get propSearchFonts => '글꼴 검색';

  @override
  String get propSectionAllFonts => '모든 글꼴';

  @override
  String get propSectionAppearance => '모양';

  @override
  String get propSectionContent => '내용';

  @override
  String get propSectionFormField => '양식 필드';

  @override
  String get propSectionInThisDocument => '이 문서 내';

  @override
  String get propSectionPositionSize => '위치 및 크기 (pt)';

  @override
  String get propSectionSelection => '선택 항목';

  @override
  String get propSectionText => '텍스트';

  @override
  String get propSelectAnnotationPrompt => '속성을 보려면 주석을 선택하세요';

  @override
  String get propSize => '크기';

  @override
  String get propStandardPdfFont => '표준 PDF 글꼴';

  @override
  String get propStroke => '선 굵기';

  @override
  String get propStyle => '스타일';

  @override
  String get propSystemFont => '시스템 글꼴';

  @override
  String get propType => '유형';

  @override
  String get propUnderline => '밑줄';

  @override
  String get propVaries => '다양함';

  @override
  String get redo => '다시 실행';

  @override
  String get reflowNoContent => '추출 가능한 콘텐츠 없음';

  @override
  String reflowPageLabel(int number) {
    return '$number페이지';
  }

  @override
  String get reflowSaveOrShare => '저장 또는 공유';

  @override
  String get reflowViewFigure => '그림 보기';

  @override
  String get remove => '제거';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get reset => '재설정';

  @override
  String get save => '저장';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return '$page페이지';
  }

  @override
  String get sbarCallout => '콜아웃';

  @override
  String get sbarFieldButton => '버튼 필드';

  @override
  String get sbarFieldChoice => '선택 필드';

  @override
  String get sbarFieldGeneric => '양식 필드';

  @override
  String get sbarFieldSignature => '서명 필드';

  @override
  String get sbarFieldText => '텍스트 필드';

  @override
  String get sbarStateAccepted => '수락됨';

  @override
  String get sbarStateCancelled => '취소됨';

  @override
  String get sbarStateMarked => '표시됨';

  @override
  String get sbarStateRejected => '거부됨';

  @override
  String get sbarStateResolved => '해결됨';

  @override
  String get sbarStateUnmarked => '표시 해제됨';

  @override
  String get searchAnnotations => '주석 검색';

  @override
  String get searchClearSearch => '검색 지우기';

  @override
  String get searchEmptyHint => '문서를 검색하면 모든 일치 항목이 여기에 표시됩니다';

  @override
  String get searchMatchCase => '대소문자 구분';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '일치 $count개',
      one: '일치 1개',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => '다음 일치';

  @override
  String searchNoMatches(String query) {
    return '“$query”에 대한 일치 항목 없음';
  }

  @override
  String searchPageHeader(int page) {
    return '$page페이지';
  }

  @override
  String get searchPreviousMatch => '이전 일치';

  @override
  String get searchRegex => '정규 표현식';

  @override
  String get searchReplace => '바꾸기';

  @override
  String get searchReplaceAll => '모두 바꾸기';

  @override
  String get searchReplaceHint => '바꿀 내용';

  @override
  String get searchReplaceNotTargetable =>
      '이 일치 항목은 단독으로 바꿀 수 없습니다. ‘모두 바꾸기’를 사용하거나 콘텐츠 도구로 편집하세요';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '일치 $count개 바꿈',
      one: '일치 1개 바꿈',
      zero: '바꾼 항목 없음',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => '검색 결과';

  @override
  String get searchWholeWord => '전체 단어';

  @override
  String get shellControls => '컨트롤';

  @override
  String get shellDefaultAuthor => '기본 작성자…';

  @override
  String get shellHighlightFormFields => '양식 필드 강조';

  @override
  String get shellKeyboardShortcutsMenu => '키보드 단축키…';

  @override
  String get shellKeyboardShortcutsTitle => '키보드 단축키';

  @override
  String get shellShortcutsSearchHint => '단축키 검색';

  @override
  String shellShortcutsNoMatches(String query) {
    return '“$query”와 일치하는 단축키 없음';
  }

  @override
  String get shellShortcutGroupSelect => '선택';

  @override
  String get shellShortcutGroupMarkup => '마크업';

  @override
  String get shellShortcutGroupDraw => '그리기';

  @override
  String get shellShortcutGroupShapes => '도형';

  @override
  String get shellShortcutGroupInsert => '삽입';

  @override
  String get shellShortcutGroupMeasure => '측정';

  @override
  String get shellShortcutGroupEdit => '편집';

  @override
  String get shellNotSet => '설정되지 않음';

  @override
  String get shellPageColor => '페이지 색상…';

  @override
  String get shellPageGrid => '페이지 그리드';

  @override
  String get shellPanelAnnotations => '주석';

  @override
  String get shellPanelBookmarks => '책갈피';

  @override
  String get shellPanelPages => '페이지';

  @override
  String get shellPanelProperties => '속성';

  @override
  String get shellPanelSearchResults => '검색 결과';

  @override
  String get shellPanels => '패널';

  @override
  String get shellPressAKey => '키를 누르세요';

  @override
  String get shellPressLetterKeyHint => '문자 키를 누르거나 Delete를 눌러 지우세요.';

  @override
  String get shellReflow => '리플로우';

  @override
  String get shellReflowText => '텍스트 리플로우';

  @override
  String get shellResetZoom => '확대/축소 재설정';

  @override
  String get shellSectionShell => '셸';

  @override
  String get shellSectionView => '보기';

  @override
  String get shellSettings => '설정';

  @override
  String get shellShowAnnotations => '주석 표시';

  @override
  String get shellShowScrollbarChapters => '스크롤바에 장 표시';

  @override
  String get shellTabHere => '여기에 탭';

  @override
  String get shellUnbound => '미지정';

  @override
  String get shellZoom => '확대/축소';

  @override
  String sidebarByAuthor(String author) {
    return '$author';
  }

  @override
  String get sidebarCancelSelection => '선택 취소';

  @override
  String get sidebarClearSearch => '검색 지우기';

  @override
  String get sidebarDeleteSelected => '선택 항목 삭제';

  @override
  String get sidebarDeleteSignature => '서명 삭제';

  @override
  String get sidebarLockAnnotation => '잠금';

  @override
  String get sidebarUnlockAnnotation => '잠금 해제';

  @override
  String get sidebarMore => '더 보기';

  @override
  String get sidebarNoAnnotations => '주석 없음';

  @override
  String get sidebarNoMatchingAnnotations => '일치하는 주석 없음';

  @override
  String sidebarPageHeader(int number) {
    return '$number페이지';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      '문서에서 디지털 서명을 제거합니다. 실행을 취소할 수 있습니다.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return '문서에서 \"$name\"의 디지털 서명을 제거합니다. 실행을 취소할 수 있습니다.';
  }

  @override
  String get sidebarRemoveSignatureTitle => '서명을 제거하시겠습니까?';

  @override
  String get sidebarReopen => '다시 열기';

  @override
  String get sidebarReply => '답글';

  @override
  String get sidebarResolve => '해결';

  @override
  String get sidebarSearchHint => '주석 검색';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 선택됨',
      one: '$count개 선택됨',
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
  String get sidebarWriteReplyHint => '답글 작성…';

  @override
  String get sigTitle => '서명';

  @override
  String get signIdCreate => '만들기';

  @override
  String get signIdEmail => '이메일(선택 사항)';

  @override
  String get signIdName => '이름';

  @override
  String get signIdNameHint => '서명에 표시될 이름';

  @override
  String get signIdNameRequired => '이름을 입력하세요';

  @override
  String get signIdOrganization => '조직(선택 사항)';

  @override
  String get signIdSelfSignedInfo =>
      '자체 서명된 ID가 생성됩니다. Adobe Acrobat 및 기타 리더에서 서명은 \"서명됨, 유효성 알 수 없음\"으로 표시되며, 이는 해당 프로그램의 자체 서명 ID와 동일합니다. 녹색 체크 표시를 받으려면 유료의 공개 신뢰 CA가 필요합니다.';

  @override
  String get signIdTitle => '서명 ID 만들기';

  @override
  String get stampBox => '상자';

  @override
  String get stampCircle => '원';

  @override
  String get stampCustomCaption => '사용자 지정 스탬프';

  @override
  String get stampDateFormat => '날짜 형식';

  @override
  String get stampDeleteComponent => '선택한 구성 요소 삭제';

  @override
  String get stampDeleteStamp => '스탬프 삭제';

  @override
  String get stampEditStamp => '스탬프 편집';

  @override
  String get stampExport => '내보내기…';

  @override
  String get stampFieldDate => '날짜';

  @override
  String get stampFieldDateTime => '날짜 및 시간';

  @override
  String get stampFieldTime => '시간';

  @override
  String get stampFieldUsername => '사용자 이름';

  @override
  String get stampFont => '글꼴';

  @override
  String get stampFontBold => '굵게';

  @override
  String get stampFontItalic => '기울임꼴';

  @override
  String get stampHeight => '높이';

  @override
  String get stampImage => '이미지';

  @override
  String get stampImport => '가져오기…';

  @override
  String get stampInsertField => '필드 삽입';

  @override
  String get stampMoreColors => '더 많은 색상…';

  @override
  String get stampNewStamp => '새 스탬프…';

  @override
  String get stampNewStampTitle => '새 스탬프';

  @override
  String get stampSavedToCollection => '스탬프에 저장됨';

  @override
  String get stampSelectTextToEdit => '편집할 텍스트 선택';

  @override
  String get stampSelectedText => '선택한 텍스트';

  @override
  String get stampSignature => '서명';

  @override
  String get stampStamps => '스탬프';

  @override
  String get stampText => '텍스트';

  @override
  String get stampTime12Hour => '12시간';

  @override
  String get stampTime24Hour => '24시간';

  @override
  String get stampTimeFormat => '시간 형식';

  @override
  String get stampWidth => '너비';

  @override
  String get takeoffArea => '면적';

  @override
  String get takeoffCount => '개수';

  @override
  String get takeoffEmpty => '아직 측정값이 없습니다.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '그룹 $count개',
      one: '그룹 $count개',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
      one: '항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => '길이';

  @override
  String get takeoffTitle => '물량 산출';

  @override
  String get tbAddInkAnnotation => '잉크 주석 추가';

  @override
  String get tbAlign => '정렬';

  @override
  String get tbAlignBottom => '아래쪽 정렬';

  @override
  String get tbAlignHorizontalCenters => '가로 중앙 정렬';

  @override
  String get tbAlignLeft => '왼쪽 정렬';

  @override
  String get tbAlignRight => '오른쪽 정렬';

  @override
  String get tbAlignTop => '위쪽 정렬';

  @override
  String get tbAlignVerticalCenters => '세로 중앙 정렬';

  @override
  String get tbAnnotationsFlattened => '주석이 페이지에 병합되었습니다';

  @override
  String get tbApplyRedactionsMessage =>
      '표시된 콘텐츠가 문서에서 영구적으로 제거됩니다. 이 작업은 취소할 수 없습니다.';

  @override
  String get tbApplyRedactionsTitle => '교정을 적용하시겠습니까?';

  @override
  String get tbApplyRedactionsTooltip => '교정 적용(되돌릴 수 없음)';

  @override
  String get tbAutosizeTextBox => '텍스트 상자 자동 크기 조정 (Alt+Z)';

  @override
  String get tbAutosizeTextFont => '글꼴을 텍스트 상자에 맞추기';

  @override
  String get tbCalibrateScaleHint => '축척을 보정하려면 알려진 길이의 선을 그리세요.';

  @override
  String get tbCharSpacing => '자간';

  @override
  String get tbCheckBoxOption => '확인란';

  @override
  String get tbCheckMarksOnDocument => '문서의 체크 표시';

  @override
  String get tbCropImage => '이미지 자르기';

  @override
  String get tbCroppingImage => '이미지 자르는 중';

  @override
  String get tbCropApply => '자르기 적용';

  @override
  String get tbCropCancel => '자르기 취소';

  @override
  String get tbCropReset => '자르기 재설정';

  @override
  String get tbColorLabel => '색상';

  @override
  String get tbColorProcessingTooltip => '색상 처리 - 페이지 콘텐츠 색상 찾기 및 바꾸기';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '색상 $count개 바꿈',
      one: '색상 1개 바꿈',
      zero: '일치하는 색상을 찾을 수 없음',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => '확인란으로 변환';

  @override
  String get tbConvertToImageButton => '이미지 버튼으로 변환';

  @override
  String get tbConvertToTextField => '텍스트 필드로 변환';

  @override
  String get tbCornerRadius => '모서리 반경';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '주석 $count개 삭제',
      one: '주석 삭제',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => '요소 삭제';

  @override
  String get tbDeleteField => '필드 삭제';

  @override
  String get tbDiscardDrawing => '그리기 취소';

  @override
  String get tbDistributeHorizontally => '가로로 분산';

  @override
  String get tbDistributeVertically => '세로로 분산';

  @override
  String get tbDrawNewSignature => '새 서명 그리기…';

  @override
  String get tbEditAnnotationText => '주석 텍스트 편집';

  @override
  String get tbEditTextStyle => '텍스트 및 스타일 편집';

  @override
  String get tbElement => '요소';

  @override
  String get tbEraserSize => '지우개 크기';

  @override
  String get tbFieldActions => '필드 작업';

  @override
  String get tbFieldName => '필드 이름';

  @override
  String tbFieldNamed(String name) {
    return '필드: $name';
  }

  @override
  String get tbFieldValue => '필드 값';

  @override
  String get tbFill => '채우기';

  @override
  String get tbFingerDraws => '손가락으로 그리기 - 탭하면 스크롤로 전환';

  @override
  String get tbFingerScrolls => '손가락으로 스크롤(펜으로 그리기) - 탭하면 그리기로 전환';

  @override
  String get tbFlattenAnnotationsTooltip => '주석을 페이지에 병합';

  @override
  String get tbFlattenForm => '양식 병합';

  @override
  String get tbFlattenFormBakeValues => '양식 병합 - 값을 페이지에 고정';

  @override
  String get tbFlattenLabel => '병합';

  @override
  String get tbFont => '글꼴';

  @override
  String get tbFontSize => '글꼴 크기';

  @override
  String get tbFontWidth => '글꼴 너비';

  @override
  String get tbFormFieldsFlattened => '양식 필드가 페이지에 병합되었습니다';

  @override
  String get tbGroupDraw => '그리기';

  @override
  String get tbGroupEdit => '편집';

  @override
  String get tbGroupInsert => '삽입';

  @override
  String get tbGroupMarkup => '마크업';

  @override
  String get tbGroupMeasure => '측정';

  @override
  String get tbGroupSelect => '선택';

  @override
  String get tbGroupShapes => '도형';

  @override
  String get tbImageButtonOption => '이미지 버튼';

  @override
  String get tbLineEnd => '선 끝';

  @override
  String get tbLineSpacing => '줄 간격';

  @override
  String get tbLineStart => '선 시작';

  @override
  String get tbLineType => '선 유형';

  @override
  String get tbManageStamps => '스탬프 관리…';

  @override
  String get tbMarkupHighlight => '형광펜';

  @override
  String get tbMarkupHighlightTip => '선택 항목 강조';

  @override
  String get tbMarkupSquiggly => '물결 밑줄';

  @override
  String get tbMarkupSquigglyTip => '선택 항목에 물결 밑줄';

  @override
  String get tbMarkupStrikeOut => '취소선';

  @override
  String get tbMarkupStrikeOutTip => '선택 항목에 취소선';

  @override
  String get tbMarkupUnderline => '밑줄';

  @override
  String get tbMarkupUnderlineTip => '선택 항목에 밑줄';

  @override
  String get tbMoreColors => '더 많은 색상…';

  @override
  String get tbNameArrow => '화살표';

  @override
  String get tbNameCallout => '콜아웃';

  @override
  String get tbNameCloudPolygon => '구름 다각형';

  @override
  String get tbNameCount => '개수';

  @override
  String get tbNameDigitalSignature => '디지털 서명';

  @override
  String get tbNameDraw => '그리기';

  @override
  String get tbNameEllipse => '타원';

  @override
  String get tbNameEraser => '잉크 획 지우기';

  @override
  String get tbNameHand => '손 도구';

  @override
  String get tbNameHighlight => '형광펜';

  @override
  String get tbNameImage => '이미지';

  @override
  String get tbNameLine => '선';

  @override
  String get tbNameMeasureAngle => '각도 측정';

  @override
  String get tbNameMeasureArc => '호 길이 측정';

  @override
  String get tbNameMeasureArea => '면적 측정';

  @override
  String get tbNameMeasureDistance => '거리 측정';

  @override
  String get tbNameMeasurePerimeter => '둘레 측정';

  @override
  String get tbNameMeasureSlope => '기울기 측정(높이/거리)';

  @override
  String get tbNameMeasureVolume => '부피 측정(면적 × 깊이)';

  @override
  String get tbNameNote => '메모';

  @override
  String get tbNamePolygon => '다각형';

  @override
  String get tbNamePolyline => '폴리라인';

  @override
  String get tbNameRectangle => '사각형';

  @override
  String get tbNameSelect => '선택';

  @override
  String get tbNameSignature => '서명';

  @override
  String get tbNameStamp => '스탬프';

  @override
  String get tbNameTextBox => '텍스트 상자';

  @override
  String get tbNewFieldType => '새 필드 유형 - 추가하려면 페이지에서 드래그하세요';

  @override
  String get tbNoAnnotationsToFlatten => '병합할 주석 없음';

  @override
  String get tbNoCustomStamps => '사용자 지정 스탬프 없음';

  @override
  String get tbNoFormFieldsToFlatten => '병합할 양식 필드 없음';

  @override
  String get tbNoRedactionsToApply => '적용할 교정 없음';

  @override
  String get tbNoteTitle => '메모';

  @override
  String get tbOpacity => '불투명도';

  @override
  String get tbOutline => '윤곽선';

  @override
  String get tbPatternScale => '패턴 배율';

  @override
  String get tbPickColorFromPage => '페이지에서 색상 선택';

  @override
  String get tbRedactionsApplied => '교정이 적용되었습니다';

  @override
  String get tbRedoShortcut => '다시 실행 (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      '리플로우할 수 없음 - 이 도구가 다시 배치할 수 있는 단일 열 단락이 아닙니다. 대신 텍스트 바꾸기를 사용해 보세요.';

  @override
  String get tbReflowParagraph => '단락 리플로우';

  @override
  String get tbRenameField => '필드 이름 바꾸기';

  @override
  String get tbRenameFieldEllipsis => '필드 이름 바꾸기…';

  @override
  String get tbReplaceImage => '이미지 바꾸기';

  @override
  String get tbReplaceImageFailed => '이미지를 바꿀 수 없음';

  @override
  String get tbReplaceText => '텍스트 바꾸기';

  @override
  String get tbSaveImage => '이미지 저장';

  @override
  String get tbSaveShortcut => '저장… (⌘S / Ctrl+S)';

  @override
  String get tbScale => '축척';

  @override
  String get tbSelectTextForMarkup => '마크업을 사용하려면 텍스트를 선택하세요';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 선택됨',
      one: '선택 항목',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => '설정…';

  @override
  String get tbStamp => '스탬프';

  @override
  String get tbStampText => '스탬프 텍스트';

  @override
  String get tbStrokeOpacityFont => '선, 불투명도, 글꼴';

  @override
  String get tbStrokeWidthLabel => '선 굵기';

  @override
  String tbStrokeWidthPreset(String width) {
    return '선 굵기 $width';
  }

  @override
  String get tbStyle => '스타일';

  @override
  String get tbTakeoffTotals => '물량 산출 합계';

  @override
  String get tbTextBorder => '텍스트 테두리';

  @override
  String get tbTextColour => '텍스트 색상';

  @override
  String get tbTextFieldOption => '텍스트 필드';

  @override
  String get tbTextFill => '텍스트 채우기';

  @override
  String get tbTextStyleEllipsis => '텍스트 스타일…';

  @override
  String get tbTextTitle => '텍스트';

  @override
  String get tbTipCallout => '콜아웃 - 지점에서 상자가 놓일 위치로 드래그하세요';

  @override
  String get tbTipContent => '페이지 콘텐츠 편집';

  @override
  String get tbTipCount => '개수 - 탭하여 체크 표시를 놓고 집계하세요';

  @override
  String get tbTipDigitalSignature => '디지털 서명 - 상자를 드래그하여 배치하고 서명하세요';

  @override
  String get tbTipForm => '양식 필드 - 탭하여 선택, 더블 탭하여 입력, 드래그하여 추가';

  @override
  String get tbTipHighlightDraw => '형광펜 - 자유롭게 그리기';

  @override
  String get tbTipImage => '이미지 - 탭하여 배치하거나 상자를 드래그하세요';

  @override
  String get tbTipMeasureAngle => '각도 측정 - 세 점을 클릭하세요';

  @override
  String get tbTipMeasureArc => '호 길이 측정 - 세 점을 클릭하세요';

  @override
  String get tbTipRedact => '교정 - 영역을 드래그한 후 적용하세요';

  @override
  String get tbTipSignature => '서명 - 페이지를 탭하여 배치하세요';

  @override
  String get tbTipSnapshot => '스냅샷 - 영역을 드래그하여 캡처하세요(벡터로 다시 붙여넣기)';

  @override
  String get tbToolContent => '콘텐츠';

  @override
  String get tbToolForm => '양식';

  @override
  String get tbToolRedact => '교정';

  @override
  String get tbToolSnapshot => '스냅샷';

  @override
  String get tbTools => '도구';

  @override
  String get tbTotals => '합계';

  @override
  String get tbTypeTextEachTime => '매번 텍스트 입력';

  @override
  String get tbUnderline => '밑줄';

  @override
  String get tbUndoShortcut => '실행 취소 (⌘Z)';

  @override
  String get textStyleFont => '글꼴';

  @override
  String get textStyleFontSize => '글꼴 크기';

  @override
  String get textStyleKeep => '유지';

  @override
  String get textStyleStyle => '스타일';

  @override
  String get textStyleText => '텍스트';

  @override
  String get textStyleTextFill => '텍스트 채우기';

  @override
  String get textStyleTitle => '텍스트 및 스타일 편집';

  @override
  String get thumbAddPage => '페이지 추가';

  @override
  String get thumbClearSelection => '선택 지우기';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 복사',
      one: '페이지 복사',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => '선택한 페이지 복사';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 잘라내기',
      one: '페이지 잘라내기',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => '선택한 페이지 잘라내기';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 삭제',
      one: '페이지 삭제',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => '선택한 페이지 삭제';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 복제',
      one: '페이지 복제',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => '페이지 내보내기…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 내보내기…',
      one: '페이지 내보내기…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => '선택한 페이지 내보내기';

  @override
  String get thumbInsertBlankAfter => '뒤에 빈 페이지 삽입';

  @override
  String get thumbInsertBlankBefore => '앞에 빈 페이지 삽입';

  @override
  String get thumbInsertFileFailed => '해당 파일을 삽입할 수 없습니다.';

  @override
  String get thumbInsertPdf => 'PDF 삽입…';

  @override
  String get thumbPageActions => '페이지 작업';

  @override
  String thumbPageNumber(int number) {
    return '$number페이지';
  }

  @override
  String get thumbPages => '페이지';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 페이지 붙여넣기',
      one: '페이지 붙여넣기',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => '180° 회전';

  @override
  String get thumbRotateLeft => '왼쪽으로 회전';

  @override
  String get thumbRotatePageRight => '페이지 오른쪽으로 회전';

  @override
  String get thumbRotateRight => '오른쪽으로 회전';

  @override
  String get thumbRotateSelectedLeft => '선택한 페이지 왼쪽으로 회전';

  @override
  String get thumbRotateSelectedRight => '선택한 페이지 오른쪽으로 회전';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 선택됨',
      one: '$count개 선택됨',
    );
    return '$_temp0';
  }

  @override
  String get undo => '실행 취소';

  @override
  String get viewerEditFontUnsafe => '이 PDF 글꼴 또는 인코딩은 안전하게 편집할 수 없습니다.';

  @override
  String get viewerEditNeedsSinglePage => '편집하려면 한 페이지에서 선택해야 합니다.';

  @override
  String get viewerEditNotEditableRun =>
      '이 선택 항목은 편집 가능한 하나의 페이지 콘텐츠 텍스트 런이 아닙니다.';

  @override
  String get viewerEditStyleUnchangeable =>
      '이 PDF 글꼴은 다시 입력할 수 있지만 스타일은 변경할 수 없습니다.';

  @override
  String get viewerEditTextStyle => '텍스트 및 스타일 편집';

  @override
  String get viewerMarkup => '마크업';

  @override
  String get viewerMarkupHighlight => '형광펜';

  @override
  String get viewerMarkupSquiggly => '물결 밑줄';

  @override
  String get viewerMarkupStrikeOut => '취소선';

  @override
  String get viewerMarkupUnderline => '밑줄';

  @override
  String get viewerSelectAll => '모두 선택';

  @override
  String get annotationLibraryTitle => 'Annotation library';

  @override
  String get annotationLibraryEmpty => 'No saved annotations.';

  @override
  String get annotationLibraryHelp =>
      'Select a supported annotation and choose “Save to annotation library” from its menu. Links and form fields cannot be saved.';

  @override
  String get annotationLibrarySave => 'Save to annotation library';

  @override
  String get annotationLibrarySaveTitle => 'Save annotation';

  @override
  String get annotationLibraryRenameTitle => 'Rename library item';

  @override
  String get annotationLibraryCustomStamps => 'Custom stamps…';

  @override
  String get signatureLibraryManage => 'Manage signatures';

  @override
  String get signatureLibraryRenameTitle => 'Rename signature';

  @override
  String get signatureLibraryEmpty => 'No saved signatures.';
}
