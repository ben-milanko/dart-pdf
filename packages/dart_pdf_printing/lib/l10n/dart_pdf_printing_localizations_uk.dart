// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class DartPdfPrintingLocalizationsUk extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get cancel => 'Скасувати';

  @override
  String get printDlgPreparing => 'Підготовка…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Обробка сторінки $rendered з $total…';
  }

  @override
  String get printDlgTitle => 'Друк';

  @override
  String get printPreviewAll => 'Усі';

  @override
  String get printPreviewCurrent => 'Поточна';

  @override
  String get printPreviewNextPage => 'Наступна сторінка';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Сторінка $page з $total';
  }

  @override
  String get printPreviewPreviousPage => 'Попередня сторінка';

  @override
  String get printPreviewPrint => 'Друк';

  @override
  String get printPreviewRange => 'Діапазон';

  @override
  String printPreviewRangeError(int total) {
    return 'Введіть діапазон сторінок від 1 до $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Сторінок для друку: $count';
  }

  @override
  String get printPreviewTitle => 'Попередній перегляд друку';

  @override
  String get printPreviewUnavailable => 'Перегляд недоступний';

  @override
  String get printOptionsPrinter => 'Принтер';

  @override
  String get printOptionsNativePrinter =>
      'У наступному системному діалозі друку виберіть принтер, лоток для паперу, колір, двосторонній друк і властивості пристрою. Залиште масштаб 100% і кількість копій 1, щоб використати показаний тут макет.';

  @override
  String get printOptionsPages => 'Сторінки';

  @override
  String get printOptionsSelected => 'Вибрані';

  @override
  String get printOptionsPageRange => 'Сторінки (наприклад, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Додати файли…';

  @override
  String get printOptionsAddFailed => 'Не вдалося додати вибрані файли.';

  @override
  String get printOptionsGetWindow => 'Вибрати область';

  @override
  String get printOptionsClearWindow => 'Скинути область';

  @override
  String get printOptionsWindowHint =>
      'Виділіть прямокутник на цій вихідній сторінці, щоб вибрати область для друку.';

  @override
  String get printOptionsPaper => 'Папір';

  @override
  String get printOptionsPaperSize => 'Розмір паперу';

  @override
  String get printOptionsPageSize =>
      'Використовувати розмір сторінки документа';

  @override
  String get printOptionsOrientation => 'Орієнтація';

  @override
  String get printOptionsAuto => 'Автоматично';

  @override
  String get printOptionsPortrait => 'Книжкова';

  @override
  String get printOptionsLandscape => 'Альбомна';

  @override
  String get printOptionsCopies => 'Копії';

  @override
  String get printOptionsCollate => 'Сортувати за копіями';

  @override
  String get printOptionsReverse => 'Зворотний порядок сторінок';

  @override
  String get printOptionsLayout => 'Макет сторінки';

  @override
  String get printOptionsScaling => 'Масштабування сторінки';

  @override
  String get printOptionsScaleNone => 'Без масштабування (фактичний розмір)';

  @override
  String get printOptionsFitPaper => 'Підігнати до розміру паперу';

  @override
  String get printOptionsReducePaper => 'Зменшити до розміру паперу';

  @override
  String get printOptionsFitMargins => 'Підігнати до полів';

  @override
  String get printOptionsReduceMargins => 'Зменшити до полів';

  @override
  String get printOptionsCustomScale => 'Власний масштаб';

  @override
  String get printOptionsMultiple => 'Кілька сторінок на аркуші';

  @override
  String get printOptionsScalePercent => 'Масштаб (%)';

  @override
  String get printOptionsMargin => 'Поля (пт)';

  @override
  String get printOptionsPagesPerSheet => 'Сторінок на аркуші';

  @override
  String get printOptionsPageOrder => 'Порядок сторінок';

  @override
  String get printOptionsHorizontal => 'Горизонтально';

  @override
  String get printOptionsHorizontalReverse =>
      'Горизонтально у зворотному порядку';

  @override
  String get printOptionsVertical => 'Вертикально';

  @override
  String get printOptionsVerticalReverse => 'Вертикально у зворотному порядку';

  @override
  String get printOptionsBorder => 'Друкувати рамки сторінок';

  @override
  String get printOptionsRotation => 'Поворот (за годинниковою стрілкою)';

  @override
  String get printOptionsNoRotation => 'Немає';

  @override
  String get printOptionsCenter => 'По центру аркуша';

  @override
  String get printOptionsOffsetX => 'Зсув праворуч (пт)';

  @override
  String get printOptionsOffsetY => 'Зсув униз (пт)';

  @override
  String get printOptionsContents => 'Вміст для друку';

  @override
  String get printOptionsDocumentAndMarkups => 'Документ і анотації';

  @override
  String get printOptionsDocumentOnly => 'Лише документ';

  @override
  String get printOptionsMarkupsOnly => 'Лише анотації';

  @override
  String get printOptionsDimPage => 'Освітлити вміст сторінки';

  @override
  String get printOptionsDimMarkups => 'Освітлити анотації';

  @override
  String get printOptionsHyperlinks => 'Друкувати видимі гіперпосилання';

  @override
  String get printOptionsDefaults => 'Типові налаштування';

  @override
  String get printOptionsInvalidNumber =>
      'Перед друком введіть допустимі числа.';

  @override
  String get printOptionsInvalidValue => 'Недопустиме значення';

  @override
  String get printOptionsMarginGuide =>
      'Червоні лінії показують поля й не друкуються.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Область: $width × $height пт';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Джерело: $width × $height пт';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Аркуш: $width × $height пт';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Аркуш $sheet із $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Не вдалося підготувати цей макет. Перевірте розмір паперу, поля та масштаб.';

  @override
  String get printOptionsChoosePrinter => 'Виберіть принтер';

  @override
  String get printOptionsNoPrinters =>
      'Принтери не встановлено. Додайте принтер у параметрах Windows і повторіть спробу.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Збережений принтер «$printer» недоступний. Виберіть принтер, щоб продовжити.';
  }

  @override
  String get printOptionsPrinterError =>
      'Не вдалося завантажити налаштування принтера. Перевірте підключення принтера й повторіть спробу.';

  @override
  String get printOptionsRetry => 'Спробувати ще раз';

  @override
  String get printOptionsColor => 'Кольоровий';

  @override
  String get printOptionsGrayscale => 'Чорно-білий';

  @override
  String get printOptionsDuplex => 'Двосторонній друк';

  @override
  String get printOptionsSimplex => 'Односторонній';

  @override
  String get printOptionsLongEdge => 'Перегортати вздовж довгого краю';

  @override
  String get printOptionsShortEdge => 'Перегортати вздовж короткого краю';

  @override
  String get printOptionsTray => 'Лоток для паперу';

  @override
  String get printOptionsDefaultTray => 'Типові налаштування принтера';

  @override
  String get printOptionsProperties => 'Властивості принтера…';

  @override
  String get printOptionsDirectPrinter =>
      'Кнопка «Друк» надсилає це завдання безпосередньо на вибраний принтер.';

  @override
  String get printOptionsPropertiesError =>
      'Не вдалося відкрити властивості принтера.';

  @override
  String get printOptionsLoadingPrinters => 'Завантаження принтерів…';
}
