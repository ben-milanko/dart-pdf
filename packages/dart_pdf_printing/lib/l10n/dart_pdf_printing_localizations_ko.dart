// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class DartPdfPrintingLocalizationsKo extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get cancel => '취소';

  @override
  String get printDlgPreparing => '준비 중…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '$total페이지 중 $rendered페이지 렌더링 중…';
  }

  @override
  String get printDlgTitle => '인쇄 중';

  @override
  String get printPreviewAll => '전체';

  @override
  String get printPreviewCurrent => '현재';

  @override
  String get printPreviewNextPage => '다음 페이지';

  @override
  String printPreviewPageOf(int page, int total) {
    return '$total페이지 중 $page페이지';
  }

  @override
  String get printPreviewPreviousPage => '이전 페이지';

  @override
  String get printPreviewPrint => '인쇄';

  @override
  String get printPreviewRange => '범위';

  @override
  String printPreviewRangeError(int total) {
    return '1에서 $total 사이의 페이지 범위를 입력하세요.';
  }

  @override
  String printPreviewSelection(int count) {
    return '인쇄할 페이지: $count';
  }

  @override
  String get printPreviewTitle => '인쇄 미리 보기';

  @override
  String get printPreviewUnavailable => '미리 보기를 사용할 수 없음';

  @override
  String get printOptionsPrinter => '프린터';

  @override
  String get printOptionsNativePrinter =>
      '다음에 표시되는 시스템 인쇄 대화상자에서 프린터, 용지함, 컬러, 양면 인쇄 및 장치 속성을 선택하세요. 여기에 표시된 레이아웃을 사용하려면 배율은 100%, 부수는 1로 유지하세요.';

  @override
  String get printOptionsPages => '페이지';

  @override
  String get printOptionsSelected => '선택한 페이지';

  @override
  String get printOptionsPageRange => '페이지(예: 1, 3-5)';

  @override
  String get printOptionsAddFiles => '파일 추가…';

  @override
  String get printOptionsAddFailed => '선택한 파일을 추가할 수 없습니다.';

  @override
  String get printOptionsGetWindow => '영역 선택';

  @override
  String get printOptionsClearWindow => '영역 해제';

  @override
  String get printOptionsWindowHint => '원본 페이지에서 사각형을 드래그하여 인쇄할 영역을 선택하세요.';

  @override
  String get printOptionsPaper => '용지';

  @override
  String get printOptionsPaperSize => '용지 크기';

  @override
  String get printOptionsPageSize => '문서 페이지 크기 사용';

  @override
  String get printOptionsOrientation => '용지 방향';

  @override
  String get printOptionsAuto => '자동';

  @override
  String get printOptionsPortrait => '세로';

  @override
  String get printOptionsLandscape => '가로';

  @override
  String get printOptionsCopies => '부수';

  @override
  String get printOptionsCollate => '한 부씩 인쇄';

  @override
  String get printOptionsReverse => '페이지 역순으로 인쇄';

  @override
  String get printOptionsLayout => '페이지 레이아웃';

  @override
  String get printOptionsScaling => '페이지 배율';

  @override
  String get printOptionsScaleNone => '없음(실제 크기)';

  @override
  String get printOptionsFitPaper => '용지에 맞춤';

  @override
  String get printOptionsReducePaper => '용지에 맞게 축소';

  @override
  String get printOptionsFitMargins => '여백 안에 맞춤';

  @override
  String get printOptionsReduceMargins => '여백 안에 맞게 축소';

  @override
  String get printOptionsCustomScale => '사용자 지정 배율';

  @override
  String get printOptionsMultiple => '한 장에 여러 페이지';

  @override
  String get printOptionsScalePercent => '배율(%)';

  @override
  String get printOptionsMargin => '여백(pt)';

  @override
  String get printOptionsPagesPerSheet => '한 장에 인쇄할 페이지 수';

  @override
  String get printOptionsPageOrder => '페이지 순서';

  @override
  String get printOptionsHorizontal => '가로';

  @override
  String get printOptionsHorizontalReverse => '가로 역순';

  @override
  String get printOptionsVertical => '세로';

  @override
  String get printOptionsVerticalReverse => '세로(열은 오른쪽부터)';

  @override
  String get printOptionsBorder => '페이지 테두리 인쇄';

  @override
  String get printOptionsRotation => '회전(시계 방향)';

  @override
  String get printOptionsNoRotation => '없음';

  @override
  String get printOptionsCenter => '용지 가운데 배치';

  @override
  String get printOptionsOffsetX => '오른쪽으로 이동(pt)';

  @override
  String get printOptionsOffsetY => '아래로 이동(pt)';

  @override
  String get printOptionsContents => '인쇄할 내용';

  @override
  String get printOptionsDocumentAndMarkups => '문서 및 주석';

  @override
  String get printOptionsDocumentOnly => '문서만';

  @override
  String get printOptionsMarkupsOnly => '주석만';

  @override
  String get printOptionsDimPage => '페이지 내용을 연하게 인쇄';

  @override
  String get printOptionsDimMarkups => '주석을 연하게 인쇄';

  @override
  String get printOptionsHyperlinks => '표시된 하이퍼링크 인쇄';

  @override
  String get printOptionsDefaults => '기본값';

  @override
  String get printOptionsInvalidNumber => '인쇄하기 전에 올바른 숫자를 입력하세요.';

  @override
  String get printOptionsInvalidValue => '잘못된 값';

  @override
  String get printOptionsMarginGuide => '빨간색 선은 여백을 나타내며 인쇄되지 않습니다.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return '영역: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return '원본: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return '용지: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return '$total장 중 $sheet장';
  }

  @override
  String get printOptionsInvalidLayout =>
      '이 레이아웃을 준비할 수 없습니다. 용지 크기, 여백 및 배율을 확인하세요.';

  @override
  String get printOptionsChoosePrinter => '프린터 선택';

  @override
  String get printOptionsNoPrinters =>
      '설치된 프린터가 없습니다. Windows 설정에서 프린터를 추가한 후 다시 시도하세요.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return '저장된 프린터 “$printer”을(를) 사용할 수 없습니다. 계속하려면 프린터를 선택하세요.';
  }

  @override
  String get printOptionsPrinterError =>
      '프린터 설정을 불러올 수 없습니다. 프린터 연결을 확인하고 다시 시도하세요.';

  @override
  String get printOptionsRetry => '다시 시도';

  @override
  String get printOptionsColor => '컬러';

  @override
  String get printOptionsGrayscale => '흑백';

  @override
  String get printOptionsDuplex => '양면 인쇄';

  @override
  String get printOptionsSimplex => '단면';

  @override
  String get printOptionsLongEdge => '긴 쪽으로 넘기기';

  @override
  String get printOptionsShortEdge => '짧은 쪽으로 넘기기';

  @override
  String get printOptionsTray => '용지함';

  @override
  String get printOptionsDefaultTray => '프린터 기본값';

  @override
  String get printOptionsProperties => '프린터 속성…';

  @override
  String get printOptionsDirectPrinter => '인쇄를 누르면 선택한 프린터로 이 작업을 바로 보냅니다.';

  @override
  String get printOptionsPropertiesError => '프린터 속성을 열 수 없습니다.';

  @override
  String get printOptionsLoadingPrinters => '프린터 불러오는 중…';
}
