// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get add => '추가';

  @override
  String get apply => '적용';

  @override
  String get cancel => '취소';

  @override
  String get clear => '지우기';

  @override
  String get close => '닫기';

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
  String exActionJavaScript(String script) {
    return '앱에 노출된 JavaScript: $script';
  }

  @override
  String exActionLink(String uri) {
    return '링크: $uri';
  }

  @override
  String exActionNamed(String name) {
    return '명명된 작업: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return '처리되지 않은 작업 유형: $type';
  }

  @override
  String get exAnnotationTextCopied => '주석 텍스트가 복사되었습니다';

  @override
  String get exApiKeyHelper => 'Authorization: Bearer …로 전송됨';

  @override
  String get exApiKeyLabel => 'API 키 / 토큰(선택 사항)';

  @override
  String get exAppMenuTooltip => 'DartPDF 메뉴';

  @override
  String get exClearRecentFiles => '최근 파일 지우기';

  @override
  String get exCloseTab => '탭 닫기';

  @override
  String exCompareTabTitle(String before, String after) {
    return '비교: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => '다른 PDF와 비교…';

  @override
  String get exCopiedToClipboard => '클립보드에 복사됨';

  @override
  String get exCopySelectedText => '선택한 텍스트 복사 (⌘C)';

  @override
  String get exCopyText => '텍스트 복사';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return '$name을(를) 열 수 없습니다\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return '$path을(를) 열 수 없습니다\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return '$url을(를) 열 수 없습니다';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return '$uri을(를) 열 수 없습니다\n$error\n\n웹에서는 이것이 종종 CORS 제한 때문입니다: 서버가 Access-Control-Allow-Origin을 전송하고 Range 헤더를 노출해야 합니다.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return '$title을(를) 다시 열 수 없습니다\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return '$title을(를) 다시 열 수 없습니다 - 저장된 사본을 더 이상 사용할 수 없습니다.';
  }

  @override
  String get exDemoNoteHint => '여기에 입력하세요 - 이 텍스트 상자는 페이지 위에 떠 있습니다';

  @override
  String get exDiagnosticsCopied => '진단 정보가 클립보드에 복사됨';

  @override
  String exDownloaded(String name) {
    return '$name 다운로드됨';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return '$name 다운로드됨 - Ctrl+V로 PDF에 다시 붙여넣으세요';
  }

  @override
  String get exExport => '내보내기';

  @override
  String exExportFailed(String error) {
    return '내보내기 실패: $error';
  }

  @override
  String get exExportPageImageMenu => '페이지를 이미지로 내보내기…';

  @override
  String get exExportPageImageTitle => '페이지를 이미지로 내보내기';

  @override
  String get exFeatureShowcase => '기능 쇼케이스';

  @override
  String get exFormat => '형식';

  @override
  String get exHide => '숨기기';

  @override
  String get exHorizontalLayout => '가로 페이지 레이아웃';

  @override
  String get exHowToSetupOcr => 'OCR 서버 설정 방법';

  @override
  String get exModelName => '모델 이름';

  @override
  String get exNoMessage => '메시지 없음';

  @override
  String get exNoRecentFiles => '최근 파일 없음';

  @override
  String exNotAValidUrl(String url) {
    return '유효한 URL이 아닙니다:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR이 텍스트 스팬 $count개를 추가했습니다 - 이제 페이지 텍스트를 선택할 수 있습니다',
      one: 'OCR이 텍스트 스팬 1개를 추가했습니다 - 이제 페이지 텍스트를 선택할 수 있습니다',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      '직접 호스팅하는 비전-언어 OCR 모델(vLLM의 dots.ocr 또는 OpenAI 호환 OCR 엔드포인트)을 사용하여 스캔한 페이지 위에 선택 및 검색 가능한 텍스트 레이어를 추가합니다.';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR 실패: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => '열기';

  @override
  String get exOpenDocumentBeforeOcr => 'OCR을 실행하기 전에 문서를 여세요';

  @override
  String get exOpenDocumentFirst => '먼저 문서를 여세요';

  @override
  String get exOpenFromUrl => 'URL에서 열기…';

  @override
  String get exOpenFromUrlTitle => 'URL에서 열기';

  @override
  String get exOpenInNewTab => '새 탭에서 PDF 열기';

  @override
  String get exOpenInteractiveDemo => '인터랙티브 데모 열기';

  @override
  String get exOpenPdf => 'PDF 열기…';

  @override
  String get exOpenPdfButton => 'PDF 열기';

  @override
  String get exOpenRecent => '최근 항목 열기';

  @override
  String get exOpenUrlDescription =>
      'PdfHttpByteSource를 통해 HTTP Range 요청으로 PDF를 스트리밍하여 파서가 필요로 하는 부분만 가져오고, 서버가 range를 지원하지 않으면 전체 다운로드로 대체합니다.';

  @override
  String get exOpeningDocument => '문서 여는 중';

  @override
  String get exOpeningPdf => 'PDF 여는 중…';

  @override
  String exOpeningTitle(String title) {
    return '$title 여는 중…';
  }

  @override
  String get exPdfUrlLabel => 'PDF URL';

  @override
  String get exPerformanceAuto => '성능: 자동';

  @override
  String get exPreparing => '준비 중…';

  @override
  String get exPubDevMenuItem => 'pub.dev의 dart_pdf_editor';

  @override
  String exRecognisingPage(int current, int count) {
    return '$count페이지 중 $current페이지 인식 중…';
  }

  @override
  String get exResolution => '해상도';

  @override
  String get exRunOcr => 'OCR 실행';

  @override
  String get exSaveAs => '다른 이름으로 저장…';

  @override
  String exSaveFailed(String error) {
    return '저장 실패: $error';
  }

  @override
  String exSavedName(String name) {
    return '$name 저장됨';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return '$name 저장됨 - ⌘V로 PDF에 다시 붙여넣으세요';
  }

  @override
  String exSavedTo(String path) {
    return '$path에 저장됨';
  }

  @override
  String get exScrollIndicatorDemo => '스크롤 표시기 API 데모';

  @override
  String get exServiceEndpoint => '서비스 엔드포인트';

  @override
  String get exShow => '표시';

  @override
  String get exSingleWorker => '단일 워커';

  @override
  String get exSupplyFeedback => '피드백 보내기…';

  @override
  String get exSwitchToEdit => '편집 모드로 전환';

  @override
  String get exSwitchToReadOnly => '읽기 전용으로 전환';

  @override
  String get exThemeDark => '테마: 어둡게 - 시스템으로 전환';

  @override
  String get exThemeLight => '테마: 밝게 - 어둡게로 전환';

  @override
  String get exThemeSystem => '테마: 시스템 - 밝게로 전환';

  @override
  String get exTryDemo => '인터랙티브 데모 사용해 보기';

  @override
  String get exUntitled => '제목 없음';

  @override
  String get exVerticalLayout => '세로 페이지 레이아웃';

  @override
  String get exViewSource => 'GitHub에서 소스 보기';

  @override
  String get exWorkerAuto => '자동';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '성능: 워커 $count개',
      one: '성능: 단일 워커',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '워커 $count개';
  }

  @override
  String get feedbackAttachDiagnostics => '이 진단 정보를 보고서에 첨부';

  @override
  String get feedbackClearLog => '로그 지우기';

  @override
  String get feedbackCopyDiagnostics => '진단 정보 복사';

  @override
  String get feedbackDiagnosticsNotice =>
      '피드백 양식이 브라우저에서 열립니다. 아래 진단 정보는 이 기기에서만 수집되며 문제 재현을 돕기 위해 첨부됩니다. 먼저 검토하세요 - 비공개로 유지하고 싶은 내용은 포함하지 마세요.';

  @override
  String get feedbackOpenForm => '피드백 양식 열기';

  @override
  String get feedbackTitle => '피드백 보내기';

  @override
  String get none => '없음';

  @override
  String get ok => '확인';

  @override
  String get paste => '붙여넣기';

  @override
  String get redo => '다시 실행';

  @override
  String get remove => '제거';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get reset => '재설정';

  @override
  String get save => '저장';

  @override
  String get scrollDemoNextPage => '다음 페이지';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return '$current / $count페이지';
  }

  @override
  String get scrollDemoPreviousPage => '이전 페이지';

  @override
  String get scrollDemoSwitchHorizontal => '가로 레이아웃으로 전환';

  @override
  String get scrollDemoSwitchVertical => '세로 레이아웃으로 전환';

  @override
  String get scrollDemoTitle => '스크롤 표시기 API';

  @override
  String get undo => '실행 취소';

  @override
  String get exFileTypePdf => 'PDF 문서';

  @override
  String get exFileTypeImages => '이미지';

  @override
  String get exFileTypeFonts => '글꼴';
}
