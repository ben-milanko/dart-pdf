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
  String get appSigAddLogo => 'Adicionar logotipo…';

  @override
  String appSigAllPages(int pageCount) {
    return 'Todas as $pageCount páginas';
  }

  @override
  String get appSigAppearance => 'Aparência';

  @override
  String get appSigAppearanceDescription =>
      'A assinatura é desenhada onde você a posicionou. O nome do signatário e os detalhes são sempre exibidos; você pode adicionar uma marca desenhada à mão e um logotipo de fundo.';

  @override
  String appSigApplyTo(String label) {
    return 'Aplicar a: $label';
  }

  @override
  String get appSigApplyToPages => 'Aplicar às páginas…';

  @override
  String get appSigChooseCertificate => 'Escolher arquivo de certificado…';

  @override
  String get appSigChooseKeyDescription =>
      'Escolha sua chave privada (RSA, PEM ou DER) e seu arquivo de certificado. A chave é usada apenas para assinar e nunca é salva.';

  @override
  String get appSigChoosePngOrJpeg => 'Escolha uma imagem PNG ou JPEG.';

  @override
  String get appSigChoosePrivateKey => 'Escolher chave privada…';

  @override
  String get appSigContactInfo => 'Informações de contato';

  @override
  String get appSigCouldNotCaptureSignature =>
      'Não foi possível capturar a assinatura.';

  @override
  String appSigCouldNotReadCertificate(String error) {
    return 'Não foi possível ler o certificado: $error';
  }

  @override
  String appSigCouldNotReadKey(String error) {
    return 'Não foi possível ler a chave: $error';
  }

  @override
  String get appSigCreateOnDevice => 'Criar uma assinatura neste dispositivo';

  @override
  String appSigDate(String date) {
    return 'Data: $date';
  }

  @override
  String get appSigDigitallySign => 'Assinar digitalmente';

  @override
  String get appSigDrawSignature => 'Desenhar assinatura…';

  @override
  String get appSigFieldHelper =>
      'Deixe em branco para criar um novo campo de assinatura.';

  @override
  String get appSigFieldLabel => 'Campo de assinatura existente (opcional)';

  @override
  String appSigIdentitySubtitle(
      int count, String validFrom, String validUntil) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certificados',
      one: '1 certificado',
    );
    return '$_temp0 · válido de $validFrom a $validUntil';
  }

  @override
  String get appSigIntro =>
      'Uma assinatura digital comprova que você assinou este documento e que ele não foi alterado desde então. Escolha como deseja assinar.';

  @override
  String get appSigKeyOrCertUnreadable =>
      'Não foi possível ler a chave ou o certificado selecionado.';

  @override
  String get appSigKeylessDescription =>
      'Mais fácil. Confirmamos que é você por e-mail e assinamos por você, com um carimbo de tempo confiável. Nada para instalar ou configurar.';

  @override
  String get appSigKeylessIdentity => 'Identidade sem chave';

  @override
  String get appSigKeylessSignInExpired =>
      'Seu login sem chave expirou. Faça login novamente.';

  @override
  String appSigKeylessSignInFailed(String failure) {
    return 'Falha no login sem chave: $failure';
  }

  @override
  String get appSigKeylessSubtitle =>
      'Sem chave · com carimbo de tempo · validade desconhecida';

  @override
  String get appSigKeylessWebNote =>
      'Entrar com seu e-mail é a forma mais fácil — está disponível nos aplicativos DartPDF para desktop e celular. Por motivos de segurança, não é possível executá-lo em um navegador web.';

  @override
  String get appSigLocation => 'Local';

  @override
  String get appSigLogoAdded => 'Logotipo adicionado ✓';

  @override
  String appSigPagesRange(int start, int end) {
    return 'Páginas $start–$end';
  }

  @override
  String get appSigPreviewNote =>
      'Prévia - a caixa assinada pode ficar um pouco diferente.';

  @override
  String get appSigReason => 'Motivo';

  @override
  String appSigReasonLine(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get appSigRefreshingSignIn => 'Atualizando login…';

  @override
  String get appSigRemoveLogo => 'Remover logotipo';

  @override
  String get appSigRemoveSignature => 'Remover assinatura';

  @override
  String get appSigSelfSignedDescription =>
      'Sem necessidade de login ou arquivos. Ideal para uso pessoal — fica salvo neste dispositivo para a próxima vez. Alguns leitores de PDF a mostrarão como \"assinado, validade desconhecida\", o que é normal para uma assinatura feita por você mesmo.';

  @override
  String get appSigSelfSignedIdentity => 'Identidade autoassinada';

  @override
  String get appSigSelfSignedSubtitle => 'Autoassinada · validade desconhecida';

  @override
  String get appSigShowSignatureOnPages => 'Mostrar a assinatura nas páginas';

  @override
  String get appSigSign => 'Assinar';

  @override
  String get appSigSignInWithEmail => 'Entrar com seu e-mail';

  @override
  String get appSigSignatureAdded => 'Assinatura adicionada ✓';

  @override
  String appSigSignedBy(String signerName) {
    return 'Assinado digitalmente por $signerName';
  }

  @override
  String get appSigSigner => 'Signatário';

  @override
  String get appSigSigningYouIn => 'Fazendo seu login…';

  @override
  String get appSigThisPageOnly => 'Somente esta página';

  @override
  String get appSigUseOwnCertificate => 'Usar seu próprio certificado';

  @override
  String get appSigUseOwnCertificateSubtitle =>
      'Para um certificado de assinatura da sua organização';

  @override
  String get appSigX509Signer => 'Signatário X.509';

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
  String editorAddDroppedMessage(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Abrir estes $count PDFs em uma nova aba ou inserir suas páginas em \"$title\"?',
      one:
          'Abrir este PDF em uma nova aba ou inserir suas páginas em \"$title\"?',
    );
    return '$_temp0';
  }

  @override
  String editorAddDroppedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Adicionar PDFs soltos',
      one: 'Adicionar PDF solto',
    );
    return '$_temp0';
  }

  @override
  String get editorAnnotationTextCopied => 'Texto da anotação copiado';

  @override
  String get editorAppMenuTooltip => 'Menu do DartPDF';

  @override
  String get editorCancelOcr => 'Cancelar OCR';

  @override
  String get editorClearRecentFiles => 'Limpar arquivos recentes';

  @override
  String get editorCloseAll => 'Fechar tudo';

  @override
  String get editorCloseOthers => 'Fechar as outras';

  @override
  String get editorCloseTab => 'Fechar aba';

  @override
  String get editorCloseTabsToRight => 'Fechar abas à direita';

  @override
  String get editorCompareFailedTitle => 'Falha na comparação';

  @override
  String editorCompareTitle(String title) {
    return 'Comparar: $title';
  }

  @override
  String get editorCopiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get editorCopySelectedTextTooltip => 'Copiar texto selecionado (⌘C)';

  @override
  String get editorCopyText => 'Copiar texto';

  @override
  String editorCouldNotExport(String title) {
    return 'Não foi possível exportar $title';
  }

  @override
  String editorCouldNotImportStamps(String error) {
    return 'Não foi possível importar carimbos: $error';
  }

  @override
  String editorCouldNotInsertDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível inserir os PDFs soltos',
      one: 'Não foi possível inserir o PDF solto',
    );
    return '$_temp0';
  }

  @override
  String editorCouldNotOpenDetail(String title, String error) {
    return 'Não foi possível abrir $title\n$error';
  }

  @override
  String get editorCouldNotOpenFolder =>
      'Não foi possível abrir a pasta que contém o arquivo';

  @override
  String editorCouldNotOpenSecond(String error) {
    return 'Não foi possível abrir o segundo arquivo\n$error';
  }

  @override
  String editorCouldNotOpenSelected(String error) {
    return 'Não foi possível abrir o arquivo selecionado\n$error';
  }

  @override
  String editorCouldNotOpenUrl(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String editorCouldNotPrint(String title) {
    return 'Não foi possível imprimir $title';
  }

  @override
  String editorCouldNotReopen(String title) {
    return 'Não foi possível reabrir $title';
  }

  @override
  String editorCouldNotSign(String error) {
    return 'Não foi possível assinar digitalmente: $error';
  }

  @override
  String get editorDiscard => 'Descartar';

  @override
  String get editorDiscardChangesTitle => 'Descartar alterações?';

  @override
  String get editorDocumentSigned => 'Documento assinado digitalmente';

  @override
  String get editorDownload => 'Baixar';

  @override
  String get editorDropToOpen => 'Solte o PDF para abrir';

  @override
  String get editorDropToOpenOrInsert => 'Solte o PDF para abrir ou inserir';

  @override
  String get editorInsertPages => 'Inserir páginas';

  @override
  String editorInsertedButFailed(int count, String files) {
    return 'Inseridos $count; não foi possível ler $files';
  }

  @override
  String editorInsertedIntoTitle(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs inseridos em $title',
      one: 'Páginas inseridas em $title',
    );
    return '$_temp0';
  }

  @override
  String editorInvalidLink(String uri) {
    return 'Link inválido: $uri';
  }

  @override
  String get editorJavaScriptIgnored =>
      'Este documento tentou executar JavaScript (ignorado)';

  @override
  String get editorLoadingFullDocument => 'Carregando o documento completo';

  @override
  String get editorMenuCompareWith => 'Comparar com…';

  @override
  String get editorMenuDigitallySign => 'Assinar digitalmente…';

  @override
  String get editorMenuDigitallySigning => 'Assinando digitalmente…';

  @override
  String get editorMenuExportImage => 'Exportar página como imagem…';

  @override
  String get editorMenuNewDocument => 'Novo documento…';

  @override
  String get editorMenuOcr => 'OCR…';

  @override
  String get editorMenuOpen => 'Abrir um PDF…';

  @override
  String get editorMenuPrint => 'Imprimir…';

  @override
  String get editorMenuSaveAs => 'Salvar como…';

  @override
  String get editorMenuSettings => 'Configurações';

  @override
  String get editorMenuSwitchToEdit => 'Alternar para o modo de edição';

  @override
  String get editorMenuSwitchToReadOnly => 'Alternar para somente leitura';

  @override
  String editorNamedAction(String name) {
    return 'Ação nomeada: $name';
  }

  @override
  String get editorNoRecentFiles => 'Nenhum arquivo recente';

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
      'Abra um documento antes de executar o OCR';

  @override
  String get editorOpenFailedTitle => 'Falha ao abrir';

  @override
  String editorOpenInNewTab(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abrir em novas abas',
      one: 'Abrir em nova aba',
    );
    return '$_temp0';
  }

  @override
  String get editorOpenPdfNewTab => 'Abrir PDF em uma nova aba';

  @override
  String get editorOpenRecent => 'Abrir recentes';

  @override
  String get editorOpenTabs => 'Abas abertas';

  @override
  String get editorOpeningDocumentSemantic => 'Abrindo documento';

  @override
  String get editorOpeningPdf => 'Abrindo PDF…';

  @override
  String editorOpeningTitle(String title) {
    return 'Abrindo $title…';
  }

  @override
  String editorPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String get editorPreviewComparison => 'Comparação';

  @override
  String get editorPreviewCouldNotOpen => 'Não foi possível abrir';

  @override
  String get editorPreviewOpening => 'Abrindo';

  @override
  String get editorPreviewPdf => 'PDF';

  @override
  String get editorSignatureRemoved => 'Assinatura removida';

  @override
  String get editorSnapshotCopied =>
      'Instantâneo copiado para a área de transferência';

  @override
  String get editorSnapshotCopyFailed =>
      'Não foi possível copiar o instantâneo para a área de transferência';

  @override
  String get editorTabs => 'Abas';

  @override
  String editorTabsOpenCount(int count) {
    return '$count abertas';
  }

  @override
  String editorUnsavedChangesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documentos têm alterações não salvas.',
      one: 'Um documento tem alterações não salvas.',
    );
    return '$_temp0';
  }

  @override
  String editorUnsupportedAction(String type) {
    return 'Ação não suportada: $type';
  }

  @override
  String get editorUntitled => 'Sem título';

  @override
  String editorUpdateAvailable(String version) {
    return 'O DartPDF $version está disponível.';
  }

  @override
  String get editorUpdateLater => 'Depois';

  @override
  String get editorViewAllTabs => 'Ver todas as abas';

  @override
  String imgExportDpiValue(int dpi) {
    return '$dpi dpi';
  }

  @override
  String get imgExportExport => 'Exportar';

  @override
  String get imgExportFormat => 'Formato';

  @override
  String get imgExportResolution => 'Resolução';

  @override
  String get imgExportTitle => 'Exportar página como imagem';

  @override
  String get newDocCreate => 'Criar';

  @override
  String get newDocLandscape => 'Paisagem';

  @override
  String get newDocOrientation => 'Orientação';

  @override
  String get newDocPageSize => 'Tamanho da página';

  @override
  String get newDocPortrait => 'Retrato';

  @override
  String get newDocTitle => 'Novo documento';

  @override
  String get none => 'Nenhum';

  @override
  String get ocrAlreadyRunning =>
      'O OCR já está em execução - aguarde a conclusão ou cancele-o';

  @override
  String get ocrBrowserInitFailed => 'Falha ao inicializar o OCR do navegador';

  @override
  String get ocrCancelled => 'OCR cancelado';

  @override
  String ocrCancelledAfterSpans(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'OCR cancelado após $count trechos de texto',
      one: 'OCR cancelado após 1 trecho de texto',
    );
    return '$_temp0';
  }

  @override
  String get ocrDownload => 'Baixar';

  @override
  String ocrDownloadFailed(String error) {
    return 'Não foi possível baixar o modelo de OCR: $error';
  }

  @override
  String ocrDownloadPromptBody(String size, String model) {
    return 'Adicionar uma camada de texto selecionável requer o modelo de OCR no dispositivo$size. Ele é baixado uma vez e depois funciona offline.\n\nModelo: $model';
  }

  @override
  String get ocrDownloadPromptTitle => 'Baixar modelo de OCR?';

  @override
  String ocrFailed(String error) {
    return 'OCR falhou: $error';
  }

  @override
  String ocrModelApproxSize(int mb) {
    return '(~$mb MB)';
  }

  @override
  String get ocrNotAvailable =>
      'O OCR no dispositivo não está disponível nesta plataforma';

  @override
  String ocrResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'O OCR adicionou $count trechos de texto - o texto da página agora é selecionável',
      one:
          'O OCR adicionou 1 trecho de texto - o texto da página agora é selecionável',
      zero: 'O OCR não encontrou texto nessas páginas',
    );
    return '$_temp0';
  }

  @override
  String get ocrWebPromptBody =>
      'O OCR web baixa um modelo de linguagem e visão Florence-2 e o executa localmente com WebGPU/WASM através do Transformers.js. As páginas do PDF permanecem neste navegador; apenas os arquivos do modelo são buscados no primeiro uso.';

  @override
  String get ocrWebPromptTitle => 'Executar OCR com IA neste navegador?';

  @override
  String get ocrWebStart => 'Iniciar OCR';

  @override
  String get ok => 'OK';

  @override
  String get paste => 'Colar';

  @override
  String get printDlgPreparing => 'Preparando…';

  @override
  String printDlgRendering(int rendered, int total) {
    return 'Renderizando página $rendered de $total…';
  }

  @override
  String get printDlgTitle => 'Imprimindo';

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
  String get settingsAbout => 'Sobre';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsCheckNow => 'Verificar agora';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Padrão do sistema';

  @override
  String get settingsCheckingForUpdates => 'Verificando atualizações…';

  @override
  String get settingsCouldNotOpenDownload =>
      'Não foi possível abrir o download';

  @override
  String get settingsCouldNotOpenSystemSettings =>
      'Não foi possível abrir as configurações do sistema';

  @override
  String get settingsDeveloperTools => 'Ferramentas de desenvolvedor';

  @override
  String get settingsDeveloperToolsSubtitle =>
      'Métricas, logs, modos de renderização (F12)';

  @override
  String settingsDownloadVersion(String version) {
    return 'Baixar $version';
  }

  @override
  String get settingsOpenSettings => 'Abrir configurações';

  @override
  String settingsRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lembrados',
      one: '1 lembrado',
      zero: 'Nenhum arquivo recente',
    );
    return '$_temp0';
  }

  @override
  String get settingsRecentFiles => 'Arquivos recentes';

  @override
  String get settingsSetUpAsDefault => 'Definir como aplicativo padrão';

  @override
  String get settingsSystem => 'Sistema';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String settingsUpToDate(String version) {
    return 'Você está na versão mais recente ($version).';
  }

  @override
  String settingsUpdateAvailable(String version, String currentVersion) {
    return 'A versão $version está disponível (você tem a $currentVersion).';
  }

  @override
  String get settingsUpdateFailed =>
      'Não foi possível verificar atualizações. Tente novamente mais tarde.';

  @override
  String settingsUpdateIdle(String name, String version) {
    return 'Você tem o $name $version.';
  }

  @override
  String get settingsUpdates => 'Atualizações';

  @override
  String get settingsViewSource => 'Ver código-fonte no GitHub';

  @override
  String get undo => 'Desfazer';

  @override
  String get welcomeOpenPdf => 'Abrir um PDF';

  @override
  String get welcomePickAgainToReopen => 'Selecione novamente para reabrir';

  @override
  String get welcomeRecent => 'Recentes';

  @override
  String get welcomeRemoveFromRecent => 'Remover dos recentes';

  @override
  String get welcomeTapToReopen => 'Toque para reabrir';

  @override
  String settingsDefaultAppSubtitle(String platform) {
    String _temp0 = intl.Intl.selectLogic(
      platform,
      {
        'web': 'Instale o aplicativo web e depois escolha-o para arquivos PDF.',
        'windows':
            'Abra as configurações de aplicativos padrão do Windows para PDFs.',
        'macos': 'Siga as etapas “Sempre abrir com” do Finder.',
        'linux':
            'Use as configurações de aplicativos padrão da sua área de trabalho.',
        'android':
            'Escolha o DartPDF ao abrir um PDF e depois toque em Sempre.',
        'ios':
            'Use Compartilhar ou Abrir em, no app Arquivos, para enviar PDFs para cá.',
        'other': 'Configure o manipulador de arquivos PDF do seu sistema.',
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
            'Instale o DartPDF pelo seu navegador primeiro. Depois use as configurações de manipulador de arquivos do navegador ou do sistema operacional para associar arquivos PDF ao aplicativo instalado.',
        'windows':
            'As Configurações do Windows abrirão em Aplicativos padrão. Pesquise por “.pdf” ou “PDF”, escolha o app de PDF atual e depois selecione o DartPDF.',
        'macos':
            'No Finder, selecione qualquer PDF, escolha Arquivo > Obter informações, expanda “Abrir com”, escolha o DartPDF e depois clique em “Alterar tudo…”.',
        'linux':
            'Abra as configurações de Aplicativos padrão da sua área de trabalho ou clique com o botão direito em um PDF no Arquivos, escolha Propriedades e defina o DartPDF como padrão para documentos PDF.',
        'android':
            'Abra um PDF pelo Arquivos ou Downloads, escolha o DartPDF no seletor de apps e depois selecione Sempre. Se outro app já abrir PDFs, limpe primeiro os padrões desse app nas Configurações do Android.',
        'ios':
            'O iOS não oferece um editor de PDF padrão global. Use Arquivos > Compartilhar ou pressione e segure um PDF e escolha Compartilhar/Abrir em, depois selecione o DartPDF.',
        'other':
            'Use as configurações do sistema para manipuladores de arquivos para associar documentos PDF ao DartPDF.',
      },
    );
    return '$_temp0';
  }

  @override
  String get ocrChipDownloadingModel => 'Baixando modelo de OCR…';

  @override
  String ocrChipDownloadingModelPercent(int percent) {
    return 'Baixando modelo $percent%';
  }

  @override
  String ocrChipRecognising(int page, int pageCount) {
    return 'OCR $page/$pageCount';
  }

  @override
  String get ocrChipFinishing => 'Concluindo OCR…';

  @override
  String get fileTypePdf => 'Documentos PDF';

  @override
  String get fileTypeImages => 'Imagens';

  @override
  String get fileTypeStampBundle => 'Carimbos do DartPDF';

  @override
  String get appSigKeyFileType => 'Chaves privadas RSA';

  @override
  String get appSigCertificateFileType => 'Certificados X.509';

  @override
  String get appSigErrorNoCertificateSelected =>
      'Selecione pelo menos um certificado X.509.';

  @override
  String appSigErrorInvalidCertificate(int index) {
    return 'O certificado $index não é um X.509 válido.';
  }

  @override
  String get appSigErrorKeyCertificateMismatch =>
      'A chave privada não corresponde a nenhum certificado RSA selecionado.';

  @override
  String get appSigErrorEncryptedKeyUnsupported =>
      'Chaves privadas criptografadas não são suportadas. Escolha uma chave RSA PKCS#1 ou PKCS#8 não criptografada.';

  @override
  String get appSigErrorKeyNotRsa =>
      'A chave privada não é uma chave RSA PKCS#1 ou PKCS#8 não criptografada.';

  @override
  String get appSigErrorNoCertificateFound =>
      'Nenhum certificado X.509 foi encontrado.';
}
