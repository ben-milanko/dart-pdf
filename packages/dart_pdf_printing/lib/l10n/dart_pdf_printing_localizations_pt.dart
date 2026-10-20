// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_printing_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class DartPdfPrintingLocalizationsPt extends DartPdfPrintingLocalizations {
  DartPdfPrintingLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get printDlgPreparing => 'Preparando…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Renderizando página $rendered de $total…';
  }

  @override
  String get printDlgTitle => 'Imprimindo';

  @override
  String get printPreviewAll => 'Todas';

  @override
  String get printPreviewCurrent => 'Atual';

  @override
  String get printPreviewNextPage => 'Próxima página';

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
    return 'Insira um intervalo de páginas entre 1 e $total.';
  }

  @override
  String printPreviewSelection(int count) {
    return 'Páginas para imprimir: $count';
  }

  @override
  String get printPreviewTitle => 'Visualização de impressão';

  @override
  String get printPreviewUnavailable => 'Visualização indisponível';

  @override
  String get printOptionsPrinter => 'Impressora';

  @override
  String get printOptionsNativePrinter =>
      'Na próxima caixa de diálogo de impressão do sistema, escolha a impressora, a bandeja de papel, a cor, a impressão frente e verso e as propriedades do dispositivo. Mantenha a escala em 100% e o número de cópias em 1 para usar o layout mostrado aqui.';

  @override
  String get printOptionsPages => 'Páginas';

  @override
  String get printOptionsSelected => 'Selecionadas';

  @override
  String get printOptionsPageRange => 'Páginas (por exemplo, 1, 3-5)';

  @override
  String get printOptionsAddFiles => 'Adicionar arquivos…';

  @override
  String get printOptionsAddFailed =>
      'Não foi possível adicionar os arquivos selecionados.';

  @override
  String get printOptionsGetWindow => 'Selecionar área';

  @override
  String get printOptionsClearWindow => 'Limpar área';

  @override
  String get printOptionsWindowHint =>
      'Arraste um retângulo nesta página de origem para escolher a área a imprimir.';

  @override
  String get printOptionsPaper => 'Papel';

  @override
  String get printOptionsPaperSize => 'Tamanho do papel';

  @override
  String get printOptionsPageSize => 'Usar tamanho da página do documento';

  @override
  String get printOptionsOrientation => 'Orientação';

  @override
  String get printOptionsAuto => 'Automática';

  @override
  String get printOptionsPortrait => 'Retrato';

  @override
  String get printOptionsLandscape => 'Paisagem';

  @override
  String get printOptionsCopies => 'Cópias';

  @override
  String get printOptionsCollate => 'Agrupar cópias';

  @override
  String get printOptionsReverse => 'Inverter ordem das páginas';

  @override
  String get printOptionsLayout => 'Layout da página';

  @override
  String get printOptionsScaling => 'Escala da página';

  @override
  String get printOptionsScaleNone => 'Nenhuma (tamanho real)';

  @override
  String get printOptionsFitPaper => 'Ajustar ao papel';

  @override
  String get printOptionsReducePaper => 'Reduzir ao tamanho do papel';

  @override
  String get printOptionsFitMargins => 'Ajustar às margens';

  @override
  String get printOptionsReduceMargins => 'Reduzir para caber nas margens';

  @override
  String get printOptionsCustomScale => 'Escala personalizada';

  @override
  String get printOptionsMultiple => 'Várias páginas por folha';

  @override
  String get printOptionsScalePercent => 'Escala (%)';

  @override
  String get printOptionsMargin => 'Margens (pt)';

  @override
  String get printOptionsPagesPerSheet => 'Páginas por folha';

  @override
  String get printOptionsPageOrder => 'Ordem das páginas';

  @override
  String get printOptionsHorizontal => 'Horizontal';

  @override
  String get printOptionsHorizontalReverse => 'Horizontal invertida';

  @override
  String get printOptionsVertical => 'Vertical';

  @override
  String get printOptionsVerticalReverse => 'Vertical invertida';

  @override
  String get printOptionsBorder => 'Imprimir bordas das páginas';

  @override
  String get printOptionsRotation => 'Rotação (sentido horário)';

  @override
  String get printOptionsNoRotation => 'Nenhuma';

  @override
  String get printOptionsCenter => 'Centralizar no papel';

  @override
  String get printOptionsOffsetX => 'Deslocamento à direita (pt)';

  @override
  String get printOptionsOffsetY => 'Deslocamento para baixo (pt)';

  @override
  String get printOptionsContents => 'Conteúdo a imprimir';

  @override
  String get printOptionsDocumentAndMarkups => 'Documento e anotações';

  @override
  String get printOptionsDocumentOnly => 'Somente documento';

  @override
  String get printOptionsMarkupsOnly => 'Somente anotações';

  @override
  String get printOptionsDimPage => 'Clarear conteúdo da página';

  @override
  String get printOptionsDimMarkups => 'Clarear anotações';

  @override
  String get printOptionsHyperlinks => 'Imprimir hiperlinks visíveis';

  @override
  String get printOptionsDefaults => 'Padrões';

  @override
  String get printOptionsInvalidNumber =>
      'Insira números válidos antes de imprimir.';

  @override
  String get printOptionsInvalidValue => 'Valor inválido';

  @override
  String get printOptionsMarginGuide =>
      'As linhas vermelhas mostram as margens e não são impressas.';

  @override
  String printOptionsAreaSize(String width, String height) {
    return 'Área: $width × $height pt';
  }

  @override
  String printOptionsSourceSize(String width, String height) {
    return 'Origem: $width × $height pt';
  }

  @override
  String printOptionsSheetSize(String width, String height) {
    return 'Folha: $width × $height pt';
  }

  @override
  String printOptionsSheetOf(int sheet, int total) {
    return 'Folha $sheet de $total';
  }

  @override
  String get printOptionsInvalidLayout =>
      'Não foi possível preparar este layout. Verifique o tamanho do papel, as margens e a escala.';

  @override
  String get printOptionsChoosePrinter => 'Escolher uma impressora';

  @override
  String get printOptionsNoPrinters =>
      'Nenhuma impressora está instalada. Adicione uma impressora nas Configurações do Windows e tente novamente.';

  @override
  String printOptionsPrinterUnavailable(String printer) {
    return 'A impressora salva “$printer” está indisponível. Escolha uma impressora para continuar.';
  }

  @override
  String get printOptionsPrinterError =>
      'Não foi possível carregar as configurações da impressora. Verifique a conexão da impressora e tente novamente.';

  @override
  String get printOptionsRetry => 'Tentar novamente';

  @override
  String get printOptionsColor => 'Cor';

  @override
  String get printOptionsGrayscale => 'Preto e branco';

  @override
  String get printOptionsDuplex => 'Impressão frente e verso';

  @override
  String get printOptionsSimplex => 'Um lado';

  @override
  String get printOptionsLongEdge => 'Virar na borda longa';

  @override
  String get printOptionsShortEdge => 'Virar na borda curta';

  @override
  String get printOptionsTray => 'Bandeja de papel';

  @override
  String get printOptionsDefaultTray => 'Padrão da impressora';

  @override
  String get printOptionsProperties => 'Propriedades da impressora…';

  @override
  String get printOptionsDirectPrinter =>
      'Imprimir envia este trabalho diretamente à impressora selecionada.';

  @override
  String get printOptionsPropertiesError =>
      'Não foi possível abrir as propriedades da impressora.';

  @override
  String get printOptionsLoadingPrinters => 'Carregando impressoras…';
}
