// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get add => 'Añadir';

  @override
  String get apply => 'Aplicar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get clear => 'Borrar';

  @override
  String get close => 'Cerrar';

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
  String exActionJavaScript(String script) {
    return 'JavaScript expuesto a la aplicación: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Enlace: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Acción con nombre: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Tipo de acción no admitido: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Texto de la anotación copiado';

  @override
  String get exApiKeyHelper => 'Se envía como Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Clave de API / token (opcional)';

  @override
  String get exAppMenuTooltip => 'Menú de DartPDF';

  @override
  String get exClearRecentFiles => 'Borrar archivos recientes';

  @override
  String get exCloseTab => 'Cerrar pestaña';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Comparar: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Comparar con otro PDF…';

  @override
  String get exCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get exCopySelectedText => 'Copiar texto seleccionado (⌘C)';

  @override
  String get exCopyText => 'Copiar texto';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'No se pudo abrir $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'No se pudo abrir $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'No se pudo abrir $uri\n$error\n\nEn la web esto suele deberse a una restricción CORS: el servidor debe enviar Access-Control-Allow-Origin y exponer los encabezados Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'No se pudo volver a abrir $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'No se pudo volver a abrir $title: su copia guardada ya no está disponible.';
  }

  @override
  String get exDemoNoteHint =>
      'Escribe aquí: este cuadro de texto flota sobre la página';

  @override
  String get exDiagnosticsCopied => 'Diagnósticos copiados al portapapeles';

  @override
  String exDownloaded(String name) {
    return 'Se descargó $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Se descargó $name: pégalo de vuelta en el PDF con Ctrl+V';
  }

  @override
  String get exExport => 'Exportar';

  @override
  String exExportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get exExportPageImageMenu => 'Exportar página como imagen…';

  @override
  String get exExportPageImageTitle => 'Exportar página como imagen';

  @override
  String get exFeatureShowcase => 'Muestra de funciones';

  @override
  String get exFormat => 'Formato';

  @override
  String get exHide => 'Ocultar';

  @override
  String get exHorizontalLayout => 'Diseño de página horizontal';

  @override
  String get exHowToSetupOcr => 'Cómo configurar un servidor de OCR';

  @override
  String get exModelName => 'Nombre del modelo';

  @override
  String get exNoMessage => 'Sin mensaje';

  @override
  String get exNoRecentFiles => 'No hay archivos recientes';

  @override
  String exNotAValidUrl(String url) {
    return 'URL no válida:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'El OCR añadió $count fragmentos de texto: el texto de la página ahora se puede seleccionar',
      one:
          'El OCR añadió 1 fragmento de texto: el texto de la página ahora se puede seleccionar',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Añade una capa de texto seleccionable y con capacidad de búsqueda sobre las páginas escaneadas usando un modelo de OCR de visión y lenguaje que tú alojas (dots.ocr en vLLM, o cualquier endpoint de OCR compatible con OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'Error de OCR: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Abrir';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Abre un documento antes de ejecutar el OCR';

  @override
  String get exOpenDocumentFirst => 'Abre un documento primero';

  @override
  String get exOpenFromUrl => 'Abrir desde una URL…';

  @override
  String get exOpenFromUrlTitle => 'Abrir desde una URL';

  @override
  String get exOpenInNewTab => 'Abrir PDF en una pestaña nueva';

  @override
  String get exOpenInteractiveDemo => 'Abrir la demostración interactiva';

  @override
  String get exOpenPdf => 'Abrir un PDF…';

  @override
  String get exOpenPdfButton => 'Abrir un PDF';

  @override
  String get exOpenRecent => 'Abrir recientes';

  @override
  String get exRecentFiles => 'Archivos recientes';

  @override
  String get exViewAllRecentFiles => 'Ver todos los archivos recientes…';

  @override
  String get exSearchRecentFiles => 'Buscar en archivos recientes';

  @override
  String get exNoMatchingRecentFiles =>
      'Ningún archivo reciente coincide con la búsqueda';

  @override
  String get exGridView => 'Vista de cuadrícula';

  @override
  String get exListView => 'Vista de lista';

  @override
  String get exOpenUrlDescription =>
      'Transmite el PDF mediante solicitudes HTTP Range a través de PdfHttpByteSource, obteniendo solo lo que el analizador necesita y recurriendo a una descarga completa cuando el servidor no admite rangos.';

  @override
  String get exOpeningDocument => 'Abriendo documento';

  @override
  String get exOpeningPdf => 'Abriendo PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Abriendo $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL del PDF';

  @override
  String get exPerformanceAuto => 'Rendimiento: automático';

  @override
  String get exPreparing => 'Preparando…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor en pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Reconociendo la página $current de $count…';
  }

  @override
  String get exResolution => 'Resolución';

  @override
  String get exRunOcr => 'Ejecutar OCR';

  @override
  String get exSaveAs => 'Guardar como…';

  @override
  String exSaveFailed(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Se guardó $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Se guardó $name: pégalo de vuelta en el PDF con ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Se guardó en $path';
  }

  @override
  String get exScrollIndicatorDemo =>
      'Demostración de la API del indicador de desplazamiento';

  @override
  String get exServiceEndpoint => 'Endpoint del servicio';

  @override
  String get exShow => 'Mostrar';

  @override
  String get exSingleWorker => 'Un solo trabajador';

  @override
  String get exSupplyFeedback => 'Enviar comentarios…';

  @override
  String get exSwitchToEdit => 'Cambiar al modo de edición';

  @override
  String get exSwitchToReadOnly => 'Cambiar a solo lectura';

  @override
  String get exThemeDark => 'Tema: oscuro - cambiar a sistema';

  @override
  String get exThemeLight => 'Tema: claro - cambiar a oscuro';

  @override
  String get exThemeSystem => 'Tema: sistema - cambiar a claro';

  @override
  String get exTryDemo => 'Probar la demostración interactiva';

  @override
  String get exUntitled => 'Sin título';

  @override
  String get exVerticalLayout => 'Diseño de página vertical';

  @override
  String get exViewSource => 'Ver el código fuente en GitHub';

  @override
  String get exWorkerAuto => 'Automático';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rendimiento: $count trabajadores',
      one: 'Rendimiento: un solo trabajador',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count trabajadores';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Adjuntar estos diagnósticos al informe';

  @override
  String get feedbackClearLog => 'Borrar registro';

  @override
  String get feedbackCopyDiagnostics => 'Copiar diagnósticos';

  @override
  String get feedbackDiagnosticsNotice =>
      'El formulario de comentarios se abre en tu navegador. Los diagnósticos que aparecen a continuación se recopilan solo en este dispositivo y se adjuntan para ayudar a reproducir el problema. Revísalos primero: no incluyas nada que prefieras mantener privado.';

  @override
  String get feedbackOpenForm => 'Abrir formulario de comentarios';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get none => 'Ninguno';

  @override
  String get ok => 'Aceptar';

  @override
  String get paste => 'Pegar';

  @override
  String get redo => 'Rehacer';

  @override
  String get remove => 'Quitar';

  @override
  String get rename => 'Cambiar nombre';

  @override
  String get reset => 'Restablecer';

  @override
  String get save => 'Guardar';

  @override
  String get scrollDemoNextPage => 'Página siguiente';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Página $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Página anterior';

  @override
  String get scrollDemoSwitchHorizontal => 'Cambiar a diseño horizontal';

  @override
  String get scrollDemoSwitchVertical => 'Cambiar a diseño vertical';

  @override
  String get scrollDemoTitle => 'API del indicador de desplazamiento';

  @override
  String get undo => 'Deshacer';

  @override
  String get exFileTypePdf => 'Documentos PDF';

  @override
  String get exFileTypeImages => 'Imágenes';

  @override
  String get exFileTypeFonts => 'Fuentes';
}
