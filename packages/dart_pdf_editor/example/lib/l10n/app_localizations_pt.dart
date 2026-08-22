// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get add => 'Adicionar';

  @override
  String get apply => 'Aplicar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get clear => 'Limpar';

  @override
  String get close => 'Fechar';

  @override
  String get copy => 'Copiar';

  @override
  String get cut => 'Recortar';

  @override
  String get delete => 'Excluir';

  @override
  String get done => 'Concluído';

  @override
  String get edit => 'Editar';

  @override
  String exActionJavaScript(String script) {
    return 'JavaScript exibido para o app: $script';
  }

  @override
  String exActionLink(String uri) {
    return 'Link: $uri';
  }

  @override
  String exActionNamed(String name) {
    return 'Ação nomeada: $name';
  }

  @override
  String exActionUnhandled(String type) {
    return 'Tipo de ação não tratado: $type';
  }

  @override
  String get exAnnotationTextCopied => 'Texto da anotação copiado';

  @override
  String get exApiKeyHelper => 'Enviado como Authorization: Bearer …';

  @override
  String get exApiKeyLabel => 'Chave de API / token (opcional)';

  @override
  String get exAppMenuTooltip => 'Menu do DartPDF';

  @override
  String get exClearRecentFiles => 'Limpar arquivos recentes';

  @override
  String get exCloseTab => 'Fechar aba';

  @override
  String exCompareTabTitle(String before, String after) {
    return 'Comparar: $before ↔ $after';
  }

  @override
  String get exCompareWithAnother => 'Comparar com outro PDF…';

  @override
  String get exCopiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get exCopySelectedText => 'Copiar texto selecionado (⌘C)';

  @override
  String get exCopyText => 'Copiar texto';

  @override
  String exCouldNotOpenFile(String name, String error) {
    return 'Não foi possível abrir $name\n$error';
  }

  @override
  String exCouldNotOpenPath(String path, String error) {
    return 'Não foi possível abrir $path\n$error';
  }

  @override
  String exCouldNotOpenUrl(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String exCouldNotOpenUrlCors(String uri, String error) {
    return 'Não foi possível abrir $uri\n$error\n\nNa web, isso costuma ser uma restrição de CORS: o servidor deve enviar Access-Control-Allow-Origin e expor os cabeçalhos Range.';
  }

  @override
  String exCouldNotReopen(String title, String error) {
    return 'Não foi possível reabrir $title\n$error';
  }

  @override
  String exCouldNotReopenGone(String title) {
    return 'Não foi possível reabrir $title - sua cópia salva não está mais disponível.';
  }

  @override
  String get exDemoNoteHint =>
      'Digite aqui - esta caixa de texto flutua sobre a página';

  @override
  String get exDiagnosticsCopied =>
      'Diagnósticos copiados para a área de transferência';

  @override
  String exDownloaded(String name) {
    return 'Baixado $name';
  }

  @override
  String exDownloadedSnapshotCtrl(String name) {
    return 'Baixado $name - cole de volta no PDF com Ctrl+V';
  }

  @override
  String get exExport => 'Exportar';

  @override
  String exExportFailed(String error) {
    return 'Falha na exportação: $error';
  }

  @override
  String get exExportPageImageMenu => 'Exportar página como imagem…';

  @override
  String get exExportPageImageTitle => 'Exportar página como imagem';

  @override
  String get exFeatureShowcase => 'Demonstração de recursos';

  @override
  String get exFormat => 'Formato';

  @override
  String get exHide => 'Ocultar';

  @override
  String get exHorizontalLayout => 'Layout de página horizontal';

  @override
  String get exHowToSetupOcr => 'Como configurar um servidor de OCR';

  @override
  String get exModelName => 'Nome do modelo';

  @override
  String get exNoMessage => 'Sem mensagem';

  @override
  String get exNoRecentFiles => 'Nenhum arquivo recente';

  @override
  String exNotAValidUrl(String url) {
    return 'URL inválida:\n$url';
  }

  @override
  String exOcrAddedSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'O OCR adicionou $count trechos de texto - o texto da página agora é selecionável',
      one:
          'O OCR adicionou 1 trecho de texto - o texto da página agora é selecionável',
    );
    return '$_temp0';
  }

  @override
  String get exOcrDescription =>
      'Adiciona uma camada de texto selecionável e pesquisável sobre páginas digitalizadas usando um modelo de OCR de linguagem e visão hospedado por você (dots.ocr no vLLM ou qualquer endpoint de OCR compatível com OpenAI).';

  @override
  String exOcrDocumentTitle(String title) {
    return '$title (OCR)';
  }

  @override
  String exOcrFailed(String error) {
    return 'OCR falhou: $error';
  }

  @override
  String get exOcrMenu => 'OCR…';

  @override
  String get exOpen => 'Abrir';

  @override
  String get exOpenDocumentBeforeOcr =>
      'Abra um documento antes de executar o OCR';

  @override
  String get exOpenDocumentFirst => 'Abra um documento primeiro';

  @override
  String get exOpenFromUrl => 'Abrir de uma URL…';

  @override
  String get exOpenFromUrlTitle => 'Abrir de uma URL';

  @override
  String get exOpenInNewTab => 'Abrir PDF em uma nova aba';

  @override
  String get exOpenInteractiveDemo => 'Abrir a demonstração interativa';

  @override
  String get exOpenPdf => 'Abrir um PDF…';

  @override
  String get exOpenPdfButton => 'Abrir um PDF';

  @override
  String get exOpenRecent => 'Abrir recentes';

  @override
  String get exOpenUrlDescription =>
      'Transmite o PDF por requisições HTTP Range via PdfHttpByteSource, buscando apenas o que o analisador precisa e recorrendo a um download completo quando o servidor não oferece suporte a Range.';

  @override
  String get exOpeningDocument => 'Abrindo documento';

  @override
  String get exOpeningPdf => 'Abrindo PDF…';

  @override
  String exOpeningTitle(String title) {
    return 'Abrindo $title…';
  }

  @override
  String get exPdfUrlLabel => 'URL do PDF';

  @override
  String get exPerformanceAuto => 'Desempenho: Automático';

  @override
  String get exPreparing => 'Preparando…';

  @override
  String get exPubDevMenuItem => 'dart_pdf_editor no pub.dev';

  @override
  String exRecognisingPage(int current, int count) {
    return 'Reconhecendo página $current de $count…';
  }

  @override
  String get exResolution => 'Resolução';

  @override
  String get exRunOcr => 'Executar OCR';

  @override
  String get exSaveAs => 'Salvar como…';

  @override
  String exSaveFailed(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String exSavedName(String name) {
    return 'Salvo $name';
  }

  @override
  String exSavedSnapshotCmd(String name) {
    return 'Salvo $name - cole de volta no PDF com ⌘V';
  }

  @override
  String exSavedTo(String path) {
    return 'Salvo em $path';
  }

  @override
  String get exScrollIndicatorDemo =>
      'Demonstração da API de indicador de rolagem';

  @override
  String get exServiceEndpoint => 'Endpoint do serviço';

  @override
  String get exShow => 'Mostrar';

  @override
  String get exSingleWorker => 'Um único worker';

  @override
  String get exSupplyFeedback => 'Enviar feedback…';

  @override
  String get exSwitchToEdit => 'Alternar para o modo de edição';

  @override
  String get exSwitchToReadOnly => 'Alternar para somente leitura';

  @override
  String get exThemeDark => 'Tema: escuro - alternar para o sistema';

  @override
  String get exThemeLight => 'Tema: claro - alternar para escuro';

  @override
  String get exThemeSystem => 'Tema: sistema - alternar para claro';

  @override
  String get exTryDemo => 'Experimentar a demonstração interativa';

  @override
  String get exUntitled => 'Sem título';

  @override
  String get exVerticalLayout => 'Layout de página vertical';

  @override
  String get exViewSource => 'Ver código-fonte no GitHub';

  @override
  String get exWorkerAuto => 'Automático';

  @override
  String exWorkerPoolTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Desempenho: $count workers',
      one: 'Desempenho: um único worker',
    );
    return '$_temp0';
  }

  @override
  String exWorkersCount(int count) {
    return '$count workers';
  }

  @override
  String get feedbackAttachDiagnostics =>
      'Anexar estes diagnósticos ao relatório';

  @override
  String get feedbackClearLog => 'Limpar log';

  @override
  String get feedbackCopyDiagnostics => 'Copiar diagnósticos';

  @override
  String get feedbackDiagnosticsNotice =>
      'O formulário de feedback abre no seu navegador. Os diagnósticos abaixo são coletados apenas neste dispositivo e são anexados para ajudar a reproduzir o problema. Revise-os antes - não inclua nada que você prefira manter privado.';

  @override
  String get feedbackOpenForm => 'Abrir formulário de feedback';

  @override
  String get feedbackTitle => 'Enviar feedback';

  @override
  String get none => 'Nenhum';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Colar';

  @override
  String get redo => 'Refazer';

  @override
  String get remove => 'Remover';

  @override
  String get rename => 'Renomear';

  @override
  String get reset => 'Redefinir';

  @override
  String get save => 'Salvar';

  @override
  String get scrollDemoNextPage => 'Próxima página';

  @override
  String scrollDemoPageBubble(int current, int count) {
    return 'Página $current / $count';
  }

  @override
  String get scrollDemoPreviousPage => 'Página anterior';

  @override
  String get scrollDemoSwitchHorizontal => 'Alternar para layout horizontal';

  @override
  String get scrollDemoSwitchVertical => 'Alternar para layout vertical';

  @override
  String get scrollDemoTitle => 'API de indicador de rolagem';

  @override
  String get undo => 'Desfazer';

  @override
  String get exFileTypePdf => 'Documentos PDF';

  @override
  String get exFileTypeImages => 'Imagens';

  @override
  String get exFileTypeFonts => 'Fontes';
}
