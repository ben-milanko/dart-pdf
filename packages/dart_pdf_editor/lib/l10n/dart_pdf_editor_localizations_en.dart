// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'dart_pdf_editor_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class DartPdfEditorLocalizationsEn extends DartPdfEditorLocalizations {
  DartPdfEditorLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get add => 'Add';

  @override
  String get annotCaret => 'Caret';

  @override
  String get annotCircle => 'Circle';

  @override
  String get annotFileAttachment => 'File attachment';

  @override
  String get annotFreeText => 'Text box';

  @override
  String get annotHighlight => 'Highlight';

  @override
  String get annotInk => 'Ink';

  @override
  String get annotLine => 'Line';

  @override
  String get annotLink => 'Link';

  @override
  String get annotPolygon => 'Polygon';

  @override
  String get annotPolyline => 'Polyline';

  @override
  String get annotRedact => 'Redaction';

  @override
  String get annotSquare => 'Square';

  @override
  String get annotSquiggly => 'Squiggly';

  @override
  String get annotStamp => 'Stamp';

  @override
  String get annotStrikeOut => 'Strike-out';

  @override
  String get annotText => 'Note';

  @override
  String get annotUnderline => 'Underline';

  @override
  String get annotWidget => 'Form field';

  @override
  String get apply => 'Apply';

  @override
  String get bookmarkAdd => 'Add bookmark';

  @override
  String get bookmarkAddChild => 'Add child bookmark';

  @override
  String get bookmarkCollapse => 'Collapse';

  @override
  String get bookmarkDelete => 'Delete bookmark';

  @override
  String get bookmarkEdit => 'Edit bookmark';

  @override
  String get bookmarkEmpty => 'No bookmarks';

  @override
  String get bookmarkExpand => 'Expand';

  @override
  String get bookmarkExpandedByDefault => 'Expanded by default';

  @override
  String get bookmarkNoDestination => 'No destination';

  @override
  String get bookmarkPageFieldLabel => 'Page';

  @override
  String bookmarkPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String bookmarkPageRangeHint(int count) {
    return '1-$count';
  }

  @override
  String get bookmarkTitle => 'Bookmarks';

  @override
  String get bookmarkTitleLabel => 'Title';

  @override
  String get bookmarkUntitled => 'Untitled';

  @override
  String get cancel => 'Cancel';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get colorApplyingChanges => 'Applying color changes…';

  @override
  String get colorColorFormat => 'Color format';

  @override
  String get colorColorTitle => 'Color';

  @override
  String colorColorsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colors selected',
      one: '$count color selected',
    );
    return '$_temp0';
  }

  @override
  String get colorDocumentColors => 'Document colors';

  @override
  String get colorFillColors => 'Fill colors';

  @override
  String get colorFind => 'Find';

  @override
  String get colorInDocument => 'In document';

  @override
  String get colorNoColorsFound => 'No colors found yet';

  @override
  String get colorNoPageContentColors => 'No page-content colors found';

  @override
  String get colorPalette => 'Palette';

  @override
  String get colorPickColor => 'Pick color';

  @override
  String get colorProcessingTitle => 'Color processing';

  @override
  String get colorRecent => 'Recent';

  @override
  String get colorReplace => 'Replace';

  @override
  String get colorReplaceWithTransparent => 'Replace with transparent';

  @override
  String get colorScanning => 'Scanning…';

  @override
  String colorScanningProgress(int progress, int total) {
    return 'Scanning $progress / $total';
  }

  @override
  String colorSelectedPages(int count) {
    return 'Selected pages ($count)';
  }

  @override
  String get colorStrokeColors => 'Stroke colors';

  @override
  String get colorTolerance => 'Tolerance';

  @override
  String get colorTransparent => 'Transparent';

  @override
  String get colorWholeDocument => 'Whole document';

  @override
  String get compareAfter => 'After';

  @override
  String get compareBefore => 'Before';

  @override
  String compareChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0';
  }

  @override
  String compareChangePosition(int current, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$current / $_temp0';
  }

  @override
  String get compareEmptyLabel => '(empty)';

  @override
  String get compareNextChange => 'Next change';

  @override
  String get compareNoChanges => 'No changes';

  @override
  String get compareNoDifferences => 'No differences between the two documents';

  @override
  String get compareOverlay => 'Overlay';

  @override
  String comparePageHeader(int page) {
    return 'Page $page';
  }

  @override
  String get comparePreviousChange => 'Previous change';

  @override
  String get compareSideBySide => 'Side by side';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get editorViewAuthorNameTitle => 'Author name';

  @override
  String get lineStyleDashDot => 'Dash-dot';

  @override
  String get lineStyleDashed => 'Dashed';

  @override
  String get lineStyleDotted => 'Dotted';

  @override
  String get lineStyleSolid => 'Solid';

  @override
  String get measCalibrate => 'Calibrate';

  @override
  String get measCalibrateScale => 'Calibrate scale';

  @override
  String get measDepthLabel => 'Depth: ';

  @override
  String get measKindAngle => 'Angle';

  @override
  String get measKindArc => 'Arc';

  @override
  String get measKindArea => 'Area';

  @override
  String get measKindCount => 'Count';

  @override
  String get measKindLength => 'Length';

  @override
  String get measKindNetArea => 'Net area';

  @override
  String get measKindPerimeter => 'Perimeter';

  @override
  String get measKindSlope => 'Slope';

  @override
  String get measKindVolume => 'Volume';

  @override
  String get measLineRepresents => 'The line you drew represents:';

  @override
  String get measMeasure => 'Measure';

  @override
  String get measSetScale => 'Set measurement scale';

  @override
  String get measSetScaleButton => 'Set scale';

  @override
  String get measVolumeDepth => 'Volume depth';

  @override
  String get menuAddNode => 'Add node';

  @override
  String menuApplyAnnotationsToPagesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Apply annotations to pages',
      one: 'Apply annotation to pages',
    );
    return '$_temp0';
  }

  @override
  String get menuApplyToPages => 'Apply to pages…';

  @override
  String get menuBringToFront => 'Bring to front';

  @override
  String get menuCheck => 'Check';

  @override
  String get menuChooseValue => 'Choose value…';

  @override
  String get menuClearCheck => 'Clear check';

  @override
  String get menuConvertToCheckBox => 'Convert to check box';

  @override
  String get menuConvertToImageButton => 'Convert to image button';

  @override
  String get menuConvertToTextField => 'Convert to text field';

  @override
  String get menuDeleteField => 'Delete field';

  @override
  String get menuEditValue => 'Edit value…';

  @override
  String get menuFieldName => 'Field name';

  @override
  String get menuFieldValue => 'Field value';

  @override
  String get menuFlattenForm => 'Flatten form';

  @override
  String get menuLock => 'Lock';

  @override
  String get menuUnlock => 'Unlock';

  @override
  String get menuRecolour => 'Recolour…';

  @override
  String get menuRemoveNode => 'Remove node';

  @override
  String get menuSaveToStamps => 'Save to stamps';

  @override
  String get menuSetAsDefaultStyle => 'Set as default style';

  @override
  String get menuRename => 'Rename…';

  @override
  String get menuSelectOption => 'Select option';

  @override
  String get menuSendToBack => 'Send to back';

  @override
  String get menuSetImage => 'Set image…';

  @override
  String get menuTextStyle => 'Text style…';

  @override
  String get none => 'None';

  @override
  String get ok => 'OK';

  @override
  String get overlayColor => 'Color';

  @override
  String get overlayEditText => 'Edit text';

  @override
  String get overlayFont => 'Font';

  @override
  String get overlayLarger => 'Larger';

  @override
  String get overlayMore => 'More';

  @override
  String get overlayNote => 'Note';

  @override
  String get overlaySmaller => 'Smaller';

  @override
  String get overlayStampText => 'Stamp text';

  @override
  String get linkDialogTitle => 'Add link';

  @override
  String get linkKindWeb => 'Web address';

  @override
  String get linkKindPage => 'Page in document';

  @override
  String get linkUrlLabel => 'URL';

  @override
  String get linkPageLabel => 'Page number';

  @override
  String get toolLink => 'Link';

  @override
  String get overlayUnderline => 'Underline';

  @override
  String pageRangeErrorBounds(int count) {
    return 'Enter pages between 1 and $count.';
  }

  @override
  String get pageRangeErrorOrder =>
      'The last page must not be before the first.';

  @override
  String get pageRangeFrom => 'From';

  @override
  String pageRangePageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get pageRangeTo => 'To';

  @override
  String get panelDragToMovePanel => 'Drag to move panel';

  @override
  String get paste => 'Paste';

  @override
  String get propAlign => 'Align';

  @override
  String get propAlignCenter => 'Align center';

  @override
  String get propAlignLeft => 'Align left';

  @override
  String get propAlignRight => 'Align right';

  @override
  String propAnnotationCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count annotations',
      one: '$count annotation',
    );
    return '$_temp0';
  }

  @override
  String get propAuthor => 'Author';

  @override
  String get propAutoSize => 'Auto-size';

  @override
  String get propBold => 'Bold';

  @override
  String get propBoldLetter => 'B';

  @override
  String get propBundledFont => 'Bundled font';

  @override
  String get propCallout => 'Callout';

  @override
  String get propCharSpacing => 'Char spacing';

  @override
  String get propColor => 'Color';

  @override
  String get propColour => 'Colour';

  @override
  String get propContents => 'Contents';

  @override
  String get propCornerRadius => 'Corner radius';

  @override
  String get propEditsApplyToAll => 'Edits apply to all compatible annotations';

  @override
  String get propFieldName => 'Field name';

  @override
  String get propFieldTypeCheckBox => 'Check box';

  @override
  String get propFieldTypeComboBox => 'Combo box';

  @override
  String get propFieldTypeImageButton => 'Image button';

  @override
  String get propFieldTypeListBox => 'List box';

  @override
  String get propFieldTypeRadioGroup => 'Radio group';

  @override
  String get propFieldTypeSignature => 'Signature';

  @override
  String get propFieldTypeText => 'Text field';

  @override
  String propFieldTypeTooltip(String type) {
    return 'Field type: $type';
  }

  @override
  String get propFieldTypeUnknown => 'Unknown field';

  @override
  String get propFill => 'Fill';

  @override
  String get propFont => 'Font';

  @override
  String get propFontSubsetTooltip =>
      'This font is subset - only the characters already used in the document can be typed.';

  @override
  String get propFontWidth => 'Font width';

  @override
  String get propGeometryHeight => 'H';

  @override
  String get propGeometryWidth => 'W';

  @override
  String get propGeometryX => 'X';

  @override
  String get propGeometryY => 'Y';

  @override
  String get propItalic => 'Italic';

  @override
  String get propItalicLetter => 'I';

  @override
  String get propLimitedCharacters => 'Limited characters';

  @override
  String get propLineEnd => 'Line end';

  @override
  String get propLineEndingButt => 'Butt';

  @override
  String get propLineEndingCircle => 'Circle';

  @override
  String get propLineEndingClosedArrow => 'Closed arrow';

  @override
  String get propLineEndingClosedArrowRev => 'Closed arrow (rev.)';

  @override
  String get propLineEndingDiamond => 'Diamond';

  @override
  String get propLineEndingOpenArrow => 'Open arrow';

  @override
  String get propLineEndingOpenArrowRev => 'Open arrow (rev.)';

  @override
  String get propLineEndingSlash => 'Slash';

  @override
  String get propLineEndingSquare => 'Square';

  @override
  String get propLineSpacing => 'Line spacing';

  @override
  String get propLineStart => 'Line start';

  @override
  String get propLineType => 'Line type';

  @override
  String get propLoadFont => 'Load font…';

  @override
  String get propLoadFontSubtitle => 'TTF or OTF file';

  @override
  String get propMoreColors => 'More colors…';

  @override
  String get propMultiline => 'Multiline';

  @override
  String get propNoFill => 'No fill';

  @override
  String get propNoFontsFound => 'No fonts found';

  @override
  String get propNoOutline => 'No outline';

  @override
  String get propOpacity => 'Opacity';

  @override
  String get propOutline => 'Outline';

  @override
  String get propPageLabel => 'Page';

  @override
  String propPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get propPropertiesTitle => 'Properties';

  @override
  String get propRecentlyUsed => 'Recently used';

  @override
  String get propScale => 'Scale';

  @override
  String get propSearchFonts => 'Search fonts';

  @override
  String get propSectionAllFonts => 'All fonts';

  @override
  String get propSectionAppearance => 'Appearance';

  @override
  String get propSectionContent => 'Content';

  @override
  String get propSectionFormField => 'Form field';

  @override
  String get propSectionInThisDocument => 'In this document';

  @override
  String get propSectionPositionSize => 'Position & size (pt)';

  @override
  String get propSectionSelection => 'Selection';

  @override
  String get propSectionText => 'Text';

  @override
  String get propSelectAnnotationPrompt =>
      'Select an annotation to see its properties';

  @override
  String get propSize => 'Size';

  @override
  String get propStandardPdfFont => 'Standard PDF font';

  @override
  String get propStroke => 'Stroke';

  @override
  String get propStyle => 'Style';

  @override
  String get propSystemFont => 'System font';

  @override
  String get propType => 'Type';

  @override
  String get propUnderline => 'Underline';

  @override
  String get propVaries => 'Varies';

  @override
  String get redo => 'Redo';

  @override
  String get reflowNoContent => 'No extractable content';

  @override
  String reflowPageLabel(int number) {
    return 'Page $number';
  }

  @override
  String get reflowSaveOrShare => 'Save or share';

  @override
  String get reflowViewFigure => 'View figure';

  @override
  String get remove => 'Remove';

  @override
  String get rename => 'Rename';

  @override
  String get reset => 'Reset';

  @override
  String get save => 'Save';

  @override
  String get sbarActionJavaScript => 'JavaScript';

  @override
  String sbarActionPage(int page) {
    return 'Page $page';
  }

  @override
  String get sbarCallout => 'Callout';

  @override
  String get sbarFieldButton => 'Button field';

  @override
  String get sbarFieldChoice => 'Choice field';

  @override
  String get sbarFieldGeneric => 'Form field';

  @override
  String get sbarFieldSignature => 'Signature field';

  @override
  String get sbarFieldText => 'Text field';

  @override
  String get sbarStateAccepted => 'Accepted';

  @override
  String get sbarStateCancelled => 'Cancelled';

  @override
  String get sbarStateMarked => 'Marked';

  @override
  String get sbarStateRejected => 'Rejected';

  @override
  String get sbarStateResolved => 'Resolved';

  @override
  String get sbarStateUnmarked => 'Unmarked';

  @override
  String get searchAnnotations => 'Search annotations';

  @override
  String get searchClearSearch => 'Clear search';

  @override
  String get searchEmptyHint => 'Search the document to list every match here';

  @override
  String get searchMatchCase => 'Match case';

  @override
  String searchMatchCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get searchNextMatch => 'Next match';

  @override
  String searchNoMatches(String query) {
    return 'No matches for “$query”';
  }

  @override
  String searchPageHeader(int page) {
    return 'Page $page';
  }

  @override
  String get searchPreviousMatch => 'Previous match';

  @override
  String get searchRegex => 'Regular expression';

  @override
  String get searchReplace => 'Replace';

  @override
  String get searchReplaceAll => 'Replace all';

  @override
  String get searchReplaceHint => 'Replace with';

  @override
  String get searchReplaceNotTargetable =>
      'That match can’t be replaced on its own — use Replace all, or edit it with the content tool';

  @override
  String searchReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches replaced',
      one: '1 match replaced',
      zero: 'Nothing replaced',
    );
    return '$_temp0';
  }

  @override
  String get searchResultsTitle => 'Search results';

  @override
  String get searchWholeWord => 'Whole word';

  @override
  String get shellControls => 'Controls';

  @override
  String get shellDefaultAuthor => 'Default author…';

  @override
  String get shellHighlightFormFields => 'Highlight form fields';

  @override
  String get shellKeyboardShortcutsMenu => 'Keyboard shortcuts…';

  @override
  String get shellKeyboardShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shellShortcutsSearchHint => 'Search shortcuts';

  @override
  String shellShortcutsNoMatches(String query) {
    return 'No shortcuts match “$query”';
  }

  @override
  String get shellShortcutGroupSelect => 'Select';

  @override
  String get shellShortcutGroupMarkup => 'Markup';

  @override
  String get shellShortcutGroupDraw => 'Draw';

  @override
  String get shellShortcutGroupShapes => 'Shapes';

  @override
  String get shellShortcutGroupInsert => 'Insert';

  @override
  String get shellShortcutGroupMeasure => 'Measure';

  @override
  String get shellShortcutGroupEdit => 'Edit';

  @override
  String get shellNotSet => 'Not set';

  @override
  String get shellPageColor => 'Page color…';

  @override
  String get shellPageGrid => 'Page grid';

  @override
  String get shellPanelAnnotations => 'Annotations';

  @override
  String get shellPanelBookmarks => 'Bookmarks';

  @override
  String get shellPanelPages => 'Pages';

  @override
  String get shellPanelProperties => 'Properties';

  @override
  String get shellPanelSearchResults => 'Search results';

  @override
  String get shellPanels => 'Panels';

  @override
  String get shellPressAKey => 'Press a key';

  @override
  String get shellPressLetterKeyHint =>
      'Press a letter key, add Shift for a variant, or Delete to clear.';

  @override
  String get shellReflow => 'Reflow';

  @override
  String get shellReflowText => 'Reflow text';

  @override
  String get shellResetZoom => 'Reset zoom';

  @override
  String get shellSectionShell => 'Shell';

  @override
  String get shellSectionView => 'View';

  @override
  String get shellSettings => 'Settings';

  @override
  String get shellShowAnnotations => 'Show annotations';

  @override
  String get shellShowScrollbarChapters => 'Show chapters on scrollbar';

  @override
  String get shellTabHere => 'Tab here';

  @override
  String get shellUnbound => 'Unbound';

  @override
  String get shellZoom => 'Zoom';

  @override
  String sidebarByAuthor(String author) {
    return 'by $author';
  }

  @override
  String get sidebarCancelSelection => 'Cancel selection';

  @override
  String get sidebarClearSearch => 'Clear search';

  @override
  String get sidebarDeleteSelected => 'Delete selected';

  @override
  String get sidebarDeleteSignature => 'Delete signature';

  @override
  String get sidebarLockAnnotation => 'Lock';

  @override
  String get sidebarUnlockAnnotation => 'Unlock';

  @override
  String get sidebarMore => 'More';

  @override
  String get sidebarNoAnnotations => 'No annotations';

  @override
  String get sidebarNoMatchingAnnotations => 'No matching annotations';

  @override
  String sidebarPageHeader(int number) {
    return 'Page $number';
  }

  @override
  String get sidebarRemoveSignatureBody =>
      'This removes the digital signature from the document. You can undo this.';

  @override
  String sidebarRemoveSignatureBodyNamed(String name) {
    return 'This removes the digital signature by \"$name\" from the document. You can undo this.';
  }

  @override
  String get sidebarRemoveSignatureTitle => 'Remove signature?';

  @override
  String get sidebarReopen => 'Reopen';

  @override
  String get sidebarReply => 'Reply';

  @override
  String get sidebarResolve => 'Resolve';

  @override
  String get sidebarSearchHint => 'Search annotations';

  @override
  String sidebarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '$count selected',
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
  String get sidebarWriteReplyHint => 'Write a reply…';

  @override
  String get sigTitle => 'Signature';

  @override
  String get signIdCreate => 'Create';

  @override
  String get signIdEmail => 'Email (optional)';

  @override
  String get signIdName => 'Name';

  @override
  String get signIdNameHint =>
      'Your name, as it should appear on the signature';

  @override
  String get signIdNameRequired => 'Enter a name';

  @override
  String get signIdOrganization => 'Organization (optional)';

  @override
  String get signIdSelfSignedInfo =>
      'This creates a self-signed identity. Signatures will read as \"signed, validity unknown\" in Adobe Acrobat and other readers - the same as their own self-signed IDs. The green checkmark requires a paid, publicly trusted CA.';

  @override
  String get signIdTitle => 'Create signing identity';

  @override
  String get stampBox => 'Box';

  @override
  String get stampCircle => 'Circle';

  @override
  String get stampCustomCaption => 'Custom stamp';

  @override
  String get stampDateFormat => 'Date format';

  @override
  String get stampDeleteComponent => 'Delete selected component';

  @override
  String get stampDeleteStamp => 'Delete stamp';

  @override
  String get stampEditStamp => 'Edit stamp';

  @override
  String get stampExport => 'Export…';

  @override
  String get stampFieldDate => 'Date';

  @override
  String get stampFieldDateTime => 'Date & time';

  @override
  String get stampFieldTime => 'Time';

  @override
  String get stampFieldUsername => 'Username';

  @override
  String get stampFont => 'Font';

  @override
  String get stampFontBold => 'Bold';

  @override
  String get stampFontItalic => 'Italic';

  @override
  String get stampHeight => 'Height';

  @override
  String get stampImage => 'Image';

  @override
  String get stampImport => 'Import…';

  @override
  String get stampInsertField => 'Insert field';

  @override
  String get stampMoreColors => 'More colors…';

  @override
  String get stampNewStamp => 'New stamp…';

  @override
  String get stampNewStampTitle => 'New stamp';

  @override
  String get stampSavedToCollection => 'Saved to stamps';

  @override
  String get stampSelectTextToEdit => 'Select text to edit';

  @override
  String get stampSelectedText => 'Selected text';

  @override
  String get stampSignature => 'Signature';

  @override
  String get stampStamps => 'Stamps';

  @override
  String get stampText => 'Text';

  @override
  String get stampTime12Hour => '12 hr';

  @override
  String get stampTime24Hour => '24 hr';

  @override
  String get stampTimeFormat => 'Time format';

  @override
  String get stampWidth => 'Width';

  @override
  String get takeoffArea => 'Area';

  @override
  String get takeoffCount => 'Count';

  @override
  String get takeoffEmpty => 'No measurements yet.';

  @override
  String takeoffGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '$count group',
    );
    return '$_temp0';
  }

  @override
  String takeoffItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get takeoffLength => 'Length';

  @override
  String get takeoffTitle => 'Takeoff';

  @override
  String get tbAddInkAnnotation => 'Add ink annotation';

  @override
  String get tbAlign => 'Align';

  @override
  String get tbAlignBottom => 'Align bottom';

  @override
  String get tbAlignHorizontalCenters => 'Align horizontal centers';

  @override
  String get tbAlignLeft => 'Align left';

  @override
  String get tbAlignRight => 'Align right';

  @override
  String get tbAlignTop => 'Align top';

  @override
  String get tbAlignVerticalCenters => 'Align vertical centers';

  @override
  String get tbAnnotationsFlattened =>
      'Annotations and form fields flattened into the pages';

  @override
  String get tbApplyRedactionsMessage =>
      'The marked content will be permanently removed from the document. This cannot be undone.';

  @override
  String get tbApplyRedactionsTitle => 'Apply redactions?';

  @override
  String get tbApplyRedactionsTooltip => 'Apply redactions (irreversible)';

  @override
  String get tbAutosizeTextBox => 'Autosize text box (Alt+Z)';

  @override
  String get tbAutosizeTextFont => 'Fit font to text box';

  @override
  String get tbCalibrateScaleHint =>
      'Draw a line of known length to calibrate the scale.';

  @override
  String get tbCharSpacing => 'Char spacing';

  @override
  String get tbCheckBoxOption => 'Check box';

  @override
  String get tbCheckMarksOnDocument => 'Check-marks on the document';

  @override
  String get tbCropImage => 'Crop image';

  @override
  String get tbCroppingImage => 'Cropping image';

  @override
  String get tbCropApply => 'Apply crop';

  @override
  String get tbCropCancel => 'Cancel crop';

  @override
  String get tbCropReset => 'Reset crop';

  @override
  String get tbColorLabel => 'Color';

  @override
  String get tbColorProcessingTooltip =>
      'Color processing - find and replace page-content colors';

  @override
  String tbColorsReplaced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Replaced $count colors',
      one: 'Replaced 1 color',
      zero: 'No matching colors found',
    );
    return '$_temp0';
  }

  @override
  String get tbConvertToCheckBox => 'Convert to check box';

  @override
  String get tbConvertToImageButton => 'Convert to image button';

  @override
  String get tbConvertToTextField => 'Convert to text field';

  @override
  String get tbCornerRadius => 'Corner radius';

  @override
  String tbDeleteAnnotations(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count annotations',
      one: 'Delete annotation',
    );
    return '$_temp0';
  }

  @override
  String get tbDeleteElement => 'Delete element';

  @override
  String get tbDeleteField => 'Delete field';

  @override
  String get tbDiscardDrawing => 'Discard drawing';

  @override
  String get tbDistributeHorizontally => 'Distribute horizontally';

  @override
  String get tbDistributeVertically => 'Distribute vertically';

  @override
  String get tbDrawNewSignature => 'Draw a new signature…';

  @override
  String get tbEditAnnotationText => 'Edit annotation text';

  @override
  String get tbEditTextStyle => 'Edit text & style';

  @override
  String get tbElement => 'Element';

  @override
  String get tbEraserSize => 'Eraser size';

  @override
  String get tbFieldActions => 'Field actions';

  @override
  String get tbFieldName => 'Field name';

  @override
  String tbFieldNamed(String name) {
    return 'Field: $name';
  }

  @override
  String get tbFieldValue => 'Field value';

  @override
  String get tbFill => 'Fill';

  @override
  String get tbFingerDraws => 'Finger draws - tap so it scrolls instead';

  @override
  String get tbFingerScrolls => 'Finger scrolls (pen draws) - tap so it draws';

  @override
  String get tbFlattenAnnotationsTooltip =>
      'Flatten annotations and form fields into the pages';

  @override
  String get tbFlattenForm => 'Flatten form';

  @override
  String get tbFlattenFormBakeValues =>
      'Flatten form - bake values into the pages';

  @override
  String get tbFlattenLabel => 'Flatten';

  @override
  String get tbFont => 'Font';

  @override
  String get tbFontSize => 'Font size';

  @override
  String get tbFontWidth => 'Font width';

  @override
  String get tbFormFieldsFlattened => 'Form fields flattened into the pages';

  @override
  String get tbGroupDraw => 'Draw';

  @override
  String get tbGroupEdit => 'Edit';

  @override
  String get tbGroupInsert => 'Insert';

  @override
  String get tbGroupMarkup => 'Markup';

  @override
  String get tbGroupMeasure => 'Measure';

  @override
  String get tbGroupSelect => 'Select';

  @override
  String get tbGroupShapes => 'Shapes';

  @override
  String get tbImageButtonOption => 'Image button';

  @override
  String get tbLineEnd => 'Line end';

  @override
  String get tbLineSpacing => 'Line spacing';

  @override
  String get tbLineStart => 'Line start';

  @override
  String get tbLineType => 'Line type';

  @override
  String get tbManageStamps => 'Manage stamps…';

  @override
  String get tbMarkupHighlight => 'Highlight';

  @override
  String get tbMarkupHighlightTip => 'Highlight text';

  @override
  String get tbMarkupSquiggly => 'Squiggly-underline';

  @override
  String get tbMarkupSquigglyTip => 'Squiggly-underline text';

  @override
  String get tbMarkupStrikeOut => 'Strike out';

  @override
  String get tbMarkupStrikeOutTip => 'Strike out text';

  @override
  String get tbMarkupUnderline => 'Underline';

  @override
  String get tbMarkupUnderlineTip => 'Underline text';

  @override
  String get tbMoreColors => 'More colors…';

  @override
  String get tbNameArrow => 'Arrow';

  @override
  String get tbNameCallout => 'Callout';

  @override
  String get tbNameCloudPolygon => 'Cloud polygon';

  @override
  String get tbNameCount => 'Count';

  @override
  String get tbNameDigitalSignature => 'Digital signature';

  @override
  String get tbNameDraw => 'Draw';

  @override
  String get tbNameEllipse => 'Ellipse';

  @override
  String get tbNameEraser => 'Erase ink strokes';

  @override
  String get tbNameHand => 'Hand';

  @override
  String get tbNameHighlight => 'Highlight';

  @override
  String get tbNameImage => 'Image';

  @override
  String get tbNameLine => 'Line';

  @override
  String get tbNameMeasureAngle => 'Measure angle';

  @override
  String get tbNameMeasureArc => 'Measure arc length';

  @override
  String get tbNameMeasureArea => 'Measure area';

  @override
  String get tbNameMeasureDistance => 'Measure distance';

  @override
  String get tbNameMeasurePerimeter => 'Measure perimeter';

  @override
  String get tbNameMeasureSlope => 'Measure slope (rise/run)';

  @override
  String get tbNameMeasureVolume => 'Measure volume (area × depth)';

  @override
  String get tbNameNote => 'Note';

  @override
  String get tbNamePolygon => 'Polygon';

  @override
  String get tbNamePolyline => 'Polyline';

  @override
  String get tbNameRectangle => 'Rectangle';

  @override
  String get tbNameSelect => 'Select';

  @override
  String get tbNameSignature => 'Signature';

  @override
  String get tbNameStamp => 'Stamp';

  @override
  String get tbNameTextBox => 'Text box';

  @override
  String get tbNewFieldType => 'New field type - drag on a page to add one';

  @override
  String get tbNoAnnotationsToFlatten =>
      'No annotations or form fields to flatten';

  @override
  String get tbNoCustomStamps => 'No custom stamps';

  @override
  String get tbNoFormFieldsToFlatten => 'No form fields to flatten';

  @override
  String get tbNoRedactionsToApply => 'No redactions to apply';

  @override
  String get tbNoteTitle => 'Note';

  @override
  String get tbOpacity => 'Opacity';

  @override
  String get tbOutline => 'Outline';

  @override
  String get tbPatternScale => 'Pattern scale';

  @override
  String get tbPickColorFromPage => 'Pick a color from the page';

  @override
  String get tbRedactionsApplied => 'Redactions applied';

  @override
  String get tbRedoShortcut => 'Redo (⇧⌘Z)';

  @override
  String get tbReflowFailed =>
      'Couldn\'t reflow - this isn\'t a single-column paragraph this tool can re-wrap. Try Replace text instead.';

  @override
  String get tbReflowParagraph => 'Reflow paragraph';

  @override
  String get tbRenameField => 'Rename field';

  @override
  String get tbRenameFieldEllipsis => 'Rename field…';

  @override
  String get tbReplaceImage => 'Replace image';

  @override
  String get tbReplaceImageFailed => 'Couldn\'t replace image';

  @override
  String get tbReplaceText => 'Replace text';

  @override
  String get tbSaveImage => 'Save image';

  @override
  String get tbSaveShortcut => 'Save… (⌘S / Ctrl+S)';

  @override
  String get tbScale => 'Scale';

  @override
  String get tbSelectTextForMarkup => 'Choose a markup, then select text';

  @override
  String tbSelectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: 'Selection',
    );
    return '$_temp0';
  }

  @override
  String get tbSetEllipsis => 'Set…';

  @override
  String get tbStamp => 'Stamp';

  @override
  String get tbStampText => 'Stamp text';

  @override
  String get tbStrokeOpacityFont => 'Stroke, opacity, font';

  @override
  String get tbStrokeWidthLabel => 'Stroke width';

  @override
  String tbStrokeWidthPreset(String width) {
    return 'Stroke $width';
  }

  @override
  String get tbStyle => 'Style';

  @override
  String get tbTakeoffTotals => 'Takeoff totals';

  @override
  String get tbTextBorder => 'Text border';

  @override
  String get tbTextColour => 'Text colour';

  @override
  String get tbTextFieldOption => 'Text field';

  @override
  String get tbTextFill => 'Text fill';

  @override
  String get tbTextStyleEllipsis => 'Text style…';

  @override
  String get tbTextTitle => 'Text';

  @override
  String get tbTipCallout =>
      'Callout - drag from the point to where the box goes';

  @override
  String get tbTipContent => 'Edit page content';

  @override
  String get tbTipCount => 'Count - tap to drop check-marks and tally them';

  @override
  String get tbTipDigitalSignature =>
      'Digital signature - drag a box to place and sign';

  @override
  String get tbTipForm =>
      'Form fields - tap to select, double-tap to fill, drag to add';

  @override
  String get tbTipHighlightDraw => 'Highlight - draw freehand';

  @override
  String get tbTipImage => 'Image - tap to place, or drag out a box';

  @override
  String get tbTipMeasureAngle => 'Measure angle - click three points';

  @override
  String get tbTipMeasureArc => 'Measure arc length - click three points';

  @override
  String get tbTipRedact => 'Redact - drag a region, then apply';

  @override
  String get tbTipSignature => 'Signature - tap a page to place it';

  @override
  String get tbTipSnapshot =>
      'Snapshot - drag a region to capture it (paste back as vector)';

  @override
  String get tbToolContent => 'Content';

  @override
  String get tbToolForm => 'Form';

  @override
  String get tbToolRedact => 'Redact';

  @override
  String get tbToolSnapshot => 'Snapshot';

  @override
  String get tbTools => 'Tools';

  @override
  String get tbTotals => 'Totals';

  @override
  String get tbTypeTextEachTime => 'Type text each time';

  @override
  String get tbUnderline => 'Underline';

  @override
  String get tbUndoShortcut => 'Undo (⌘Z)';

  @override
  String get textStyleFont => 'Font';

  @override
  String get textStyleFontSize => 'Font size';

  @override
  String get textStyleKeep => 'keep';

  @override
  String get textStyleStyle => 'Style';

  @override
  String get textStyleText => 'Text';

  @override
  String get textStyleTextFill => 'Text fill';

  @override
  String get textStyleTitle => 'Edit text & style';

  @override
  String get thumbAddPage => 'Add page';

  @override
  String get thumbClearSelection => 'Clear selection';

  @override
  String thumbCopyPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copy $count pages',
      one: 'Copy page',
    );
    return '$_temp0';
  }

  @override
  String get thumbCopySelectedPages => 'Copy selected pages';

  @override
  String thumbCutPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cut $count pages',
      one: 'Cut page',
    );
    return '$_temp0';
  }

  @override
  String get thumbCutSelectedPages => 'Cut selected pages';

  @override
  String thumbDeletePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count pages',
      one: 'Delete page',
    );
    return '$_temp0';
  }

  @override
  String get thumbDeleteSelectedPages => 'Delete selected pages';

  @override
  String thumbDuplicatePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplicate $count pages',
      one: 'Duplicate page',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportPagesEllipsis => 'Export pages…';

  @override
  String thumbExportPagesMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Export $count pages…',
      one: 'Export page…',
    );
    return '$_temp0';
  }

  @override
  String get thumbExportSelectedPages => 'Export selected pages';

  @override
  String get thumbInsertBlankAfter => 'Insert blank page after';

  @override
  String get thumbInsertBlankBefore => 'Insert blank page before';

  @override
  String get thumbInsertFileFailed => 'Couldn\'t insert that file.';

  @override
  String get thumbInsertPdf => 'Insert PDF…';

  @override
  String get thumbPageActions => 'Page actions';

  @override
  String thumbPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get thumbPages => 'Pages';

  @override
  String thumbPastePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Paste $count pages',
      one: 'Paste page',
    );
    return '$_temp0';
  }

  @override
  String get thumbRotate180 => 'Rotate 180°';

  @override
  String get thumbRotateLeft => 'Rotate left';

  @override
  String get thumbRotatePageRight => 'Rotate page right';

  @override
  String get thumbRotateRight => 'Rotate right';

  @override
  String get thumbRotateSelectedLeft => 'Rotate selected pages left';

  @override
  String get thumbRotateSelectedRight => 'Rotate selected pages right';

  @override
  String thumbSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '$count selected',
    );
    return '$_temp0';
  }

  @override
  String get undo => 'Undo';

  @override
  String get viewerEditFontUnsafe =>
      'This PDF font or encoding cannot be edited safely.';

  @override
  String get viewerEditNeedsSinglePage =>
      'Editing requires a selection on one page.';

  @override
  String get viewerEditNotEditableRun =>
      'This selection is not one editable page-content text run.';

  @override
  String get viewerEditStyleUnchangeable =>
      'This PDF font can be re-typed, but its style cannot be changed.';

  @override
  String get viewerEditTextStyle => 'Edit text & style';

  @override
  String get viewerMarkup => 'Markup';

  @override
  String get viewerMarkupHighlight => 'Highlight';

  @override
  String get viewerMarkupSquiggly => 'Squiggly';

  @override
  String get viewerMarkupStrikeOut => 'Strike out';

  @override
  String get viewerMarkupUnderline => 'Underline';

  @override
  String get viewerSelectAll => 'Select all';
}
