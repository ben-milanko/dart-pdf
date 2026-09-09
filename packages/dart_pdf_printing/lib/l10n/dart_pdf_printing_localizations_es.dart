// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class DartPdfPrintingLocalizationsEs extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get printDlgPreparing => 'Preparando…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Procesando página $rendered de $total…';
  }

  @override
  String get printDlgTitle => 'Imprimiendo';

  @override
  String get printPreviewAll => 'Todas';

  @override
  String get printPreviewCurrent => 'Actual';

  @override
  String get printPreviewNextPage => 'Página siguiente';

  @override
  String printPreviewPageOf(int page, int total) {
    return 'Página $page de $total';
  }

  @override
  String get printPreviewPreviousPage => 'Página anterior';

  @override
  String get printPreviewPrint => 'Imprimir';

  @override
  String get printPreviewRange => 'Intervalo';

  @override
  String printPreviewRangeError(int total) {
    return 'Introduce un intervalo de páginas entre 1 y $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Páginas para imprimir: $count';
  }

  @override
  String get printPreviewTitle => 'Vista previa de impresión';

  @override
  String get printPreviewUnavailable => 'Vista previa no disponible';

  @override
  String get printOptionsPrinter => 'Impresora';

  @override
  String get printOptionsNativePrinter =>
      'Elija la impresora, la bandeja de papel, el color, la impresión a doble cara y las propiedades del dispositivo en el siguiente diálogo de impresión del sistema. Mantenga la escala al 100 % y las copias en 1 para usar el diseño que se muestra aquí.';

  @override
  String get printOptionsPages => 'Páginas';

  @override
  String get printOptionsSelected => 'Seleccionadas';

  @override
  String get printOptionsPageRange => 'Páginas (por ejemplo, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Añadir archivos…';

  @override
  String get printOptionsAddFailed =>
      'No se pudieron añadir los archivos seleccionados.';

  @override
  String get printOptionsGetWindow => 'Seleccionar área';

  @override
  String get printOptionsClearWindow => 'Borrar área';

  @override
  String get printOptionsWindowHint =>
      'Arrastre un rectángulo sobre esta página original para elegir el área que desea imprimir.';

  @override
  String get printOptionsPaper => 'Papel';

  @override
  String get printOptionsPaperSize => 'Tamaño del papel';

  @override
  String get printOptionsPageSize => 'Usar el tamaño de página del documento';

  @override
  String get printOptionsOrientation => 'Orientación';

  @override
  String get printOptionsAuto => 'Automática';

  @override
  String get printOptionsPortrait => 'Vertical';

  @override
  String get printOptionsLandscape => 'Horizontal';

  @override
  String get printOptionsCopies => 'Copias';

  @override
  String get printOptionsCollate => 'Intercalar';

  @override
  String get printOptionsReverse => 'Invertir el orden de las páginas';

  @override
  String get printOptionsLayout => 'Diseño de página';

  @override
  String get printOptionsScaling => 'Escala de página';

  @override
  String get printOptionsScaleNone => 'Ninguna (tamaño real)';

  @override
  String get printOptionsFitPaper => 'Ajustar al papel';

  @override
  String get printOptionsReducePaper => 'Reducir al tamaño del papel';

  @override
  String get printOptionsFitMargins => 'Ajustar a los márgenes';

  @override
  String get printOptionsReduceMargins => 'Reducir a los márgenes';

  @override
  String get printOptionsCustomScale => 'Escala personalizada';

  @override
  String get printOptionsMultiple => 'Varias páginas por hoja';

  @override
  String get printOptionsScalePercent => 'Escala (%)';

  @override
  String get printOptionsMargin => 'Márgenes (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Páginas por hoja';

  @override
  String get printOptionsPageOrder => 'Orden de las páginas';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal invertido';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical invertido';

  @override
  String get printOptionsBorder => 'Imprimir bordes de página';

  @override
  String get printOptionsRotation => 'Rotación (sentido horario)';

  @override
  String get printOptionsNoRotation => 'Ninguna';

  @override
  String get printOptionsCenter => 'Centrar en el papel';

  @override
  String get printOptionsOffsetX => 'Desplazamiento a la derecha (pt)';

  @override
  String get printOptionsOffsetY => 'Desplazamiento hacia abajo (pt)';

  @override
  String get printOptionsContents => 'Contenido de impresión';

  @override
  String get printOptionsDocumentAndMarkups => 'Documento y anotaciones';

  @override
  String get printOptionsDocumentOnly => 'Solo documento';

  @override
  String get printOptionsMarkupsOnly => 'Solo anotaciones';

  @override
  String get printOptionsDimPage => 'Atenuar el contenido de la página';

  @override
  String get printOptionsDimMarkups => 'Atenuar las anotaciones';

  @override
  String get printOptionsHyperlinks => 'Imprimir hipervínculos visibles';

  @override
  String get printOptionsDefaults => 'Valores predeterminados';

  @override
  String get printOptionsInvalidNumber =>
      'Introduzca números válidos antes de imprimir.';

  @override
  String get printOptionsInvalidValue => 'Valor no válido';

  @override
  String get printOptionsMarginGuide =>
      'Las líneas rojas muestran los márgenes; no se imprimen.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Área: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Original: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Hoja: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Hoja $sheet de $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'No se pudo preparar este diseño. Compruebe el tamaño del papel, los márgenes y la escala.';

  @override
  String get printOptionsChoosePrinter => 'Elegir una impresora';

  @override
  String get printOptionsNoPrinters =>
      'No hay impresoras instaladas. Añade una impresora en la Configuración de Windows y vuelve a intentarlo.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'La impresora guardada «$printer» no está disponible. Elige una impresora para continuar.';
  }

  @override
  String get printOptionsPrinterError =>
      'No se pudo cargar la configuración de la impresora. Comprueba la conexión de la impresora y vuelve a intentarlo.';

  @override
  String get printOptionsRetry => 'Reintentar';

  @override
  String get printOptionsColor => 'Color';

  @override
  String get printOptionsGrayscale => 'Blanco y negro';

  @override
  String get printOptionsDuplex => 'Impresión a doble cara';

  @override
  String get printOptionsSimplex => 'Una cara';

  @override
  String get printOptionsLongEdge => 'Voltear por el borde largo';

  @override
  String get printOptionsShortEdge => 'Voltear por el borde corto';

  @override
  String get printOptionsTray => 'Bandeja de papel';

  @override
  String get printOptionsDefaultTray => 'Predeterminado de la impresora';

  @override
  String get printOptionsProperties => 'Propiedades de la impresora…';

  @override
  String get printOptionsDirectPrinter =>
      'Imprimir envía este trabajo directamente a la impresora seleccionada.';

  @override
  String get printOptionsPropertiesError =>
      'No se pudieron abrir las propiedades de la impresora.';

  @override
  String get printOptionsLoadingPrinters => 'Cargando impresoras…';
}
