// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class DartPdfPrintingLocalizationsRu extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get cancel => 'Отмена';

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
  String get printPreviewUnavailable => 'Просмотр недоступен';

  @override
  String get printOptionsPrinter => 'Принтер';

  @override
  String get printOptionsNativePrinter =>
      'В следующем системном диалоге печати выберите принтер, лоток для бумаги, цвет, двустороннюю печать и свойства устройства. Оставьте масштаб 100% и число копий 1, чтобы использовать показанный здесь макет.';

  @override
  String get printOptionsPages => 'Страницы';

  @override
  String get printOptionsSelected => 'Выбранные';

  @override
  String get printOptionsPageRange => 'Страницы (например, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Добавить файлы…';

  @override
  String get printOptionsAddFailed => 'Не удалось добавить выбранные файлы.';

  @override
  String get printOptionsGetWindow => 'Выбрать область';

  @override
  String get printOptionsClearWindow => 'Сбросить область';

  @override
  String get printOptionsWindowHint =>
      'Выделите прямоугольник на исходной странице, чтобы выбрать область для печати.';

  @override
  String get printOptionsPaper => 'Бумага';

  @override
  String get printOptionsPaperSize => 'Размер бумаги';

  @override
  String get printOptionsPageSize => 'Использовать размер страницы документа';

  @override
  String get printOptionsOrientation => 'Ориентация';

  @override
  String get printOptionsAuto => 'Автоматически';

  @override
  String get printOptionsPortrait => 'Книжная';

  @override
  String get printOptionsLandscape => 'Альбомная';

  @override
  String get printOptionsCopies => 'Копии';

  @override
  String get printOptionsCollate => 'Разобрать по копиям';

  @override
  String get printOptionsReverse => 'Обратный порядок страниц';

  @override
  String get printOptionsLayout => 'Макет страницы';

  @override
  String get printOptionsScaling => 'Масштабирование страницы';

  @override
  String get printOptionsScaleNone =>
      'Без масштабирования (фактический размер)';

  @override
  String get printOptionsFitPaper => 'Подогнать под размер бумаги';

  @override
  String get printOptionsReducePaper => 'Уменьшить до размера бумаги';

  @override
  String get printOptionsFitMargins => 'Подогнать по полям';

  @override
  String get printOptionsReduceMargins => 'Уменьшить до полей';

  @override
  String get printOptionsCustomScale => 'Произвольный масштаб';

  @override
  String get printOptionsMultiple => 'Несколько страниц на листе';

  @override
  String get printOptionsScalePercent => 'Масштаб (%)';

  @override
  String get printOptionsMargin => 'Поля (пт)';

  @override
  String get printOptionsPagesPerSheet => 'Страниц на листе';

  @override
  String get printOptionsPageOrder => 'Порядок страниц';

  @override
  String get printOptionsHorizontal => 'По горизонтали';

  @override
  String get printOptionsHorizontalReverse =>
      'По горизонтали в обратном порядке';

  @override
  String get printOptionsVertical => 'По вертикали';

  @override
  String get printOptionsVerticalReverse => 'По вертикали в обратном порядке';

  @override
  String get printOptionsBorder => 'Печатать рамки страниц';

  @override
  String get printOptionsRotation => 'Поворот (по часовой стрелке)';

  @override
  String get printOptionsNoRotation => 'Нет';

  @override
  String get printOptionsCenter => 'По центру листа';

  @override
  String get printOptionsOffsetX => 'Смещение вправо (пт)';

  @override
  String get printOptionsOffsetY => 'Смещение вниз (пт)';

  @override
  String get printOptionsContents => 'Содержимое для печати';

  @override
  String get printOptionsDocumentAndMarkups => 'Документ и аннотации';

  @override
  String get printOptionsDocumentOnly => 'Только документ';

  @override
  String get printOptionsMarkupsOnly => 'Только аннотации';

  @override
  String get printOptionsDimPage => 'Осветлить содержимое страницы';

  @override
  String get printOptionsDimMarkups => 'Осветлить аннотации';

  @override
  String get printOptionsHyperlinks => 'Печатать видимые гиперссылки';

  @override
  String get printOptionsDefaults => 'По умолчанию';

  @override
  String get printOptionsInvalidNumber =>
      'Перед печатью введите допустимые числа.';

  @override
  String get printOptionsInvalidValue => 'Недопустимое значение';

  @override
  String get printOptionsMarginGuide =>
      'Красные линии показывают поля и не выводятся на печать.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Область: $width × $height пт';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Источник: $width × $height пт';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Лист: $width × $height пт';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Лист $sheet из $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Не удалось подготовить этот макет. Проверьте размер бумаги, поля и масштаб.';

  @override
  String get printOptionsChoosePrinter => 'Выберите принтер';

  @override
  String get printOptionsNoPrinters =>
      'Принтеры не установлены. Добавьте принтер в параметрах Windows и повторите попытку.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'Сохранённый принтер «$printer» недоступен. Выберите принтер, чтобы продолжить.';
  }

  @override
  String get printOptionsPrinterError =>
      'Не удалось загрузить настройки принтера. Проверьте подключение принтера и повторите попытку.';

  @override
  String get printOptionsRetry => 'Повторить';

  @override
  String get printOptionsColor => 'Цветная';

  @override
  String get printOptionsGrayscale => 'Чёрно-белая';

  @override
  String get printOptionsDuplex => 'Двусторонняя печать';

  @override
  String get printOptionsSimplex => 'Односторонняя';

  @override
  String get printOptionsLongEdge => 'Переворот по длинному краю';

  @override
  String get printOptionsShortEdge => 'Переворот по короткому краю';

  @override
  String get printOptionsTray => 'Лоток для бумаги';

  @override
  String get printOptionsDefaultTray => 'По умолчанию принтера';

  @override
  String get printOptionsProperties => 'Свойства принтера…';

  @override
  String get printOptionsDirectPrinter =>
      'Кнопка «Печать» отправляет это задание прямо на выбранный принтер.';

  @override
  String get printOptionsPropertiesError =>
      'Не удалось открыть свойства принтера.';

  @override
  String get printOptionsLoadingPrinters => 'Загрузка принтеров…';
}
