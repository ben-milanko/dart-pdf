// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get add => 'Добавить';

  @override
  String get appSigAddLogo => 'Добавить логотип…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Все $pageCount страниц';
  }

  @override
  String get appSigAppearance => 'Внешний вид';

  @override
  String get appSigAppearanceDescription =>
      'Подпись размещается там, где вы её поставили. Имя подписавшего и данные показываются всегда; вы можете добавить рукописную отметку и фоновый логотип.';

  @override
  String appSigApplyTo(String label) {
    return 'Применить к: $label';
  }

  @override
  String get appSigApplyToPages => 'Применить к страницам…';

  @override
  String get appSigChooseCertificate => 'Выбрать файл сертификата…';

  @override
  String get appSigChooseKeyDescription =>
      'Выберите свой закрытый ключ (RSA, PEM или DER) и файл сертификата. Ключ используется только для подписи и никогда не сохраняется.';

  @override
  String get appSigChoosePngOrJpeg => 'Выберите изображение PNG или JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Выбрать закрытый ключ…';

  @override
  String get appSigContactInfo => 'Контактная информация';

  @override
  String get appSigCouldNotCaptureSignature => 'Не удалось получить подпись.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Не удалось прочитать сертификат: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Не удалось прочитать ключ: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Создать подпись на этом устройстве';

  @override
  String appSigDate(String date) {
    return 'Дата: $date';
  }

  @override
  String get appSigDigitallySign => 'Поставить цифровую подпись';

  @override
  String get appSigDrawSignature => 'Нарисовать подпись…';

  @override
  String get appSigFieldHelper =>
      'Оставьте пустым, чтобы создать новое поле подписи.';

  @override
  String get appSigFieldLabel => 'Существующее поле подписи (необязательно)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сертификата',
      many: '$count сертификатов',
      few: '$count сертификата',
      one: '1 сертификат',
    );
    return '$_temp0 · действует с $validFrom по $validUntil';
  }

  @override
  String get appSigIntro =>
      'Цифровая подпись подтверждает, что вы подписали этот документ и что он не изменялся с тех пор. Выберите, как вы хотите подписать.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Не удалось прочитать выбранный ключ или сертификат.';

  @override
  String get appSigKeylessDescription =>
      'Проще всего. Мы подтверждаем вашу личность по электронной почте и подписываем за вас с доверенной меткой времени. Ничего не нужно устанавливать или настраивать.';

  @override
  String get appSigKeylessIdentity => 'Личность без ключа';

  @override
  String get appSigKeylessSignInExpired =>
      'Срок вашего входа без ключа истёк. Пожалуйста, войдите снова.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Не удалось выполнить вход без ключа: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Без ключа · с меткой времени · достоверность неизвестна';

  @override
  String get appSigKeylessWebNote =>
      'Вход по электронной почте — самый простой способ; он доступен в настольных и мобильных приложениях DartPDF. По соображениям безопасности он не работает в веб-браузере.';

  @override
  String get appSigLocation => 'Местоположение';

  @override
  String get appSigLogoAdded => 'Логотип добавлен ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Страницы $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Предварительный просмотр — подписанное поле может немного отличаться.';

  @override
  String get appSigReason => 'Причина';

  @override
  String appSigReasonLine(String reason) {
    return 'Причина: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Обновление входа…';

  @override
  String get appSigRemoveLogo => 'Удалить логотип';

  @override
  String get appSigRemoveSignature => 'Удалить подпись';

  @override
  String get appSigSelfSignedDescription =>
      'Не требуется вход или файлы. Лучше всего для личного использования — сохраняется на этом устройстве на будущее. Некоторые программы для чтения PDF покажут её как «подписано, достоверность неизвестна», что нормально для подписи, которую вы создаёте сами.';

  @override
  String get appSigSelfSignedIdentity => 'Самоподписанная личность';

  @override
  String get appSigSelfSignedSubtitle =>
      'Самоподписанная · достоверность неизвестна';

  @override
  String get appSigShowSignatureOnPages => 'Показывать подпись на страницах';

  @override
  String get appSigSign => 'Подписать';

  @override
  String get appSigSignInWithEmail => 'Войти по электронной почте';

  @override
  String get appSigSignatureAdded => 'Подпись добавлена ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Цифровая подпись: $signerName';
  }

  @override
  String get appSigSigner => 'Подписавший';

  @override
  String get appSigSigningYouIn => 'Выполняется вход…';

  @override
  String get appSigThisPageOnly => 'Только эта страница';

  @override
  String get appSigUseOwnCertificate => 'Использовать свой сертификат';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Для сертификата подписи от вашей организации';

  @override
  String get appSigX509Signer => 'Подписавший X.509';

  @override
  String get apply => 'Применить';

  @override
  String get cancel => 'Отмена';

  @override
  String get clear => 'Очистить';

  @override
  String get close => 'Закрыть';

  @override
  String get copy => 'Копировать';

  @override
  String get cut => 'Вырезать';

  @override
  String get delete => 'Удалить';

  @override
  String get done => 'Готово';

  @override
  String get edit => 'Изменить';

  @override
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Открыть эти $count PDF в новой вкладке или вставить их страницы в «$title»?',
      one:
          'Открыть этот PDF в новой вкладке или вставить его страницы в «$title»?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавить перетащенные PDF',
      one: 'Добавить перетащенный PDF',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Текст аннотации скопирован';

  @override
  String get editorAppMenuTooltip => 'Меню DartPDF';

  @override
  String get editorCancelOcr => 'Отменить OCR';

  @override
  String get editorClearRecentFiles => 'Очистить недавние файлы';

  @override
  String get editorCloseAll => 'Закрыть все';

  @override
  String get editorCloseOthers => 'Закрыть другие';

  @override
  String get editorCloseTab => 'Закрыть вкладку';

  @override
  String get editorCloseTabsToRight => 'Закрыть вкладки справа';

  @override
  String get editorCompareFailedTitle => 'Сравнение не удалось';

  @override
  String editorCompareTitle(String title) {
    return 'Сравнение: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get editorCopySelectedTextTooltip => 'Копировать выбранный текст (⌘C)';

  @override
  String get editorCopyText => 'Копировать текст';

  @override
  String editorCouldNotExport(String title) {
    return 'Не удалось экспортировать $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Не удалось импортировать штампы: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не удалось вставить перетащенные PDF',
      one: 'Не удалось вставить перетащенный PDF',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Не удалось открыть $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder => 'Не удалось открыть содержащую папку';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Не удалось открыть второй файл\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Не удалось открыть выбранный файл\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Не удалось открыть $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Не удалось напечатать $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Не удалось повторно открыть $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Не удалось поставить цифровую подпись: $error';
  }

  @override
  String get editorDiscard => 'Отклонить';

  @override
  String get editorDiscardChangesTitle => 'Отклонить изменения?';

  @override
  String get editorDocumentSigned => 'Документ подписан цифровой подписью';

  @override
  String get editorDownload => 'Скачать';

  @override
  String get editorDropToOpen => 'Перетащите PDF, чтобы открыть';

  @override
  String get editorDropToOpenOrInsert =>
      'Перетащите PDF, чтобы открыть или вставить';

  @override
  String get editorInsertPages => 'Вставить страницы';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Вставлено $count; не удалось прочитать $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF вставлено в $title',
      one: 'Страницы вставлены в $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Недопустимая ссылка: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Этот документ пытался выполнить JavaScript (проигнорировано)';

  @override
  String get editorLoadingFullDocument => 'Загрузка полного документа';

  @override
  String get editorMenuCompareWith => 'Сравнить с…';

  @override
  String get editorMenuDigitallySign => 'Поставить цифровую подпись…';

  @override
  String get editorMenuDigitallySigning => 'Постановка цифровой подписи…';

  @override
  String get editorMenuExportImage =>
      'Экспортировать страницу как изображение…';

  @override
  String get editorMenuNewDocument => 'Новый документ…';

  @override
  String get editorMenuNewWindow => 'Новое окно';

  @override
  String get editorMoveToNewWindow => 'Переместить в новое окно';

  @override
  String get editorUnableToOpenNewWindow => 'Не удалось открыть новое окно';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Открыть PDF…';

  @override
  String get editorMenuPrint => 'Печать…';

  @override
  String get editorMenuSaveAs => 'Сохранить как…';

  @override
  String get editorMenuScanDocument => 'Сканировать в новый документ…';

  @override
  String get editorMenuInsertDocument => 'Вставить документ…';

  @override
  String get editorMenuInsertScan => 'Вставить скан…';

  @override
  String get editorScanFailed => 'Не удалось отсканировать документ.';

  @override
  String get editorInsertedScan => 'Отсканированные страницы вставлены.';

  @override
  String get editorMenuSettings => 'Настройки';

  @override
  String get editorMenuSectionFile => 'Файл';

  @override
  String get editorMenuSectionDocument => 'Этот документ';

  @override
  String get editorMenuSectionApp => 'Приложение';

  @override
  String get editorMenuReadOnly => 'Только чтение';

  @override
  String get editorMenuSearchActions => 'Поиск действий…';

  @override
  String get paletteHint => 'Поиск действий, инструментов и панелей';

  @override
  String get paletteNoMatch => 'Команды не найдены';

  @override
  String get paletteKeyHints => '↑↓ выбор · ⏎ выполнить · esc закрыть';

  @override
  String paletteCount(int count) {
    return 'Команд: $count';
  }

  @override
  String paletteCountFiltered(int count, int total) {
    return '$count из $total';
  }

  @override
  String get paletteSourceMenu => 'Меню';

  @override
  String get paletteSourcePanel => 'Панель';

  @override
  String get paletteSourceView => 'Вид';

  @override
  String get paletteSourceFile => 'Файл';

  @override
  String paletteSourceTool(String group) {
    return 'Инструмент «$group»';
  }

  @override
  String get paletteNeedsDocument => 'Нужен открытый документ';

  @override
  String editorNamedAction(String name) {
    return 'Именованное действие: $name';
  }

  @override
  String get editorNoRecentFiles => 'Нет недавних файлов';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr => 'Откройте документ перед запуском OCR';

  @override
  String get editorOpenFailedTitle => 'Не удалось открыть';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Открыть в новых вкладках',
      one: 'Открыть в новой вкладке',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Открыть PDF в новой вкладке';

  @override
  String get editorOpenRecent => 'Открыть недавние';

  @override
  String get editorViewAllRecentFiles => 'Показать все недавние файлы…';

  @override
  String get editorOpenTabs => 'Открытые вкладки';

  @override
  String get editorOpeningDocumentSemantic => 'Открытие документа';

  @override
  String get editorOpeningPdf => 'Открытие PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Открытие $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Страница $number';
  }

  @override
  String get editorPreviewComparison => 'Сравнение';

  @override
  String get editorPreviewCouldNotOpen => 'Не удалось открыть';

  @override
  String get editorPreviewOpening => 'Открытие';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Несохранённые изменения в $count документах из прошлого сеанса восстановлены.',
      one: 'Несохранённые изменения из прошлого сеанса восстановлены.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Подпись удалена';

  @override
  String get editorSnapshotCopied => 'Снимок скопирован в буфер обмена';

  @override
  String get editorSnapshotCopyFailed =>
      'Не удалось скопировать снимок в буфер обмена';

  @override
  String get editorTabs => 'Вкладки';

  @override
  String editorTabsOpenCount(int count) {
    return 'Открыто: $count';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'В $count документах есть несохранённые изменения.',
      one: 'В документе есть несохранённые изменения.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Неподдерживаемое действие: $type';
  }

  @override
  String get editorUntitled => 'Без названия';

  @override
  String editorUpdateAvailable(String version) {
    return 'Доступна версия DartPDF $version.';
  }

  @override
  String get editorUpdateLater => 'Позже';

  @override
  String get updateInstallNow => 'Обновить сейчас';

  @override
  String get updateDownloadingTitle => 'Загрузка обновления';

  @override
  String get updatePreparing => 'Подготовка…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Загрузка… $percent%';
  }

  @override
  String get updateRestarting => 'Перезапуск для завершения обновления…';

  @override
  String get updateHandedOff => 'Обновление загружено. Открытие установщика…';

  @override
  String updateFailed(String error) {
    return 'Не удалось обновить: $error';
  }

  @override
  String get editorViewAllTabs => 'Показать все вкладки';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi DPI';
  }

  @override
  String get imgExportExport => 'Экспорт';

  @override
  String get imgExportFormat => 'Формат';

  @override
  String get imgExportResolution => 'Разрешение';

  @override
  String get imgExportTitle => 'Экспортировать страницу как изображение';

  @override
  String get newDocCreate => 'Создать';

  @override
  String get newDocLandscape => 'Альбомная';

  @override
  String get newDocOrientation => 'Ориентация';

  @override
  String get newDocPageSize => 'Размер страницы';

  @override
  String get newDocPortrait => 'Книжная';

  @override
  String get newDocTitle => 'Новый документ';

  @override
  String get none => 'Нет';

  @override
  String get ocrAlreadyRunning =>
      'OCR уже выполняется — дождитесь завершения или отмените';

  @override
  String get ocrBrowserInitFailed =>
      'Не удалось инициализировать OCR в браузере';

  @override
  String get ocrCancelled => 'OCR отменён';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR отменён после $count текстовых фрагментов',
      many: 'OCR отменён после $count текстовых фрагментов',
      few: 'OCR отменён после $count текстовых фрагментов',
      one: 'OCR отменён после 1 текстового фрагмента',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Скачать';

  @override
  String ocrDownloadFailed(String error) {
    return 'Не удалось скачать модель OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Для добавления слоя выделяемого текста нужна модель OCR на устройстве$size. Она скачивается один раз и затем работает офлайн.\n\nМодель: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Скачать модель OCR?';

  @override
  String ocrFailed(String error) {
    return 'Сбой OCR: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb МБ)';
  }

  @override
  String get ocrNotAvailable =>
      'OCR на устройстве недоступен на этой платформе';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'OCR добавил $count текстовых фрагмента — текст страницы теперь можно выделять',
      many:
          'OCR добавил $count текстовых фрагментов — текст страницы теперь можно выделять',
      few:
          'OCR добавил $count текстовых фрагмента — текст страницы теперь можно выделять',
      one:
          'OCR добавил 1 текстовый фрагмент — текст страницы теперь можно выделять',
      zero: 'OCR не нашёл текста на этих страницах',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'Веб-OCR скачивает визуально-языковую модель Florence-2 и запускает её локально через WebGPU/WASM с помощью Transformers.js. Страницы PDF остаются в этом браузере; при первом использовании загружаются только файлы модели.';

  @override
  String get ocrWebPromptTitle => 'Запустить ИИ-OCR в этом браузере?';

  @override
  String get ocrWebStart => 'Запустить OCR';

  @override
  String get ok => 'ОК';

  @override
  String get paste => 'Вставить';

  @override
  String get printDlgPreparing => 'Подготовка…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Отрисовка страницы $rendered из $total…';
  }

  @override
  String get printDlgTitle => 'Печать';

  @override
  String get printPreviewAll => 'Все';

  @override
  String get printPreviewCurrent => 'Текущая';

  @override
  String get printPreviewFrom => 'С';

  @override
  String get printPreviewNextPage => 'Следующая страница';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Страница $page из $total';
  }

  @override
  String get printPreviewPreviousPage => 'Предыдущая страница';

  @override
  String get printPreviewPrint => 'Печать';

  @override
  String get printPreviewRange => 'Диапазон';

  @override
  String printPreviewRangeError(int total) {
    return 'Укажите диапазон страниц от 1 до $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Страниц для печати: $count';
  }

  @override
  String get printPreviewTitle => 'Предварительный просмотр';

  @override
  String get printPreviewTo => 'По';

  @override
  String get printPreviewUnavailable => 'Просмотр недоступен';

  @override
  String get redo => 'Повторить';

  @override
  String get remove => 'Удалить';

  @override
  String get rename => 'Переименовать';

  @override
  String get reset => 'Сбросить';

  @override
  String get save => 'Сохранить';

  @override
  String get settingsAbout => 'О программе';

  @override
  String get settingsAppearance => 'Внешний вид';

  @override
  String get settingsCheckNow => 'Проверить сейчас';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsCheckingForUpdates => 'Проверка обновлений…';

  @override
  String get settingsCouldNotOpenDownload => 'Не удалось открыть загрузку';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Не удалось открыть системные настройки';

  @override
  String get settingsDeveloperTools => 'Инструменты разработчика';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Метрики, журналы, режимы отрисовки (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Скачать $version';
  }

  @override
  String get settingsOpenSettings => 'Открыть настройки';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count запомнено',
      many: '$count запомнено',
      few: '$count запомнено',
      one: '1 запомнен',
      zero: 'Нет недавних файлов',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Недавние файлы';

  @override
  String get settingsSetUpAsDefault => 'Настроить как приложение по умолчанию';

  @override
  String get settingsSystem => 'Система';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeSystem => 'Системная';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String settingsUpToDate(String version) {
    return 'У вас установлена последняя версия ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'Доступна версия $version (у вас $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Не удалось проверить обновления. Попробуйте позже.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'У вас $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Ночные обновления';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Получайте автоматические уведомления о неподписанных тестовых сборках Windows из main.';

  @override
  String get settingsUpdates => 'Обновления';

  @override
  String get settingsViewSource => 'Посмотреть исходный код на GitHub';

  @override
  String get undo => 'Отменить';

  @override
  String get welcomeOpenPdf => 'Открыть PDF';

  @override
  String get welcomePickAgainToReopen => 'Выберите снова, чтобы открыть заново';

  @override
  String get welcomeRecent => 'Недавние';

  @override
  String get welcomeSearchRecentFiles => 'Поиск по недавним файлам';

  @override
  String get welcomeNoMatchingRecentFiles =>
      'Нет недавних файлов, соответствующих поиску';

  @override
  String get welcomeRemoveFromRecent => 'Удалить из недавних';

  @override
  String get welcomeTapToReopen => 'Коснитесь, чтобы открыть заново';

  @override
  String get welcomeViewAsGrid => 'Сетка';

  @override
  String get welcomeViewAsList => 'Список';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Установите веб-приложение, затем выберите его для файлов PDF.',
        'windows':
            'Откройте параметры приложений по умолчанию Windows для PDF.',
        'macos': 'Следуйте шагам «Всегда открывать в» в Finder.',
        'linux':
            'Используйте настройки приложений по умолчанию вашего рабочего стола.',
        'android': 'Выберите DartPDF при открытии PDF, затем нажмите «Всегда».',
        'ios':
            'Используйте «Поделиться» или «Открыть в» в приложении «Файлы», чтобы отправлять PDF сюда.',
        'other': 'Настройте обработчик файлов PDF в вашей системе.',
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
            'Сначала установите DartPDF из браузера. Затем используйте настройки обработчика файлов браузера или операционной системы, чтобы связать файлы PDF с установленным приложением.',
        'windows':
            'Откроются «Параметры Windows» в разделе «Приложения по умолчанию». Найдите «.pdf» или «PDF», выберите текущее приложение для PDF, затем выберите DartPDF.',
        'macos':
            'В Finder выберите любой PDF, откройте «Файл» > «Свойства», разверните «Открывать в программе», выберите DartPDF, затем нажмите «Изменить всё…».',
        'linux':
            'Откройте настройки рабочего стола для приложений по умолчанию или щёлкните PDF правой кнопкой в «Файлах», выберите «Свойства» и назначьте DartPDF по умолчанию для документов PDF.',
        'android':
            'Откройте PDF из «Файлов» или «Загрузок», выберите DartPDF в списке приложений, затем выберите «Всегда». Если PDF уже открывает другое приложение, сначала очистите его настройки по умолчанию в настройках Android.',
        'ios':
            'iOS не предоставляет глобального редактора PDF по умолчанию. Используйте «Файлы» > «Поделиться» или нажмите и удерживайте PDF, выберите «Поделиться»/«Открыть в», затем выберите DartPDF.',
        'other':
            'Используйте системные настройки обработчиков файлов, чтобы связать документы PDF с DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Скачивание модели OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Скачивание модели $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Завершение OCR…';

  @override
  String get fileTypePdf => 'Документы PDF';

  @override
  String get fileTypeImages => 'Изображения';

  @override
  String get fileTypeStampBundle => 'Штампы DartPDF';

  @override
  String get appSigKeyFileType => 'Закрытые ключи RSA';

  @override
  String get appSigCertificateFileType => 'Сертификаты X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Выберите хотя бы один сертификат X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'Сертификат $index не является допустимым X.509.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'Закрытый ключ не соответствует ни одному выбранному сертификату RSA.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Зашифрованные закрытые ключи не поддерживаются. Выберите незашифрованный ключ RSA PKCS#1 или PKCS#8.';

  @override
  String get appSigErrorKeyNotRsa =>
      'Закрытый ключ не является незашифрованным ключом RSA PKCS#1 или PKCS#8.';

  @override
  String get appSigErrorNoCertificateFound => 'Сертификаты X.509 не найдены.';

  @override
  String get imageSourceTakePhoto => 'Сделать снимок';

  @override
  String get imageSourceChooseFile => 'Выбрать файл';

  @override
  String get imageSourceCameraFailed => 'Не удалось сделать снимок';

  @override
  String get settingsCachedDocuments => 'Кэшированные документы';

  @override
  String settingsCacheUsage(String used, String limit) {
    return 'Использовано $used МиБ из $limit МиБ';
  }

  @override
  String settingsCacheExplanation(String limit) {
    return 'Файлы больше $limit МиБ не кэшируются. Очистка сохраняет список недавних файлов, открытые документы и несохранённые изменения; для открытия кэшированных файлов потребуется выбрать их заново.';
  }

  @override
  String get settingsClearCachedDocuments => 'Очистить кэш документов';

  @override
  String get settingsCacheUnavailable => 'Размер кэша недоступен';

  @override
  String get settingsCacheClearFailed =>
      'Не удалось очистить кэш документов. Повторите попытку.';
}
