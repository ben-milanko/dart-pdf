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
  String exActionJavaScript(String script) {
    return 'JavaScript, переданный приложению: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Ссылка: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Именованное действие: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Необработанный тип действия: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Текст аннотации скопирован';

  @override
  String get exApiKeyHelper => 'Отправляется как Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Ключ API / токен (необязательно)';

  @override
  String get exAppMenuTooltip => 'Меню DartPDF';

  @override
  String get exClearRecentFiles => 'Очистить недавние файлы';

  @override
  String get exCloseTab => 'Закрыть вкладку';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Сравнение: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Сравнить с другим PDF…';

  @override
  String get exCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get exCopySelectedText => 'Копировать выбранный текст (⌘C)';

  @override
  String get exCopyText => 'Копировать текст';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Не удалось открыть $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Не удалось открыть $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Не удалось открыть $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Не удалось открыть $uri\n$error\n\nВ вебе это часто ограничение CORS: сервер должен отправлять Access-Control-Allow-Origin и открывать заголовки Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Не удалось повторно открыть $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Не удалось повторно открыть $title — сохранённая копия больше недоступна.';
  }

  @override
  String get exDemoNoteHint =>
      'Печатайте здесь — это текстовое поле парит над страницей';

  @override
  String get exDiagnosticsCopied => 'Диагностика скопирована в буфер обмена';

  @override
  String exDownloaded(String name) {
    return 'Скачано $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Скачано $name — вставьте обратно в PDF с помощью Ctrl+V';
  }

  @override
  String get exExport => 'Экспорт';

  @override
  String exExportFailed(String error) {
    return 'Сбой экспорта: $error';
  }

  @override
  String get exExportPageImageMenu =>
      'Экспортировать страницу как изображение…';

  @override
  String get exExportPageImageTitle =>
      'Экспортировать страницу как изображение';

  @override
  String get exFeatureShowcase => 'Демонстрация возможностей';

  @override
  String get exFormat => 'Формат';

  @override
  String get exHide => 'Скрыть';

  @override
  String get exHorizontalLayout => 'Горизонтальное расположение страниц';

  @override
  String get exHowToSetupOcr => 'Как настроить сервер OCR';

  @override
  String get exModelName => 'Имя модели';

  @override
  String get exNoMessage => 'Нет сообщения';

  @override
  String get exNoRecentFiles => 'Нет недавних файлов';

  @override
  String exNotAValidUrl(String url) {
    return 'Недопустимый URL:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
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
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Добавляет выделяемый текстовый слой с возможностью поиска поверх отсканированных страниц с помощью визуально-языковой модели OCR, которую вы размещаете сами (dots.ocr на vLLM или любую OCR-конечную точку, совместимую с OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'Сбой OCR: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Открыть';

  @override
  String get exOpenDocumentBeforeOcr => 'Откройте документ перед запуском OCR';

  @override
  String get exOpenDocumentFirst => 'Сначала откройте документ';

  @override
  String get exOpenFromUrl => 'Открыть по URL…';

  @override
  String get exOpenFromUrlTitle => 'Открыть по URL';

  @override
  String get exOpenInNewTab => 'Открыть PDF в новой вкладке';

  @override
  String get exOpenInteractiveDemo => 'Открыть интерактивную демонстрацию';

  @override
  String get exOpenPdf => 'Открыть PDF…';

  @override
  String get exOpenPdfButton => 'Открыть PDF';

  @override
  String get exOpenRecent => 'Открыть недавние';

  @override
  String get exOpenUrlDescription =>
      'Передаёт PDF через HTTP-запросы Range с помощью PdfHttpByteSource, загружая только то, что нужно парсеру, и переходя к полной загрузке, когда сервер не поддерживает диапазоны.';

  @override
  String get exOpeningDocument => 'Открытие документа';

  @override
  String get exOpeningPdf => 'Открытие PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Открытие $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL PDF';

  @override
  String get exPerformanceAuto => 'Производительность: Авто';

  @override
  String get exPreparing => 'Подготовка…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor на pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Распознавание страницы $current из $count…';
  }

  @override
  String get exResolution => 'Разрешение';

  @override
  String get exRunOcr => 'Запустить OCR';

  @override
  String get exSaveAs => 'Сохранить как…';

  @override
  String exSaveFailed(String error) {
    return 'Сбой сохранения: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Сохранено $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Сохранено $name — вставьте обратно в PDF с помощью ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Сохранено в $path';
  }

  @override
  String get exScrollIndicatorDemo => 'Демонстрация API индикатора прокрутки';

  @override
  String get exServiceEndpoint => 'Конечная точка службы';

  @override
  String get exShow => 'Показать';

  @override
  String get exSingleWorker => 'Один рабочий поток';

  @override
  String get exSupplyFeedback => 'Отправить отзыв…';

  @override
  String get exSwitchToEdit => 'Перейти в режим редактирования';

  @override
  String get exSwitchToReadOnly => 'Перейти в режим только для чтения';

  @override
  String get exThemeDark => 'Тема: тёмная — переключить на системную';

  @override
  String get exThemeLight => 'Тема: светлая — переключить на тёмную';

  @override
  String get exThemeSystem => 'Тема: системная — переключить на светлую';

  @override
  String get exTryDemo => 'Попробовать интерактивную демонстрацию';

  @override
  String get exUntitled => 'Без названия';

  @override
  String get exVerticalLayout => 'Вертикальное расположение страниц';

  @override
  String get exViewSource => 'Посмотреть исходный код на GitHub';

  @override
  String get exWorkerAuto => 'Авто';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Производительность: $count рабочих потока',
      many: 'Производительность: $count рабочих потоков',
      few: 'Производительность: $count рабочих потока',
      one: 'Производительность: один рабочий поток',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count рабочих потоков';
  }

  @override
  String get feedbackAttachDiagnostics => 'Приложить эту диагностику к отчёту';

  @override
  String get feedbackClearLog => 'Очистить журнал';

  @override
  String get feedbackCopyDiagnostics => 'Копировать диагностику';

  @override
  String get feedbackDiagnosticsNotice =>
      'Форма отзыва открывается в вашем браузере. Диагностика ниже собирается только на этом устройстве и прилагается, чтобы помочь воспроизвести проблему. Сначала просмотрите её — не включайте ничего, что вы хотели бы сохранить в тайне.';

  @override
  String get feedbackOpenForm => 'Открыть форму отзыва';

  @override
  String get feedbackTitle => 'Отправить отзыв';

  @override
  String get none => 'Нет';

  @override
  String get ok => 'ОК';

  @override
  String get paste => 'Вставить';

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
  String get scrollDemoNextPage => 'Следующая страница';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Страница $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Предыдущая страница';

  @override
  String get scrollDemoSwitchHorizontal =>
      'Переключить на горизонтальное расположение';

  @override
  String get scrollDemoSwitchVertical =>
      'Переключить на вертикальное расположение';

  @override
  String get scrollDemoTitle => 'API индикатора прокрутки';

  @override
  String get undo => 'Отменить';

  @override
  String get exFileTypePdf => 'Документы PDF';

  @override
  String get exFileTypeImages => 'Изображения';

  @override
  String get exFileTypeFonts => 'Шрифты';
}
