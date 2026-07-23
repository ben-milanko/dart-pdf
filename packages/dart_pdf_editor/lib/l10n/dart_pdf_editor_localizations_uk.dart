// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class DartPdfEditorLocalizationsUk extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get add => 'Додати';

  @override
  String get annotCaret => 'Каретка';

  @override
  String get annotCircle => 'Коло';

  @override
  String get annotFileAttachment => 'Вкладений файл';

  @override
  String get annotFreeText => 'Текстове поле';

  @override
  String get annotHighlight => 'Виділення';

  @override
  String get annotInk => 'Малюнок';

  @override
  String get annotLine => 'Лінія';

  @override
  String get annotLink => 'Посилання';

  @override
  String get annotPolygon => 'Багатокутник';

  @override
  String get annotPolyline => 'Ламана лінія';

  @override
  String get annotRedact => 'Редагування';

  @override
  String get annotSquare => 'Квадрат';

  @override
  String get annotSquiggly => 'Хвиляста лінія';

  @override
  String get annotStamp => 'Штамп';

  @override
  String get annotStrikeOut => 'Закреслення';

  @override
  String get annotText => 'Нотатка';

  @override
  String get annotUnderline => 'Підкреслення';

  @override
  String get annotWidget => 'Поле форми';

  @override
  String get apply => 'Застосувати';

  @override
  String get bookmarkAdd => 'Додати закладку';

  @override
  String get bookmarkAddChild => 'Додати дочірню закладку';

  @override
  String get bookmarkCollapse => 'Згорнути';

  @override
  String get bookmarkDelete => 'Видалити закладку';

  @override
  String get bookmarkEdit => 'Редагувати закладку';

  @override
  String get bookmarkEmpty => 'Немає закладок';

  @override
  String get bookmarkExpand => 'Розгорнути';

  @override
  String get bookmarkExpandedByDefault => 'Розгорнуто за замовчуванням';

  @override
  String get bookmarkNoDestination => 'Немає призначення';

  @override
  String get bookmarkPageFieldLabel => 'Сторінка';

  @override
  String bookmarkPageLabel(int number) {
    return 'Сторінка $number';
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
  String get bookmarkUntitled => 'Без назви';

  @override
  String get cancel => 'Скасувати';

  @override
  String get clear => 'Очистити';

  @override
  String get close => 'Закрити';

  @override
  String get colorApplyingChanges => 'Застосування змін кольору…';

  @override
  String get colorColorFormat => 'Формат кольору';

  @override
  String get colorColorTitle => 'Колір';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count кольору',
      many: 'Вибрано $count кольорів',
      few: 'Вибрано $count кольори',
      one: 'Вибрано $count колір',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Кольори документа';

  @override
  String get colorFillColors => 'Кольори заливки';

  @override
  String get colorFind => 'Знайти';

  @override
  String get colorInDocument => 'У документі';

  @override
  String get colorNoColorsFound => 'Кольорів поки що не знайдено';

  @override
  String get colorNoPageContentColors => 'Кольорів вмісту сторінки не знайдено';

  @override
  String get colorPalette => 'Палітра';

  @override
  String get colorPickColor => 'Вибрати колір';

  @override
  String get colorProcessingTitle => 'Обробка кольорів';

  @override
  String get colorRecent => 'Нещодавні';

  @override
  String get colorReplace => 'Замінити';

  @override
  String get colorReplaceWithTransparent => 'Замінити прозорістю';

  @override
  String get colorScanning => 'Сканування…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Сканування $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Вибрані сторінки ($count)';
  }

  @override
  String get colorStrokeColors => 'Кольори обведення';

  @override
  String get colorTolerance => 'Допуск';

  @override
  String get colorTransparent => 'Прозорий';

  @override
  String get colorWholeDocument => 'Весь документ';

  @override
  String get compareAfter => 'Після';

  @override
  String get compareBefore => 'До';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count зміни',
      many: '$count змін',
      few: '$count зміни',
      one: '1 зміна',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count зміни',
      many: '$count змін',
      few: '$count зміни',
      one: '1 зміна',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(порожньо)';

  @override
  String get compareNextChange => 'Наступна зміна';

  @override
  String get compareNoChanges => 'Немає змін';

  @override
  String get compareNoDifferences => 'Немає відмінностей між двома документами';

  @override
  String get compareOverlay => 'Накладання';

  @override
  String comparePageHeader(int page) {
    return 'Сторінка $page';
  }

  @override
  String get comparePreviousChange => 'Попередня зміна';

  @override
  String get compareSideBySide => 'Поруч';

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
  String get editorViewAuthorNameTitle => 'Ім’я автора';

  @override
  String get lineStyleDashDot => 'Штрих-пунктир';

  @override
  String get lineStyleDashed => 'Штрихова';

  @override
  String get lineStyleDotted => 'Пунктирна';

  @override
  String get lineStyleSolid => 'Суцільна';

  @override
  String get measCalibrate => 'Калібрувати';

  @override
  String get measCalibrateScale => 'Калібрувати масштаб';

  @override
  String get measDepthLabel => 'Глибина: ';

  @override
  String get measKindAngle => 'Кут';

  @override
  String get measKindArc => 'Дуга';

  @override
  String get measKindArea => 'Площа';

  @override
  String get measKindCount => 'Кількість';

  @override
  String get measKindLength => 'Довжина';

  @override
  String get measKindNetArea => 'Чиста площа';

  @override
  String get measKindPerimeter => 'Периметр';

  @override
  String get measKindSlope => 'Ухил';

  @override
  String get measKindVolume => 'Об’єм';

  @override
  String get measLineRepresents => 'Намальована вами лінія відповідає:';

  @override
  String get measMeasure => 'Виміряти';

  @override
  String get measSetScale => 'Установити масштаб вимірювання';

  @override
  String get measSetScaleButton => 'Установити масштаб';

  @override
  String get measVolumeDepth => 'Глибина об’єму';

  @override
  String get menuAddNode => 'Додати вузол';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Застосувати анотації до сторінок',
      one: 'Застосувати анотацію до сторінок',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Застосувати до сторінок…';

  @override
  String get menuBringToFront => 'На передній план';

  @override
  String get menuCheck => 'Позначити';

  @override
  String get menuChooseValue => 'Вибрати значення…';

  @override
  String get menuClearCheck => 'Зняти позначку';

  @override
  String get menuConvertToCheckBox => 'Перетворити на прапорець';

  @override
  String get menuConvertToImageButton => 'Перетворити на кнопку із зображенням';

  @override
  String get menuConvertToTextField => 'Перетворити на текстове поле';

  @override
  String get menuDeleteField => 'Видалити поле';

  @override
  String get menuEditValue => 'Редагувати значення…';

  @override
  String get menuFieldName => 'Назва поля';

  @override
  String get menuFieldValue => 'Значення поля';

  @override
  String get menuFlattenForm => 'Звести форму';

  @override
  String get menuRecolour => 'Перефарбувати…';

  @override
  String get menuRemoveNode => 'Вилучити вузол';

  @override
  String get menuSetAsDefaultStyle => 'Установити як стиль за замовчуванням';

  @override
  String get menuRename => 'Перейменувати…';

  @override
  String get menuSelectOption => 'Вибрати варіант';

  @override
  String get menuSendToBack => 'На задній план';

  @override
  String get menuSetImage => 'Установити зображення…';

  @override
  String get menuTextStyle => 'Стиль тексту…';

  @override
  String get none => 'Немає';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Колір';

  @override
  String get overlayEditText => 'Редагувати текст';

  @override
  String get overlayFont => 'Шрифт';

  @override
  String get overlayLarger => 'Більше';

  @override
  String get overlayMore => 'Більше';

  @override
  String get overlayNote => 'Нотатка';

  @override
  String get overlaySmaller => 'Менше';

  @override
  String get overlayStampText => 'Текст штампа';

  @override
  String get overlayUnderline => 'Підкреслення';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Уведіть сторінки в діапазоні від 1 до $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'Остання сторінка не повинна бути раніше за першу.';

  @override
  String get pageRangeFrom => 'Від';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сторінки',
      many: '$count сторінок',
      few: '$count сторінки',
      one: '1 сторінка',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'До';

  @override
  String get panelDragToMovePanel => 'Перетягніть, щоб перемістити панель';

  @override
  String get paste => 'Вставити';

  @override
  String get propAlign => 'Вирівнювання';

  @override
  String get propAlignCenter => 'Вирівняти по центру';

  @override
  String get propAlignLeft => 'Вирівняти ліворуч';

  @override
  String get propAlignRight => 'Вирівняти праворуч';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count анотації',
      many: '$count анотацій',
      few: '$count анотації',
      one: '$count анотація',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Автор';

  @override
  String get propAutoSize => 'Автопідбір розміру';

  @override
  String get propBold => 'Жирний';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Вбудований шрифт';

  @override
  String get propCallout => 'Виноска';

  @override
  String get propCharSpacing => 'Міжсимвольний інтервал';

  @override
  String get propColor => 'Колір';

  @override
  String get propColour => 'Колір';

  @override
  String get propContents => 'Вміст';

  @override
  String get propEditsApplyToAll =>
      'Зміни застосовуються до всіх сумісних анотацій';

  @override
  String get propFieldName => 'Назва поля';

  @override
  String get propFieldTypeCheckBox => 'Прапорець';

  @override
  String get propFieldTypeComboBox => 'Поле зі списком';

  @override
  String get propFieldTypeImageButton => 'Кнопка із зображенням';

  @override
  String get propFieldTypeListBox => 'Список';

  @override
  String get propFieldTypeRadioGroup => 'Група перемикачів';

  @override
  String get propFieldTypeSignature => 'Підпис';

  @override
  String get propFieldTypeText => 'Текстове поле';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Тип поля: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Невідоме поле';

  @override
  String get propFill => 'Заливка';

  @override
  String get propFont => 'Шрифт';

  @override
  String get propFontSubsetTooltip =>
      'Цей шрифт є підмножиною — можна вводити лише символи, уже використані в документі.';

  @override
  String get propFontWidth => 'Ширина шрифту';

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
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Обмежені символи';

  @override
  String get propLineEnd => 'Кінець лінії';

  @override
  String get propLineEndingButt => 'Плоский';

  @override
  String get propLineEndingCircle => 'Коло';

  @override
  String get propLineEndingClosedArrow => 'Закрита стрілка';

  @override
  String get propLineEndingClosedArrowRev => 'Закрита стрілка (зворотна)';

  @override
  String get propLineEndingDiamond => 'Ромб';

  @override
  String get propLineEndingOpenArrow => 'Відкрита стрілка';

  @override
  String get propLineEndingOpenArrowRev => 'Відкрита стрілка (зворотна)';

  @override
  String get propLineEndingSlash => 'Скіс';

  @override
  String get propLineEndingSquare => 'Квадрат';

  @override
  String get propLineSpacing => 'Міжрядковий інтервал';

  @override
  String get propLineStart => 'Початок лінії';

  @override
  String get propLineType => 'Тип лінії';

  @override
  String get propLoadFont => 'Завантажити шрифт…';

  @override
  String get propLoadFontSubtitle => 'Файл TTF або OTF';

  @override
  String get propMoreColors => 'Більше кольорів…';

  @override
  String get propMultiline => 'Багаторядкове';

  @override
  String get propNoFill => 'Без заливки';

  @override
  String get propNoFontsFound => 'Шрифтів не знайдено';

  @override
  String get propNoOutline => 'Без контуру';

  @override
  String get propOpacity => 'Непрозорість';

  @override
  String get propOutline => 'Контур';

  @override
  String get propPageLabel => 'Сторінка';

  @override
  String propPageNumber(int number) {
    return 'Сторінка $number';
  }

  @override
  String get propPropertiesTitle => 'Властивості';

  @override
  String get propRecentlyUsed => 'Нещодавно використані';

  @override
  String get propScale => 'Масштаб';

  @override
  String get propSearchFonts => 'Пошук шрифтів';

  @override
  String get propSectionAllFonts => 'Усі шрифти';

  @override
  String get propSectionAppearance => 'Вигляд';

  @override
  String get propSectionContent => 'Вміст';

  @override
  String get propSectionFormField => 'Поле форми';

  @override
  String get propSectionInThisDocument => 'У цьому документі';

  @override
  String get propSectionPositionSize => 'Позиція та розмір (pt)';

  @override
  String get propSectionSelection => 'Виділення';

  @override
  String get propSectionText => 'Текст';

  @override
  String get propSelectAnnotationPrompt =>
      'Виберіть анотацію, щоб побачити її властивості';

  @override
  String get propSize => 'Розмір';

  @override
  String get propStandardPdfFont => 'Стандартний шрифт PDF';

  @override
  String get propStroke => 'Обведення';

  @override
  String get propStyle => 'Стиль';

  @override
  String get propSystemFont => 'Системний шрифт';

  @override
  String get propType => 'Тип';

  @override
  String get propUnderline => 'Підкреслення';

  @override
  String get propVaries => 'Різняться';

  @override
  String get redo => 'Повторити';

  @override
  String get reflowNoContent => 'Немає видобувного вмісту';

  @override
  String reflowPageLabel(int number) {
    return 'Сторінка $number';
  }

  @override
  String get reflowSaveOrShare => 'Зберегти або поділитися';

  @override
  String get reflowViewFigure => 'Переглянути зображення';

  @override
  String get remove => 'Вилучити';

  @override
  String get rename => 'Перейменувати';

  @override
  String get reset => 'Скинути';

  @override
  String get save => 'Зберегти';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Сторінка $page';
  }

  @override
  String get sbarCallout => 'Виноска';

  @override
  String get sbarFieldButton => 'Поле-кнопка';

  @override
  String get sbarFieldChoice => 'Поле вибору';

  @override
  String get sbarFieldGeneric => 'Поле форми';

  @override
  String get sbarFieldSignature => 'Поле підпису';

  @override
  String get sbarFieldText => 'Текстове поле';

  @override
  String get sbarStateAccepted => 'Прийнято';

  @override
  String get sbarStateCancelled => 'Скасовано';

  @override
  String get sbarStateMarked => 'Позначено';

  @override
  String get sbarStateRejected => 'Відхилено';

  @override
  String get sbarStateResolved => 'Вирішено';

  @override
  String get sbarStateUnmarked => 'Знято позначку';

  @override
  String get searchClearSearch => 'Очистити пошук';

  @override
  String get searchEmptyHint =>
      'Виконайте пошук у документі, щоб побачити тут усі збіги';

  @override
  String get searchMatchCase => 'Враховувати регістр';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count збігу',
      many: '$count збігів',
      few: '$count збіги',
      one: '1 збіг',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Наступний збіг';

  @override
  String searchNoMatches(String query) {
    return 'Немає збігів для «$query»';
  }

  @override
  String searchPageHeader(int page) {
    return 'Сторінка $page';
  }

  @override
  String get searchPreviousMatch => 'Попередній збіг';

  @override
  String get searchRegex => 'Регулярний вираз';

  @override
  String get searchResultsTitle => 'Результати пошуку';

  @override
  String get searchWholeWord => 'Слово цілком';

  @override
  String get shellControls => 'Елементи керування';

  @override
  String get shellDefaultAuthor => 'Автор за замовчуванням…';

  @override
  String get shellHighlightFormFields => 'Підсвічувати поля форми';

  @override
  String get shellKeyboardShortcutsMenu => 'Клавіатурні скорочення…';

  @override
  String get shellKeyboardShortcutsTitle => 'Клавіатурні скорочення';

  @override
  String get shellShortcutsSearchHint => 'Пошук скорочень';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Немає скорочень, що відповідають «$query»';
  }

  @override
  String get shellShortcutGroupSelect => 'Виділення';

  @override
  String get shellShortcutGroupMarkup => 'Розмітка';

  @override
  String get shellShortcutGroupDraw => 'Малювання';

  @override
  String get shellShortcutGroupShapes => 'Фігури';

  @override
  String get shellShortcutGroupInsert => 'Вставлення';

  @override
  String get shellShortcutGroupMeasure => 'Вимірювання';

  @override
  String get shellShortcutGroupEdit => 'Редагування';

  @override
  String get shellNotSet => 'Не встановлено';

  @override
  String get shellPageColor => 'Колір сторінки…';

  @override
  String get shellPageGrid => 'Сітка сторінок';

  @override
  String get shellPanelAnnotations => 'Анотації';

  @override
  String get shellPanelBookmarks => 'Закладки';

  @override
  String get shellPanelPages => 'Сторінки';

  @override
  String get shellPanelProperties => 'Властивості';

  @override
  String get shellPanelSearchResults => 'Результати пошуку';

  @override
  String get shellPanels => 'Панелі';

  @override
  String get shellPressAKey => 'Натисніть клавішу';

  @override
  String get shellPressLetterKeyHint =>
      'Натисніть літерну клавішу або Delete, щоб очистити.';

  @override
  String get shellReflow => 'Переформатування';

  @override
  String get shellReflowText => 'Переформатувати текст';

  @override
  String get shellResetZoom => 'Скинути масштаб';

  @override
  String get shellSectionShell => 'Оболонка';

  @override
  String get shellSectionView => 'Перегляд';

  @override
  String get shellSettings => 'Налаштування';

  @override
  String get shellShowAnnotations => 'Показувати анотації';

  @override
  String get shellTabHere => 'Вкладка тут';

  @override
  String get shellUnbound => 'Не призначено';

  @override
  String get shellZoom => 'Масштаб';

  @override
  String sidebarByAuthor(String author) {
    return 'від $author';
  }

  @override
  String get sidebarCancelSelection => 'Скасувати виділення';

  @override
  String get sidebarClearSearch => 'Очистити пошук';

  @override
  String get sidebarDeleteSelected => 'Видалити вибрані';

  @override
  String get sidebarDeleteSignature => 'Видалити підпис';

  @override
  String get sidebarMore => 'Більше';

  @override
  String get sidebarNoAnnotations => 'Немає анотацій';

  @override
  String get sidebarNoMatchingAnnotations => 'Немає відповідних анотацій';

  @override
  String sidebarPageHeader(int number) {
    return 'Сторінка $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Це вилучить цифровий підпис з документа. Цю дію можна скасувати.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Це вилучить цифровий підпис від «$name» з документа. Цю дію можна скасувати.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Вилучити підпис?';

  @override
  String get sidebarReopen => 'Відкрити знову';

  @override
  String get sidebarReply => 'Відповісти';

  @override
  String get sidebarResolve => 'Вирішити';

  @override
  String get sidebarSearchHint => 'Пошук анотацій';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count',
      many: 'Вибрано $count',
      few: 'Вибрано $count',
      one: 'Вибрано $count',
    );
    return '$_temp0';
  }

  @override
  String get sidebarWriteReplyHint => 'Напишіть відповідь…';

  @override
  String get sigTitle => 'Підпис';

  @override
  String get signIdCreate => 'Створити';

  @override
  String get signIdEmail => 'Електронна пошта (необов’язково)';

  @override
  String get signIdName => 'Ім’я';

  @override
  String get signIdNameHint => 'Ваше ім’я, як воно має відображатися в підписі';

  @override
  String get signIdNameRequired => 'Уведіть ім’я';

  @override
  String get signIdOrganization => 'Організація (необов’язково)';

  @override
  String get signIdSelfSignedInfo =>
      'Це створює самопідписану особу. Підписи читатимуться як «підписано, дійсність невідома» в Adobe Acrobat та інших програмах для читання — так само, як їхні власні самопідписані ідентифікатори. Зелена позначка потребує платного, публічно довіреного центру сертифікації.';

  @override
  String get signIdTitle => 'Створити особу для підписування';

  @override
  String get stampBox => 'Прямокутник';

  @override
  String get stampCircle => 'Коло';

  @override
  String get stampCustomCaption => 'Власний штамп';

  @override
  String get stampDateFormat => 'Формат дати';

  @override
  String get stampDeleteComponent => 'Видалити вибраний компонент';

  @override
  String get stampDeleteStamp => 'Видалити штамп';

  @override
  String get stampEditStamp => 'Редагувати штамп';

  @override
  String get stampExport => 'Експортувати…';

  @override
  String get stampFieldDate => 'Дата';

  @override
  String get stampFieldDateTime => 'Дата й час';

  @override
  String get stampFieldTime => 'Час';

  @override
  String get stampFieldUsername => 'Ім’я користувача';

  @override
  String get stampFont => 'Шрифт';

  @override
  String get stampFontBold => 'Жирний';

  @override
  String get stampFontItalic => 'Курсив';

  @override
  String get stampHeight => 'Висота';

  @override
  String get stampImage => 'Зображення';

  @override
  String get stampImport => 'Імпортувати…';

  @override
  String get stampInsertField => 'Вставити поле';

  @override
  String get stampMoreColors => 'Більше кольорів…';

  @override
  String get stampNewStamp => 'Новий штамп…';

  @override
  String get stampNewStampTitle => 'Новий штамп';

  @override
  String get stampSelectTextToEdit => 'Виберіть текст для редагування';

  @override
  String get stampSelectedText => 'Вибраний текст';

  @override
  String get stampSignature => 'Підпис';

  @override
  String get stampStamps => 'Штампи';

  @override
  String get stampText => 'Текст';

  @override
  String get stampTime12Hour => '12 год';

  @override
  String get stampTime24Hour => '24 год';

  @override
  String get stampTimeFormat => 'Формат часу';

  @override
  String get stampWidth => 'Ширина';

  @override
  String get takeoffArea => 'Площа';

  @override
  String get takeoffCount => 'Кількість';

  @override
  String get takeoffEmpty => 'Вимірювань поки що немає.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count групи',
      many: '$count груп',
      few: '$count групи',
      one: '$count група',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елемента',
      many: '$count елементів',
      few: '$count елементи',
      one: '$count елемент',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Довжина';

  @override
  String get takeoffTitle => 'Обсяг робіт';

  @override
  String get tbAddInkAnnotation => 'Додати анотацію-малюнок';

  @override
  String get tbAlign => 'Вирівнювання';

  @override
  String get tbAlignBottom => 'Вирівняти по нижньому краю';

  @override
  String get tbAlignHorizontalCenters => 'Вирівняти по горизонтальних центрах';

  @override
  String get tbAlignLeft => 'Вирівняти ліворуч';

  @override
  String get tbAlignRight => 'Вирівняти праворуч';

  @override
  String get tbAlignTop => 'Вирівняти по верхньому краю';

  @override
  String get tbAlignVerticalCenters => 'Вирівняти по вертикальних центрах';

  @override
  String get tbAnnotationsFlattened => 'Анотації зведено у сторінки';

  @override
  String get tbApplyRedactionsMessage =>
      'Позначений вміст буде остаточно вилучено з документа. Це не можна скасувати.';

  @override
  String get tbApplyRedactionsTitle => 'Застосувати редагування?';

  @override
  String get tbApplyRedactionsTooltip => 'Застосувати редагування (незворотно)';

  @override
  String get tbAutosizeTextBox => 'Автопідбір розміру текстового поля (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Намалюйте лінію відомої довжини, щоб відкалібрувати масштаб.';

  @override
  String get tbCharSpacing => 'Міжсимвольний інтервал';

  @override
  String get tbCheckBoxOption => 'Прапорець';

  @override
  String get tbCheckMarksOnDocument => 'Позначки на документі';

  @override
  String get tbColorLabel => 'Колір';

  @override
  String get tbColorProcessingTooltip =>
      'Обробка кольорів — знайти й замінити кольори вмісту сторінки';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Замінено $count кольору',
      many: 'Замінено $count кольорів',
      few: 'Замінено $count кольори',
      one: 'Замінено 1 колір',
      zero: 'Відповідних кольорів не знайдено',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Перетворити на прапорець';

  @override
  String get tbConvertToImageButton => 'Перетворити на кнопку із зображенням';

  @override
  String get tbConvertToTextField => 'Перетворити на текстове поле';

  @override
  String get tbCornerRadius => 'Радіус кута';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count анотації',
      many: 'Видалити $count анотацій',
      few: 'Видалити $count анотації',
      one: 'Видалити анотацію',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Видалити елемент';

  @override
  String get tbDeleteField => 'Видалити поле';

  @override
  String get tbDiscardDrawing => 'Відхилити малюнок';

  @override
  String get tbDistributeHorizontally => 'Розподілити горизонтально';

  @override
  String get tbDistributeVertically => 'Розподілити вертикально';

  @override
  String get tbDrawNewSignature => 'Намалювати новий підпис…';

  @override
  String get tbEditAnnotationText => 'Редагувати текст анотації';

  @override
  String get tbEditTextStyle => 'Редагувати текст і стиль';

  @override
  String get tbElement => 'Елемент';

  @override
  String get tbEraserSize => 'Розмір гумки';

  @override
  String get tbFieldActions => 'Дії поля';

  @override
  String get tbFieldName => 'Назва поля';

  @override
  String tbFieldNamed(String name) {
    return 'Поле: $name';
  }

  @override
  String get tbFieldValue => 'Значення поля';

  @override
  String get tbFill => 'Заливка';

  @override
  String get tbFingerDraws =>
      'Палець малює — торкніться, щоб натомість прокручувати';

  @override
  String get tbFingerScrolls =>
      'Палець прокручує (перо малює) — торкніться, щоб він малював';

  @override
  String get tbFlattenAnnotationsTooltip => 'Звести анотації у сторінки';

  @override
  String get tbFlattenForm => 'Звести форму';

  @override
  String get tbFlattenFormBakeValues =>
      'Звести форму — закріпити значення у сторінках';

  @override
  String get tbFlattenLabel => 'Звести';

  @override
  String get tbFont => 'Шрифт';

  @override
  String get tbFontSize => 'Розмір шрифту';

  @override
  String get tbFontWidth => 'Ширина шрифту';

  @override
  String get tbFormFieldsFlattened => 'Поля форми зведено у сторінки';

  @override
  String get tbGroupDraw => 'Малювання';

  @override
  String get tbGroupEdit => 'Редагування';

  @override
  String get tbGroupInsert => 'Вставлення';

  @override
  String get tbGroupMarkup => 'Розмітка';

  @override
  String get tbGroupMeasure => 'Вимірювання';

  @override
  String get tbGroupSelect => 'Виділення';

  @override
  String get tbGroupShapes => 'Фігури';

  @override
  String get tbImageButtonOption => 'Кнопка із зображенням';

  @override
  String get tbLineEnd => 'Кінець лінії';

  @override
  String get tbLineSpacing => 'Міжрядковий інтервал';

  @override
  String get tbLineStart => 'Початок лінії';

  @override
  String get tbLineType => 'Тип лінії';

  @override
  String get tbManageStamps => 'Керувати штампами…';

  @override
  String get tbMarkupHighlight => 'Виділення';

  @override
  String get tbMarkupHighlightTip => 'Виділити виділене';

  @override
  String get tbMarkupSquiggly => 'Хвиляста лінія';

  @override
  String get tbMarkupSquigglyTip => 'Хвиляста лінія під виділеним';

  @override
  String get tbMarkupStrikeOut => 'Закреслити';

  @override
  String get tbMarkupStrikeOutTip => 'Закреслити виділене';

  @override
  String get tbMarkupUnderline => 'Підкреслення';

  @override
  String get tbMarkupUnderlineTip => 'Підкреслити виділене';

  @override
  String get tbMoreColors => 'Більше кольорів…';

  @override
  String get tbNameArrow => 'Стрілка';

  @override
  String get tbNameCallout => 'Виноска';

  @override
  String get tbNameCloudPolygon => 'Хмароподібний багатокутник';

  @override
  String get tbNameCount => 'Підрахунок';

  @override
  String get tbNameDigitalSignature => 'Цифровий підпис';

  @override
  String get tbNameDraw => 'Малювати';

  @override
  String get tbNameEllipse => 'Еліпс';

  @override
  String get tbNameEraser => 'Стерти штрихи малюнка';

  @override
  String get tbNameHighlight => 'Виділення';

  @override
  String get tbNameImage => 'Зображення';

  @override
  String get tbNameLine => 'Лінія';

  @override
  String get tbNameMeasureAngle => 'Виміряти кут';

  @override
  String get tbNameMeasureArc => 'Виміряти довжину дуги';

  @override
  String get tbNameMeasureArea => 'Виміряти площу';

  @override
  String get tbNameMeasureDistance => 'Виміряти відстань';

  @override
  String get tbNameMeasurePerimeter => 'Виміряти периметр';

  @override
  String get tbNameMeasureSlope => 'Виміряти ухил (підйом/пробіг)';

  @override
  String get tbNameMeasureVolume => 'Виміряти об’єм (площа × глибина)';

  @override
  String get tbNameNote => 'Нотатка';

  @override
  String get tbNamePolygon => 'Багатокутник';

  @override
  String get tbNamePolyline => 'Ламана лінія';

  @override
  String get tbNameRectangle => 'Прямокутник';

  @override
  String get tbNameSelect => 'Виділити';

  @override
  String get tbNameSignature => 'Підпис';

  @override
  String get tbNameStamp => 'Штамп';

  @override
  String get tbNameTextBox => 'Текстове поле';

  @override
  String get tbNewFieldType =>
      'Тип нового поля — перетягніть на сторінці, щоб додати його';

  @override
  String get tbNoAnnotationsToFlatten => 'Немає анотацій для зведення';

  @override
  String get tbNoCustomStamps => 'Немає власних штампів';

  @override
  String get tbNoFormFieldsToFlatten => 'Немає полів форми для зведення';

  @override
  String get tbNoRedactionsToApply => 'Немає редагувань для застосування';

  @override
  String get tbNoteTitle => 'Нотатка';

  @override
  String get tbOpacity => 'Непрозорість';

  @override
  String get tbOutline => 'Контур';

  @override
  String get tbPatternScale => 'Масштаб візерунка';

  @override
  String get tbPickColorFromPage => 'Вибрати колір зі сторінки';

  @override
  String get tbRedactionsApplied => 'Редагування застосовано';

  @override
  String get tbRedoShortcut => 'Повторити (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Не вдалося переформатувати — це не одноколонковий абзац, який цей інструмент може переверстати. Спробуйте натомість «Замінити текст».';

  @override
  String get tbReflowParagraph => 'Переформатувати абзац';

  @override
  String get tbRenameField => 'Перейменувати поле';

  @override
  String get tbRenameFieldEllipsis => 'Перейменувати поле…';

  @override
  String get tbReplaceImage => 'Замінити зображення';

  @override
  String get tbReplaceImageFailed => 'Не вдалося замінити зображення';

  @override
  String get tbReplaceText => 'Замінити текст';

  @override
  String get tbSaveImage => 'Зберегти зображення';

  @override
  String get tbSaveShortcut => 'Зберегти… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Масштаб';

  @override
  String get tbSelectTextForMarkup =>
      'Виберіть текст, щоб скористатися розміткою';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count',
      many: 'Вибрано $count',
      few: 'Вибрано $count',
      one: 'Виділення',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Установити…';

  @override
  String get tbStamp => 'Штамп';

  @override
  String get tbStampText => 'Текст штампа';

  @override
  String get tbStrokeOpacityFont => 'Обведення, непрозорість, шрифт';

  @override
  String get tbStrokeWidthLabel => 'Товщина обведення';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Обведення $width';
  }

  @override
  String get tbStyle => 'Стиль';

  @override
  String get tbTakeoffTotals => 'Підсумки обсягу робіт';

  @override
  String get tbTextBorder => 'Рамка тексту';

  @override
  String get tbTextColour => 'Колір тексту';

  @override
  String get tbTextFieldOption => 'Текстове поле';

  @override
  String get tbTextFill => 'Заливка тексту';

  @override
  String get tbTextStyleEllipsis => 'Стиль тексту…';

  @override
  String get tbTextTitle => 'Текст';

  @override
  String get tbTipCallout =>
      'Виноска — перетягніть від точки туди, де має бути поле';

  @override
  String get tbTipContent => 'Редагувати вміст сторінки';

  @override
  String get tbTipCount =>
      'Підрахунок — торкайтеся, щоб ставити позначки й підраховувати їх';

  @override
  String get tbTipDigitalSignature =>
      'Цифровий підпис — перетягніть поле, щоб розмістити й підписати';

  @override
  String get tbTipForm =>
      'Поля форми — торкніться, щоб вибрати, торкніться двічі, щоб заповнити, перетягніть, щоб додати';

  @override
  String get tbTipHighlightDraw => 'Виділення — малюйте від руки';

  @override
  String get tbTipImage =>
      'Зображення — торкніться, щоб розмістити, або перетягніть поле';

  @override
  String get tbTipMeasureAngle => 'Виміряти кут — клацніть три точки';

  @override
  String get tbTipMeasureArc => 'Виміряти довжину дуги — клацніть три точки';

  @override
  String get tbTipRedact =>
      'Редагувати — перетягніть область, потім застосуйте';

  @override
  String get tbTipSignature =>
      'Підпис — торкніться сторінки, щоб розмістити його';

  @override
  String get tbTipSnapshot =>
      'Знімок — перетягніть область, щоб захопити її (вставляється назад як вектор)';

  @override
  String get tbToolContent => 'Вміст';

  @override
  String get tbToolForm => 'Форма';

  @override
  String get tbToolRedact => 'Редагувати';

  @override
  String get tbToolSnapshot => 'Знімок';

  @override
  String get tbTools => 'Інструменти';

  @override
  String get tbTotals => 'Підсумки';

  @override
  String get tbTypeTextEachTime => 'Уводити текст щоразу';

  @override
  String get tbUnderline => 'Підкреслення';

  @override
  String get tbUndoShortcut => 'Відмінити (⌘Z)';

  @override
  String get textStyleFont => 'Шрифт';

  @override
  String get textStyleFontSize => 'Розмір шрифту';

  @override
  String get textStyleKeep => 'залишити';

  @override
  String get textStyleStyle => 'Стиль';

  @override
  String get textStyleText => 'Текст';

  @override
  String get textStyleTextFill => 'Заливка тексту';

  @override
  String get textStyleTitle => 'Редагувати текст і стиль';

  @override
  String get thumbAddPage => 'Додати сторінку';

  @override
  String get thumbClearSelection => 'Очистити виділення';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Копіювати $count сторінки',
      many: 'Копіювати $count сторінок',
      few: 'Копіювати $count сторінки',
      one: 'Копіювати сторінку',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Копіювати вибрані сторінки';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вирізати $count сторінки',
      many: 'Вирізати $count сторінок',
      few: 'Вирізати $count сторінки',
      one: 'Вирізати сторінку',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Вирізати вибрані сторінки';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count сторінки',
      many: 'Видалити $count сторінок',
      few: 'Видалити $count сторінки',
      one: 'Видалити сторінку',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Видалити вибрані сторінки';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Дублювати $count сторінки',
      many: 'Дублювати $count сторінок',
      few: 'Дублювати $count сторінки',
      one: 'Дублювати сторінку',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Експортувати сторінки…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Експортувати $count сторінки…',
      many: 'Експортувати $count сторінок…',
      few: 'Експортувати $count сторінки…',
      one: 'Експортувати сторінку…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Експортувати вибрані сторінки';

  @override
  String get thumbInsertBlankAfter => 'Вставити порожню сторінку після';

  @override
  String get thumbInsertBlankBefore => 'Вставити порожню сторінку перед';

  @override
  String get thumbInsertFileFailed => 'Не вдалося вставити цей файл.';

  @override
  String get thumbInsertPdf => 'Вставити PDF…';

  @override
  String get thumbPageActions => 'Дії зі сторінкою';

  @override
  String thumbPageNumber(int number) {
    return 'Сторінка $number';
  }

  @override
  String get thumbPages => 'Сторінки';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вставити $count сторінки',
      many: 'Вставити $count сторінок',
      few: 'Вставити $count сторінки',
      one: 'Вставити сторінку',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Повернути на 180°';

  @override
  String get thumbRotateLeft => 'Повернути ліворуч';

  @override
  String get thumbRotatePageRight => 'Повернути сторінку праворуч';

  @override
  String get thumbRotateRight => 'Повернути праворуч';

  @override
  String get thumbRotateSelectedLeft => 'Повернути вибрані сторінки ліворуч';

  @override
  String get thumbRotateSelectedRight => 'Повернути вибрані сторінки праворуч';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count',
      many: 'Вибрано $count',
      few: 'Вибрано $count',
      one: 'Вибрано $count',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Відмінити';

  @override
  String get viewerEditFontUnsafe =>
      'Цей шрифт або кодування PDF не можна безпечно редагувати.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Редагування потребує виділення на одній сторінці.';

  @override
  String get viewerEditNotEditableRun =>
      'Це виділення не є одним придатним для редагування текстовим фрагментом вмісту сторінки.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Цей шрифт PDF можна перевводити, але його стиль змінити не можна.';

  @override
  String get viewerEditTextStyle => 'Редагувати текст і стиль';

  @override
  String get viewerMarkup => 'Розмітка';

  @override
  String get viewerMarkupHighlight => 'Виділення';

  @override
  String get viewerMarkupSquiggly => 'Хвиляста лінія';

  @override
  String get viewerMarkupStrikeOut => 'Закреслити';

  @override
  String get viewerMarkupUnderline => 'Підкреслення';

  @override
  String get viewerSelectAll => 'Виділити все';
}
