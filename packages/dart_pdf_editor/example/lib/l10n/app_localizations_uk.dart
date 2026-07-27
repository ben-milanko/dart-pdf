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
  String exActionJavaScript(String script) {
    return 'JavaScript, переданий у застосунок: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Посилання: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Іменована дія: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Необроблюваний тип дії: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Текст анотації скопійовано';

  @override
  String get exApiKeyHelper => 'Надсилається як Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Ключ / токен API (необов’язково)';

  @override
  String get exAppMenuTooltip => 'Меню DartPDF';

  @override
  String get exClearRecentFiles => 'Очистити нещодавні файли';

  @override
  String get exCloseTab => 'Закрити вкладку';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Порівняння: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Порівняти з іншим PDF…';

  @override
  String get exCopiedToClipboard => 'Скопійовано в буфер обміну';

  @override
  String get exCopySelectedText => 'Копіювати виділений текст (⌘C)';

  @override
  String get exCopyText => 'Копіювати текст';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Не вдалося відкрити $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Не вдалося відкрити $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Не вдалося відкрити $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Не вдалося відкрити $uri\n$error\n\nУ веб-версії це часто пов’язано з обмеженням CORS: сервер має надсилати Access-Control-Allow-Origin і відкривати заголовки Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Не вдалося повторно відкрити $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Не вдалося повторно відкрити $title — збереженої копії більше немає.';
  }

  @override
  String get exDemoNoteHint =>
      'Друкуйте тут — це текстове поле плаває над сторінкою';

  @override
  String get exDiagnosticsCopied => 'Діагностику скопійовано в буфер обміну';

  @override
  String exDownloaded(String name) {
    return 'Завантажено $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Завантажено $name — вставте назад у PDF за допомогою Ctrl+V';
  }

  @override
  String get exExport => 'Експортувати';

  @override
  String exExportFailed(String error) {
    return 'Помилка експорту: $error';
  }

  @override
  String get exExportPageImageMenu => 'Експортувати сторінку як зображення…';

  @override
  String get exExportPageImageTitle => 'Експортувати сторінку як зображення';

  @override
  String get exFeatureShowcase => 'Демонстрація можливостей';

  @override
  String get exFormat => 'Формат';

  @override
  String get exHide => 'Приховати';

  @override
  String get exHorizontalLayout => 'Горизонтальне розташування сторінок';

  @override
  String get exHowToSetupOcr => 'Як налаштувати сервер OCR';

  @override
  String get exModelName => 'Назва моделі';

  @override
  String get exNoMessage => 'Немає повідомлення';

  @override
  String get exNoRecentFiles => 'Немає нещодавніх файлів';

  @override
  String exNotAValidUrl(String url) {
    return 'Недійсна URL-адреса:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
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
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Додає виділюваний текстовий шар із можливістю пошуку поверх сканованих сторінок за допомогою OCR-моделі «зображення-мова», яку ви розміщуєте самостійно (dots.ocr на vLLM або будь-яка OCR-точка доступу, сумісна з OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'Помилка OCR: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Відкрити';

  @override
  String get exOpenDocumentBeforeOcr => 'Відкрийте документ перед запуском OCR';

  @override
  String get exOpenDocumentFirst => 'Спершу відкрийте документ';

  @override
  String get exOpenFromUrl => 'Відкрити з URL-адреси…';

  @override
  String get exOpenFromUrlTitle => 'Відкрити з URL-адреси';

  @override
  String get exOpenInNewTab => 'Відкрити PDF у новій вкладці';

  @override
  String get exOpenInteractiveDemo => 'Відкрити інтерактивну демонстрацію';

  @override
  String get exOpenPdf => 'Відкрити PDF…';

  @override
  String get exOpenPdfButton => 'Відкрити PDF';

  @override
  String get exOpenRecent => 'Відкрити нещодавні';

  @override
  String get exOpenUrlDescription =>
      'Передає PDF через HTTP-запити Range за допомогою PdfHttpByteSource, завантажуючи лише те, що потрібно парсеру, і переходить до повного завантаження, якщо сервер не підтримує запити діапазону.';

  @override
  String get exOpeningDocument => 'Відкриття документа';

  @override
  String get exOpeningPdf => 'Відкриття PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Відкриття $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL-адреса PDF';

  @override
  String get exPerformanceAuto => 'Продуктивність: авто';

  @override
  String get exPreparing => 'Підготовка…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor на pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Розпізнавання сторінки $current з $count…';
  }

  @override
  String get exResolution => 'Роздільна здатність';

  @override
  String get exRunOcr => 'Запустити OCR';

  @override
  String get exSaveAs => 'Зберегти як…';

  @override
  String exSaveFailed(String error) {
    return 'Помилка збереження: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Збережено $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Збережено $name — вставте назад у PDF за допомогою ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Збережено в $path';
  }

  @override
  String get exScrollIndicatorDemo =>
      'Демонстрація API індикатора прокручування';

  @override
  String get exServiceEndpoint => 'Точка доступу служби';

  @override
  String get exShow => 'Показати';

  @override
  String get exSingleWorker => 'Один робочий процес';

  @override
  String get exSupplyFeedback => 'Надіслати відгук…';

  @override
  String get exSwitchToEdit => 'Перейти в режим редагування';

  @override
  String get exSwitchToReadOnly => 'Перейти в режим лише для читання';

  @override
  String get exThemeDark => 'Тема: темна — перемкнути на системну';

  @override
  String get exThemeLight => 'Тема: світла — перемкнути на темну';

  @override
  String get exThemeSystem => 'Тема: системна — перемкнути на світлу';

  @override
  String get exTryDemo => 'Спробувати інтерактивну демонстрацію';

  @override
  String get exWelcomeScreen => 'Екран привітання';

  @override
  String get exUntitled => 'Без назви';

  @override
  String get exVerticalLayout => 'Вертикальне розташування сторінок';

  @override
  String get exViewSource => 'Переглянути код на GitHub';

  @override
  String get exWorkerAuto => 'Авто';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Продуктивність: $count робочого процесу',
      many: 'Продуктивність: $count робочих процесів',
      few: 'Продуктивність: $count робочі процеси',
      one: 'Продуктивність: один робочий процес',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count робочого процесу',
      many: '$count робочих процесів',
      few: '$count робочі процеси',
      one: '$count робочий процес',
    );
    return '$_temp0';
  }

  @override
  String get feedbackAttachDiagnostics => 'Долучити цю діагностику до звіту';

  @override
  String get feedbackClearLog => 'Очистити журнал';

  @override
  String get feedbackCopyDiagnostics => 'Копіювати діагностику';

  @override
  String get feedbackDiagnosticsNotice =>
      'Форма відгуку відкривається у вашому браузері. Наведена нижче діагностика збирається лише на цьому пристрої й долучається, щоб допомогти відтворити проблему. Спершу перегляньте її — не додавайте нічого, що воліли б залишити конфіденційним.';

  @override
  String get feedbackOpenForm => 'Відкрити форму відгуку';

  @override
  String get feedbackTitle => 'Надіслати відгук';

  @override
  String get none => 'Немає';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Вставити';

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
  String get scrollDemoNextPage => 'Наступна сторінка';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Сторінка $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Попередня сторінка';

  @override
  String get scrollDemoSwitchHorizontal =>
      'Перемкнути на горизонтальне розташування';

  @override
  String get scrollDemoSwitchVertical =>
      'Перемкнути на вертикальне розташування';

  @override
  String get scrollDemoTitle => 'API індикатора прокручування';

  @override
  String get undo => 'Відмінити';

  @override
  String get exFileTypePdf => 'Документи PDF';

  @override
  String get exFileTypeImages => 'Зображення';

  @override
  String get exFileTypeFonts => 'Шрифти';
}
