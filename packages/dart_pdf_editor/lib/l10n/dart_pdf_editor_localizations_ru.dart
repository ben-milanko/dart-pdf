// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class DartPdfEditorLocalizationsRu extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get add => 'Добавить';

  @override
  String get annotCaret => 'Знак вставки';

  @override
  String get annotCircle => 'Круг';

  @override
  String get annotFileAttachment => 'Вложение файла';

  @override
  String get annotFreeText => 'Текстовое поле';

  @override
  String get annotHighlight => 'Выделение';

  @override
  String get annotInk => 'Рисунок от руки';

  @override
  String get annotLine => 'Линия';

  @override
  String get annotLink => 'Ссылка';

  @override
  String get annotPolygon => 'Многоугольник';

  @override
  String get annotPolyline => 'Ломаная линия';

  @override
  String get annotRedact => 'Вымарывание';

  @override
  String get annotSquare => 'Прямоугольник';

  @override
  String get annotSquiggly => 'Волнистое подчёркивание';

  @override
  String get annotStamp => 'Штамп';

  @override
  String get annotStrikeOut => 'Зачёркивание';

  @override
  String get annotText => 'Заметка';

  @override
  String get annotUnderline => 'Подчёркивание';

  @override
  String get annotWidget => 'Поле формы';

  @override
  String get apply => 'Применить';

  @override
  String get bookmarkAdd => 'Добавить закладку';

  @override
  String get bookmarkAddChild => 'Добавить дочернюю закладку';

  @override
  String get bookmarkCollapse => 'Свернуть';

  @override
  String get bookmarkDelete => 'Удалить закладку';

  @override
  String get bookmarkEdit => 'Изменить закладку';

  @override
  String get bookmarkEmpty => 'Нет закладок';

  @override
  String get bookmarkExpand => 'Развернуть';

  @override
  String get bookmarkExpandedByDefault => 'Развёрнуто по умолчанию';

  @override
  String get bookmarkNoDestination => 'Нет назначения';

  @override
  String get bookmarkPageFieldLabel => 'Страница';

  @override
  String bookmarkPageLabel(int number) {
    return 'Страница $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Закладки';

  @override
  String get bookmarkTitleLabel => 'Заголовок';

  @override
  String get bookmarkUntitled => 'Без названия';

  @override
  String get cancel => 'Отмена';

  @override
  String get clear => 'Очистить';

  @override
  String get close => 'Закрыть';

  @override
  String get colorApplyingChanges => 'Применение изменений цвета…';

  @override
  String get colorColorFormat => 'Формат цвета';

  @override
  String get colorColorTitle => 'Цвет';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Выбрано $count цвета',
      many: 'Выбрано $count цветов',
      few: 'Выбрано $count цвета',
      one: 'Выбран $count цвет',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Цвета документа';

  @override
  String get colorFillColors => 'Цвета заливки';

  @override
  String get colorFind => 'Найти';

  @override
  String get colorInDocument => 'В документе';

  @override
  String get colorNoColorsFound => 'Цвета пока не найдены';

  @override
  String get colorNoPageContentColors => 'Цвета содержимого страниц не найдены';

  @override
  String get colorPalette => 'Палитра';

  @override
  String get colorPickColor => 'Выбрать цвет';

  @override
  String get colorProcessingTitle => 'Обработка цветов';

  @override
  String get colorRecent => 'Недавние';

  @override
  String get colorReplace => 'Заменить';

  @override
  String get colorReplaceWithTransparent => 'Заменить прозрачностью';

  @override
  String get colorScanning => 'Сканирование…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Сканирование $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Выбранные страницы ($count)';
  }

  @override
  String get colorStrokeColors => 'Цвета обводки';

  @override
  String get colorTolerance => 'Допуск';

  @override
  String get colorTransparent => 'Прозрачный';

  @override
  String get colorWholeDocument => 'Весь документ';

  @override
  String get compareAfter => 'После';

  @override
  String get compareBefore => 'До';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count изменения',
      many: '$count изменений',
      few: '$count изменения',
      one: '1 изменение',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count изменения',
      many: '$count изменений',
      few: '$count изменения',
      one: '1 изменение',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(пусто)';

  @override
  String get compareNextChange => 'Следующее изменение';

  @override
  String get compareNoChanges => 'Нет изменений';

  @override
  String get compareNoDifferences => 'Между двумя документами нет различий';

  @override
  String get compareOverlay => 'Наложение';

  @override
  String comparePageHeader(int page) {
    return 'Страница $page';
  }

  @override
  String get comparePreviousChange => 'Предыдущее изменение';

  @override
  String get compareSideBySide => 'Рядом';

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
  String get editorViewAuthorNameTitle => 'Имя автора';

  @override
  String get lineStyleDashDot => 'Штрихпунктирная';

  @override
  String get lineStyleDashed => 'Пунктирная';

  @override
  String get lineStyleDotted => 'Точечная';

  @override
  String get lineStyleSolid => 'Сплошная';

  @override
  String get measCalibrate => 'Калибровать';

  @override
  String get measCalibrateScale => 'Калибровка масштаба';

  @override
  String get measDepthLabel => 'Глубина: ';

  @override
  String get measKindAngle => 'Угол';

  @override
  String get measKindArc => 'Дуга';

  @override
  String get measKindArea => 'Площадь';

  @override
  String get measKindCount => 'Количество';

  @override
  String get measKindLength => 'Длина';

  @override
  String get measKindNetArea => 'Чистая площадь';

  @override
  String get measKindPerimeter => 'Периметр';

  @override
  String get measKindSlope => 'Уклон';

  @override
  String get measKindVolume => 'Объём';

  @override
  String get measLineRepresents => 'Нарисованная линия соответствует:';

  @override
  String get measMeasure => 'Измерить';

  @override
  String get measSetScale => 'Задать масштаб измерений';

  @override
  String get measSetScaleButton => 'Задать масштаб';

  @override
  String get measVolumeDepth => 'Глубина объёма';

  @override
  String get menuAddNode => 'Добавить узел';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Применить аннотации к страницам',
      one: 'Применить аннотацию к страницам',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Применить к страницам…';

  @override
  String get menuBringToFront => 'На передний план';

  @override
  String get menuCheck => 'Отметить';

  @override
  String get menuChooseValue => 'Выбрать значение…';

  @override
  String get menuClearCheck => 'Снять отметку';

  @override
  String get menuConvertToCheckBox => 'Преобразовать в флажок';

  @override
  String get menuConvertToImageButton =>
      'Преобразовать в кнопку с изображением';

  @override
  String get menuConvertToTextField => 'Преобразовать в текстовое поле';

  @override
  String get menuDeleteField => 'Удалить поле';

  @override
  String get menuEditValue => 'Изменить значение…';

  @override
  String get menuFieldName => 'Имя поля';

  @override
  String get menuFieldValue => 'Значение поля';

  @override
  String get menuFlattenForm => 'Свести форму';

  @override
  String get menuLock => 'Заблокировать';

  @override
  String get menuUnlock => 'Разблокировать';

  @override
  String get menuRecolour => 'Перекрасить…';

  @override
  String get menuRemoveNode => 'Удалить узел';

  @override
  String get menuSaveToStamps => 'Сохранить в штампы';

  @override
  String get menuSetAsDefaultStyle => 'Задать стилем по умолчанию';

  @override
  String get menuRename => 'Переименовать…';

  @override
  String get menuSelectOption => 'Выбрать вариант';

  @override
  String get menuSendToBack => 'На задний план';

  @override
  String get menuSetImage => 'Задать изображение…';

  @override
  String get menuTextStyle => 'Стиль текста…';

  @override
  String get none => 'Нет';

  @override
  String get ok => 'ОК';

  @override
  String get overlayColor => 'Цвет';

  @override
  String get overlayEditText => 'Изменить текст';

  @override
  String get overlayFont => 'Шрифт';

  @override
  String get overlayLarger => 'Больше';

  @override
  String get overlayMore => 'Ещё';

  @override
  String get overlayNote => 'Заметка';

  @override
  String get overlaySmaller => 'Меньше';

  @override
  String get overlayStampText => 'Текст штампа';

  @override
  String get linkDialogTitle => 'Добавить ссылку';

  @override
  String get linkKindWeb => 'Веб-адрес';

  @override
  String get linkKindPage => 'Страница в документе';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Номер страницы';

  @override
  String get toolLink => 'Ссылка';

  @override
  String get overlayUnderline => 'Подчёркивание';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Укажите страницы от 1 до $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Последняя страница не может быть раньше первой.';

  @override
  String get pageRangeFrom => 'С';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count страницы',
      many: '$count страниц',
      few: '$count страницы',
      one: '1 страница',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'По';

  @override
  String get panelDragToMovePanel => 'Перетащите, чтобы переместить панель';

  @override
  String get paste => 'Вставить';

  @override
  String get propAlign => 'Выравнивание';

  @override
  String get propAlignCenter => 'По центру';

  @override
  String get propAlignLeft => 'По левому краю';

  @override
  String get propAlignRight => 'По правому краю';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count аннотации',
      many: '$count аннотаций',
      few: '$count аннотации',
      one: '$count аннотация',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Автор';

  @override
  String get propAutoSize => 'Автоподбор размера';

  @override
  String get propBold => 'Полужирный';

  @override
  String get propBoldLetter => 'Ж';

  @override
  String get propBundledFont => 'Шрифт из комплекта';

  @override
  String get propCallout => 'Выноска';

  @override
  String get propCharSpacing => 'Межбуквенный интервал';

  @override
  String get propColor => 'Цвет';

  @override
  String get propColour => 'Цвет';

  @override
  String get propContents => 'Содержимое';

  @override
  String get propCornerRadius => 'Радиус скругления';

  @override
  String get propEditsApplyToAll =>
      'Изменения применяются ко всем совместимым аннотациям';

  @override
  String get propFieldName => 'Имя поля';

  @override
  String get propFieldTypeCheckBox => 'Флажок';

  @override
  String get propFieldTypeComboBox => 'Раскрывающийся список';

  @override
  String get propFieldTypeImageButton => 'Кнопка с изображением';

  @override
  String get propFieldTypeListBox => 'Список';

  @override
  String get propFieldTypeRadioGroup => 'Группа переключателей';

  @override
  String get propFieldTypeSignature => 'Подпись';

  @override
  String get propFieldTypeText => 'Текстовое поле';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Тип поля: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Неизвестное поле';

  @override
  String get propFill => 'Заливка';

  @override
  String get propFont => 'Шрифт';

  @override
  String get propFontSubsetTooltip =>
      'Этот шрифт является подмножеством — можно вводить только символы, уже используемые в документе.';

  @override
  String get propFontWidth => 'Ширина шрифта';

  @override
  String get propGeometryHeight => 'В';

  @override
  String get propGeometryWidth => 'Ш';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Курсив';

  @override
  String get propItalicLetter => 'К';

  @override
  String get propLimitedCharacters => 'Ограниченный набор символов';

  @override
  String get propLineEnd => 'Конец линии';

  @override
  String get propLineEndingButt => 'Плоский';

  @override
  String get propLineEndingCircle => 'Круг';

  @override
  String get propLineEndingClosedArrow => 'Закрытая стрелка';

  @override
  String get propLineEndingClosedArrowRev => 'Закрытая стрелка (обр.)';

  @override
  String get propLineEndingDiamond => 'Ромб';

  @override
  String get propLineEndingOpenArrow => 'Открытая стрелка';

  @override
  String get propLineEndingOpenArrowRev => 'Открытая стрелка (обр.)';

  @override
  String get propLineEndingSlash => 'Косая черта';

  @override
  String get propLineEndingSquare => 'Квадрат';

  @override
  String get propLineSpacing => 'Межстрочный интервал';

  @override
  String get propLineStart => 'Начало линии';

  @override
  String get propLineType => 'Тип линии';

  @override
  String get propLoadFont => 'Загрузить шрифт…';

  @override
  String get propLoadFontSubtitle => 'Файл TTF или OTF';

  @override
  String get propMoreColors => 'Больше цветов…';

  @override
  String get propMultiline => 'Многострочное';

  @override
  String get propNoFill => 'Без заливки';

  @override
  String get propNoFontsFound => 'Шрифты не найдены';

  @override
  String get propNoOutline => 'Без контура';

  @override
  String get propOpacity => 'Непрозрачность';

  @override
  String get propOutline => 'Контур';

  @override
  String get propPageLabel => 'Страница';

  @override
  String propPageNumber(int number) {
    return 'Страница $number';
  }

  @override
  String get propPropertiesTitle => 'Свойства';

  @override
  String get propRecentlyUsed => 'Недавно использованные';

  @override
  String get propScale => 'Масштаб';

  @override
  String get propSearchFonts => 'Поиск шрифтов';

  @override
  String get propSectionAllFonts => 'Все шрифты';

  @override
  String get propSectionAppearance => 'Внешний вид';

  @override
  String get propSectionContent => 'Содержимое';

  @override
  String get propSectionFormField => 'Поле формы';

  @override
  String get propSectionInThisDocument => 'В этом документе';

  @override
  String get propSectionPositionSize => 'Положение и размер (пт)';

  @override
  String get propSectionSelection => 'Выбор';

  @override
  String get propSectionText => 'Текст';

  @override
  String get propSelectAnnotationPrompt =>
      'Выберите аннотацию, чтобы увидеть её свойства';

  @override
  String get propSize => 'Размер';

  @override
  String get propStandardPdfFont => 'Стандартный шрифт PDF';

  @override
  String get propStroke => 'Обводка';

  @override
  String get propStyle => 'Стиль';

  @override
  String get propSystemFont => 'Системный шрифт';

  @override
  String get propType => 'Тип';

  @override
  String get propUnderline => 'Подчёркивание';

  @override
  String get propVaries => 'Различается';

  @override
  String get redo => 'Повторить';

  @override
  String get reflowNoContent => 'Нет извлекаемого содержимого';

  @override
  String reflowPageLabel(int number) {
    return 'Страница $number';
  }

  @override
  String get reflowSaveOrShare => 'Сохранить или поделиться';

  @override
  String get reflowViewFigure => 'Просмотреть изображение';

  @override
  String get remove => 'Удалить';

  @override
  String get rename => 'Переименовать';

  @override
  String get reset => 'Сбросить';

  @override
  String get save => 'Сохранить';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Страница $page';
  }

  @override
  String get sbarCallout => 'Выноска';

  @override
  String get sbarFieldButton => 'Поле-кнопка';

  @override
  String get sbarFieldChoice => 'Поле выбора';

  @override
  String get sbarFieldGeneric => 'Поле формы';

  @override
  String get sbarFieldSignature => 'Поле подписи';

  @override
  String get sbarFieldText => 'Текстовое поле';

  @override
  String get sbarStateAccepted => 'Принято';

  @override
  String get sbarStateCancelled => 'Отменено';

  @override
  String get sbarStateMarked => 'Отмечено';

  @override
  String get sbarStateRejected => 'Отклонено';

  @override
  String get sbarStateResolved => 'Решено';

  @override
  String get sbarStateUnmarked => 'Без отметки';

  @override
  String get searchAnnotations => 'Поиск по аннотациям';

  @override
  String get searchClearSearch => 'Очистить поиск';

  @override
  String get searchEmptyHint =>
      'Выполните поиск по документу, чтобы увидеть все совпадения';

  @override
  String get searchMatchCase => 'Учитывать регистр';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count совпадения',
      many: '$count совпадений',
      few: '$count совпадения',
      one: '1 совпадение',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Следующее совпадение';

  @override
  String searchNoMatches(String query) {
    return 'Нет совпадений для «$query»';
  }

  @override
  String searchPageHeader(int page) {
    return 'Страница $page';
  }

  @override
  String get searchPreviousMatch => 'Предыдущее совпадение';

  @override
  String get searchRegex => 'Регулярное выражение';

  @override
  String get searchReplace => 'Заменить';

  @override
  String get searchReplaceAll => 'Заменить все';

  @override
  String get searchReplaceHint => 'Заменить на';

  @override
  String get searchReplaceNotTargetable =>
      'Это совпадение нельзя заменить отдельно — используйте «Заменить все» или измените его инструментом содержимого';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Заменено $count совпадения',
      many: 'Заменено $count совпадений',
      few: 'Заменено $count совпадения',
      one: 'Заменено 1 совпадение',
      zero: 'Ничего не заменено',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'Результаты поиска';

  @override
  String get searchWholeWord => 'Слово целиком';

  @override
  String get shellControls => 'Элементы управления';

  @override
  String get shellDefaultAuthor => 'Автор по умолчанию…';

  @override
  String get shellHighlightFormFields => 'Выделять поля форм';

  @override
  String get shellKeyboardShortcutsMenu => 'Сочетания клавиш…';

  @override
  String get shellKeyboardShortcutsTitle => 'Сочетания клавиш';

  @override
  String get shellShortcutsSearchHint => 'Поиск сочетаний';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Нет сочетаний для «$query»';
  }

  @override
  String get shellShortcutGroupSelect => 'Выбор';

  @override
  String get shellShortcutGroupMarkup => 'Разметка';

  @override
  String get shellShortcutGroupDraw => 'Рисование';

  @override
  String get shellShortcutGroupShapes => 'Фигуры';

  @override
  String get shellShortcutGroupInsert => 'Вставка';

  @override
  String get shellShortcutGroupMeasure => 'Измерение';

  @override
  String get shellShortcutGroupEdit => 'Правка';

  @override
  String get shellNotSet => 'Не задано';

  @override
  String get shellPageColor => 'Цвет страницы…';

  @override
  String get shellPageGrid => 'Сетка страниц';

  @override
  String get shellPanelAnnotations => 'Аннотации';

  @override
  String get shellPanelBookmarks => 'Закладки';

  @override
  String get shellPanelPages => 'Страницы';

  @override
  String get shellPanelProperties => 'Свойства';

  @override
  String get shellPanelSearchResults => 'Результаты поиска';

  @override
  String get shellPanels => 'Панели';

  @override
  String get shellPressAKey => 'Нажмите клавишу';

  @override
  String get shellPressLetterKeyHint =>
      'Нажмите буквенную клавишу или Delete, чтобы очистить.';

  @override
  String get shellReflow => 'Перекомпоновка';

  @override
  String get shellReflowText => 'Перекомпоновать текст';

  @override
  String get shellResetZoom => 'Сбросить масштаб';

  @override
  String get shellSectionShell => 'Оболочка';

  @override
  String get shellSectionView => 'Вид';

  @override
  String get shellSettings => 'Настройки';

  @override
  String get shellShowAnnotations => 'Показывать аннотации';

  @override
  String get shellShowScrollbarChapters =>
      'Показывать главы на полосе прокрутки';

  @override
  String get shellTabHere => 'Вкладка сюда';

  @override
  String get shellUnbound => 'Не назначено';

  @override
  String get shellZoom => 'Масштаб';

  @override
  String sidebarByAuthor(String author) {
    return 'автор: $author';
  }

  @override
  String get sidebarCancelSelection => 'Отменить выбор';

  @override
  String get sidebarClearSearch => 'Очистить поиск';

  @override
  String get sidebarDeleteSelected => 'Удалить выбранные';

  @override
  String get sidebarDeleteSignature => 'Удалить подпись';

  @override
  String get sidebarLockAnnotation => 'Заблокировать';

  @override
  String get sidebarUnlockAnnotation => 'Разблокировать';

  @override
  String get sidebarMore => 'Ещё';

  @override
  String get sidebarNoAnnotations => 'Нет аннотаций';

  @override
  String get sidebarNoMatchingAnnotations => 'Нет подходящих аннотаций';

  @override
  String sidebarPageHeader(int number) {
    return 'Страница $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Это удалит цифровую подпись из документа. Это можно отменить.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Это удалит цифровую подпись «$name» из документа. Это можно отменить.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Удалить подпись?';

  @override
  String get sidebarReopen => 'Открыть заново';

  @override
  String get sidebarReply => 'Ответить';

  @override
  String get sidebarResolve => 'Решить';

  @override
  String get sidebarSearchHint => 'Поиск аннотаций';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'выбрано $count',
      many: 'выбрано $count',
      few: 'выбрано $count',
      one: 'выбрано $count',
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
  String get sidebarWriteReplyHint => 'Написать ответ…';

  @override
  String get sigTitle => 'Подпись';

  @override
  String get signIdCreate => 'Создать';

  @override
  String get signIdEmail => 'Эл. почта (необязательно)';

  @override
  String get signIdName => 'Имя';

  @override
  String get signIdNameHint =>
      'Ваше имя в том виде, в каком оно должно отображаться в подписи';

  @override
  String get signIdNameRequired => 'Введите имя';

  @override
  String get signIdOrganization => 'Организация (необязательно)';

  @override
  String get signIdSelfSignedInfo =>
      'Создаётся самоподписанная личность. В Adobe Acrobat и других программах подписи будут отображаться как «подписано, достоверность неизвестна» — так же, как их собственные самоподписанные ID. Зелёная галочка требует платного, публично доверенного УЦ.';

  @override
  String get signIdTitle => 'Создать личность для подписи';

  @override
  String get stampBox => 'Прямоугольник';

  @override
  String get stampCircle => 'Круг';

  @override
  String get stampCustomCaption => 'Пользовательский штамп';

  @override
  String get stampDateFormat => 'Формат даты';

  @override
  String get stampDeleteComponent => 'Удалить выбранный компонент';

  @override
  String get stampDeleteStamp => 'Удалить штамп';

  @override
  String get stampEditStamp => 'Изменить штамп';

  @override
  String get stampExport => 'Экспорт…';

  @override
  String get stampFieldDate => 'Дата';

  @override
  String get stampFieldDateTime => 'Дата и время';

  @override
  String get stampFieldTime => 'Время';

  @override
  String get stampFieldUsername => 'Имя пользователя';

  @override
  String get stampFont => 'Шрифт';

  @override
  String get stampFontBold => 'Полужирный';

  @override
  String get stampFontItalic => 'Курсив';

  @override
  String get stampHeight => 'Высота';

  @override
  String get stampImage => 'Изображение';

  @override
  String get stampImport => 'Импорт…';

  @override
  String get stampInsertField => 'Вставить поле';

  @override
  String get stampMoreColors => 'Больше цветов…';

  @override
  String get stampNewStamp => 'Новый штамп…';

  @override
  String get stampNewStampTitle => 'Новый штамп';

  @override
  String get stampSavedToCollection => 'Сохранено в штампы';

  @override
  String get stampSelectTextToEdit => 'Выберите текст для редактирования';

  @override
  String get stampSelectedText => 'Выбранный текст';

  @override
  String get stampSignature => 'Подпись';

  @override
  String get stampStamps => 'Штампы';

  @override
  String get stampText => 'Текст';

  @override
  String get stampTime12Hour => '12 ч';

  @override
  String get stampTime24Hour => '24 ч';

  @override
  String get stampTimeFormat => 'Формат времени';

  @override
  String get stampWidth => 'Ширина';

  @override
  String get takeoffArea => 'Площадь';

  @override
  String get takeoffCount => 'Количество';

  @override
  String get takeoffEmpty => 'Измерений пока нет.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count группы',
      many: '$count групп',
      few: '$count группы',
      one: '$count группа',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count элемента',
      many: '$count элементов',
      few: '$count элемента',
      one: '$count элемент',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Длина';

  @override
  String get takeoffTitle => 'Обмер';

  @override
  String get tbAddInkAnnotation => 'Добавить рукописную аннотацию';

  @override
  String get tbAlign => 'Выравнивание';

  @override
  String get tbAlignBottom => 'Выровнять по нижнему краю';

  @override
  String get tbAlignHorizontalCenters => 'Выровнять по горизонтальным центрам';

  @override
  String get tbAlignLeft => 'Выровнять по левому краю';

  @override
  String get tbAlignRight => 'Выровнять по правому краю';

  @override
  String get tbAlignTop => 'Выровнять по верхнему краю';

  @override
  String get tbAlignVerticalCenters => 'Выровнять по вертикальным центрам';

  @override
  String get tbAnnotationsFlattened => 'Аннотации сведены со страницами';

  @override
  String get tbApplyRedactionsMessage =>
      'Отмеченное содержимое будет безвозвратно удалено из документа. Это нельзя отменить.';

  @override
  String get tbApplyRedactionsTitle => 'Применить вымарывания?';

  @override
  String get tbApplyRedactionsTooltip => 'Применить вымарывания (необратимо)';

  @override
  String get tbAutosizeTextBox => 'Автоподбор размера текстового поля (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Нарисуйте линию известной длины, чтобы откалибровать масштаб.';

  @override
  String get tbCharSpacing => 'Межбуквенный интервал';

  @override
  String get tbCheckBoxOption => 'Флажок';

  @override
  String get tbCheckMarksOnDocument => 'Галочки на документе';

  @override
  String get tbCropImage => 'Обрезать изображение';

  @override
  String get tbCroppingImage => 'Обрезка изображения';

  @override
  String get tbCropApply => 'Применить обрезку';

  @override
  String get tbCropCancel => 'Отменить обрезку';

  @override
  String get tbCropReset => 'Сбросить обрезку';

  @override
  String get tbColorLabel => 'Цвет';

  @override
  String get tbColorProcessingTooltip =>
      'Обработка цветов — поиск и замена цветов содержимого страниц';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Заменено $count цвета',
      many: 'Заменено $count цветов',
      few: 'Заменено $count цвета',
      one: 'Заменён 1 цвет',
      zero: 'Подходящие цвета не найдены',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Преобразовать в флажок';

  @override
  String get tbConvertToImageButton => 'Преобразовать в кнопку с изображением';

  @override
  String get tbConvertToTextField => 'Преобразовать в текстовое поле';

  @override
  String get tbCornerRadius => 'Радиус скругления';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удалить $count аннотации',
      many: 'Удалить $count аннотаций',
      few: 'Удалить $count аннотации',
      one: 'Удалить аннотацию',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Удалить элемент';

  @override
  String get tbDeleteField => 'Удалить поле';

  @override
  String get tbDiscardDrawing => 'Отменить рисунок';

  @override
  String get tbDistributeHorizontally => 'Распределить по горизонтали';

  @override
  String get tbDistributeVertically => 'Распределить по вертикали';

  @override
  String get tbDrawNewSignature => 'Нарисовать новую подпись…';

  @override
  String get tbEditAnnotationText => 'Изменить текст аннотации';

  @override
  String get tbEditTextStyle => 'Изменить текст и стиль';

  @override
  String get tbElement => 'Элемент';

  @override
  String get tbEraserSize => 'Размер ластика';

  @override
  String get tbFieldActions => 'Действия с полем';

  @override
  String get tbFieldName => 'Имя поля';

  @override
  String tbFieldNamed(String name) {
    return 'Поле: $name';
  }

  @override
  String get tbFieldValue => 'Значение поля';

  @override
  String get tbFill => 'Заливка';

  @override
  String get tbFingerDraws =>
      'Палец рисует — коснитесь, чтобы вместо этого прокручивать';

  @override
  String get tbFingerScrolls =>
      'Палец прокручивает (перо рисует) — коснитесь, чтобы рисовать';

  @override
  String get tbFlattenAnnotationsTooltip => 'Свести аннотации со страницами';

  @override
  String get tbFlattenForm => 'Свести форму';

  @override
  String get tbFlattenFormBakeValues =>
      'Свести форму — зафиксировать значения на страницах';

  @override
  String get tbFlattenLabel => 'Свести';

  @override
  String get tbFont => 'Шрифт';

  @override
  String get tbFontSize => 'Размер шрифта';

  @override
  String get tbFontWidth => 'Ширина шрифта';

  @override
  String get tbFormFieldsFlattened => 'Поля формы сведены со страницами';

  @override
  String get tbGroupDraw => 'Рисование';

  @override
  String get tbGroupEdit => 'Правка';

  @override
  String get tbGroupInsert => 'Вставка';

  @override
  String get tbGroupMarkup => 'Разметка';

  @override
  String get tbGroupMeasure => 'Измерение';

  @override
  String get tbGroupSelect => 'Выбор';

  @override
  String get tbGroupShapes => 'Фигуры';

  @override
  String get tbImageButtonOption => 'Кнопка с изображением';

  @override
  String get tbLineEnd => 'Конец линии';

  @override
  String get tbLineSpacing => 'Межстрочный интервал';

  @override
  String get tbLineStart => 'Начало линии';

  @override
  String get tbLineType => 'Тип линии';

  @override
  String get tbManageStamps => 'Управление штампами…';

  @override
  String get tbMarkupHighlight => 'Выделение';

  @override
  String get tbMarkupHighlightTip => 'Выделить выбранное';

  @override
  String get tbMarkupSquiggly => 'Волнистое подчёркивание';

  @override
  String get tbMarkupSquigglyTip => 'Волнистое подчёркивание выбранного';

  @override
  String get tbMarkupStrikeOut => 'Зачеркнуть';

  @override
  String get tbMarkupStrikeOutTip => 'Зачеркнуть выбранное';

  @override
  String get tbMarkupUnderline => 'Подчёркивание';

  @override
  String get tbMarkupUnderlineTip => 'Подчеркнуть выбранное';

  @override
  String get tbMoreColors => 'Больше цветов…';

  @override
  String get tbNameArrow => 'Стрелка';

  @override
  String get tbNameCallout => 'Выноска';

  @override
  String get tbNameCloudPolygon => 'Облачный многоугольник';

  @override
  String get tbNameCount => 'Подсчёт';

  @override
  String get tbNameDigitalSignature => 'Цифровая подпись';

  @override
  String get tbNameDraw => 'Рисование';

  @override
  String get tbNameEllipse => 'Эллипс';

  @override
  String get tbNameEraser => 'Стереть рукописные штрихи';

  @override
  String get tbNameHand => 'Hand';

  @override
  String get tbNameHighlight => 'Выделение';

  @override
  String get tbNameImage => 'Изображение';

  @override
  String get tbNameLine => 'Линия';

  @override
  String get tbNameMeasureAngle => 'Измерить угол';

  @override
  String get tbNameMeasureArc => 'Измерить длину дуги';

  @override
  String get tbNameMeasureArea => 'Измерить площадь';

  @override
  String get tbNameMeasureDistance => 'Измерить расстояние';

  @override
  String get tbNameMeasurePerimeter => 'Измерить периметр';

  @override
  String get tbNameMeasureSlope => 'Измерить уклон (подъём/заложение)';

  @override
  String get tbNameMeasureVolume => 'Измерить объём (площадь × глубина)';

  @override
  String get tbNameNote => 'Заметка';

  @override
  String get tbNamePolygon => 'Многоугольник';

  @override
  String get tbNamePolyline => 'Ломаная линия';

  @override
  String get tbNameRectangle => 'Прямоугольник';

  @override
  String get tbNameSelect => 'Выбор';

  @override
  String get tbNameSignature => 'Подпись';

  @override
  String get tbNameStamp => 'Штамп';

  @override
  String get tbNameTextBox => 'Текстовое поле';

  @override
  String get tbNewFieldType =>
      'Тип нового поля — перетащите на странице, чтобы добавить';

  @override
  String get tbNoAnnotationsToFlatten => 'Нет аннотаций для сведения';

  @override
  String get tbNoCustomStamps => 'Нет пользовательских штампов';

  @override
  String get tbNoFormFieldsToFlatten => 'Нет полей формы для сведения';

  @override
  String get tbNoRedactionsToApply => 'Нет вымараний для применения';

  @override
  String get tbNoteTitle => 'Заметка';

  @override
  String get tbOpacity => 'Непрозрачность';

  @override
  String get tbOutline => 'Контур';

  @override
  String get tbPatternScale => 'Масштаб узора';

  @override
  String get tbPickColorFromPage => 'Выбрать цвет со страницы';

  @override
  String get tbRedactionsApplied => 'Вымарывания применены';

  @override
  String get tbRedoShortcut => 'Повторить (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Не удалось перекомпоновать — это не одноколоночный абзац, который этот инструмент может переформатировать. Попробуйте «Заменить текст».';

  @override
  String get tbReflowParagraph => 'Перекомпоновать абзац';

  @override
  String get tbRenameField => 'Переименовать поле';

  @override
  String get tbRenameFieldEllipsis => 'Переименовать поле…';

  @override
  String get tbReplaceImage => 'Заменить изображение';

  @override
  String get tbReplaceImageFailed => 'Не удалось заменить изображение';

  @override
  String get tbReplaceText => 'Заменить текст';

  @override
  String get tbSaveImage => 'Сохранить изображение';

  @override
  String get tbSaveShortcut => 'Сохранить… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Масштаб';

  @override
  String get tbSelectTextForMarkup => 'Выберите текст для разметки';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'выбрано $count',
      many: 'выбрано $count',
      few: 'выбрано $count',
      one: 'Выбор',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Задать…';

  @override
  String get tbStamp => 'Штамп';

  @override
  String get tbStampText => 'Текст штампа';

  @override
  String get tbStrokeOpacityFont => 'Обводка, непрозрачность, шрифт';

  @override
  String get tbStrokeWidthLabel => 'Толщина обводки';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Обводка $width';
  }

  @override
  String get tbStyle => 'Стиль';

  @override
  String get tbTakeoffTotals => 'Итоги обмера';

  @override
  String get tbTextBorder => 'Граница текста';

  @override
  String get tbTextColour => 'Цвет текста';

  @override
  String get tbTextFieldOption => 'Текстовое поле';

  @override
  String get tbTextFill => 'Заливка текста';

  @override
  String get tbTextStyleEllipsis => 'Стиль текста…';

  @override
  String get tbTextTitle => 'Текст';

  @override
  String get tbTipCallout =>
      'Выноска — перетащите от точки к месту размещения поля';

  @override
  String get tbTipContent => 'Редактировать содержимое страницы';

  @override
  String get tbTipCount =>
      'Подсчёт — коснитесь, чтобы ставить галочки и подсчитывать их';

  @override
  String get tbTipDigitalSignature =>
      'Цифровая подпись — перетащите поле, чтобы разместить и подписать';

  @override
  String get tbTipForm =>
      'Поля формы — коснитесь для выбора, дважды коснитесь для заполнения, перетащите для добавления';

  @override
  String get tbTipHighlightDraw => 'Выделение — рисуйте от руки';

  @override
  String get tbTipImage =>
      'Изображение — коснитесь для размещения или растяните рамку';

  @override
  String get tbTipMeasureAngle => 'Измерить угол — щёлкните три точки';

  @override
  String get tbTipMeasureArc => 'Измерить длину дуги — щёлкните три точки';

  @override
  String get tbTipRedact => 'Вымарать — растяните область, затем примените';

  @override
  String get tbTipSignature => 'Подпись — коснитесь страницы, чтобы разместить';

  @override
  String get tbTipSnapshot =>
      'Снимок — растяните область для захвата (вставляется обратно как вектор)';

  @override
  String get tbToolContent => 'Содержимое';

  @override
  String get tbToolForm => 'Форма';

  @override
  String get tbToolRedact => 'Вымарать';

  @override
  String get tbToolSnapshot => 'Снимок';

  @override
  String get tbTools => 'Инструменты';

  @override
  String get tbTotals => 'Итоги';

  @override
  String get tbTypeTextEachTime => 'Вводить текст каждый раз';

  @override
  String get tbUnderline => 'Подчёркивание';

  @override
  String get tbUndoShortcut => 'Отменить (⌘Z)';

  @override
  String get textStyleFont => 'Шрифт';

  @override
  String get textStyleFontSize => 'Размер шрифта';

  @override
  String get textStyleKeep => 'без изменений';

  @override
  String get textStyleStyle => 'Стиль';

  @override
  String get textStyleText => 'Текст';

  @override
  String get textStyleTextFill => 'Заливка текста';

  @override
  String get textStyleTitle => 'Изменить текст и стиль';

  @override
  String get thumbAddPage => 'Добавить страницу';

  @override
  String get thumbClearSelection => 'Очистить выбор';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Копировать $count страницы',
      many: 'Копировать $count страниц',
      few: 'Копировать $count страницы',
      one: 'Копировать страницу',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Копировать выбранные страницы';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вырезать $count страницы',
      many: 'Вырезать $count страниц',
      few: 'Вырезать $count страницы',
      one: 'Вырезать страницу',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Вырезать выбранные страницы';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Удалить $count страницы',
      many: 'Удалить $count страниц',
      few: 'Удалить $count страницы',
      one: 'Удалить страницу',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Удалить выбранные страницы';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Дублировать $count страницы',
      many: 'Дублировать $count страниц',
      few: 'Дублировать $count страницы',
      one: 'Дублировать страницу',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Экспортировать страницы…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Экспортировать $count страницы…',
      many: 'Экспортировать $count страниц…',
      few: 'Экспортировать $count страницы…',
      one: 'Экспортировать страницу…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Экспортировать выбранные страницы';

  @override
  String get thumbInsertBlankAfter => 'Вставить пустую страницу после';

  @override
  String get thumbInsertBlankBefore => 'Вставить пустую страницу перед';

  @override
  String get thumbInsertFileFailed => 'Не удалось вставить этот файл.';

  @override
  String get thumbInsertPdf => 'Вставить PDF…';

  @override
  String get thumbPageActions => 'Действия со страницей';

  @override
  String thumbPageNumber(int number) {
    return 'Страница $number';
  }

  @override
  String get thumbPages => 'Страницы';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вставить $count страницы',
      many: 'Вставить $count страниц',
      few: 'Вставить $count страницы',
      one: 'Вставить страницу',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Повернуть на 180°';

  @override
  String get thumbRotateLeft => 'Повернуть влево';

  @override
  String get thumbRotatePageRight => 'Повернуть страницу вправо';

  @override
  String get thumbRotateRight => 'Повернуть вправо';

  @override
  String get thumbRotateSelectedLeft => 'Повернуть выбранные страницы влево';

  @override
  String get thumbRotateSelectedRight => 'Повернуть выбранные страницы вправо';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'выбрано $count',
      many: 'выбрано $count',
      few: 'выбрано $count',
      one: 'выбрано $count',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Отменить';

  @override
  String get viewerEditFontUnsafe =>
      'Этот шрифт PDF или кодировку нельзя безопасно редактировать.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Для редактирования нужен выбор на одной странице.';

  @override
  String get viewerEditNotEditableRun =>
      'Этот выбор не является одним редактируемым текстовым фрагментом содержимого страницы.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Этот шрифт PDF можно перепечатать, но его стиль изменить нельзя.';

  @override
  String get viewerEditTextStyle => 'Изменить текст и стиль';

  @override
  String get viewerMarkup => 'Разметка';

  @override
  String get viewerMarkupHighlight => 'Выделение';

  @override
  String get viewerMarkupSquiggly => 'Волнистое';

  @override
  String get viewerMarkupStrikeOut => 'Зачеркнуть';

  @override
  String get viewerMarkupUnderline => 'Подчёркивание';

  @override
  String get viewerSelectAll => 'Выбрать всё';
}
