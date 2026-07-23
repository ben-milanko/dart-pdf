// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get add => 'Додати';

  @override
  String get appSigAddLogo => 'Додати логотип…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Усі сторінки ($pageCount)';
  }

  @override
  String get appSigAppearance => 'Вигляд';

  @override
  String get appSigAppearanceDescription =>
      'Підпис малюється там, де ви його розмістили. Ім’я та дані підписувача завжди показуються; ви можете додати намальований від руки знак і тло-логотип.';

  @override
  String appSigApplyTo(String label) {
    return 'Застосувати до: $label';
  }

  @override
  String get appSigApplyToPages => 'Застосувати до сторінок…';

  @override
  String get appSigChooseCertificate => 'Вибрати файл сертифіката…';

  @override
  String get appSigChooseKeyDescription =>
      'Виберіть свій приватний ключ (RSA, PEM або DER) та його файл сертифіката. Ключ використовується лише для підписування й ніколи не зберігається.';

  @override
  String get appSigChoosePngOrJpeg => 'Виберіть зображення PNG або JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Вибрати приватний ключ…';

  @override
  String get appSigContactInfo => 'Контактні дані';

  @override
  String get appSigCouldNotCaptureSignature => 'Не вдалося захопити підпис.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Не вдалося прочитати сертифікат: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Не вдалося прочитати ключ: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Створити підпис на цьому пристрої';

  @override
  String appSigDate(String date) {
    return 'Дата: $date';
  }

  @override
  String get appSigDigitallySign => 'Цифровий підпис';

  @override
  String get appSigDrawSignature => 'Намалювати підпис…';

  @override
  String get appSigFieldHelper =>
      'Залиште порожнім, щоб створити нове поле підпису.';

  @override
  String get appSigFieldLabel => 'Наявне поле підпису (необов’язково)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сертифіката',
      many: '$count сертифікатів',
      few: '$count сертифікати',
      one: '1 сертифікат',
    );
    return '$_temp0 · дійсний з $validFrom до $validUntil';
  }

  @override
  String get appSigIntro =>
      'Цифровий підпис підтверджує, що ви підписали цей документ і що його не змінювали відтоді. Виберіть, як ви хочете підписати.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Не вдалося прочитати вибраний ключ або сертифікат.';

  @override
  String get appSigKeylessDescription =>
      'Найпростіше. Ми підтверджуємо вашу особу електронною поштою й підписуємо за вас із довіреною позначкою часу. Нічого встановлювати чи налаштовувати не потрібно.';

  @override
  String get appSigKeylessIdentity => 'Особа без ключа';

  @override
  String get appSigKeylessSignInExpired =>
      'Термін вашого входу без ключа минув. Будь ласка, увійдіть знову.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Помилка входу без ключа: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Без ключа · з позначкою часу · дійсність невідома';

  @override
  String get appSigKeylessWebNote =>
      'Вхід за електронною поштою — найпростіший спосіб, він доступний у застосунках DartPDF для комп’ютера й мобільних пристроїв. З міркувань безпеки він не може працювати у веб-браузері.';

  @override
  String get appSigLocation => 'Місце';

  @override
  String get appSigLogoAdded => 'Логотип додано ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Сторінки $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Попередній перегляд — підписаний блок може дещо відрізнятися.';

  @override
  String get appSigReason => 'Причина';

  @override
  String appSigReasonLine(String reason) {
    return 'Причина: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Оновлення входу…';

  @override
  String get appSigRemoveLogo => 'Вилучити логотип';

  @override
  String get appSigRemoveSignature => 'Вилучити підпис';

  @override
  String get appSigSelfSignedDescription =>
      'Не потрібні вхід чи файли. Найкраще для особистого використання — зберігається на цьому пристрої для наступного разу. Деякі програми для читання PDF показуватимуть його як «підписано, дійсність невідома», що є нормальним для підпису, який ви створюєте самостійно.';

  @override
  String get appSigSelfSignedIdentity => 'Самопідписана особа';

  @override
  String get appSigSelfSignedSubtitle => 'Самопідписано · дійсність невідома';

  @override
  String get appSigShowSignatureOnPages => 'Показувати підпис на сторінках';

  @override
  String get appSigSign => 'Підписати';

  @override
  String get appSigSignInWithEmail => 'Увійти за електронною поштою';

  @override
  String get appSigSignatureAdded => 'Підпис додано ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Цифровий підпис від $signerName';
  }

  @override
  String get appSigSigner => 'Підписувач';

  @override
  String get appSigSigningYouIn => 'Виконується вхід…';

  @override
  String get appSigThisPageOnly => 'Лише ця сторінка';

  @override
  String get appSigUseOwnCertificate => 'Використати власний сертифікат';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Для сертифіката підписування від вашої організації';

  @override
  String get appSigX509Signer => 'Підписувач X.509';

  @override
  String get apply => 'Застосувати';

  @override
  String get cancel => 'Скасувати';

  @override
  String get clear => 'Очистити';

  @override
  String get close => 'Закрити';

  @override
  String get copy => 'Копіювати';

  @override
  String get cut => 'Вирізати';

  @override
  String get delete => 'Видалити';

  @override
  String get done => 'Готово';

  @override
  String get edit => 'Редагувати';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Відкрити ці $count PDF-файлів у новій вкладці чи вставити їхні сторінки в «$title»?',
      one:
          'Відкрити цей PDF у новій вкладці чи вставити його сторінки в «$title»?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Додати перетягнуті PDF',
      one: 'Додати перетягнутий PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Текст анотації скопійовано';

  @override
  String get editorAppMenuTooltip => 'Меню DartPDF';

  @override
  String get editorCancelOcr => 'Скасувати OCR';

  @override
  String get editorClearRecentFiles => 'Очистити нещодавні файли';

  @override
  String get editorCloseAll => 'Закрити всі';

  @override
  String get editorCloseOthers => 'Закрити інші';

  @override
  String get editorCloseTab => 'Закрити вкладку';

  @override
  String get editorCloseTabsToRight => 'Закрити вкладки праворуч';

  @override
  String get editorCompareFailedTitle => 'Помилка порівняння';

  @override
  String editorCompareTitle(String title) {
    return 'Порівняння: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Скопійовано в буфер обміну';

  @override
  String get editorCopySelectedTextTooltip => 'Копіювати виділений текст (⌘C)';

  @override
  String get editorCopyText => 'Копіювати текст';

  @override
  String editorCouldNotExport(String title) {
    return 'Не вдалося експортувати $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Не вдалося імпортувати штампи: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не вдалося вставити перетягнуті PDF',
      one: 'Не вдалося вставити перетягнутий PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Не вдалося відкрити $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Не вдалося відкрити теку, що містить файл';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Не вдалося відкрити другий файл\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Не вдалося відкрити вибраний файл\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Не вдалося відкрити $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Не вдалося надрукувати $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Не вдалося повторно відкрити $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Не вдалося поставити цифровий підпис: $error';
  }

  @override
  String get editorDiscard => 'Відхилити';

  @override
  String get editorDiscardChangesTitle => 'Відхилити зміни?';

  @override
  String get editorDocumentSigned => 'Документ підписано цифровим підписом';

  @override
  String get editorDownload => 'Завантажити';

  @override
  String get editorDropToOpen => 'Перетягніть PDF, щоб відкрити';

  @override
  String get editorDropToOpenOrInsert =>
      'Перетягніть PDF, щоб відкрити або вставити';

  @override
  String get editorInsertPages => 'Вставити сторінки';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Вставлено $count; не вдалося прочитати $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF-файлів вставлено в $title',
      one: 'Сторінки вставлено в $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Недійсне посилання: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Цей документ намагався виконати JavaScript (проігноровано)';

  @override
  String get editorLoadingFullDocument => 'Завантаження повного документа';

  @override
  String get editorMenuCompareWith => 'Порівняти з…';

  @override
  String get editorMenuDigitallySign => 'Поставити цифровий підпис…';

  @override
  String get editorMenuDigitallySigning => 'Цифрове підписування…';

  @override
  String get editorMenuExportImage => 'Експортувати сторінку як зображення…';

  @override
  String get editorMenuNewDocument => 'Новий документ…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Відкрити PDF…';

  @override
  String get editorMenuPrint => 'Друк…';

  @override
  String get editorMenuSaveAs => 'Зберегти як…';

  @override
  String get editorMenuScanDocument => 'Scan to new document…';

  @override
  String get editorMenuInsertScan => 'Insert scan…';

  @override
  String get editorScanFailed => 'Couldn\'t scan the document.';

  @override
  String get editorInsertedScan => 'Inserted scanned pages.';

  @override
  String get editorMenuSettings => 'Налаштування';

  @override
  String get editorMenuSwitchToEdit => 'Перейти в режим редагування';

  @override
  String get editorMenuSwitchToReadOnly => 'Перейти в режим лише для читання';

  @override
  String editorNamedAction(String name) {
    return 'Іменована дія: $name';
  }

  @override
  String get editorNoRecentFiles => 'Немає нещодавніх файлів';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Відкрийте документ перед запуском OCR';

  @override
  String get editorOpenFailedTitle => 'Помилка відкриття';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Відкрити в нових вкладках',
      one: 'Відкрити в новій вкладці',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Відкрити PDF у новій вкладці';

  @override
  String get editorOpenRecent => 'Відкрити нещодавні';

  @override
  String get editorOpenTabs => 'Відкриті вкладки';

  @override
  String get editorOpeningDocumentSemantic => 'Відкриття документа';

  @override
  String get editorOpeningPdf => 'Відкриття PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Відкриття $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Сторінка $number';
  }

  @override
  String get editorPreviewComparison => 'Порівняння';

  @override
  String get editorPreviewCouldNotOpen => 'Не вдалося відкрити';

  @override
  String get editorPreviewOpening => 'Відкриття';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Підпис вилучено';

  @override
  String get editorSnapshotCopied => 'Знімок скопійовано в буфер обміну';

  @override
  String get editorSnapshotCopyFailed =>
      'Не вдалося скопіювати знімок у буфер обміну';

  @override
  String get editorTabs => 'Вкладки';

  @override
  String editorTabsOpenCount(int count) {
    return '$count відкрито';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count документа мають незбережені зміни.',
      many: '$count документів мають незбережені зміни.',
      few: '$count документи мають незбережені зміни.',
      one: 'Документ має незбережені зміни.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Непідтримувана дія: $type';
  }

  @override
  String get editorUntitled => 'Без назви';

  @override
  String editorUpdateAvailable(String version) {
    return 'Доступна версія DartPDF $version.';
  }

  @override
  String get editorUpdateLater => 'Пізніше';

  @override
  String get editorViewAllTabs => 'Переглянути всі вкладки';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Експортувати';

  @override
  String get imgExportFormat => 'Формат';

  @override
  String get imgExportResolution => 'Роздільна здатність';

  @override
  String get imgExportTitle => 'Експортувати сторінку як зображення';

  @override
  String get newDocCreate => 'Створити';

  @override
  String get newDocLandscape => 'Альбомна';

  @override
  String get newDocOrientation => 'Орієнтація';

  @override
  String get newDocPageSize => 'Розмір сторінки';

  @override
  String get newDocPortrait => 'Книжкова';

  @override
  String get newDocTitle => 'Новий документ';

  @override
  String get none => 'Немає';

  @override
  String get ocrAlreadyRunning =>
      'OCR уже виконується — зачекайте на завершення або скасуйте';

  @override
  String get ocrBrowserInitFailed => 'Не вдалося ініціалізувати OCR у браузері';

  @override
  String get ocrCancelled => 'OCR скасовано';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR скасовано після $count текстового фрагмента',
      many: 'OCR скасовано після $count текстових фрагментів',
      few: 'OCR скасовано після $count текстових фрагментів',
      one: 'OCR скасовано після 1 текстового фрагмента',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Завантажити';

  @override
  String ocrDownloadFailed(String error) {
    return 'Не вдалося завантажити модель OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Для додавання виділюваного текстового шару потрібна вбудована модель OCR$size. Вона завантажується один раз і потім працює офлайн.\n\nМодель: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Завантажити модель OCR?';

  @override
  String ocrFailed(String error) {
    return 'Помилка OCR: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb МБ)';
  }

  @override
  String get ocrNotAvailable => 'Вбудований OCR недоступний на цій платформі';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR додав $count текстового фрагмента — текст сторінки тепер можна виділяти',
      many:
          'OCR додав $count текстових фрагментів — текст сторінки тепер можна виділяти',
      few:
          'OCR додав $count текстові фрагменти — текст сторінки тепер можна виділяти',
      one:
          'OCR додав 1 текстовий фрагмент — текст сторінки тепер можна виділяти',
      zero: 'OCR не знайшов тексту на цих сторінках',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Веб-OCR завантажує модель «зображення-мова» Florence-2 і запускає її локально за допомогою WebGPU/WASM через Transformers.js. Сторінки PDF залишаються в цьому браузері; лише файли моделі завантажуються під час першого використання.';

  @override
  String get ocrWebPromptTitle =>
      'Запустити OCR зі штучним інтелектом у цьому браузері?';

  @override
  String get ocrWebStart => 'Запустити OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Вставити';

  @override
  String get printDlgPreparing => 'Підготовка…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Обробка сторінки $rendered з $total…';
  }

  @override
  String get printDlgTitle => 'Друк';

  @override
  String get redo => 'Повторити';

  @override
  String get remove => 'Вилучити';

  @override
  String get rename => 'Перейменувати';

  @override
  String get reset => 'Скинути';

  @override
  String get save => 'Зберегти';

  @override
  String get settingsAbout => 'Про програму';

  @override
  String get settingsAppearance => 'Вигляд';

  @override
  String get settingsCheckNow => 'Перевірити зараз';

  @override
  String get settingsLanguage => 'Мова';

  @override
  String get settingsLanguageSystem => 'Системна за замовчуванням';

  @override
  String get settingsCheckingForUpdates => 'Перевірка оновлень…';

  @override
  String get settingsCouldNotOpenDownload => 'Не вдалося відкрити завантаження';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Не вдалося відкрити системні налаштування';

  @override
  String get settingsDeveloperTools => 'Інструменти розробника';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Метрики, журнали, режими рендерингу (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Завантажити $version';
  }

  @override
  String get settingsOpenSettings => 'Відкрити налаштування';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count запам’ятано',
      many: '$count запам’ятано',
      few: '$count запам’ятано',
      one: '1 запам’ятано',
      zero: 'Немає нещодавніх файлів',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Нещодавні файли';

  @override
  String get settingsSetUpAsDefault =>
      'Налаштувати як застосунок за замовчуванням';

  @override
  String get settingsSystem => 'Система';

  @override
  String get settingsThemeDark => 'Темна';

  @override
  String get settingsThemeLight => 'Світла';

  @override
  String get settingsThemeSystem => 'Системна';

  @override
  String get settingsTitle => 'Налаштування';

  @override
  String settingsUpToDate(String version) {
    return 'У вас найновіша версія ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Доступна версія $version (у вас $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Не вдалося перевірити оновлення. Спробуйте пізніше.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'У вас $name $version.';
  }

  @override
  String get settingsUpdates => 'Оновлення';

  @override
  String get settingsViewSource => 'Переглянути код на GitHub';

  @override
  String get undo => 'Відмінити';

  @override
  String get welcomeOpenPdf => 'Відкрити PDF';

  @override
  String get welcomePickAgainToReopen =>
      'Виберіть знову, щоб повторно відкрити';

  @override
  String get welcomeRecent => 'Нещодавні';

  @override
  String get welcomeRemoveFromRecent => 'Вилучити з нещодавніх';

  @override
  String get welcomeTapToReopen => 'Торкніться, щоб повторно відкрити';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Установіть веб-застосунок, потім виберіть його для файлів PDF.',
        'windows':
            'Відкрийте налаштування застосунків за замовчуванням Windows для PDF.',
        'macos': 'Виконайте кроки «Завжди відкривати за допомогою» у Finder.',
        'linux':
            'Скористайтеся налаштуваннями застосунків за замовчуванням вашого середовища.',
        'android':
            'Виберіть DartPDF під час відкриття PDF, потім торкніться «Завжди».',
        'ios':
            'Скористайтеся «Поділитися» або «Відкрити в» з «Файлів», щоб надіслати PDF сюди.',
        'other': 'Налаштуйте обробник файлів PDF у вашій системі.',
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
            'Спершу встановіть DartPDF зі свого браузера. Потім скористайтеся налаштуваннями обробника файлів браузера чи операційної системи, щоб пов’язати файли PDF зі встановленим застосунком.',
        'windows':
            'Налаштування Windows відкриються на «Застосунки за замовчуванням». Знайдіть «.pdf» або «PDF», виберіть поточний застосунок для PDF, а потім виберіть DartPDF.',
        'macos':
            'У Finder виберіть будь-який PDF, оберіть «Файл > Отримати інформацію», розгорніть «Відкривати за допомогою», виберіть DartPDF, потім натисніть «Змінити всі…».',
        'linux':
            'Відкрийте налаштування середовища для застосунків за замовчуванням або клацніть PDF у «Файлах» правою кнопкою, оберіть «Властивості» й установіть DartPDF як типовий для документів PDF.',
        'android':
            'Відкрийте PDF із «Файлів» чи «Завантажень», виберіть DartPDF у виборі застосунку, потім оберіть «Завжди». Якщо PDF уже відкриває інший застосунок, спершу очистіть його типові значення в налаштуваннях Android.',
        'ios':
            'iOS не надає глобального типового редактора PDF. Скористайтеся «Файли > Поділитися» або натисніть і утримуйте PDF та виберіть «Поділитися»/«Відкрити в», потім виберіть DartPDF.',
        'other':
            'Скористайтеся системними налаштуваннями обробників файлів, щоб пов’язати документи PDF із DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Завантаження моделі OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Завантаження моделі $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Завершення OCR…';

  @override
  String get fileTypePdf => 'Документи PDF';

  @override
  String get fileTypeImages => 'Зображення';

  @override
  String get fileTypeStampBundle => 'Штампи DartPDF';

  @override
  String get appSigKeyFileType => 'Приватні ключі RSA';

  @override
  String get appSigCertificateFileType => 'Сертифікати X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Виберіть принаймні один сертифікат X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Сертифікат $index не є дійсним X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Приватний ключ не відповідає жодному вибраному сертифікату RSA.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Зашифровані приватні ключі не підтримуються. Виберіть незашифрований ключ RSA PKCS#1 або PKCS#8.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Приватний ключ не є незашифрованим ключем RSA PKCS#1 або PKCS#8.';

  @override
  String get appSigErrorNoCertificateFound => 'Сертифікатів X.509 не знайдено.';
}
