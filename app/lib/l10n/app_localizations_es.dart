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
  String get appSigAddLogo => 'Añadir logotipo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Las $pageCount páginas';
  }

  @override
  String get appSigAppearance => 'Apariencia';

  @override
  String get appSigAppearanceDescription =>
      'La firma se dibuja donde la coloques. El nombre del firmante y los detalles siempre se muestran; puedes añadir una marca dibujada a mano y un logotipo de fondo.';

  @override
  String appSigApplyTo(String label) {
    return 'Aplicar a: $label';
  }

  @override
  String get appSigApplyToPages => 'Aplicar a páginas…';

  @override
  String get appSigChooseCertificate => 'Elegir archivo de certificado…';

  @override
  String get appSigChooseKeyDescription =>
      'Elige tu clave privada (RSA, PEM o DER) y su archivo de certificado. La clave solo se usa para firmar y nunca se guarda.';

  @override
  String get appSigChoosePngOrJpeg => 'Elige una imagen PNG o JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Elegir clave privada…';

  @override
  String get appSigContactInfo => 'Información de contacto';

  @override
  String get appSigCouldNotCaptureSignature => 'No se pudo capturar la firma.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'No se pudo leer el certificado: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'No se pudo leer la clave: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Crear una firma en este dispositivo';

  @override
  String appSigDate(String date) {
    return 'Fecha: $date';
  }

  @override
  String get appSigDigitallySign => 'Firmar digitalmente';

  @override
  String get appSigDrawSignature => 'Dibujar firma…';

  @override
  String get appSigFieldHelper =>
      'Déjalo en blanco para crear un nuevo campo de firma.';

  @override
  String get appSigFieldLabel => 'Campo de firma existente (opcional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificados',
      one: '1 certificado',
    );
    return '$_temp0 · válido del $validFrom al $validUntil';
  }

  @override
  String get appSigIntro =>
      'Una firma digital demuestra que firmaste este documento y que no se ha modificado desde entonces. Elige cómo quieres firmar.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'No se pudo leer la clave o el certificado seleccionados.';

  @override
  String get appSigKeylessDescription =>
      'Lo más sencillo. Confirmamos que eres tú por correo electrónico y firmamos por ti, con una marca de tiempo de confianza. No hay nada que instalar ni configurar.';

  @override
  String get appSigKeylessIdentity => 'Identidad sin clave';

  @override
  String get appSigKeylessSignInExpired =>
      'Tu sesión sin clave ha caducado. Vuelve a iniciar sesión.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Error al iniciar sesión sin clave: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Sin clave · con marca de tiempo · validez desconocida';

  @override
  String get appSigKeylessWebNote =>
      'Iniciar sesión con tu correo electrónico es la forma más sencilla: está disponible en las apps de escritorio y móviles de DartPDF. Por motivos de seguridad no puede ejecutarse en un navegador web.';

  @override
  String get appSigLocation => 'Ubicación';

  @override
  String get appSigLogoAdded => 'Logotipo añadido ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Páginas $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Vista previa: el cuadro firmado puede diferir ligeramente.';

  @override
  String get appSigReason => 'Motivo';

  @override
  String appSigReasonLine(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Actualizando la sesión…';

  @override
  String get appSigRemoveLogo => 'Quitar logotipo';

  @override
  String get appSigRemoveSignature => 'Quitar firma';

  @override
  String get appSigSelfSignedDescription =>
      'No se necesita iniciar sesión ni archivos. Ideal para uso personal: se guarda en este dispositivo para la próxima vez. Algunos lectores de PDF la mostrarán como «firmada, validez desconocida», lo cual es normal para una firma que creas tú mismo.';

  @override
  String get appSigSelfSignedIdentity => 'Identidad autofirmada';

  @override
  String get appSigSelfSignedSubtitle => 'Autofirmada · validez desconocida';

  @override
  String get appSigShowSignatureOnPages => 'Mostrar la firma en las páginas';

  @override
  String get appSigSign => 'Firmar';

  @override
  String get appSigSignInWithEmail =>
      'Iniciar sesión con tu correo electrónico';

  @override
  String get appSigSignatureAdded => 'Firma añadida ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Firmado digitalmente por $signerName';
  }

  @override
  String get appSigSigner => 'Firmante';

  @override
  String get appSigSigningYouIn => 'Iniciando tu sesión…';

  @override
  String get appSigThisPageOnly => 'Solo esta página';

  @override
  String get appSigUseOwnCertificate => 'Usar tu propio certificado';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Para un certificado de firma de tu organización';

  @override
  String get appSigX509Signer => 'Firmante X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '¿Abrir estos $count PDF en una pestaña nueva o insertar sus páginas en «$title»?',
      one:
          '¿Abrir este PDF en una pestaña nueva o insertar sus páginas en «$title»?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Añadir PDF soltados',
      one: 'Añadir PDF soltado',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Texto de la anotación copiado';

  @override
  String get editorAppMenuTooltip => 'Menú de DartPDF';

  @override
  String get editorCancelOcr => 'Cancelar OCR';

  @override
  String get editorClearRecentFiles => 'Borrar archivos recientes';

  @override
  String get editorCloseAll => 'Cerrar todo';

  @override
  String get editorCloseOthers => 'Cerrar las demás';

  @override
  String get editorCloseTab => 'Cerrar pestaña';

  @override
  String get editorCloseTabsToRight => 'Cerrar pestañas a la derecha';

  @override
  String get editorCompareFailedTitle => 'Error en la comparación';

  @override
  String editorCompareTitle(String title) {
    return 'Comparar: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get editorCopySelectedTextTooltip => 'Copiar texto seleccionado (⌘C)';

  @override
  String get editorCopyText => 'Copiar texto';

  @override
  String editorCouldNotExport(String title) {
    return 'No se pudo exportar $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'No se pudieron importar los sellos: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No se pudieron insertar los PDF soltados',
      one: 'No se pudo insertar el PDF soltado',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'No se pudo abrir $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'No se pudo abrir la carpeta contenedora';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'No se pudo abrir el segundo archivo\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'No se pudo abrir el archivo seleccionado\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'No se pudo imprimir $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'No se pudo volver a abrir $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'No se pudo firmar digitalmente: $error';
  }

  @override
  String get editorDiscard => 'Descartar';

  @override
  String get editorDiscardChangesTitle => '¿Descartar cambios?';

  @override
  String get editorDocumentSigned => 'Documento firmado digitalmente';

  @override
  String get editorDownload => 'Descargar';

  @override
  String get editorDropToOpen => 'Suelta un PDF para abrirlo';

  @override
  String get editorDropToOpenOrInsert =>
      'Suelta un PDF para abrirlo o insertarlo';

  @override
  String get editorInsertPages => 'Insertar páginas';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Se insertaron $count; no se pudieron leer $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF insertados en $title',
      one: 'Páginas insertadas en $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Enlace no válido: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Este documento intentó ejecutar JavaScript (ignorado)';

  @override
  String get editorLoadingFullDocument => 'Cargando el documento completo';

  @override
  String get editorMenuCompareWith => 'Comparar con…';

  @override
  String get editorMenuDigitallySign => 'Firmar digitalmente…';

  @override
  String get editorMenuDigitallySigning => 'Firmando digitalmente…';

  @override
  String get editorMenuExportImage => 'Exportar página como imagen…';

  @override
  String get editorMenuNewDocument => 'Nuevo documento…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Abrir un PDF…';

  @override
  String get editorMenuPrint => 'Imprimir…';

  @override
  String get editorMenuSaveAs => 'Guardar como…';

  @override
  String get editorMenuScanDocument => 'Escanear a un nuevo documento…';

  @override
  String get editorMenuInsertScan => 'Insertar escaneo…';

  @override
  String get editorScanFailed => 'No se pudo escanear el documento.';

  @override
  String get editorInsertedScan => 'Páginas escaneadas insertadas.';

  @override
  String get editorMenuSettings => 'Configuración';

  @override
  String get editorMenuSwitchToEdit => 'Cambiar a modo de edición';

  @override
  String get editorMenuSwitchToReadOnly => 'Cambiar a solo lectura';

  @override
  String editorNamedAction(String name) {
    return 'Acción con nombre: $name';
  }

  @override
  String get editorNoRecentFiles => 'No hay archivos recientes';

  @override
  String editorOcrTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String editorOcrTooltip(String title) {
    return 'OCR · $title';
  }

  @override
  String get editorOpenDocBeforeOcr =>
      'Abre un documento antes de ejecutar el OCR';

  @override
  String get editorOpenFailedTitle => 'Error al abrir';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abrir en pestañas nuevas',
      one: 'Abrir en pestaña nueva',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Abrir PDF en una pestaña nueva';

  @override
  String get editorOpenRecent => 'Abrir reciente';

  @override
  String get editorOpenTabs => 'Pestañas abiertas';

  @override
  String get editorOpeningDocumentSemantic => 'Abriendo documento';

  @override
  String get editorOpeningPdf => 'Abriendo PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Abriendo $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get editorPreviewComparison => 'Comparación';

  @override
  String get editorPreviewCouldNotOpen => 'No se pudo abrir';

  @override
  String get editorPreviewOpening => 'Abriendo';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String editorRecoveredUnsavedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se recuperaron los cambios sin guardar de $count documentos de la última sesión.',
      one: 'Se recuperaron los cambios sin guardar de la última sesión.',
    );
    return '$_temp0';
  }

  @override
  String get editorSignatureRemoved => 'Firma eliminada';

  @override
  String get editorSnapshotCopied => 'Captura copiada al portapapeles';

  @override
  String get editorSnapshotCopyFailed =>
      'No se pudo copiar la captura al portapapeles';

  @override
  String get editorTabs => 'Pestañas';

  @override
  String editorTabsOpenCount(int count) {
    return '$count abiertas';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documentos tienen cambios sin guardar.',
      one: 'Un documento tiene cambios sin guardar.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Acción no admitida: $type';
  }

  @override
  String get editorUntitled => 'Sin título';

  @override
  String editorUpdateAvailable(String version) {
    return 'DartPDF $version está disponible.';
  }

  @override
  String get editorUpdateLater => 'Más tarde';

  @override
  String get updateInstallNow => 'Actualizar ahora';

  @override
  String get updateDownloadingTitle => 'Descargando actualización';

  @override
  String get updatePreparing => 'Preparando…';

  @override
  String updateDownloadingPercent(int percent) {
    return 'Descargando… $percent%';
  }

  @override
  String get updateRestarting => 'Reiniciando para completar la actualización…';

  @override
  String get updateHandedOff =>
      'Actualización descargada. Abriendo el instalador…';

  @override
  String updateFailed(String error) {
    return 'Error en la actualización: $error';
  }

  @override
  String get editorViewAllTabs => 'Ver todas las pestañas';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi ppp';
  }

  @override
  String get imgExportExport => 'Exportar';

  @override
  String get imgExportFormat => 'Formato';

  @override
  String get imgExportResolution => 'Resolución';

  @override
  String get imgExportTitle => 'Exportar página como imagen';

  @override
  String get newDocCreate => 'Crear';

  @override
  String get newDocLandscape => 'Horizontal';

  @override
  String get newDocOrientation => 'Orientación';

  @override
  String get newDocPageSize => 'Tamaño de página';

  @override
  String get newDocPortrait => 'Vertical';

  @override
  String get newDocTitle => 'Nuevo documento';

  @override
  String get none => 'Ninguno';

  @override
  String get ocrAlreadyRunning =>
      'El OCR ya se está ejecutando: espera a que termine o cancélalo';

  @override
  String get ocrBrowserInitFailed =>
      'No se pudo inicializar el OCR del navegador';

  @override
  String get ocrCancelled => 'OCR cancelado';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR cancelado tras $count fragmentos de texto',
      one: 'OCR cancelado tras 1 fragmento de texto',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Descargar';

  @override
  String ocrDownloadFailed(String error) {
    return 'No se pudo descargar el modelo de OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Añadir una capa de texto seleccionable requiere el modelo de OCR en el dispositivo$size. Se descarga una vez y luego funciona sin conexión.\n\nModelo: $model';
  }

  @override
  String get ocrDownloadPromptTitle => '¿Descargar el modelo de OCR?';

  @override
  String ocrFailed(String error) {
    return 'Error en el OCR: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'El OCR en el dispositivo no está disponible en esta plataforma';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'El OCR añadió $count fragmentos de texto: el texto de la página ahora se puede seleccionar',
      one:
          'El OCR añadió 1 fragmento de texto: el texto de la página ahora se puede seleccionar',
      zero: 'El OCR no encontró texto en estas páginas',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'El OCR web descarga un modelo de lenguaje-visión Florence-2 y lo ejecuta localmente con WebGPU/WASM a través de Transformers.js. Las páginas del PDF permanecen en este navegador; solo se obtienen los archivos del modelo en el primer uso.';

  @override
  String get ocrWebPromptTitle => '¿Ejecutar OCR con IA en este navegador?';

  @override
  String get ocrWebStart => 'Iniciar OCR';

  @override
  String get ok => 'Aceptar';

  @override
  String get paste => 'Pegar';

  @override
  String get printDlgPreparing => 'Preparando…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Procesando página $rendered de $total…';
  }

  @override
  String get printDlgTitle => 'Imprimiendo';

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
  String get settingsAbout => 'Acerca de';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsCheckNow => 'Comprobar ahora';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Predeterminado del sistema';

  @override
  String get settingsCheckingForUpdates => 'Buscando actualizaciones…';

  @override
  String get settingsCouldNotOpenDownload => 'No se pudo abrir la descarga';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'No se pudo abrir la configuración del sistema';

  @override
  String get settingsDeveloperTools => 'Herramientas para desarrolladores';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Métricas, registros, modos de renderizado (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Descargar $version';
  }

  @override
  String get settingsOpenSettings => 'Abrir configuración';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordados',
      one: '1 recordado',
      zero: 'No hay archivos recientes',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Archivos recientes';

  @override
  String get settingsSetUpAsDefault =>
      'Configurar como aplicación predeterminada';

  @override
  String get settingsSystem => 'Sistema';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Configuración';

  @override
  String settingsUpToDate(String version) {
    return 'Tienes la última versión ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'La versión $version está disponible (tienes la $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'No se pudieron comprobar las actualizaciones. Inténtalo de nuevo más tarde.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Tienes $name $version.';
  }

  @override
  String get settingsNightlyUpdates => 'Actualizaciones nocturnas';

  @override
  String get settingsNightlyUpdatesSubtitle =>
      'Recibe notificaciones automáticas de actualizaciones para compilaciones de prueba de Windows sin firmar desde main.';

  @override
  String get settingsUpdates => 'Actualizaciones';

  @override
  String get settingsViewSource => 'Ver el código fuente en GitHub';

  @override
  String get undo => 'Deshacer';

  @override
  String get welcomeOpenPdf => 'Abrir un PDF';

  @override
  String get welcomePickAgainToReopen =>
      'Selecciónalo de nuevo para volver a abrirlo';

  @override
  String get welcomeRecent => 'Recientes';

  @override
  String get welcomeRemoveFromRecent => 'Quitar de recientes';

  @override
  String get welcomeTapToReopen => 'Toca para volver a abrir';

  @override
  String get welcomeViewAsGrid => 'Vista de cuadrícula';

  @override
  String get welcomeViewAsList => 'Vista de lista';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web':
            'Instala la aplicación web y luego elígela para los archivos PDF.',
        'windows':
            'Abre la configuración de aplicaciones predeterminadas de Windows para los PDF.',
        'macos': 'Sigue los pasos «Abrir siempre con» del Finder.',
        'linux':
            'Usa la configuración de aplicaciones predeterminadas de tu escritorio.',
        'android': 'Elige DartPDF al abrir un PDF y luego toca Siempre.',
        'ios':
            'Usa Compartir o Abrir en desde Archivos para enviar los PDF aquí.',
        'other': 'Configura el gestor de archivos PDF de tu sistema.',
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
            'Instala DartPDF desde tu navegador primero. Luego usa la configuración del gestor de archivos del navegador o del sistema operativo para asociar los archivos PDF con la aplicación instalada.',
        'windows':
            'La configuración de Windows se abrirá en Aplicaciones predeterminadas. Busca «.pdf» o «PDF», elige la aplicación de PDF actual y luego selecciona DartPDF.',
        'macos':
            'En el Finder, selecciona cualquier PDF, elige Archivo > Obtener información, expande «Abrir con», elige DartPDF y luego haz clic en «Cambiar todo…».',
        'linux':
            'Abre la configuración de tu escritorio para Aplicaciones predeterminadas, o haz clic derecho en un PDF en Archivos, elige Propiedades y establece DartPDF como predeterminada para los documentos PDF.',
        'android':
            'Abre un PDF desde Archivos o Descargas, elige DartPDF en el selector de aplicaciones y luego selecciona Siempre. Si otra aplicación ya abre los PDF, borra primero los valores predeterminados de esa aplicación en la configuración de Android.',
        'ios':
            'iOS no ofrece un editor de PDF predeterminado global. Usa Archivos > Compartir, o mantén pulsado un PDF y elige Compartir/Abrir en, luego selecciona DartPDF.',
        'other':
            'Usa la configuración del sistema para gestores de archivos y asociar los documentos PDF con DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Descargando el modelo de OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Descargando el modelo $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Finalizando el OCR…';

  @override
  String get fileTypePdf => 'Documentos PDF';

  @override
  String get fileTypeImages => 'Imágenes';

  @override
  String get fileTypeStampBundle => 'Sellos de DartPDF';

  @override
  String get appSigKeyFileType => 'Claves privadas RSA';

  @override
  String get appSigCertificateFileType => 'Certificados X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Selecciona al menos un certificado X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'El certificado $index no es un X.509 válido.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'La clave privada no coincide con ningún certificado RSA seleccionado.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Las claves privadas cifradas no son compatibles. Elige una clave RSA PKCS#1 o PKCS#8 sin cifrar.';

  @override
  String get appSigErrorKeyNotRsa =>
      'La clave privada no es una clave RSA PKCS#1 o PKCS#8 sin cifrar.';

  @override
  String get appSigErrorNoCertificateFound =>
      'No se encontraron certificados X.509.';

  @override
  String get imageSourceTakePhoto => 'Hacer foto';

  @override
  String get imageSourceChooseFile => 'Elegir archivo';

  @override
  String get imageSourceCameraFailed => 'No se pudo hacer la foto';
}
