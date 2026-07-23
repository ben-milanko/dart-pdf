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
  String get appSigAddLogo => '로고 추가…';

  @override
  String appSigAllPages(int pageCount) {
    return '전체 $pageCount페이지';
  }

  @override
  String get appSigAppearance => '모양';

  @override
  String get appSigAppearanceDescription =>
      '서명은 배치한 위치에 그려집니다. 서명자 이름과 세부 정보는 항상 표시되며, 손으로 그린 표시와 로고 배경을 추가할 수 있습니다.';

  @override
  String appSigApplyTo(String label) {
    return '적용 대상: $label';
  }

  @override
  String get appSigApplyToPages => '페이지에 적용…';

  @override
  String get appSigChooseCertificate => '인증서 파일 선택…';

  @override
  String get appSigChooseKeyDescription =>
      '개인 키(RSA, PEM 또는 DER)와 인증서 파일을 선택하세요. 키는 서명에만 사용되며 저장되지 않습니다.';

  @override
  String get appSigChoosePngOrJpeg => 'PNG 또는 JPEG 이미지를 선택하세요.';

  @override
  String get appSigChoosePrivateKey => '개인 키 선택…';

  @override
  String get appSigContactInfo => '연락처 정보';

  @override
  String get appSigCouldNotCaptureSignature => '서명을 캡처할 수 없습니다.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return '인증서를 읽을 수 없습니다: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return '키를 읽을 수 없습니다: $error';
  }

  @override
  String get appSigCreateOnDevice => '이 기기에서 서명 만들기';

  @override
  String appSigDate(String date) {
    return '날짜: $date';
  }

  @override
  String get appSigDigitallySign => '디지털 서명';

  @override
  String get appSigDrawSignature => '서명 그리기…';

  @override
  String get appSigFieldHelper => '비워 두면 새 서명 필드를 만듭니다.';

  @override
  String get appSigFieldLabel => '기존 서명 필드(선택 사항)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '인증서 $count개',
      one: '인증서 1개',
    );
    return '$_temp0 · 유효 기간 $validFrom ~ $validUntil';
  }

  @override
  String get appSigIntro =>
      '디지털 서명은 이 문서에 서명했으며 그 이후 변경되지 않았음을 증명합니다. 서명 방법을 선택하세요.';

  @override
  String get appSigKeyOrCertUnreadable => '선택한 키 또는 인증서를 읽을 수 없습니다.';

  @override
  String get appSigKeylessDescription =>
      '가장 간편합니다. 이메일로 본인임을 확인한 후 신뢰할 수 있는 타임스탬프와 함께 대신 서명해 드립니다. 설치나 설정이 필요 없습니다.';

  @override
  String get appSigKeylessIdentity => '키리스 ID';

  @override
  String get appSigKeylessSignInExpired => '키리스 로그인이 만료되었습니다. 다시 로그인하세요.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return '키리스 로그인 실패: $failure';
  }

  @override
  String get appSigKeylessSubtitle => '키리스 · 타임스탬프됨 · 유효성 알 수 없음';

  @override
  String get appSigKeylessWebNote =>
      '이메일로 로그인하는 것이 가장 간편한 방법이며, DartPDF 데스크톱 및 모바일 앱에서 사용할 수 있습니다. 보안상의 이유로 웹 브라우저에서는 실행할 수 없습니다.';

  @override
  String get appSigLocation => '위치';

  @override
  String get appSigLogoAdded => '로고 추가됨 ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return '$start–$end페이지';
  }

  @override
  String get appSigPreviewNote => '미리 보기 - 실제 서명된 상자는 약간 다를 수 있습니다.';

  @override
  String get appSigReason => '사유';

  @override
  String appSigReasonLine(String reason) {
    return '사유: $reason';
  }

  @override
  String get appSigRefreshingSignIn => '로그인 갱신 중…';

  @override
  String get appSigRemoveLogo => '로고 제거';

  @override
  String get appSigRemoveSignature => '서명 제거';

  @override
  String get appSigSelfSignedDescription =>
      '로그인이나 파일이 필요 없습니다. 개인 용도에 가장 적합하며, 다음에 사용할 수 있도록 이 기기에 저장됩니다. 일부 PDF 리더는 이를 \"서명됨, 유효성 알 수 없음\"으로 표시하는데, 이는 직접 만든 서명에서 정상적인 현상입니다.';

  @override
  String get appSigSelfSignedIdentity => '자체 서명 ID';

  @override
  String get appSigSelfSignedSubtitle => '자체 서명 · 유효성 알 수 없음';

  @override
  String get appSigShowSignatureOnPages => '페이지에 서명 표시';

  @override
  String get appSigSign => '서명';

  @override
  String get appSigSignInWithEmail => '이메일로 로그인';

  @override
  String get appSigSignatureAdded => '서명 추가됨 ✓';

  @override
  String appSigSignedBy(String signerName) {
    return '$signerName이(가) 디지털 서명함';
  }

  @override
  String get appSigSigner => '서명자';

  @override
  String get appSigSigningYouIn => '로그인 중…';

  @override
  String get appSigThisPageOnly => '이 페이지만';

  @override
  String get appSigUseOwnCertificate => '직접 만든 인증서 사용';

  @override
  String get appSigUseOwnCertificateSubtitle => '조직에서 발급받은 서명 인증서용';

  @override
  String get appSigX509Signer => 'X.509 서명자';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이 $count개의 PDF를 새 탭에서 열까요, 아니면 해당 페이지를 \"$title\"에 삽입할까요?',
      one: '이 PDF를 새 탭에서 열까요, 아니면 해당 페이지를 \"$title\"에 삽입할까요?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '드롭한 PDF 추가',
      one: '드롭한 PDF 추가',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => '주석 텍스트가 복사되었습니다';

  @override
  String get editorAppMenuTooltip => 'DartPDF 메뉴';

  @override
  String get editorCancelOcr => 'OCR 취소';

  @override
  String get editorClearRecentFiles => '최근 파일 지우기';

  @override
  String get editorCloseAll => '모두 닫기';

  @override
  String get editorCloseOthers => '다른 탭 닫기';

  @override
  String get editorCloseTab => '탭 닫기';

  @override
  String get editorCloseTabsToRight => '오른쪽 탭 닫기';

  @override
  String get editorCompareFailedTitle => '비교 실패';

  @override
  String editorCompareTitle(String title) {
    return '비교: $title';
  }

  @override
  String get editorCopiedToClipboard => '클립보드에 복사됨';

  @override
  String get editorCopySelectedTextTooltip => '선택한 텍스트 복사 (⌘C)';

  @override
  String get editorCopyText => '텍스트 복사';

  @override
  String editorCouldNotExport(String title) {
    return '$title을(를) 내보낼 수 없습니다';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return '스탬프를 가져올 수 없습니다: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '드롭한 PDF를 삽입할 수 없습니다',
      one: '드롭한 PDF를 삽입할 수 없습니다',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return '$title을(를) 열 수 없습니다\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => '포함된 폴더를 열 수 없습니다';

  @override
  String editorCouldNotOpenSecond(String error) {
    return '두 번째 파일을 열 수 없습니다\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return '선택한 파일을 열 수 없습니다\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return '$url을(를) 열 수 없습니다';
  }

  @override
  String editorCouldNotPrint(String title) {
    return '$title을(를) 인쇄할 수 없습니다';
  }

  @override
  String editorCouldNotReopen(String title) {
    return '$title을(를) 다시 열 수 없습니다';
  }

  @override
  String editorCouldNotSign(String error) {
    return '디지털 서명할 수 없습니다: $error';
  }

  @override
  String get editorDiscard => '버리기';

  @override
  String get editorDiscardChangesTitle => '변경 사항을 버리시겠습니까?';

  @override
  String get editorDocumentSigned => '문서에 디지털 서명함';

  @override
  String get editorDownload => '다운로드';

  @override
  String get editorDropToOpen => 'PDF를 드롭하여 열기';

  @override
  String get editorDropToOpenOrInsert => 'PDF를 드롭하여 열거나 삽입';

  @override
  String get editorInsertPages => '페이지 삽입';

  @override
  String editorInsertedButFailed(int count, String files) {
    return '$count개 삽입됨; $files을(를) 읽을 수 없음';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개의 PDF를 $title에 삽입함',
      one: '$title에 페이지 삽입됨',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return '잘못된 링크: $uri';
  }

  @override
  String get editorJavaScriptIgnored => '이 문서가 JavaScript를 실행하려고 했습니다(무시됨)';

  @override
  String get editorLoadingFullDocument => '전체 문서 로드 중';

  @override
  String get editorMenuCompareWith => '다음과 비교…';

  @override
  String get editorMenuDigitallySign => '디지털 서명…';

  @override
  String get editorMenuDigitallySigning => '디지털 서명 중…';

  @override
  String get editorMenuExportImage => '페이지를 이미지로 내보내기…';

  @override
  String get editorMenuNewDocument => '새 문서…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'PDF 열기…';

  @override
  String get editorMenuPrint => '인쇄…';

  @override
  String get editorMenuSaveAs => '다른 이름으로 저장…';

  @override
  String get editorMenuScanDocument => '새 문서로 스캔…';

  @override
  String get editorMenuInsertScan => '스캔 삽입…';

  @override
  String get editorScanFailed => '문서를 스캔할 수 없습니다.';

  @override
  String get editorInsertedScan => '스캔한 페이지를 삽입했습니다.';

  @override
  String get editorMenuSettings => '설정';

  @override
  String get editorMenuSwitchToEdit => '편집 모드로 전환';

  @override
  String get editorMenuSwitchToReadOnly => '읽기 전용으로 전환';

  @override
  String editorNamedAction(String name) {
    return '명명된 작업: $name';
  }

  @override
  String get editorNoRecentFiles => '최근 파일 없음';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'OCR을 실행하기 전에 문서를 여세요';

  @override
  String get editorOpenFailedTitle => '열기 실패';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '새 탭에서 열기',
      one: '새 탭에서 열기',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => '새 탭에서 PDF 열기';

  @override
  String get editorOpenRecent => '최근 항목 열기';

  @override
  String get editorOpenTabs => '열린 탭';

  @override
  String get editorOpeningDocumentSemantic => '문서 여는 중';

  @override
  String get editorOpeningPdf => 'PDF 여는 중…';

  @override
  String editorOpeningTitle(String title) {
    return '$title 여는 중…';
  }

  @override
  String editorPageNumber(int number) {
    return '$number페이지';
  }

  @override
  String get editorPreviewComparison => '비교';

  @override
  String get editorPreviewCouldNotOpen => '열 수 없음';

  @override
  String get editorPreviewOpening => '여는 중';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => '서명이 제거되었습니다';

  @override
  String get editorSnapshotCopied => '스냅샷이 클립보드에 복사됨';

  @override
  String get editorSnapshotCopyFailed => '스냅샷을 클립보드에 복사할 수 없습니다';

  @override
  String get editorTabs => '탭';

  @override
  String editorTabsOpenCount(int count) {
    return '$count개 열림';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 문서에 저장되지 않은 변경 사항이 있습니다.',
      one: '한 문서에 저장되지 않은 변경 사항이 있습니다.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return '지원되지 않는 작업: $type';
  }

  @override
  String get editorUntitled => '제목 없음';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version을(를) 사용할 수 있습니다.';
  }

  @override
  String get editorUpdateLater => '나중에';

  @override
  String get editorViewAllTabs => '모든 탭 보기';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => '내보내기';

  @override
  String get imgExportFormat => '형식';

  @override
  String get imgExportResolution => '해상도';

  @override
  String get imgExportTitle => '페이지를 이미지로 내보내기';

  @override
  String get newDocCreate => '만들기';

  @override
  String get newDocLandscape => '가로';

  @override
  String get newDocOrientation => '방향';

  @override
  String get newDocPageSize => '페이지 크기';

  @override
  String get newDocPortrait => '세로';

  @override
  String get newDocTitle => '새 문서';

  @override
  String get none => '없음';

  @override
  String get ocrAlreadyRunning => 'OCR이 이미 실행 중입니다 - 완료될 때까지 기다리거나 취소하세요';

  @override
  String get ocrBrowserInitFailed => '브라우저 OCR 초기화에 실패했습니다';

  @override
  String get ocrCancelled => 'OCR이 취소되었습니다';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '텍스트 스팬 $count개 후 OCR 취소됨',
      one: '텍스트 스팬 1개 후 OCR 취소됨',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => '다운로드';

  @override
  String ocrDownloadFailed(String error) {
    return 'OCR 모델을 다운로드할 수 없습니다: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return '선택 가능한 텍스트 레이어를 추가하려면 온디바이스 OCR 모델$size이 필요합니다. 한 번 다운로드하면 이후에는 오프라인으로 실행됩니다.\n\n모델: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'OCR 모델을 다운로드하시겠습니까?';

  @override
  String ocrFailed(String error) {
    return 'OCR 실패: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable => '이 플랫폼에서는 온디바이스 OCR을 사용할 수 없습니다';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR이 텍스트 스팬 $count개를 추가했습니다 - 이제 페이지 텍스트를 선택할 수 있습니다',
      one: 'OCR이 텍스트 스팬 1개를 추가했습니다 - 이제 페이지 텍스트를 선택할 수 있습니다',
      zero: '이 페이지에서 OCR이 텍스트를 찾지 못했습니다',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      '웹 OCR은 Florence-2 비전-언어 모델을 다운로드하여 Transformers.js를 통해 WebGPU/WASM으로 로컬에서 실행합니다. PDF 페이지는 이 브라우저에 그대로 유지되며, 처음 사용할 때 모델 파일만 가져옵니다.';

  @override
  String get ocrWebPromptTitle => '이 브라우저에서 AI OCR을 실행하시겠습니까?';

  @override
  String get ocrWebStart => 'OCR 시작';

  @override
  String get ok => '확인';

  @override
  String get paste => '붙여넣기';

  @override
  String get printDlgPreparing => '준비 중…';

  @override
  String printDlgRendering(int rendered, int total) {
    return '$total페이지 중 $rendered페이지 렌더링 중…';
  }

  @override
  String get printDlgTitle => '인쇄 중';

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
  String get settingsAbout => '정보';

  @override
  String get settingsAppearance => '모양';

  @override
  String get settingsCheckNow => '지금 확인';

  @override
  String get settingsLanguage => '언어';

  @override
  String get settingsLanguageSystem => '시스템 기본값';

  @override
  String get settingsCheckingForUpdates => '업데이트 확인 중…';

  @override
  String get settingsCouldNotOpenDownload => '다운로드를 열 수 없습니다';

  @override
  String get settingsCouldNotOpenSystemSettings => '시스템 설정을 열 수 없습니다';

  @override
  String get settingsDeveloperTools => '개발자 도구';

  @override
  String get settingsDeveloperToolsSubtitle => '메트릭, 로그, 렌더링 모드 (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return '$version 다운로드';
  }

  @override
  String get settingsOpenSettings => '설정 열기';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 기억됨',
      one: '1개 기억됨',
      zero: '최근 파일 없음',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => '최근 파일';

  @override
  String get settingsSetUpAsDefault => '기본 애플리케이션으로 설정';

  @override
  String get settingsSystem => '시스템';

  @override
  String get settingsThemeDark => '어둡게';

  @override
  String get settingsThemeLight => '밝게';

  @override
  String get settingsThemeSystem => '시스템';

  @override
  String get settingsTitle => '설정';

  @override
  String settingsUpToDate(String version) {
    return '최신 버전($version)을 사용 중입니다.';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return '버전 $version을(를) 사용할 수 있습니다(현재 $currentVersion).';
  }

  @override
  String get settingsUpdateFailed => '업데이트를 확인할 수 없습니다. 나중에 다시 시도하세요.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return '$name $version을(를) 사용 중입니다.';
  }

  @override
  String get settingsUpdates => '업데이트';

  @override
  String get settingsViewSource => 'GitHub에서 소스 보기';

  @override
  String get undo => '실행 취소';

  @override
  String get welcomeOpenPdf => 'PDF 열기';

  @override
  String get welcomePickAgainToReopen => '다시 열려면 다시 선택하세요';

  @override
  String get welcomeRecent => '최근';

  @override
  String get welcomeRemoveFromRecent => '최근 항목에서 제거';

  @override
  String get welcomeTapToReopen => '탭하여 다시 열기';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': '웹 앱을 설치한 후 PDF 파일용으로 선택하세요.',
        'windows': 'Windows 기본 앱 설정에서 PDF를 여세요.',
        'macos': 'Finder의 “항상 다음으로 열기” 단계를 따르세요.',
        'linux': '데스크톱의 기본 애플리케이션 설정을 사용하세요.',
        'android': 'PDF를 열 때 DartPDF를 선택한 후 항상을 탭하세요.',
        'ios': '파일 앱에서 공유 또는 다음으로 열기를 사용해 PDF를 여기로 보내세요.',
        'other': '시스템의 PDF 파일 핸들러를 구성하세요.',
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
            '먼저 브라우저에서 DartPDF를 설치하세요. 그런 다음 브라우저 또는 운영 체제 파일 핸들러 설정을 사용하여 PDF 파일을 설치된 앱과 연결하세요.',
        'windows':
            'Windows 설정이 기본 앱으로 열립니다. “.pdf” 또는 “PDF”를 검색하고 현재 PDF 앱을 선택한 후 DartPDF를 선택하세요.',
        'macos':
            'Finder에서 아무 PDF나 선택하고 파일 > 정보 가져오기를 선택한 후 “다음으로 열기”를 펼치고 DartPDF를 선택한 다음 “모두 변경…”을 클릭하세요.',
        'linux':
            '데스크톱 설정에서 기본 애플리케이션을 열거나, 파일 앱에서 PDF를 마우스 오른쪽 버튼으로 클릭하고 속성을 선택한 후 DartPDF를 PDF 문서의 기본값으로 설정하세요.',
        'android':
            '파일 또는 다운로드에서 PDF를 열고 앱 선택기에서 DartPDF를 선택한 후 항상을 선택하세요. 다른 앱이 이미 PDF를 연다면 먼저 Android 설정에서 해당 앱의 기본값을 지우세요.',
        'ios':
            'iOS는 전역 기본 PDF 편집기를 제공하지 않습니다. 파일 > 공유를 사용하거나 PDF를 길게 눌러 공유/다음으로 열기를 선택한 후 DartPDF를 선택하세요.',
        'other': '시스템 파일 핸들러 설정을 사용하여 PDF 문서를 DartPDF와 연결하세요.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'OCR 모델 다운로드 중…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return '모델 다운로드 중 $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'OCR 마무리 중…';

  @override
  String get fileTypePdf => 'PDF 문서';

  @override
  String get fileTypeImages => '이미지';

  @override
  String get fileTypeStampBundle => 'DartPDF 스탬프';

  @override
  String get appSigKeyFileType => 'RSA 개인 키';

  @override
  String get appSigCertificateFileType => 'X.509 인증서';

  @override
  String get appSigErrorNoCertificateSelected => 'X.509 인증서를 하나 이상 선택하세요.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return '인증서 $index은(는) 유효한 X.509가 아닙니다.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      '개인 키가 선택한 어떤 RSA 인증서와도 일치하지 않습니다.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      '암호화된 개인 키는 지원되지 않습니다. 암호화되지 않은 RSA PKCS#1 또는 PKCS#8 키를 선택하세요.';

  @override
  String get appSigErrorKeyNotRsa =>
      '개인 키가 암호화되지 않은 RSA PKCS#1 또는 PKCS#8 키가 아닙니다.';

  @override
  String get appSigErrorNoCertificateFound => 'X.509 인증서를 찾을 수 없습니다.';
}
