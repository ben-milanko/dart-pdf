// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class DartPdfEditorLocalizationsEs extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get add => 'Añadir';

  @override
  String get annotCaret => 'Cursor de inserción';

  @override
  String get annotCircle => 'Círculo';

  @override
  String get annotFileAttachment => 'Archivo adjunto';

  @override
  String get annotFreeText => 'Cuadro de texto';

  @override
  String get annotHighlight => 'Resaltado';

  @override
  String get annotInk => 'Trazo a mano';

  @override
  String get annotLine => 'Línea';

  @override
  String get annotLink => 'Enlace';

  @override
  String get annotPolygon => 'Polígono';

  @override
  String get annotPolyline => 'Polilínea';

  @override
  String get annotRedact => 'Censura';

  @override
  String get annotSquare => 'Rectángulo';

  @override
  String get annotSquiggly => 'Ondulado';

  @override
  String get annotStamp => 'Sello';

  @override
  String get annotStrikeOut => 'Tachado';

  @override
  String get annotText => 'Nota';

  @override
  String get annotUnderline => 'Subrayado';

  @override
  String get annotWidget => 'Campo de formulario';

  @override
  String get apply => 'Aplicar';

  @override
  String get bookmarkAdd => 'Añadir marcador';

  @override
  String get bookmarkAddChild => 'Añadir marcador secundario';

  @override
  String get bookmarkCollapse => 'Contraer';

  @override
  String get bookmarkDelete => 'Eliminar marcador';

  @override
  String get bookmarkEdit => 'Editar marcador';

  @override
  String get bookmarkEmpty => 'Sin marcadores';

  @override
  String get bookmarkExpand => 'Expandir';

  @override
  String get bookmarkExpandedByDefault => 'Expandido de forma predeterminada';

  @override
  String get bookmarkNoDestination => 'Sin destino';

  @override
  String get bookmarkPageFieldLabel => 'Página';

  @override
  String bookmarkPageLabel(int number) {
    return 'Página $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Marcadores';

  @override
  String get bookmarkTitleLabel => 'Título';

  @override
  String get bookmarkUntitled => 'Sin título';

  @override
  String get cancel => 'Cancelar';

  @override
  String get clear => 'Borrar';

  @override
  String get close => 'Cerrar';

  @override
  String get colorApplyingChanges => 'Aplicando cambios de color…';

  @override
  String get colorColorFormat => 'Formato de color';

  @override
  String get colorColorTitle => 'Color';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colores seleccionados',
      one: '$count color seleccionado',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Colores del documento';

  @override
  String get colorFillColors => 'Colores de relleno';

  @override
  String get colorFind => 'Buscar';

  @override
  String get colorInDocument => 'En el documento';

  @override
  String get colorNoColorsFound => 'Aún no se han encontrado colores';

  @override
  String get colorNoPageContentColors =>
      'No se encontraron colores en el contenido de la página';

  @override
  String get colorPalette => 'Paleta';

  @override
  String get colorPickColor => 'Elegir color';

  @override
  String get colorProcessingTitle => 'Procesamiento de color';

  @override
  String get colorRecent => 'Recientes';

  @override
  String get colorReplace => 'Reemplazar';

  @override
  String get colorReplaceWithTransparent => 'Reemplazar por transparente';

  @override
  String get colorScanning => 'Analizando…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Analizando $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Páginas seleccionadas ($count)';
  }

  @override
  String get colorStrokeColors => 'Colores de trazo';

  @override
  String get colorTolerance => 'Tolerancia';

  @override
  String get colorTransparent => 'Transparente';

  @override
  String get colorWholeDocument => 'Todo el documento';

  @override
  String get compareAfter => 'Después';

  @override
  String get compareBefore => 'Antes';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios',
      one: '1 cambio',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios',
      one: '1 cambio',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(vacío)';

  @override
  String get compareNextChange => 'Cambio siguiente';

  @override
  String get compareNoChanges => 'Sin cambios';

  @override
  String get compareNoDifferences =>
      'No hay diferencias entre los dos documentos';

  @override
  String get compareOverlay => 'Superposición';

  @override
  String comparePageHeader(int page) {
    return 'Página $page';
  }

  @override
  String get comparePreviousChange => 'Cambio anterior';

  @override
  String get compareSideBySide => 'Lado a lado';

  @override
  String get copy => 'Copiar';

  @override
  String get cut => 'Cortar';

  @override
  String get delete => 'Eliminar';

  @override
  String get done => 'Listo';

  @override
  String get edit => 'Editar';

  @override
  String get editorViewAuthorNameTitle => 'Nombre del autor';

  @override
  String get lineStyleDashDot => 'Trazo y punto';

  @override
  String get lineStyleDashed => 'Discontinua';

  @override
  String get lineStyleDotted => 'Punteada';

  @override
  String get lineStyleSolid => 'Continua';

  @override
  String get measCalibrate => 'Calibrar';

  @override
  String get measCalibrateScale => 'Calibrar escala';

  @override
  String get measDepthLabel => 'Profundidad: ';

  @override
  String get measKindAngle => 'Ángulo';

  @override
  String get measKindArc => 'Arco';

  @override
  String get measKindArea => 'Área';

  @override
  String get measKindCount => 'Recuento';

  @override
  String get measKindLength => 'Longitud';

  @override
  String get measKindNetArea => 'Área neta';

  @override
  String get measKindPerimeter => 'Perímetro';

  @override
  String get measKindSlope => 'Pendiente';

  @override
  String get measKindVolume => 'Volumen';

  @override
  String get measLineRepresents => 'La línea que dibujaste representa:';

  @override
  String get measMeasure => 'Medir';

  @override
  String get measSetScale => 'Establecer escala de medición';

  @override
  String get measSetScaleButton => 'Establecer escala';

  @override
  String get measVolumeDepth => 'Profundidad del volumen';

  @override
  String get menuAddNode => 'Añadir nodo';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aplicar anotaciones a páginas',
      one: 'Aplicar anotación a páginas',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Aplicar a páginas…';

  @override
  String get menuBringToFront => 'Traer al frente';

  @override
  String get menuCheck => 'Marcar';

  @override
  String get menuChooseValue => 'Elegir valor…';

  @override
  String get menuClearCheck => 'Desmarcar';

  @override
  String get menuConvertToCheckBox => 'Convertir en casilla';

  @override
  String get menuConvertToImageButton => 'Convertir en botón de imagen';

  @override
  String get menuConvertToTextField => 'Convertir en campo de texto';

  @override
  String get menuDeleteField => 'Eliminar campo';

  @override
  String get menuEditValue => 'Editar valor…';

  @override
  String get menuFieldName => 'Nombre del campo';

  @override
  String get menuFieldValue => 'Valor del campo';

  @override
  String get menuFlattenForm => 'Aplanar formulario';

  @override
  String get menuLock => 'Bloquear';

  @override
  String get menuUnlock => 'Desbloquear';

  @override
  String get menuRecolour => 'Recolorear…';

  @override
  String get menuRemoveNode => 'Quitar nodo';

  @override
  String get menuSaveToStamps => 'Guardar en sellos';

  @override
  String get menuSetAsDefaultStyle => 'Establecer como estilo predeterminado';

  @override
  String get menuRename => 'Cambiar nombre…';

  @override
  String get menuSelectOption => 'Seleccionar opción';

  @override
  String get menuSendToBack => 'Enviar al fondo';

  @override
  String get menuSetImage => 'Establecer imagen…';

  @override
  String get menuTextStyle => 'Estilo de texto…';

  @override
  String get none => 'Ninguno';

  @override
  String get ok => 'Aceptar';

  @override
  String get overlayColor => 'Color';

  @override
  String get overlayEditText => 'Editar texto';

  @override
  String get overlayFont => 'Fuente';

  @override
  String get overlayLarger => 'Más grande';

  @override
  String get overlayMore => 'Más';

  @override
  String get overlayNote => 'Nota';

  @override
  String get overlaySmaller => 'Más pequeño';

  @override
  String get overlayStampText => 'Texto del sello';

  @override
  String get linkDialogTitle => 'Añadir enlace';

  @override
  String get linkKindWeb => 'Dirección web';

  @override
  String get linkKindPage => 'Página del documento';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Número de página';

  @override
  String get toolLink => 'Enlace';

  @override
  String get overlayUnderline => 'Subrayado';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Introduce páginas entre 1 y $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'La última página no puede ser anterior a la primera.';

  @override
  String get pageRangeFrom => 'Desde';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'Hasta';

  @override
  String get panelDragToMovePanel => 'Arrastra para mover el panel';

  @override
  String get paste => 'Pegar';

  @override
  String get propAlign => 'Alinear';

  @override
  String get propAlignCenter => 'Centrar';

  @override
  String get propAlignLeft => 'Alinear a la izquierda';

  @override
  String get propAlignRight => 'Alinear a la derecha';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anotaciones',
      one: '$count anotación',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Autor';

  @override
  String get propAutoSize => 'Autoajustar';

  @override
  String get propBold => 'Negrita';

  @override
  String get propBoldLetter => 'N';

  @override
  String get propBundledFont => 'Fuente incluida';

  @override
  String get propCallout => 'Llamada';

  @override
  String get propCharSpacing => 'Espaciado entre caracteres';

  @override
  String get propColor => 'Color';

  @override
  String get propColour => 'Color';

  @override
  String get propContents => 'Contenido';

  @override
  String get propCornerRadius => 'Radio de esquina';

  @override
  String get propEditsApplyToAll =>
      'Los cambios se aplican a todas las anotaciones compatibles';

  @override
  String get propFieldName => 'Nombre del campo';

  @override
  String get propFieldTypeCheckBox => 'Casilla';

  @override
  String get propFieldTypeComboBox => 'Cuadro combinado';

  @override
  String get propFieldTypeImageButton => 'Botón de imagen';

  @override
  String get propFieldTypeListBox => 'Cuadro de lista';

  @override
  String get propFieldTypeRadioGroup => 'Grupo de opciones';

  @override
  String get propFieldTypeSignature => 'Firma';

  @override
  String get propFieldTypeText => 'Campo de texto';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Tipo de campo: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Campo desconocido';

  @override
  String get propFill => 'Relleno';

  @override
  String get propFont => 'Fuente';

  @override
  String get propFontSubsetTooltip =>
      'Esta fuente está subconjuntada: solo se pueden escribir los caracteres que ya se usan en el documento.';

  @override
  String get propFontWidth => 'Ancho de fuente';

  @override
  String get propGeometryHeight => 'Al';

  @override
  String get propGeometryWidth => 'An';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Cursiva';

  @override
  String get propItalicLetter => 'C';

  @override
  String get propLimitedCharacters => 'Caracteres limitados';

  @override
  String get propLineEnd => 'Fin de línea';

  @override
  String get propLineEndingButt => 'Plano';

  @override
  String get propLineEndingCircle => 'Círculo';

  @override
  String get propLineEndingClosedArrow => 'Flecha cerrada';

  @override
  String get propLineEndingClosedArrowRev => 'Flecha cerrada (inv.)';

  @override
  String get propLineEndingDiamond => 'Rombo';

  @override
  String get propLineEndingOpenArrow => 'Flecha abierta';

  @override
  String get propLineEndingOpenArrowRev => 'Flecha abierta (inv.)';

  @override
  String get propLineEndingSlash => 'Barra';

  @override
  String get propLineEndingSquare => 'Cuadrado';

  @override
  String get propLineSpacing => 'Interlineado';

  @override
  String get propLineStart => 'Inicio de línea';

  @override
  String get propLineType => 'Tipo de línea';

  @override
  String get propLoadFont => 'Cargar fuente…';

  @override
  String get propLoadFontSubtitle => 'Archivo TTF u OTF';

  @override
  String get propMoreColors => 'Más colores…';

  @override
  String get propMultiline => 'Multilínea';

  @override
  String get propNoFill => 'Sin relleno';

  @override
  String get propNoFontsFound => 'No se encontraron fuentes';

  @override
  String get propNoOutline => 'Sin contorno';

  @override
  String get propOpacity => 'Opacidad';

  @override
  String get propOutline => 'Contorno';

  @override
  String get propPageLabel => 'Página';

  @override
  String propPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get propPropertiesTitle => 'Propiedades';

  @override
  String get propRecentlyUsed => 'Usadas recientemente';

  @override
  String get propScale => 'Escala';

  @override
  String get propSearchFonts => 'Buscar fuentes';

  @override
  String get propSectionAllFonts => 'Todas las fuentes';

  @override
  String get propSectionAppearance => 'Apariencia';

  @override
  String get propSectionContent => 'Contenido';

  @override
  String get propSectionFormField => 'Campo de formulario';

  @override
  String get propSectionInThisDocument => 'En este documento';

  @override
  String get propSectionPositionSize => 'Posición y tamaño (pt)';

  @override
  String get propSectionSelection => 'Selección';

  @override
  String get propSectionText => 'Texto';

  @override
  String get propSelectAnnotationPrompt =>
      'Selecciona una anotación para ver sus propiedades';

  @override
  String get propSize => 'Tamaño';

  @override
  String get propStandardPdfFont => 'Fuente PDF estándar';

  @override
  String get propStroke => 'Trazo';

  @override
  String get propStyle => 'Estilo';

  @override
  String get propSystemFont => 'Fuente del sistema';

  @override
  String get propType => 'Tipo';

  @override
  String get propUnderline => 'Subrayado';

  @override
  String get propVaries => 'Varía';

  @override
  String get redo => 'Rehacer';

  @override
  String get reflowNoContent => 'No hay contenido extraíble';

  @override
  String reflowPageLabel(int number) {
    return 'Página $number';
  }

  @override
  String get reflowSaveOrShare => 'Guardar o compartir';

  @override
  String get reflowViewFigure => 'Ver figura';

  @override
  String get remove => 'Quitar';

  @override
  String get rename => 'Cambiar nombre';

  @override
  String get reset => 'Restablecer';

  @override
  String get save => 'Guardar';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Página $page';
  }

  @override
  String get sbarCallout => 'Llamada';

  @override
  String get sbarFieldButton => 'Campo de botón';

  @override
  String get sbarFieldChoice => 'Campo de elección';

  @override
  String get sbarFieldGeneric => 'Campo de formulario';

  @override
  String get sbarFieldSignature => 'Campo de firma';

  @override
  String get sbarFieldText => 'Campo de texto';

  @override
  String get sbarStateAccepted => 'Aceptado';

  @override
  String get sbarStateCancelled => 'Cancelado';

  @override
  String get sbarStateMarked => 'Marcado';

  @override
  String get sbarStateRejected => 'Rechazado';

  @override
  String get sbarStateResolved => 'Resuelto';

  @override
  String get sbarStateUnmarked => 'Sin marcar';

  @override
  String get searchAnnotations => 'Buscar anotaciones';

  @override
  String get searchClearSearch => 'Borrar búsqueda';

  @override
  String get searchEmptyHint =>
      'Busca en el documento para ver aquí todas las coincidencias';

  @override
  String get searchMatchCase => 'Coincidir mayúsculas y minúsculas';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coincidencias',
      one: '1 coincidencia',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Coincidencia siguiente';

  @override
  String searchNoMatches(String query) {
    return 'Sin coincidencias para “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Página $page';
  }

  @override
  String get searchPreviousMatch => 'Coincidencia anterior';

  @override
  String get searchRegex => 'Expresión regular';

  @override
  String get searchResultsTitle => 'Resultados de búsqueda';

  @override
  String get searchWholeWord => 'Palabra completa';

  @override
  String get shellControls => 'Controles';

  @override
  String get shellDefaultAuthor => 'Autor predeterminado…';

  @override
  String get shellHighlightFormFields => 'Resaltar campos de formulario';

  @override
  String get shellKeyboardShortcutsMenu => 'Atajos de teclado…';

  @override
  String get shellKeyboardShortcutsTitle => 'Atajos de teclado';

  @override
  String get shellShortcutsSearchHint => 'Buscar atajos';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'Ningún atajo coincide con “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Seleccionar';

  @override
  String get shellShortcutGroupMarkup => 'Marcado';

  @override
  String get shellShortcutGroupDraw => 'Dibujar';

  @override
  String get shellShortcutGroupShapes => 'Formas';

  @override
  String get shellShortcutGroupInsert => 'Insertar';

  @override
  String get shellShortcutGroupMeasure => 'Medir';

  @override
  String get shellShortcutGroupEdit => 'Editar';

  @override
  String get shellNotSet => 'Sin establecer';

  @override
  String get shellPageColor => 'Color de página…';

  @override
  String get shellPageGrid => 'Cuadrícula de páginas';

  @override
  String get shellPanelAnnotations => 'Anotaciones';

  @override
  String get shellPanelBookmarks => 'Marcadores';

  @override
  String get shellPanelPages => 'Páginas';

  @override
  String get shellPanelProperties => 'Propiedades';

  @override
  String get shellPanelSearchResults => 'Resultados de búsqueda';

  @override
  String get shellPanels => 'Paneles';

  @override
  String get shellPressAKey => 'Pulsa una tecla';

  @override
  String get shellPressLetterKeyHint => 'Pulsa una letra o Supr para borrar.';

  @override
  String get shellReflow => 'Reajustar';

  @override
  String get shellReflowText => 'Reajustar texto';

  @override
  String get shellResetZoom => 'Restablecer zoom';

  @override
  String get shellSectionShell => 'Entorno';

  @override
  String get shellSectionView => 'Vista';

  @override
  String get shellSettings => 'Ajustes';

  @override
  String get shellShowAnnotations => 'Mostrar anotaciones';

  @override
  String get shellTabHere => 'Pestaña aquí';

  @override
  String get shellUnbound => 'Sin asignar';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'por $author';
  }

  @override
  String get sidebarCancelSelection => 'Cancelar selección';

  @override
  String get sidebarClearSearch => 'Borrar búsqueda';

  @override
  String get sidebarDeleteSelected => 'Eliminar seleccionadas';

  @override
  String get sidebarDeleteSignature => 'Eliminar firma';

  @override
  String get sidebarLockAnnotation => 'Bloquear';

  @override
  String get sidebarUnlockAnnotation => 'Desbloquear';

  @override
  String get sidebarMore => 'Más';

  @override
  String get sidebarNoAnnotations => 'Sin anotaciones';

  @override
  String get sidebarNoMatchingAnnotations => 'No hay anotaciones coincidentes';

  @override
  String sidebarPageHeader(int number) {
    return 'Página $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'Esto elimina la firma digital del documento. Puedes deshacer esta acción.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'Esto elimina la firma digital de \"$name\" del documento. Puedes deshacer esta acción.';
  }

  @override
  String get sidebarRemoveSignatureTitle => '¿Eliminar la firma?';

  @override
  String get sidebarReopen => 'Reabrir';

  @override
  String get sidebarReply => 'Responder';

  @override
  String get sidebarResolve => 'Resolver';

  @override
  String get sidebarSearchHint => 'Buscar anotaciones';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionadas',
      one: '$count seleccionada',
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
  String get sidebarWriteReplyHint => 'Escribe una respuesta…';

  @override
  String get sigTitle => 'Firma';

  @override
  String get signIdCreate => 'Crear';

  @override
  String get signIdEmail => 'Correo electrónico (opcional)';

  @override
  String get signIdName => 'Nombre';

  @override
  String get signIdNameHint => 'Tu nombre, tal como debe aparecer en la firma';

  @override
  String get signIdNameRequired => 'Introduce un nombre';

  @override
  String get signIdOrganization => 'Organización (opcional)';

  @override
  String get signIdSelfSignedInfo =>
      'Esto crea una identidad autofirmada. Las firmas se mostrarán como \"firmado, validez desconocida\" en Adobe Acrobat y otros lectores, igual que sus propias identidades autofirmadas. La marca de verificación verde requiere una CA de pago y de confianza pública.';

  @override
  String get signIdTitle => 'Crear identidad de firma';

  @override
  String get stampBox => 'Rectángulo';

  @override
  String get stampCircle => 'Círculo';

  @override
  String get stampCustomCaption => 'Sello personalizado';

  @override
  String get stampDateFormat => 'Formato de fecha';

  @override
  String get stampDeleteComponent => 'Eliminar componente seleccionado';

  @override
  String get stampDeleteStamp => 'Eliminar sello';

  @override
  String get stampEditStamp => 'Editar sello';

  @override
  String get stampExport => 'Exportar…';

  @override
  String get stampFieldDate => 'Fecha';

  @override
  String get stampFieldDateTime => 'Fecha y hora';

  @override
  String get stampFieldTime => 'Hora';

  @override
  String get stampFieldUsername => 'Nombre de usuario';

  @override
  String get stampFont => 'Fuente';

  @override
  String get stampFontBold => 'Negrita';

  @override
  String get stampFontItalic => 'Cursiva';

  @override
  String get stampHeight => 'Alto';

  @override
  String get stampImage => 'Imagen';

  @override
  String get stampImport => 'Importar…';

  @override
  String get stampInsertField => 'Insertar campo';

  @override
  String get stampMoreColors => 'Más colores…';

  @override
  String get stampNewStamp => 'Nuevo sello…';

  @override
  String get stampNewStampTitle => 'Nuevo sello';

  @override
  String get stampSavedToCollection => 'Guardado en sellos';

  @override
  String get stampSelectTextToEdit => 'Selecciona texto para editar';

  @override
  String get stampSelectedText => 'Texto seleccionado';

  @override
  String get stampSignature => 'Firma';

  @override
  String get stampStamps => 'Sellos';

  @override
  String get stampText => 'Texto';

  @override
  String get stampTime12Hour => '12 h';

  @override
  String get stampTime24Hour => '24 h';

  @override
  String get stampTimeFormat => 'Formato de hora';

  @override
  String get stampWidth => 'Ancho';

  @override
  String get takeoffArea => 'Área';

  @override
  String get takeoffCount => 'Recuento';

  @override
  String get takeoffEmpty => 'Aún no hay mediciones.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupos',
      one: '$count grupo',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '$count elemento',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Longitud';

  @override
  String get takeoffTitle => 'Cómputo';

  @override
  String get tbAddInkAnnotation => 'Añadir anotación de trazo';

  @override
  String get tbAlign => 'Alinear';

  @override
  String get tbAlignBottom => 'Alinear abajo';

  @override
  String get tbAlignHorizontalCenters => 'Alinear centros horizontales';

  @override
  String get tbAlignLeft => 'Alinear a la izquierda';

  @override
  String get tbAlignRight => 'Alinear a la derecha';

  @override
  String get tbAlignTop => 'Alinear arriba';

  @override
  String get tbAlignVerticalCenters => 'Alinear centros verticales';

  @override
  String get tbAnnotationsFlattened => 'Anotaciones aplanadas en las páginas';

  @override
  String get tbApplyRedactionsMessage =>
      'El contenido marcado se eliminará permanentemente del documento. Esta acción no se puede deshacer.';

  @override
  String get tbApplyRedactionsTitle => '¿Aplicar censuras?';

  @override
  String get tbApplyRedactionsTooltip => 'Aplicar censuras (irreversible)';

  @override
  String get tbAutosizeTextBox => 'Autoajustar cuadro de texto (Alt+Z)';

  @override
  String get tbCalibrateScaleHint =>
      'Dibuja una línea de longitud conocida para calibrar la escala.';

  @override
  String get tbCharSpacing => 'Espaciado entre caracteres';

  @override
  String get tbCheckBoxOption => 'Casilla';

  @override
  String get tbCheckMarksOnDocument => 'Marcas en el documento';

  @override
  String get tbCropImage => 'Recortar imagen';

  @override
  String get tbCroppingImage => 'Recortando imagen';

  @override
  String get tbCropApply => 'Aplicar recorte';

  @override
  String get tbCropCancel => 'Cancelar recorte';

  @override
  String get tbCropReset => 'Restablecer recorte';

  @override
  String get tbColorLabel => 'Color';

  @override
  String get tbColorProcessingTooltip =>
      'Procesamiento de color: buscar y reemplazar colores del contenido de la página';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se reemplazaron $count colores',
      one: 'Se reemplazó 1 color',
      zero: 'No se encontraron colores coincidentes',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Convertir en casilla';

  @override
  String get tbConvertToImageButton => 'Convertir en botón de imagen';

  @override
  String get tbConvertToTextField => 'Convertir en campo de texto';

  @override
  String get tbCornerRadius => 'Radio de esquina';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminar $count anotaciones',
      one: 'Eliminar anotación',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Eliminar elemento';

  @override
  String get tbDeleteField => 'Eliminar campo';

  @override
  String get tbDiscardDrawing => 'Descartar dibujo';

  @override
  String get tbDistributeHorizontally => 'Distribuir horizontalmente';

  @override
  String get tbDistributeVertically => 'Distribuir verticalmente';

  @override
  String get tbDrawNewSignature => 'Dibujar una nueva firma…';

  @override
  String get tbEditAnnotationText => 'Editar texto de la anotación';

  @override
  String get tbEditTextStyle => 'Editar texto y estilo';

  @override
  String get tbElement => 'Elemento';

  @override
  String get tbEraserSize => 'Tamaño del borrador';

  @override
  String get tbFieldActions => 'Acciones del campo';

  @override
  String get tbFieldName => 'Nombre del campo';

  @override
  String tbFieldNamed(String name) {
    return 'Campo: $name';
  }

  @override
  String get tbFieldValue => 'Valor del campo';

  @override
  String get tbFill => 'Relleno';

  @override
  String get tbFingerDraws =>
      'El dedo dibuja: toca para que desplace en su lugar';

  @override
  String get tbFingerScrolls =>
      'El dedo desplaza (el lápiz dibuja): toca para que dibuje';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Aplanar anotaciones en las páginas';

  @override
  String get tbFlattenForm => 'Aplanar formulario';

  @override
  String get tbFlattenFormBakeValues =>
      'Aplanar formulario: fijar los valores en las páginas';

  @override
  String get tbFlattenLabel => 'Aplanar';

  @override
  String get tbFont => 'Fuente';

  @override
  String get tbFontSize => 'Tamaño de fuente';

  @override
  String get tbFontWidth => 'Ancho de fuente';

  @override
  String get tbFormFieldsFlattened =>
      'Campos de formulario aplanados en las páginas';

  @override
  String get tbGroupDraw => 'Dibujar';

  @override
  String get tbGroupEdit => 'Editar';

  @override
  String get tbGroupInsert => 'Insertar';

  @override
  String get tbGroupMarkup => 'Marcado';

  @override
  String get tbGroupMeasure => 'Medir';

  @override
  String get tbGroupSelect => 'Seleccionar';

  @override
  String get tbGroupShapes => 'Formas';

  @override
  String get tbImageButtonOption => 'Botón de imagen';

  @override
  String get tbLineEnd => 'Fin de línea';

  @override
  String get tbLineSpacing => 'Interlineado';

  @override
  String get tbLineStart => 'Inicio de línea';

  @override
  String get tbLineType => 'Tipo de línea';

  @override
  String get tbManageStamps => 'Administrar sellos…';

  @override
  String get tbMarkupHighlight => 'Resaltar';

  @override
  String get tbMarkupHighlightTip => 'Resaltar selección';

  @override
  String get tbMarkupSquiggly => 'Subrayado ondulado';

  @override
  String get tbMarkupSquigglyTip => 'Subrayado ondulado de la selección';

  @override
  String get tbMarkupStrikeOut => 'Tachar';

  @override
  String get tbMarkupStrikeOutTip => 'Tachar selección';

  @override
  String get tbMarkupUnderline => 'Subrayar';

  @override
  String get tbMarkupUnderlineTip => 'Subrayar selección';

  @override
  String get tbMoreColors => 'Más colores…';

  @override
  String get tbNameArrow => 'Flecha';

  @override
  String get tbNameCallout => 'Llamada';

  @override
  String get tbNameCloudPolygon => 'Polígono en nube';

  @override
  String get tbNameCount => 'Recuento';

  @override
  String get tbNameDigitalSignature => 'Firma digital';

  @override
  String get tbNameDraw => 'Dibujar';

  @override
  String get tbNameEllipse => 'Elipse';

  @override
  String get tbNameEraser => 'Borrar trazos';

  @override
  String get tbNameHighlight => 'Resaltar';

  @override
  String get tbNameImage => 'Imagen';

  @override
  String get tbNameLine => 'Línea';

  @override
  String get tbNameMeasureAngle => 'Medir ángulo';

  @override
  String get tbNameMeasureArc => 'Medir longitud de arco';

  @override
  String get tbNameMeasureArea => 'Medir área';

  @override
  String get tbNameMeasureDistance => 'Medir distancia';

  @override
  String get tbNameMeasurePerimeter => 'Medir perímetro';

  @override
  String get tbNameMeasureSlope => 'Medir pendiente (subida/avance)';

  @override
  String get tbNameMeasureVolume => 'Medir volumen (área × profundidad)';

  @override
  String get tbNameNote => 'Nota';

  @override
  String get tbNamePolygon => 'Polígono';

  @override
  String get tbNamePolyline => 'Polilínea';

  @override
  String get tbNameRectangle => 'Rectángulo';

  @override
  String get tbNameSelect => 'Seleccionar';

  @override
  String get tbNameSignature => 'Firma';

  @override
  String get tbNameStamp => 'Sello';

  @override
  String get tbNameTextBox => 'Cuadro de texto';

  @override
  String get tbNewFieldType =>
      'Nuevo tipo de campo: arrastra sobre una página para añadir uno';

  @override
  String get tbNoAnnotationsToFlatten => 'No hay anotaciones para aplanar';

  @override
  String get tbNoCustomStamps => 'No hay sellos personalizados';

  @override
  String get tbNoFormFieldsToFlatten =>
      'No hay campos de formulario para aplanar';

  @override
  String get tbNoRedactionsToApply => 'No hay censuras para aplicar';

  @override
  String get tbNoteTitle => 'Nota';

  @override
  String get tbOpacity => 'Opacidad';

  @override
  String get tbOutline => 'Contorno';

  @override
  String get tbPatternScale => 'Escala del patrón';

  @override
  String get tbPickColorFromPage => 'Elegir un color de la página';

  @override
  String get tbRedactionsApplied => 'Censuras aplicadas';

  @override
  String get tbRedoShortcut => 'Rehacer (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'No se pudo reajustar: este no es un párrafo de una sola columna que esta herramienta pueda reajustar. Prueba con Reemplazar texto.';

  @override
  String get tbReflowParagraph => 'Reajustar párrafo';

  @override
  String get tbRenameField => 'Cambiar nombre del campo';

  @override
  String get tbRenameFieldEllipsis => 'Cambiar nombre del campo…';

  @override
  String get tbReplaceImage => 'Reemplazar imagen';

  @override
  String get tbReplaceImageFailed => 'No se pudo reemplazar la imagen';

  @override
  String get tbReplaceText => 'Reemplazar texto';

  @override
  String get tbSaveImage => 'Guardar imagen';

  @override
  String get tbSaveShortcut => 'Guardar… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Escala';

  @override
  String get tbSelectTextForMarkup => 'Selecciona texto para usar el marcado';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionadas',
      one: 'Selección',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Establecer…';

  @override
  String get tbStamp => 'Sello';

  @override
  String get tbStampText => 'Texto del sello';

  @override
  String get tbStrokeOpacityFont => 'Trazo, opacidad, fuente';

  @override
  String get tbStrokeWidthLabel => 'Ancho de trazo';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Trazo $width';
  }

  @override
  String get tbStyle => 'Estilo';

  @override
  String get tbTakeoffTotals => 'Totales del cómputo';

  @override
  String get tbTextBorder => 'Borde del texto';

  @override
  String get tbTextColour => 'Color del texto';

  @override
  String get tbTextFieldOption => 'Campo de texto';

  @override
  String get tbTextFill => 'Relleno del texto';

  @override
  String get tbTextStyleEllipsis => 'Estilo de texto…';

  @override
  String get tbTextTitle => 'Texto';

  @override
  String get tbTipCallout =>
      'Llamada: arrastra desde el punto hasta donde va el cuadro';

  @override
  String get tbTipContent => 'Editar contenido de la página';

  @override
  String get tbTipCount => 'Recuento: toca para colocar marcas y contarlas';

  @override
  String get tbTipDigitalSignature =>
      'Firma digital: arrastra un cuadro para colocar y firmar';

  @override
  String get tbTipForm =>
      'Campos de formulario: toca para seleccionar, doble toque para rellenar, arrastra para añadir';

  @override
  String get tbTipHighlightDraw => 'Resaltar: dibuja a mano alzada';

  @override
  String get tbTipImage => 'Imagen: toca para colocar o arrastra un cuadro';

  @override
  String get tbTipMeasureAngle => 'Medir ángulo: haz clic en tres puntos';

  @override
  String get tbTipMeasureArc =>
      'Medir longitud de arco: haz clic en tres puntos';

  @override
  String get tbTipRedact => 'Censurar: arrastra una región y luego aplica';

  @override
  String get tbTipSignature => 'Firma: toca una página para colocarla';

  @override
  String get tbTipSnapshot =>
      'Captura: arrastra una región para capturarla (pégala como vector)';

  @override
  String get tbToolContent => 'Contenido';

  @override
  String get tbToolForm => 'Formulario';

  @override
  String get tbToolRedact => 'Censurar';

  @override
  String get tbToolSnapshot => 'Captura';

  @override
  String get tbTools => 'Herramientas';

  @override
  String get tbTotals => 'Totales';

  @override
  String get tbTypeTextEachTime => 'Escribir texto cada vez';

  @override
  String get tbUnderline => 'Subrayar';

  @override
  String get tbUndoShortcut => 'Deshacer (⌘Z)';

  @override
  String get textStyleFont => 'Fuente';

  @override
  String get textStyleFontSize => 'Tamaño de fuente';

  @override
  String get textStyleKeep => 'mantener';

  @override
  String get textStyleStyle => 'Estilo';

  @override
  String get textStyleText => 'Texto';

  @override
  String get textStyleTextFill => 'Relleno del texto';

  @override
  String get textStyleTitle => 'Editar texto y estilo';

  @override
  String get thumbAddPage => 'Añadir página';

  @override
  String get thumbClearSelection => 'Borrar selección';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copiar $count páginas',
      one: 'Copiar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Copiar páginas seleccionadas';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cortar $count páginas',
      one: 'Cortar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Cortar páginas seleccionadas';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminar $count páginas',
      one: 'Eliminar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Eliminar páginas seleccionadas';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplicar $count páginas',
      one: 'Duplicar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Exportar páginas…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exportar $count páginas…',
      one: 'Exportar página…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Exportar páginas seleccionadas';

  @override
  String get thumbInsertBlankAfter => 'Insertar página en blanco después';

  @override
  String get thumbInsertBlankBefore => 'Insertar página en blanco antes';

  @override
  String get thumbInsertFileFailed => 'No se pudo insertar ese archivo.';

  @override
  String get thumbInsertPdf => 'Insertar PDF…';

  @override
  String get thumbPageActions => 'Acciones de página';

  @override
  String thumbPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get thumbPages => 'Páginas';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pegar $count páginas',
      one: 'Pegar página',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Girar 180°';

  @override
  String get thumbRotateLeft => 'Girar a la izquierda';

  @override
  String get thumbRotatePageRight => 'Girar página a la derecha';

  @override
  String get thumbRotateRight => 'Girar a la derecha';

  @override
  String get thumbRotateSelectedLeft =>
      'Girar páginas seleccionadas a la izquierda';

  @override
  String get thumbRotateSelectedRight =>
      'Girar páginas seleccionadas a la derecha';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionadas',
      one: '$count seleccionada',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Deshacer';

  @override
  String get viewerEditFontUnsafe =>
      'Esta fuente o codificación PDF no se puede editar de forma segura.';

  @override
  String get viewerEditNeedsSinglePage =>
      'La edición requiere una selección en una sola página.';

  @override
  String get viewerEditNotEditableRun =>
      'Esta selección no es un único fragmento de texto de página editable.';

  @override
  String get viewerEditStyleUnchangeable =>
      'Esta fuente PDF se puede volver a escribir, pero su estilo no se puede cambiar.';

  @override
  String get viewerEditTextStyle => 'Editar texto y estilo';

  @override
  String get viewerMarkup => 'Marcado';

  @override
  String get viewerMarkupHighlight => 'Resaltar';

  @override
  String get viewerMarkupSquiggly => 'Ondulado';

  @override
  String get viewerMarkupStrikeOut => 'Tachar';

  @override
  String get viewerMarkupUnderline => 'Subrayar';

  @override
  String get viewerSelectAll => 'Seleccionar todo';
}
