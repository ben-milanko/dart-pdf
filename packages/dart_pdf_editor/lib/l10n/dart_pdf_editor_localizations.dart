import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'dart_pdf_editor_localizations_ar.dart';
import 'dart_pdf_editor_localizations_de.dart';
import 'dart_pdf_editor_localizations_en.dart';
import 'dart_pdf_editor_localizations_es.dart';
import 'dart_pdf_editor_localizations_fr.dart';
import 'dart_pdf_editor_localizations_hi.dart';
import 'dart_pdf_editor_localizations_id.dart';
import 'dart_pdf_editor_localizations_it.dart';
import 'dart_pdf_editor_localizations_ja.dart';
import 'dart_pdf_editor_localizations_ko.dart';
import 'dart_pdf_editor_localizations_nl.dart';
import 'dart_pdf_editor_localizations_pl.dart';
import 'dart_pdf_editor_localizations_pt.dart';
import 'dart_pdf_editor_localizations_ru.dart';
import 'dart_pdf_editor_localizations_th.dart';
import 'dart_pdf_editor_localizations_tr.dart';
import 'dart_pdf_editor_localizations_uk.dart';
import 'dart_pdf_editor_localizations_vi.dart';
import 'dart_pdf_editor_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of DartPdfEditorLocalizations
/// returned by `DartPdfEditorLocalizations.of(context)`.
///
/// Applications need to include `DartPdfEditorLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/dart_pdf_editor_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: DartPdfEditorLocalizations.localizationsDelegates,
///   supportedLocales: DartPdfEditorLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the DartPdfEditorLocalizations.supportedLocales
/// property.
abstract class DartPdfEditorLocalizations {
  DartPdfEditorLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static DartPdfEditorLocalizations? of(BuildContext context) {
    return Localizations.of<DartPdfEditorLocalizations>(
        context, DartPdfEditorLocalizations);
  }

  static const LocalizationsDelegate<DartPdfEditorLocalizations> delegate =
      _DartPdfEditorLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
  ];

  /// Generic button that adds a new item.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Annotation type name: a caret marking an insertion point.
  ///
  /// In en, this message translates to:
  /// **'Caret'**
  String get annotCaret;

  /// Annotation type name: a circle/ellipse shape.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get annotCircle;

  /// Annotation type name: an embedded file attachment.
  ///
  /// In en, this message translates to:
  /// **'File attachment'**
  String get annotFileAttachment;

  /// Annotation type name: a free-text box drawn on the page.
  ///
  /// In en, this message translates to:
  /// **'Text box'**
  String get annotFreeText;

  /// Annotation type name: a text highlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get annotHighlight;

  /// Annotation type name: a freehand ink drawing.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get annotInk;

  /// Annotation type name: a straight line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get annotLine;

  /// Annotation type name: a hyperlink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get annotLink;

  /// Annotation type name: a closed polygon shape.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get annotPolygon;

  /// Annotation type name: an open multi-segment line.
  ///
  /// In en, this message translates to:
  /// **'Polyline'**
  String get annotPolyline;

  /// Annotation type name: a redaction region.
  ///
  /// In en, this message translates to:
  /// **'Redaction'**
  String get annotRedact;

  /// Annotation type name: a rectangle/square shape.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get annotSquare;

  /// Annotation type name: a squiggly (wavy) underline.
  ///
  /// In en, this message translates to:
  /// **'Squiggly'**
  String get annotSquiggly;

  /// Annotation type name: a rubber stamp.
  ///
  /// In en, this message translates to:
  /// **'Stamp'**
  String get annotStamp;

  /// Annotation type name: a strike-through over text.
  ///
  /// In en, this message translates to:
  /// **'Strike-out'**
  String get annotStrikeOut;

  /// Annotation type name: a sticky note / text comment.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get annotText;

  /// Annotation type name: a text underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get annotUnderline;

  /// Annotation type name: an interactive form field widget.
  ///
  /// In en, this message translates to:
  /// **'Form field'**
  String get annotWidget;

  /// Generic button that applies pending changes.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// Tooltip/label/dialog title for adding a new bookmark.
  ///
  /// In en, this message translates to:
  /// **'Add bookmark'**
  String get bookmarkAdd;

  /// Tooltip to add a nested child bookmark under this one.
  ///
  /// In en, this message translates to:
  /// **'Add child bookmark'**
  String get bookmarkAddChild;

  /// Tooltip to collapse an expanded bookmark's children.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get bookmarkCollapse;

  /// Tooltip to delete this bookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete bookmark'**
  String get bookmarkDelete;

  /// Tooltip/dialog title for editing an existing bookmark.
  ///
  /// In en, this message translates to:
  /// **'Edit bookmark'**
  String get bookmarkEdit;

  /// Empty-state text when the document has no bookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks'**
  String get bookmarkEmpty;

  /// Tooltip to expand a bookmark's children.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get bookmarkExpand;

  /// Checkbox label controlling whether the bookmark shows its children expanded by default.
  ///
  /// In en, this message translates to:
  /// **'Expanded by default'**
  String get bookmarkExpandedByDefault;

  /// Subtitle for a bookmark that has no page destination.
  ///
  /// In en, this message translates to:
  /// **'No destination'**
  String get bookmarkNoDestination;

  /// Field label for the bookmark's destination page number in the add/edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get bookmarkPageFieldLabel;

  /// A bookmark's destination page label (and default title for a new bookmark), 1-based.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String bookmarkPageLabel(int number);

  /// Helper text under the page field showing the valid page range (1 to the page count).
  ///
  /// In en, this message translates to:
  /// **'1-{count}'**
  String bookmarkPageRangeHint(int count);

  /// Header title of the bookmarks/outline panel.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarkTitle;

  /// Field label for the bookmark's title in the add/edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get bookmarkTitleLabel;

  /// Placeholder title for a bookmark with an empty title.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get bookmarkUntitled;

  /// Button that dismisses a dialog without applying.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic button that clears the current value or selection.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Generic button/tooltip that closes a panel or dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Progress message shown while the color-processing changes are being written to the document.
  ///
  /// In en, this message translates to:
  /// **'Applying color changes…'**
  String get colorApplyingChanges;

  /// Tooltip on the button that switches the color picker's value-entry format (hex/RGB/HSL/CMYK).
  ///
  /// In en, this message translates to:
  /// **'Color format'**
  String get colorColorFormat;

  /// Title of the standalone color picker dialog.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get colorColorTitle;

  /// Summary shown when more than one document color is selected as the find target.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} color selected} other{{count} colors selected}}'**
  String colorColorsSelected(int count);

  /// Section header above the grid of colors detected in the document's page content.
  ///
  /// In en, this message translates to:
  /// **'Document colors'**
  String get colorDocumentColors;

  /// Checkbox to include fill (non-stroke) colors when processing document colors.
  ///
  /// In en, this message translates to:
  /// **'Fill colors'**
  String get colorFillColors;

  /// Label for the color-to-find swatch row in the color-processing dialog.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get colorFind;

  /// Section header for the grid of colors already used in the open document.
  ///
  /// In en, this message translates to:
  /// **'In document'**
  String get colorInDocument;

  /// Placeholder shown in the document-colors grid before any colors have been found.
  ///
  /// In en, this message translates to:
  /// **'No colors found yet'**
  String get colorNoColorsFound;

  /// Message shown when scanning the pages found no page-content colors to process.
  ///
  /// In en, this message translates to:
  /// **'No page-content colors found'**
  String get colorNoPageContentColors;

  /// Section header for the fixed palette of quick-pick color swatches.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get colorPalette;

  /// Tooltip on the eyedropper button that opens the color picker for a color row.
  ///
  /// In en, this message translates to:
  /// **'Pick color'**
  String get colorPickColor;

  /// Title of the document color-processing (find/replace colors) dialog.
  ///
  /// In en, this message translates to:
  /// **'Color processing'**
  String get colorProcessingTitle;

  /// Section header for the grid of recently used color swatches.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get colorRecent;

  /// Label for the replacement-color swatch row in the color-processing dialog.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get colorReplace;

  /// Checkbox to replace the matched color with transparency instead of another color.
  ///
  /// In en, this message translates to:
  /// **'Replace with transparent'**
  String get colorReplaceWithTransparent;

  /// Indeterminate progress label shown while the document colors are being scanned.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get colorScanning;

  /// Progress label shown while scanning document colors; progress of total pages scanned.
  ///
  /// In en, this message translates to:
  /// **'Scanning {progress} / {total}'**
  String colorScanningProgress(int progress, int total);

  /// Radio option to apply color processing only to the currently selected pages; count is the number of selected pages.
  ///
  /// In en, this message translates to:
  /// **'Selected pages ({count})'**
  String colorSelectedPages(int count);

  /// Checkbox to include stroke (outline) colors when processing document colors.
  ///
  /// In en, this message translates to:
  /// **'Stroke colors'**
  String get colorStrokeColors;

  /// Label for the color-match tolerance slider in the color-processing dialog.
  ///
  /// In en, this message translates to:
  /// **'Tolerance'**
  String get colorTolerance;

  /// Value text shown in a color row when the replacement is transparency rather than a color.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get colorTransparent;

  /// Radio option to apply color processing to every page in the document.
  ///
  /// In en, this message translates to:
  /// **'Whole document'**
  String get colorWholeDocument;

  /// Label over the pane showing the revised document in the comparison view.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get compareAfter;

  /// Label over the pane showing the original document in the comparison view.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get compareBefore;

  /// Header above the diff navigator list showing how many changes were found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String compareChangeCount(int count);

  /// Comparison toolbar counter showing the current change position out of the total.
  ///
  /// In en, this message translates to:
  /// **'{current} / {count, plural, =1{1 change} other{{count} changes}}'**
  String compareChangePosition(int current, int count);

  /// Placeholder label for a change entry whose text is empty in the diff navigator.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get compareEmptyLabel;

  /// Tooltip on the button that steps to the next change in the comparison view.
  ///
  /// In en, this message translates to:
  /// **'Next change'**
  String get compareNextChange;

  /// Shown in the comparison toolbar when the two documents have no differences.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get compareNoChanges;

  /// Placeholder shown in the diff navigator panel when the documents are identical.
  ///
  /// In en, this message translates to:
  /// **'No differences between the two documents'**
  String get compareNoDifferences;

  /// Segmented button label for the overlay comparison mode.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get compareOverlay;

  /// Page group header in the diff navigator list (1-based page number).
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String comparePageHeader(int page);

  /// Tooltip on the button that steps to the previous change in the comparison view.
  ///
  /// In en, this message translates to:
  /// **'Previous change'**
  String get comparePreviousChange;

  /// Segmented button label for the side-by-side comparison mode.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get compareSideBySide;

  /// Generic button/menu label to copy the current item.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Generic button/menu label to cut the current item.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// Generic button/menu label to delete the current item.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic button that finishes the current interaction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Generic button/menu label to edit the current item.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Dialog title for the prompt that sets the default annotation author name.
  ///
  /// In en, this message translates to:
  /// **'Author name'**
  String get editorViewAuthorNameTitle;

  /// Border line style: an alternating dash-dot line.
  ///
  /// In en, this message translates to:
  /// **'Dash-dot'**
  String get lineStyleDashDot;

  /// Border line style: a dashed line.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get lineStyleDashed;

  /// Border line style: a dotted line.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get lineStyleDotted;

  /// Border line style: an unbroken solid line.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get lineStyleSolid;

  /// Button that switches from typing a scale to calibrating by drawing a reference segment.
  ///
  /// In en, this message translates to:
  /// **'Calibrate'**
  String get measCalibrate;

  /// Title of the dialog asking how long a just-drawn reference segment is in the real world.
  ///
  /// In en, this message translates to:
  /// **'Calibrate scale'**
  String get measCalibrateScale;

  /// Inline label preceding the volume depth input field.
  ///
  /// In en, this message translates to:
  /// **'Depth: '**
  String get measDepthLabel;

  /// Measurement kind: an angle measurement.
  ///
  /// In en, this message translates to:
  /// **'Angle'**
  String get measKindAngle;

  /// Measurement kind: an arc-length measurement.
  ///
  /// In en, this message translates to:
  /// **'Arc'**
  String get measKindArc;

  /// Measurement kind: an area measurement.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get measKindArea;

  /// Measurement kind: a running count of tally marks.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get measKindCount;

  /// Measurement kind: a distance/length measurement.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get measKindLength;

  /// Measurement kind: an area with cut-outs subtracted.
  ///
  /// In en, this message translates to:
  /// **'Net area'**
  String get measKindNetArea;

  /// Measurement kind: the perimeter of a shape.
  ///
  /// In en, this message translates to:
  /// **'Perimeter'**
  String get measKindPerimeter;

  /// Measurement kind: a slope (rise over run).
  ///
  /// In en, this message translates to:
  /// **'Slope'**
  String get measKindSlope;

  /// Measurement kind: a volume (area times depth).
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get measKindVolume;

  /// Prompt above the length input in the calibration dialog, asking what real-world length the drawn line represents.
  ///
  /// In en, this message translates to:
  /// **'The line you drew represents:'**
  String get measLineRepresents;

  /// Confirm button that applies the entered volume depth to complete the measurement.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get measMeasure;

  /// Title of the dialog that sets the drawing measurement scale.
  ///
  /// In en, this message translates to:
  /// **'Set measurement scale'**
  String get measSetScale;

  /// Confirm button that applies the entered or calibrated measurement scale.
  ///
  /// In en, this message translates to:
  /// **'Set scale'**
  String get measSetScaleButton;

  /// Title of the dialog asking for the extrusion depth of a volume measurement.
  ///
  /// In en, this message translates to:
  /// **'Volume depth'**
  String get measVolumeDepth;

  /// Annotation context-menu item that adds a vertex to a polyline or polygon at the click point.
  ///
  /// In en, this message translates to:
  /// **'Add node'**
  String get menuAddNode;

  /// Title of the page-range dialog when applying the selected annotation(s) to multiple pages.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Apply annotation to pages} other{Apply annotations to pages}}'**
  String menuApplyAnnotationsToPagesTitle(int count);

  /// Annotation context-menu item that copies the selected annotation(s) to a range of pages.
  ///
  /// In en, this message translates to:
  /// **'Apply to pages…'**
  String get menuApplyToPages;

  /// Annotation context-menu item that raises the selected annotation to the top of the z-order.
  ///
  /// In en, this message translates to:
  /// **'Bring to front'**
  String get menuBringToFront;

  /// Form-field context-menu item that checks an unchecked check box.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get menuCheck;

  /// Form-field context-menu item that opens a list of options for a combo box or list box.
  ///
  /// In en, this message translates to:
  /// **'Choose value…'**
  String get menuChooseValue;

  /// Form-field context-menu item that unchecks a checked check box.
  ///
  /// In en, this message translates to:
  /// **'Clear check'**
  String get menuClearCheck;

  /// Form-field context-menu item that converts the field to a check box.
  ///
  /// In en, this message translates to:
  /// **'Convert to check box'**
  String get menuConvertToCheckBox;

  /// Form-field context-menu item that converts the field to an image push button.
  ///
  /// In en, this message translates to:
  /// **'Convert to image button'**
  String get menuConvertToImageButton;

  /// Form-field context-menu item that converts the field to a text field.
  ///
  /// In en, this message translates to:
  /// **'Convert to text field'**
  String get menuConvertToTextField;

  /// Form-field context-menu item that deletes the field.
  ///
  /// In en, this message translates to:
  /// **'Delete field'**
  String get menuDeleteField;

  /// Form-field context-menu item that edits the value of a text field.
  ///
  /// In en, this message translates to:
  /// **'Edit value…'**
  String get menuEditValue;

  /// Title of the prompt asking for a form field's new name when renaming.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get menuFieldName;

  /// Title of the prompt asking for a form text field's value.
  ///
  /// In en, this message translates to:
  /// **'Field value'**
  String get menuFieldValue;

  /// Form-field context-menu item that flattens all form fields into page content.
  ///
  /// In en, this message translates to:
  /// **'Flatten form'**
  String get menuFlattenForm;

  /// Annotation context-menu item that opens a color picker to recolour a pasted vector snapshot.
  ///
  /// In en, this message translates to:
  /// **'Recolour…'**
  String get menuRecolour;

  /// Annotation context-menu item that removes the nearest vertex of a polyline or polygon.
  ///
  /// In en, this message translates to:
  /// **'Remove node'**
  String get menuRemoveNode;

  /// Annotation context-menu item that captures the selected annotation's appearance as the default for new annotations of the same kind.
  ///
  /// In en, this message translates to:
  /// **'Set as default style'**
  String get menuSetAsDefaultStyle;

  /// Form-field context-menu item that renames the field.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get menuRename;

  /// Form-field context-menu item that selects the clicked option of a radio button group.
  ///
  /// In en, this message translates to:
  /// **'Select option'**
  String get menuSelectOption;

  /// Annotation context-menu item that lowers the selected annotation to the bottom of the z-order.
  ///
  /// In en, this message translates to:
  /// **'Send to back'**
  String get menuSendToBack;

  /// Form-field context-menu item that sets the image of a push-button field.
  ///
  /// In en, this message translates to:
  /// **'Set image…'**
  String get menuSetImage;

  /// Form-field context-menu item that opens the text style popup for a text field.
  ///
  /// In en, this message translates to:
  /// **'Text style…'**
  String get menuTextStyle;

  /// Label for the absence of a selection or value.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// Button that confirms a dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Tooltip on the inline text-style chip button that opens the text color picker.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get overlayColor;

  /// Tooltip on the selection chip button that opens the inline text editor for the selected annotation.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get overlayEditText;

  /// Tooltip on the inline text-style chip button that opens the font menu.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get overlayFont;

  /// Tooltip on the inline text-style chip button that increases the text size.
  ///
  /// In en, this message translates to:
  /// **'Larger'**
  String get overlayLarger;

  /// Tooltip on the selection chip button that opens the annotation's overflow menu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get overlayMore;

  /// Title of the prompt asking for the body text of a sticky note annotation.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get overlayNote;

  /// Tooltip on the inline text-style chip button that decreases the text size.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get overlaySmaller;

  /// Title of the prompt asking for the caption of a text stamp being placed on a page.
  ///
  /// In en, this message translates to:
  /// **'Stamp text'**
  String get overlayStampText;

  /// Tooltip on the inline text-style chip button that toggles underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get overlayUnderline;

  /// Validation error in the page range dialog when a field is outside the valid page range.
  ///
  /// In en, this message translates to:
  /// **'Enter pages between 1 and {count}.'**
  String pageRangeErrorBounds(int count);

  /// Validation error in the page range dialog when the end page precedes the start page.
  ///
  /// In en, this message translates to:
  /// **'The last page must not be before the first.'**
  String get pageRangeErrorOrder;

  /// Label for the start-page field in the page range dialog.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get pageRangeFrom;

  /// Shows the total number of pages in the document, above the page range fields.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String pageRangePageCount(int count);

  /// Label for the end-page field in the page range dialog.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get pageRangeTo;

  /// Tooltip on a docked sidebar panel's grab handle that redocks the panel by dragging.
  ///
  /// In en, this message translates to:
  /// **'Drag to move panel'**
  String get panelDragToMovePanel;

  /// Generic button/menu label to paste from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Row label for the text alignment toggles.
  ///
  /// In en, this message translates to:
  /// **'Align'**
  String get propAlign;

  /// Tooltip on the center-align toggle button.
  ///
  /// In en, this message translates to:
  /// **'Align center'**
  String get propAlignCenter;

  /// Tooltip on the left-align toggle button.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get propAlignLeft;

  /// Tooltip on the right-align toggle button.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get propAlignRight;

  /// Title summarizing how many annotations are selected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} annotation} other{{count} annotations}}'**
  String propAnnotationCount(int count);

  /// Label for the editable author of an annotation.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get propAuthor;

  /// Toggle label for a form text field's auto-size option.
  ///
  /// In en, this message translates to:
  /// **'Auto-size'**
  String get propAutoSize;

  /// Tooltip on the bold toggle button.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get propBold;

  /// Single-letter label on the bold toggle button.
  ///
  /// In en, this message translates to:
  /// **'B'**
  String get propBoldLetter;

  /// Subtitle for a font bundled with the editor package.
  ///
  /// In en, this message translates to:
  /// **'Bundled font'**
  String get propBundledFont;

  /// Type name shown for a callout annotation.
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get propCallout;

  /// Slider label for a free-text box's character spacing.
  ///
  /// In en, this message translates to:
  /// **'Char spacing'**
  String get propCharSpacing;

  /// Row label for an annotation's or form field's color swatch.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get propColor;

  /// Row label for the form text field's colour swatch (British spelling as shown in the form style popup).
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get propColour;

  /// Label for the editable contents/text of an annotation.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get propContents;

  /// Subtitle explaining that edits in a multi-selection affect every compatible annotation.
  ///
  /// In en, this message translates to:
  /// **'Edits apply to all compatible annotations'**
  String get propEditsApplyToAll;

  /// Label for the editable name of a selected form field.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get propFieldName;

  /// Form field type: a checkbox.
  ///
  /// In en, this message translates to:
  /// **'Check box'**
  String get propFieldTypeCheckBox;

  /// Form field type: a combo box (editable dropdown).
  ///
  /// In en, this message translates to:
  /// **'Combo box'**
  String get propFieldTypeComboBox;

  /// Form field type: a push button that displays an image.
  ///
  /// In en, this message translates to:
  /// **'Image button'**
  String get propFieldTypeImageButton;

  /// Form field type: a scrollable list box.
  ///
  /// In en, this message translates to:
  /// **'List box'**
  String get propFieldTypeListBox;

  /// Form field type: a group of radio buttons.
  ///
  /// In en, this message translates to:
  /// **'Radio group'**
  String get propFieldTypeRadioGroup;

  /// Form field type: a digital signature field.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get propFieldTypeSignature;

  /// Form field type: a text-input field.
  ///
  /// In en, this message translates to:
  /// **'Text field'**
  String get propFieldTypeText;

  /// Tooltip on the form field-type menu, showing the current type.
  ///
  /// In en, this message translates to:
  /// **'Field type: {type}'**
  String propFieldTypeTooltip(String type);

  /// Form field type shown when the field's type is not recognized.
  ///
  /// In en, this message translates to:
  /// **'Unknown field'**
  String get propFieldTypeUnknown;

  /// Row label for an annotation's fill-color swatch.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get propFill;

  /// Row label for the font-family selector, and the title of the font picker dialog.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get propFont;

  /// Warning tooltip on a document font that is subset and cannot type all characters.
  ///
  /// In en, this message translates to:
  /// **'This font is subset - only the characters already used in the document can be typed.'**
  String get propFontSubsetTooltip;

  /// Slider label for a free-text box's horizontal font-width scale.
  ///
  /// In en, this message translates to:
  /// **'Font width'**
  String get propFontWidth;

  /// Short label for the height field of an annotation's bounds.
  ///
  /// In en, this message translates to:
  /// **'H'**
  String get propGeometryHeight;

  /// Short label for the width field of an annotation's bounds.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get propGeometryWidth;

  /// Label for the X (horizontal position) field of an annotation's bounds.
  ///
  /// In en, this message translates to:
  /// **'X'**
  String get propGeometryX;

  /// Label for the Y (vertical position) field of an annotation's bounds.
  ///
  /// In en, this message translates to:
  /// **'Y'**
  String get propGeometryY;

  /// Tooltip on the italic toggle button.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get propItalic;

  /// Single-letter label on the italic toggle button.
  ///
  /// In en, this message translates to:
  /// **'I'**
  String get propItalicLetter;

  /// Subtitle flagging a subset document font that supports only a limited character set.
  ///
  /// In en, this message translates to:
  /// **'Limited characters'**
  String get propLimitedCharacters;

  /// Row label for the end line-ending dropdown of a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Line end'**
  String get propLineEnd;

  /// Name of the butt (flat cap) line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Butt'**
  String get propLineEndingButt;

  /// Name of the circle line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get propLineEndingCircle;

  /// Name of the closed-arrow line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Closed arrow'**
  String get propLineEndingClosedArrow;

  /// Name of the reversed closed-arrow line-ending style; 'rev.' abbreviates 'reversed'.
  ///
  /// In en, this message translates to:
  /// **'Closed arrow (rev.)'**
  String get propLineEndingClosedArrowRev;

  /// Name of the diamond line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Diamond'**
  String get propLineEndingDiamond;

  /// Name of the open-arrow line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Open arrow'**
  String get propLineEndingOpenArrow;

  /// Name of the reversed open-arrow line-ending style; 'rev.' abbreviates 'reversed'.
  ///
  /// In en, this message translates to:
  /// **'Open arrow (rev.)'**
  String get propLineEndingOpenArrowRev;

  /// Name of the slash line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Slash'**
  String get propLineEndingSlash;

  /// Name of the square line-ending style for a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get propLineEndingSquare;

  /// Slider label for a free-text box's line spacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get propLineSpacing;

  /// Row label for the start line-ending dropdown of a line/arrow annotation.
  ///
  /// In en, this message translates to:
  /// **'Line start'**
  String get propLineStart;

  /// Row label for the line-style (solid/dashed) dropdown.
  ///
  /// In en, this message translates to:
  /// **'Line type'**
  String get propLineType;

  /// Font picker entry that opens a file picker to load a custom font.
  ///
  /// In en, this message translates to:
  /// **'Load font…'**
  String get propLoadFont;

  /// Subtitle for the load-custom-font entry, naming the accepted file formats.
  ///
  /// In en, this message translates to:
  /// **'TTF or OTF file'**
  String get propLoadFontSubtitle;

  /// Tooltip on the button that opens the full color picker.
  ///
  /// In en, this message translates to:
  /// **'More colors…'**
  String get propMoreColors;

  /// Toggle label for a form text field's multiline option.
  ///
  /// In en, this message translates to:
  /// **'Multiline'**
  String get propMultiline;

  /// Tooltip on the button that clears an annotation's fill color.
  ///
  /// In en, this message translates to:
  /// **'No fill'**
  String get propNoFill;

  /// Empty-state message when a font search matches nothing.
  ///
  /// In en, this message translates to:
  /// **'No fonts found'**
  String get propNoFontsFound;

  /// Tooltip on the button that clears a free-text box's outline color.
  ///
  /// In en, this message translates to:
  /// **'No outline'**
  String get propNoOutline;

  /// Slider label for an annotation's opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get propOpacity;

  /// Row label for a free-text box's outline-color swatch.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get propOutline;

  /// Row label for the page number in a multi-annotation selection summary.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get propPageLabel;

  /// Subtitle showing which page a selected annotation is on.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String propPageNumber(int number);

  /// Header title of the annotation properties panel.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get propPropertiesTitle;

  /// Section header for the recently used fonts group in the font picker.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get propRecentlyUsed;

  /// Slider label for a line/arrow's scale multiplier.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get propScale;

  /// Hint text in the font picker's search field.
  ///
  /// In en, this message translates to:
  /// **'Search fonts'**
  String get propSearchFonts;

  /// Font picker section header grouping all available fonts.
  ///
  /// In en, this message translates to:
  /// **'All fonts'**
  String get propSectionAllFonts;

  /// Section header for the appearance (color/stroke/opacity) controls in the annotation properties panel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get propSectionAppearance;

  /// Section header for the contents/author controls in the annotation properties panel.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get propSectionContent;

  /// Section header for the form-field controls in the annotation properties panel.
  ///
  /// In en, this message translates to:
  /// **'Form field'**
  String get propSectionFormField;

  /// Font picker section header grouping fonts already embedded in the open document.
  ///
  /// In en, this message translates to:
  /// **'In this document'**
  String get propSectionInThisDocument;

  /// Section header for the position and size fields; 'pt' means PDF points (the unit).
  ///
  /// In en, this message translates to:
  /// **'Position & size (pt)'**
  String get propSectionPositionSize;

  /// Section header for the summary of a multi-annotation selection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get propSectionSelection;

  /// Section header for the text-styling controls in the annotation properties panel.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get propSectionText;

  /// Empty-state message shown when no annotation is selected in the properties panel.
  ///
  /// In en, this message translates to:
  /// **'Select an annotation to see its properties'**
  String get propSelectAnnotationPrompt;

  /// Slider label for the font size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get propSize;

  /// Subtitle for one of the standard base-14 PDF font families in the font picker.
  ///
  /// In en, this message translates to:
  /// **'Standard PDF font'**
  String get propStandardPdfFont;

  /// Slider label for an annotation's stroke width.
  ///
  /// In en, this message translates to:
  /// **'Stroke'**
  String get propStroke;

  /// Row label for the bold/italic style toggles.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get propStyle;

  /// Subtitle for a font installed on the host platform.
  ///
  /// In en, this message translates to:
  /// **'System font'**
  String get propSystemFont;

  /// Row label for a form field's or selection's type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get propType;

  /// Row label and tooltip for the free-text underline toggle.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get propUnderline;

  /// Placeholder shown when a property has mixed values across a multi-selection.
  ///
  /// In en, this message translates to:
  /// **'Varies'**
  String get propVaries;

  /// Generic button/tooltip to redo the last undone change.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// Message shown in the reflow reading view when the document has no extractable text or images.
  ///
  /// In en, this message translates to:
  /// **'No extractable content'**
  String get reflowNoContent;

  /// Heading above each page's content in the reflow reading view.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String reflowPageLabel(int number);

  /// Tooltip for the save/share action in the fullscreen figure viewer of the reflow view.
  ///
  /// In en, this message translates to:
  /// **'Save or share'**
  String get reflowSaveOrShare;

  /// Accessibility label for a tappable figure in the reflow view that opens it fullscreen.
  ///
  /// In en, this message translates to:
  /// **'View figure'**
  String get reflowViewFigure;

  /// Generic button that removes the current item.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Generic button/menu label to rename the current item.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Generic button that resets a value to its default.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Generic button that saves the document or changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Link target subtitle: runs a JavaScript action.
  ///
  /// In en, this message translates to:
  /// **'JavaScript'**
  String get sbarActionJavaScript;

  /// Link target subtitle: jumps to the given 1-based page number.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String sbarActionPage(int page);

  /// Annotation title for a callout (a text box with a leader line).
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get sbarCallout;

  /// Form-field type shown as an annotation title: a button (push/check/radio).
  ///
  /// In en, this message translates to:
  /// **'Button field'**
  String get sbarFieldButton;

  /// Form-field type shown as an annotation title: a list/combo choice field.
  ///
  /// In en, this message translates to:
  /// **'Choice field'**
  String get sbarFieldChoice;

  /// Fallback form-field type shown as an annotation title.
  ///
  /// In en, this message translates to:
  /// **'Form field'**
  String get sbarFieldGeneric;

  /// Form-field type shown as an annotation title: a digital-signature field.
  ///
  /// In en, this message translates to:
  /// **'Signature field'**
  String get sbarFieldSignature;

  /// Form-field type shown as an annotation title: a text input field.
  ///
  /// In en, this message translates to:
  /// **'Text field'**
  String get sbarFieldText;

  /// Review-state chip: the markup was accepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get sbarStateAccepted;

  /// Review-state chip: the markup was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get sbarStateCancelled;

  /// Review-state chip: the markup is flagged/marked.
  ///
  /// In en, this message translates to:
  /// **'Marked'**
  String get sbarStateMarked;

  /// Review-state chip: the markup was rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get sbarStateRejected;

  /// Review-state chip: the comment thread is resolved/completed.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get sbarStateResolved;

  /// Review-state chip: the markup's mark was cleared.
  ///
  /// In en, this message translates to:
  /// **'Unmarked'**
  String get sbarStateUnmarked;

  /// Tooltip on the search option toggle that also searches annotation contents (notes, comments, free text).
  ///
  /// In en, this message translates to:
  /// **'Search annotations'**
  String get searchAnnotations;

  /// Tooltip on the button that clears the document search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get searchClearSearch;

  /// Placeholder shown in the search results panel before any query is entered.
  ///
  /// In en, this message translates to:
  /// **'Search the document to list every match here'**
  String get searchEmptyHint;

  /// Tooltip on the search option toggle that makes the query case-sensitive.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get searchMatchCase;

  /// Header above the search results list showing how many matches were found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 match} other{{count} matches}}'**
  String searchMatchCount(int count);

  /// Tooltip on the button that steps to the next search match.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get searchNextMatch;

  /// Shown in the search results panel when the query found no matches.
  ///
  /// In en, this message translates to:
  /// **'No matches for “{query}”'**
  String searchNoMatches(String query);

  /// Page group header in the search results list (1-based page number).
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String searchPageHeader(int page);

  /// Tooltip on the button that steps to the previous search match.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get searchPreviousMatch;

  /// Tooltip on the search option toggle that treats the query as a regular expression.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get searchRegex;

  /// Title of the docked search results panel.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResultsTitle;

  /// Tooltip on the search option toggle that matches whole words only.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get searchWholeWord;

  /// Title and tooltip for the compact-layout Controls bottom sheet that holds the shell's toggles.
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get shellControls;

  /// Menu item that opens a prompt to set the default annotation author name.
  ///
  /// In en, this message translates to:
  /// **'Default author…'**
  String get shellDefaultAuthor;

  /// Toggle label controlling whether form fields are highlighted.
  ///
  /// In en, this message translates to:
  /// **'Highlight form fields'**
  String get shellHighlightFormFields;

  /// Menu item that opens the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts…'**
  String get shellKeyboardShortcutsMenu;

  /// Header of the keyboard shortcuts editor bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get shellKeyboardShortcutsTitle;

  /// Placeholder text in the search field of the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Search shortcuts'**
  String get shellShortcutsSearchHint;

  /// Message shown when a keyboard-shortcuts search matches no tools.
  ///
  /// In en, this message translates to:
  /// **'No shortcuts match “{query}”'**
  String shellShortcutsNoMatches(String query);

  /// Section header for the Select tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get shellShortcutGroupSelect;

  /// Section header for the Markup tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Markup'**
  String get shellShortcutGroupMarkup;

  /// Section header for the Draw tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get shellShortcutGroupDraw;

  /// Section header for the Shapes tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get shellShortcutGroupShapes;

  /// Section header for the Insert tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get shellShortcutGroupInsert;

  /// Section header for the Measure tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get shellShortcutGroupMeasure;

  /// Section header for the Edit tool group in the keyboard shortcuts editor.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get shellShortcutGroupEdit;

  /// Subtitle shown for the default author when no author name is configured.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get shellNotSet;

  /// Menu item that opens a color picker to change the page (paper) color.
  ///
  /// In en, this message translates to:
  /// **'Page color…'**
  String get shellPageColor;

  /// Toggle label for the full-area page thumbnail grid view.
  ///
  /// In en, this message translates to:
  /// **'Page grid'**
  String get shellPageGrid;

  /// Name of the annotations list panel (toggle tooltip and sheet title).
  ///
  /// In en, this message translates to:
  /// **'Annotations'**
  String get shellPanelAnnotations;

  /// Name of the bookmarks/outline panel (toggle tooltip, control label, and sheet title).
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get shellPanelBookmarks;

  /// Name of the page thumbnails panel (toggle tooltip, control label, and sheet title).
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get shellPanelPages;

  /// Name of the annotation properties panel (toggle tooltip and sheet title).
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get shellPanelProperties;

  /// Name of the search results panel (toggle tooltip and sheet title).
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get shellPanelSearchResults;

  /// Label preceding the grouped panel-toggle switch in the shell header.
  ///
  /// In en, this message translates to:
  /// **'Panels'**
  String get shellPanels;

  /// Dialog title shown while capturing a keyboard shortcut for an editing tool.
  ///
  /// In en, this message translates to:
  /// **'Press a key'**
  String get shellPressAKey;

  /// Instructional text in the keyboard-shortcut capture dialog.
  ///
  /// In en, this message translates to:
  /// **'Press a letter key, or Delete to clear.'**
  String get shellPressLetterKeyHint;

  /// Compact control label that toggles the reflow (text reading) view.
  ///
  /// In en, this message translates to:
  /// **'Reflow'**
  String get shellReflow;

  /// Toggle label for the reflow (text reading) view in the settings menu.
  ///
  /// In en, this message translates to:
  /// **'Reflow text'**
  String get shellReflowText;

  /// Tooltip for the button that resets the zoom level to 100%.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get shellResetZoom;

  /// Section header in the compact Controls sheet grouping shell panel toggles.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get shellSectionShell;

  /// Section header in the compact Controls sheet grouping display/view options.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get shellSectionView;

  /// Label and tooltip for the view options (display settings) button and control.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get shellSettings;

  /// Toggle label controlling whether annotations are shown.
  ///
  /// In en, this message translates to:
  /// **'Show annotations'**
  String get shellShowAnnotations;

  /// Drop hint shown when dragging a docked panel over another panel to combine them into a tabbed group.
  ///
  /// In en, this message translates to:
  /// **'Tab here'**
  String get shellTabHere;

  /// Trailing label for a tool that has no keyboard shortcut assigned.
  ///
  /// In en, this message translates to:
  /// **'Unbound'**
  String get shellUnbound;

  /// Tooltip for the zoom-level selector in the shell header.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get shellZoom;

  /// Attribution shown beside a review-state chip, naming the author who set the state.
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String sidebarByAuthor(String author);

  /// Tooltip that exits the annotation multi-select mode.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get sidebarCancelSelection;

  /// Tooltip for the button that clears the annotation search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get sidebarClearSearch;

  /// Tooltip that deletes all checked annotations as one undo step.
  ///
  /// In en, this message translates to:
  /// **'Delete selected'**
  String get sidebarDeleteSelected;

  /// Tooltip for the button that removes a digital signature from a signature-field row.
  ///
  /// In en, this message translates to:
  /// **'Delete signature'**
  String get sidebarDeleteSignature;

  /// Tooltip for a row's overflow (three-dot) menu holding thread actions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get sidebarMore;

  /// Empty-state shown when the document has no annotations.
  ///
  /// In en, this message translates to:
  /// **'No annotations'**
  String get sidebarNoAnnotations;

  /// Empty-state shown when a search filter matches no annotations.
  ///
  /// In en, this message translates to:
  /// **'No matching annotations'**
  String get sidebarNoMatchingAnnotations;

  /// Section header grouping a page's annotations in the sidebar, 1-based.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String sidebarPageHeader(int number);

  /// Body of the remove-signature confirm dialog when the signer name is unknown.
  ///
  /// In en, this message translates to:
  /// **'This removes the digital signature from the document. You can undo this.'**
  String get sidebarRemoveSignatureBody;

  /// Body of the remove-signature confirm dialog naming the signer.
  ///
  /// In en, this message translates to:
  /// **'This removes the digital signature by \"{name}\" from the document. You can undo this.'**
  String sidebarRemoveSignatureBodyNamed(String name);

  /// Title of the confirm dialog for removing a digital signature.
  ///
  /// In en, this message translates to:
  /// **'Remove signature?'**
  String get sidebarRemoveSignatureTitle;

  /// Menu entry that reopens a resolved comment thread.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get sidebarReopen;

  /// Menu entry and send button that adds a reply to a comment thread.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get sidebarReply;

  /// Menu entry that resolves an open comment thread.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get sidebarResolve;

  /// Placeholder text in the annotation sidebar's filter field.
  ///
  /// In en, this message translates to:
  /// **'Search annotations'**
  String get sidebarSearchHint;

  /// Count of annotations checked in the sidebar's multi-select header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} selected} other{{count} selected}}'**
  String sidebarSelectedCount(int count);

  /// Placeholder text in the inline reply text field.
  ///
  /// In en, this message translates to:
  /// **'Write a reply…'**
  String get sidebarWriteReplyHint;

  /// Title of the hand-drawn signature pad dialog.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get sigTitle;

  /// Confirm button label in the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get signIdCreate;

  /// Label for the optional email field in the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get signIdEmail;

  /// Label for the name field in the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get signIdName;

  /// Hint text for the name field in the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Your name, as it should appear on the signature'**
  String get signIdNameHint;

  /// Validation error when the name field in the create-signing-identity dialog is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get signIdNameRequired;

  /// Label for the optional organization field in the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Organization (optional)'**
  String get signIdOrganization;

  /// Informational note in the create-signing-identity dialog explaining self-signed identity trust behavior.
  ///
  /// In en, this message translates to:
  /// **'This creates a self-signed identity. Signatures will read as \"signed, validity unknown\" in Adobe Acrobat and other readers - the same as their own self-signed IDs. The green checkmark requires a paid, publicly trusted CA.'**
  String get signIdSelfSignedInfo;

  /// Title of the create-signing-identity dialog.
  ///
  /// In en, this message translates to:
  /// **'Create signing identity'**
  String get signIdTitle;

  /// Label of the button that adds a rectangle component to the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Box'**
  String get stampBox;

  /// Label of the button that adds an ellipse component to the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get stampCircle;

  /// Default display name for a custom stamp that has no text component.
  ///
  /// In en, this message translates to:
  /// **'Custom stamp'**
  String get stampCustomCaption;

  /// Label for the dropdown selecting the date format used by stamp {{date}} fields.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get stampDateFormat;

  /// Tooltip on the button that deletes the selected component of the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Delete selected component'**
  String get stampDeleteComponent;

  /// Tooltip on the delete-stamp button in the stamp picker.
  ///
  /// In en, this message translates to:
  /// **'Delete stamp'**
  String get stampDeleteStamp;

  /// Tooltip on the edit-stamp button in the stamp picker, and title of the stamp editor dialog when editing an existing stamp.
  ///
  /// In en, this message translates to:
  /// **'Edit stamp'**
  String get stampEditStamp;

  /// Label of the button that exports saved custom stamps out of the app.
  ///
  /// In en, this message translates to:
  /// **'Export…'**
  String get stampExport;

  /// Insertable stamp template field: the current date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get stampFieldDate;

  /// Insertable stamp template field: the current date and time.
  ///
  /// In en, this message translates to:
  /// **'Date & time'**
  String get stampFieldDateTime;

  /// Insertable stamp template field: the current time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get stampFieldTime;

  /// Insertable stamp template field: the current user's name.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get stampFieldUsername;

  /// Tooltip on the button that chooses the font of the selected stamp text component.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get stampFont;

  /// Font-style modifier shown after a font family name in the stamp font menu.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get stampFontBold;

  /// Font-style modifier shown after a font family name in the stamp font menu.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get stampFontItalic;

  /// Label for the stamp template height input field.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get stampHeight;

  /// Label of the button that adds an image component to the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get stampImage;

  /// Label of the button that imports saved custom stamps from outside the app.
  ///
  /// In en, this message translates to:
  /// **'Import…'**
  String get stampImport;

  /// Tooltip on the button that inserts a template field (date, time, username) into stamp text.
  ///
  /// In en, this message translates to:
  /// **'Insert field'**
  String get stampInsertField;

  /// Tooltip on the button that opens a full color picker for the stamp color.
  ///
  /// In en, this message translates to:
  /// **'More colors…'**
  String get stampMoreColors;

  /// Label of the stamp picker button that opens the stamp editor to create a new stamp.
  ///
  /// In en, this message translates to:
  /// **'New stamp…'**
  String get stampNewStamp;

  /// Title of the stamp editor dialog when creating a new stamp.
  ///
  /// In en, this message translates to:
  /// **'New stamp'**
  String get stampNewStampTitle;

  /// Placeholder label shown on the stamp text input when no text component is selected.
  ///
  /// In en, this message translates to:
  /// **'Select text to edit'**
  String get stampSelectTextToEdit;

  /// Label for the text input editing the currently selected text component of a stamp.
  ///
  /// In en, this message translates to:
  /// **'Selected text'**
  String get stampSelectedText;

  /// Label of the button that adds a drawn-signature component to the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get stampSignature;

  /// Title of the stamp picker dialog.
  ///
  /// In en, this message translates to:
  /// **'Stamps'**
  String get stampStamps;

  /// Label of the button that adds a text component to the stamp template.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get stampText;

  /// Suffix in the stamp time-format preview marking a 12-hour (AM/PM) clock format.
  ///
  /// In en, this message translates to:
  /// **'12 hr'**
  String get stampTime12Hour;

  /// Suffix in the stamp time-format preview marking a 24-hour clock format.
  ///
  /// In en, this message translates to:
  /// **'24 hr'**
  String get stampTime24Hour;

  /// Label for the dropdown selecting the time format used by stamp {{time}} fields.
  ///
  /// In en, this message translates to:
  /// **'Time format'**
  String get stampTimeFormat;

  /// Label for the stamp template width input field.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get stampWidth;

  /// Summary chip label for the total measured area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get takeoffArea;

  /// Summary chip label for the total count of count-type measurements.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get takeoffCount;

  /// Empty-state text when the document has no measurements.
  ///
  /// In en, this message translates to:
  /// **'No measurements yet.'**
  String get takeoffEmpty;

  /// Count of measurement groups shown in the takeoff panel header.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} group} other{{count} groups}}'**
  String takeoffGroupCount(int count);

  /// Count of measurement items in a takeoff group row.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String takeoffItemCount(int count);

  /// Summary chip label for the total measured length.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get takeoffLength;

  /// Default header title of the measurement takeoff panel.
  ///
  /// In en, this message translates to:
  /// **'Takeoff'**
  String get takeoffTitle;

  /// Tooltip for committing the pending freehand ink drawing as an annotation.
  ///
  /// In en, this message translates to:
  /// **'Add ink annotation'**
  String get tbAddInkAnnotation;

  /// Label for the text-alignment toggles row.
  ///
  /// In en, this message translates to:
  /// **'Align'**
  String get tbAlign;

  /// Tooltip: align selected annotations to their bottom edges.
  ///
  /// In en, this message translates to:
  /// **'Align bottom'**
  String get tbAlignBottom;

  /// Tooltip: align selected annotations on their horizontal centers.
  ///
  /// In en, this message translates to:
  /// **'Align horizontal centers'**
  String get tbAlignHorizontalCenters;

  /// Tooltip: align selected annotations to their left edges.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get tbAlignLeft;

  /// Tooltip: align selected annotations to their right edges.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get tbAlignRight;

  /// Tooltip: align selected annotations to their top edges.
  ///
  /// In en, this message translates to:
  /// **'Align top'**
  String get tbAlignTop;

  /// Tooltip: align selected annotations on their vertical centers.
  ///
  /// In en, this message translates to:
  /// **'Align vertical centers'**
  String get tbAlignVerticalCenters;

  /// Snackbar confirming annotations were baked into the page content.
  ///
  /// In en, this message translates to:
  /// **'Annotations flattened into the pages'**
  String get tbAnnotationsFlattened;

  /// Warning body in the redaction confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'The marked content will be permanently removed from the document. This cannot be undone.'**
  String get tbApplyRedactionsMessage;

  /// Title of the confirmation dialog before applying redactions.
  ///
  /// In en, this message translates to:
  /// **'Apply redactions?'**
  String get tbApplyRedactionsTitle;

  /// Tooltip for the button that permanently applies marked redactions.
  ///
  /// In en, this message translates to:
  /// **'Apply redactions (irreversible)'**
  String get tbApplyRedactionsTooltip;

  /// Tooltip for auto-sizing a free-text box to its content, with keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Autosize text box (Alt+Z)'**
  String get tbAutosizeTextBox;

  /// Snackbar guiding the user to draw a reference line when calibrating a measurement scale.
  ///
  /// In en, this message translates to:
  /// **'Draw a line of known length to calibrate the scale.'**
  String get tbCalibrateScaleHint;

  /// Slider label for text character spacing.
  ///
  /// In en, this message translates to:
  /// **'Char spacing'**
  String get tbCharSpacing;

  /// Menu option: create a check box form field.
  ///
  /// In en, this message translates to:
  /// **'Check box'**
  String get tbCheckBoxOption;

  /// Tooltip on the tally chip counting check-marks placed by the Count tool.
  ///
  /// In en, this message translates to:
  /// **'Check-marks on the document'**
  String get tbCheckMarksOnDocument;

  /// Short button label for the color-processing action.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get tbColorLabel;

  /// Tooltip for the color-processing action that finds and replaces colors in page content.
  ///
  /// In en, this message translates to:
  /// **'Color processing - find and replace page-content colors'**
  String get tbColorProcessingTooltip;

  /// Snackbar reporting how many page-content colors were replaced by the color-processing tool.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No matching colors found} =1{Replaced 1 color} other{Replaced {count} colors}}'**
  String tbColorsReplaced(int count);

  /// Menu item converting the selected form field into a check box.
  ///
  /// In en, this message translates to:
  /// **'Convert to check box'**
  String get tbConvertToCheckBox;

  /// Menu item converting the selected form field into an image push-button.
  ///
  /// In en, this message translates to:
  /// **'Convert to image button'**
  String get tbConvertToImageButton;

  /// Menu item converting the selected form field into a text field.
  ///
  /// In en, this message translates to:
  /// **'Convert to text field'**
  String get tbConvertToTextField;

  /// Slider label for a rectangle's corner radius.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get tbCornerRadius;

  /// Tooltip for deleting one or more selected annotations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete annotation} other{Delete {count} annotations}}'**
  String tbDeleteAnnotations(int count);

  /// Tooltip for deleting the selected page-content element.
  ///
  /// In en, this message translates to:
  /// **'Delete element'**
  String get tbDeleteElement;

  /// Tooltip/menu label for deleting the selected form field.
  ///
  /// In en, this message translates to:
  /// **'Delete field'**
  String get tbDeleteField;

  /// Tooltip for discarding the pending freehand ink drawing.
  ///
  /// In en, this message translates to:
  /// **'Discard drawing'**
  String get tbDiscardDrawing;

  /// Tooltip: evenly space selected annotations horizontally.
  ///
  /// In en, this message translates to:
  /// **'Distribute horizontally'**
  String get tbDistributeHorizontally;

  /// Tooltip: evenly space selected annotations vertically.
  ///
  /// In en, this message translates to:
  /// **'Distribute vertically'**
  String get tbDistributeVertically;

  /// Tooltip for redrawing the signature used by the signature tool.
  ///
  /// In en, this message translates to:
  /// **'Draw a new signature…'**
  String get tbDrawNewSignature;

  /// Tooltip for editing the text of the selected annotation.
  ///
  /// In en, this message translates to:
  /// **'Edit annotation text'**
  String get tbEditAnnotationText;

  /// Tooltip for editing a page-content element's text and its style.
  ///
  /// In en, this message translates to:
  /// **'Edit text & style'**
  String get tbEditTextStyle;

  /// Strip label shown while a page-content element is selected.
  ///
  /// In en, this message translates to:
  /// **'Element'**
  String get tbElement;

  /// Slider label / tooltip for the ink eraser radius.
  ///
  /// In en, this message translates to:
  /// **'Eraser size'**
  String get tbEraserSize;

  /// Tooltip for the overflow menu holding actions for the selected form field.
  ///
  /// In en, this message translates to:
  /// **'Field actions'**
  String get tbFieldActions;

  /// Dialog title for renaming a form field.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get tbFieldName;

  /// Strip label showing the name of the selected form field.
  ///
  /// In en, this message translates to:
  /// **'Field: {name}'**
  String tbFieldNamed(String name);

  /// Dialog title for editing a form field's value.
  ///
  /// In en, this message translates to:
  /// **'Field value'**
  String get tbFieldValue;

  /// Color-row label for a shape's interior fill color.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get tbFill;

  /// Tooltip when finger drawing is on; tapping switches finger to scrolling.
  ///
  /// In en, this message translates to:
  /// **'Finger draws - tap so it scrolls instead'**
  String get tbFingerDraws;

  /// Tooltip when finger scrolls and only the pen draws; tapping switches finger to drawing.
  ///
  /// In en, this message translates to:
  /// **'Finger scrolls (pen draws) - tap so it draws'**
  String get tbFingerScrolls;

  /// Tooltip for the button that bakes annotations into page content.
  ///
  /// In en, this message translates to:
  /// **'Flatten annotations into the pages'**
  String get tbFlattenAnnotationsTooltip;

  /// Menu item that flattens the form fields into the pages.
  ///
  /// In en, this message translates to:
  /// **'Flatten form'**
  String get tbFlattenForm;

  /// Tooltip for flattening form fields so their values become permanent page content.
  ///
  /// In en, this message translates to:
  /// **'Flatten form - bake values into the pages'**
  String get tbFlattenFormBakeValues;

  /// Short button label for flattening annotations into the pages.
  ///
  /// In en, this message translates to:
  /// **'Flatten'**
  String get tbFlattenLabel;

  /// Label for the font-family picker row.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get tbFont;

  /// Slider label for the font size setting.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get tbFontSize;

  /// Slider label for horizontal font scaling (glyph width).
  ///
  /// In en, this message translates to:
  /// **'Font width'**
  String get tbFontWidth;

  /// Snackbar confirming form fields were baked into the page content.
  ///
  /// In en, this message translates to:
  /// **'Form fields flattened into the pages'**
  String get tbFormFieldsFlattened;

  /// Toolbar dock group label: freehand drawing tools.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get tbGroupDraw;

  /// Toolbar dock group label: document-editing tools (content/form/redact/…).
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get tbGroupEdit;

  /// Toolbar dock group label: insert tools (text box/note/stamp/…).
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get tbGroupInsert;

  /// Toolbar dock group label: text-markup tools (highlight/underline/…).
  ///
  /// In en, this message translates to:
  /// **'Markup'**
  String get tbGroupMarkup;

  /// Toolbar dock group label: measurement tools.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get tbGroupMeasure;

  /// Toolbar dock group label: the selection tools.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get tbGroupSelect;

  /// Toolbar dock group label: shape tools (rectangle/line/…).
  ///
  /// In en, this message translates to:
  /// **'Shapes'**
  String get tbGroupShapes;

  /// Menu option: create an image push-button form field.
  ///
  /// In en, this message translates to:
  /// **'Image button'**
  String get tbImageButtonOption;

  /// Label for the dropdown selecting the end line-ending shape.
  ///
  /// In en, this message translates to:
  /// **'Line end'**
  String get tbLineEnd;

  /// Slider label for text line spacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get tbLineSpacing;

  /// Label for the dropdown selecting the start line-ending shape.
  ///
  /// In en, this message translates to:
  /// **'Line start'**
  String get tbLineStart;

  /// Label for the dropdown selecting a line's dash style.
  ///
  /// In en, this message translates to:
  /// **'Line type'**
  String get tbLineType;

  /// Stamp menu item that opens the manage-stamps dialog.
  ///
  /// In en, this message translates to:
  /// **'Manage stamps…'**
  String get tbManageStamps;

  /// Text-markup action name: highlight the text selection.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get tbMarkupHighlight;

  /// Tooltip: highlight the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Highlight selection'**
  String get tbMarkupHighlightTip;

  /// Text-markup action name: squiggly-underline the text selection.
  ///
  /// In en, this message translates to:
  /// **'Squiggly-underline'**
  String get tbMarkupSquiggly;

  /// Tooltip: squiggly-underline the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Squiggly-underline selection'**
  String get tbMarkupSquigglyTip;

  /// Text-markup action name: strike out the text selection.
  ///
  /// In en, this message translates to:
  /// **'Strike out'**
  String get tbMarkupStrikeOut;

  /// Tooltip: strike out the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Strike out selection'**
  String get tbMarkupStrikeOutTip;

  /// Text-markup action name: underline the text selection.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get tbMarkupUnderline;

  /// Tooltip: underline the current text selection.
  ///
  /// In en, this message translates to:
  /// **'Underline selection'**
  String get tbMarkupUnderlineTip;

  /// Tooltip for the button opening the full color picker.
  ///
  /// In en, this message translates to:
  /// **'More colors…'**
  String get tbMoreColors;

  /// Tool name: draw an arrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get tbNameArrow;

  /// Tool name: insert a callout (text box with a leader line).
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get tbNameCallout;

  /// Tool name: draw a cloud-outline polygon.
  ///
  /// In en, this message translates to:
  /// **'Cloud polygon'**
  String get tbNameCloudPolygon;

  /// Tool name: drop tally check-marks.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get tbNameCount;

  /// Tool name: place and cryptographically sign a signature box.
  ///
  /// In en, this message translates to:
  /// **'Digital signature'**
  String get tbNameDigitalSignature;

  /// Tool name: freehand ink drawing.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get tbNameDraw;

  /// Tool name: draw an ellipse shape.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get tbNameEllipse;

  /// Tool name: erases ink strokes.
  ///
  /// In en, this message translates to:
  /// **'Erase ink strokes'**
  String get tbNameEraser;

  /// Tool name: freehand highlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get tbNameHighlight;

  /// Tool name: insert a raster image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get tbNameImage;

  /// Tool name: draw a straight line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get tbNameLine;

  /// Tool name: measure an interior angle.
  ///
  /// In en, this message translates to:
  /// **'Measure angle'**
  String get tbNameMeasureAngle;

  /// Tool name: measure an arc length.
  ///
  /// In en, this message translates to:
  /// **'Measure arc length'**
  String get tbNameMeasureArc;

  /// Tool name: measure an area.
  ///
  /// In en, this message translates to:
  /// **'Measure area'**
  String get tbNameMeasureArea;

  /// Tool name: measure a straight-line distance.
  ///
  /// In en, this message translates to:
  /// **'Measure distance'**
  String get tbNameMeasureDistance;

  /// Tool name: measure a perimeter.
  ///
  /// In en, this message translates to:
  /// **'Measure perimeter'**
  String get tbNameMeasurePerimeter;

  /// Tool name: measure a slope as rise over run.
  ///
  /// In en, this message translates to:
  /// **'Measure slope (rise/run)'**
  String get tbNameMeasureSlope;

  /// Tool name: measure a volume as area times depth.
  ///
  /// In en, this message translates to:
  /// **'Measure volume (area × depth)'**
  String get tbNameMeasureVolume;

  /// Tool name: insert a sticky note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get tbNameNote;

  /// Tool name: draw a closed polygon.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get tbNamePolygon;

  /// Tool name: draw an open multi-segment line.
  ///
  /// In en, this message translates to:
  /// **'Polyline'**
  String get tbNamePolyline;

  /// Tool name: draw a rectangle shape.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get tbNameRectangle;

  /// Tool name: the select/move tool.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get tbNameSelect;

  /// Tool name: place a saved handwritten signature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get tbNameSignature;

  /// Tool name: insert a rubber stamp.
  ///
  /// In en, this message translates to:
  /// **'Stamp'**
  String get tbNameStamp;

  /// Tool name: insert a free-text box.
  ///
  /// In en, this message translates to:
  /// **'Text box'**
  String get tbNameTextBox;

  /// Tooltip for the menu selecting which type of form field a drag will create.
  ///
  /// In en, this message translates to:
  /// **'New field type - drag on a page to add one'**
  String get tbNewFieldType;

  /// Snackbar shown when the flatten action runs but there are no annotations.
  ///
  /// In en, this message translates to:
  /// **'No annotations to flatten'**
  String get tbNoAnnotationsToFlatten;

  /// Placeholder shown in the stamp menu when no custom stamps are saved.
  ///
  /// In en, this message translates to:
  /// **'No custom stamps'**
  String get tbNoCustomStamps;

  /// Snackbar shown when the flatten-form action runs but there are no form fields.
  ///
  /// In en, this message translates to:
  /// **'No form fields to flatten'**
  String get tbNoFormFieldsToFlatten;

  /// Snackbar shown when applying redactions but none are marked.
  ///
  /// In en, this message translates to:
  /// **'No redactions to apply'**
  String get tbNoRedactionsToApply;

  /// Dialog title for editing a sticky-note annotation's text.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get tbNoteTitle;

  /// Slider label for the opacity setting.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get tbOpacity;

  /// Color-row label for a shape's outline (stroke) color.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get tbOutline;

  /// Slider label for the dash-pattern scale of a line.
  ///
  /// In en, this message translates to:
  /// **'Pattern scale'**
  String get tbPatternScale;

  /// Tooltip for the eyedropper that samples a color from the page.
  ///
  /// In en, this message translates to:
  /// **'Pick a color from the page'**
  String get tbPickColorFromPage;

  /// Snackbar confirming redactions were applied.
  ///
  /// In en, this message translates to:
  /// **'Redactions applied'**
  String get tbRedactionsApplied;

  /// Tooltip for the Redo button, including its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Redo (⇧⌘Z)'**
  String get tbRedoShortcut;

  /// Snackbar shown when a paragraph cannot be reflowed because it is not a simple single-column paragraph.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reflow - this isn\'t a single-column paragraph this tool can re-wrap. Try Replace text instead.'**
  String get tbReflowFailed;

  /// Title/tooltip for re-wrapping a whole paragraph of page content after an edit.
  ///
  /// In en, this message translates to:
  /// **'Reflow paragraph'**
  String get tbReflowParagraph;

  /// Tooltip for the button that renames the selected form field.
  ///
  /// In en, this message translates to:
  /// **'Rename field'**
  String get tbRenameField;

  /// Menu item that opens a dialog to rename a form field.
  ///
  /// In en, this message translates to:
  /// **'Rename field…'**
  String get tbRenameFieldEllipsis;

  /// Tooltip for replacing the selected page-content image.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get tbReplaceImage;

  /// Snackbar shown when replacing a selected page-content image fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t replace image'**
  String get tbReplaceImageFailed;

  /// Title/tooltip for replacing the text of a selected page-content element.
  ///
  /// In en, this message translates to:
  /// **'Replace text'**
  String get tbReplaceText;

  /// Tooltip for exporting the selected page-content image.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get tbSaveImage;

  /// Tooltip for the Save button, including its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Save… (⌘S / Ctrl+S)'**
  String get tbSaveShortcut;

  /// Leading label of the measurement-scale chip.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get tbScale;

  /// Hint shown when the markup tools are open but no text is selected.
  ///
  /// In en, this message translates to:
  /// **'Select text to use markup'**
  String get tbSelectTextForMarkup;

  /// Strip label for one or more selected annotations.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Selection} other{{count} selected}}'**
  String tbSelectionCount(int count);

  /// Value shown on the measurement-scale chip when no scale is set yet.
  ///
  /// In en, this message translates to:
  /// **'Set…'**
  String get tbSetEllipsis;

  /// Label/header for the Stamp tool and its menu.
  ///
  /// In en, this message translates to:
  /// **'Stamp'**
  String get tbStamp;

  /// Dialog title for editing a stamp annotation's text.
  ///
  /// In en, this message translates to:
  /// **'Stamp text'**
  String get tbStampText;

  /// Tooltip for the tune button opening stroke, opacity and font controls.
  ///
  /// In en, this message translates to:
  /// **'Stroke, opacity, font'**
  String get tbStrokeOpacityFont;

  /// Slider label for the stroke width setting.
  ///
  /// In en, this message translates to:
  /// **'Stroke width'**
  String get tbStrokeWidthLabel;

  /// Tooltip on a quick stroke-width preset swatch, showing the numeric width.
  ///
  /// In en, this message translates to:
  /// **'Stroke {width}'**
  String tbStrokeWidthPreset(String width);

  /// Label for the bold/italic font-style toggles row.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get tbStyle;

  /// Tooltip for the button opening the measurement takeoff totals panel.
  ///
  /// In en, this message translates to:
  /// **'Takeoff totals'**
  String get tbTakeoffTotals;

  /// Color-row label for a text box's border color.
  ///
  /// In en, this message translates to:
  /// **'Text border'**
  String get tbTextBorder;

  /// Color-row label for the text foreground color.
  ///
  /// In en, this message translates to:
  /// **'Text colour'**
  String get tbTextColour;

  /// Menu option: create a text form field.
  ///
  /// In en, this message translates to:
  /// **'Text field'**
  String get tbTextFieldOption;

  /// Color-row label for a text box's fill (background) color.
  ///
  /// In en, this message translates to:
  /// **'Text fill'**
  String get tbTextFill;

  /// Menu item that opens the text-style controls for a form field.
  ///
  /// In en, this message translates to:
  /// **'Text style…'**
  String get tbTextStyleEllipsis;

  /// Dialog title for editing a free-text annotation's text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get tbTextTitle;

  /// Tooltip for the callout tool, explaining the drag gesture.
  ///
  /// In en, this message translates to:
  /// **'Callout - drag from the point to where the box goes'**
  String get tbTipCallout;

  /// Tooltip for the page-content editing tool.
  ///
  /// In en, this message translates to:
  /// **'Edit page content'**
  String get tbTipContent;

  /// Tooltip for the count tool.
  ///
  /// In en, this message translates to:
  /// **'Count - tap to drop check-marks and tally them'**
  String get tbTipCount;

  /// Tooltip for the digital-signature box tool.
  ///
  /// In en, this message translates to:
  /// **'Digital signature - drag a box to place and sign'**
  String get tbTipDigitalSignature;

  /// Tooltip for the form-fields tool.
  ///
  /// In en, this message translates to:
  /// **'Form fields - tap to select, double-tap to fill, drag to add'**
  String get tbTipForm;

  /// Tooltip for the freehand highlighter tool.
  ///
  /// In en, this message translates to:
  /// **'Highlight - draw freehand'**
  String get tbTipHighlightDraw;

  /// Tooltip for the insert-image tool.
  ///
  /// In en, this message translates to:
  /// **'Image - tap to place, or drag out a box'**
  String get tbTipImage;

  /// Tooltip for the angle-measurement tool.
  ///
  /// In en, this message translates to:
  /// **'Measure angle - click three points'**
  String get tbTipMeasureAngle;

  /// Tooltip for the arc-length-measurement tool.
  ///
  /// In en, this message translates to:
  /// **'Measure arc length - click three points'**
  String get tbTipMeasureArc;

  /// Tooltip for the redaction tool.
  ///
  /// In en, this message translates to:
  /// **'Redact - drag a region, then apply'**
  String get tbTipRedact;

  /// Tooltip for placing a saved handwritten signature.
  ///
  /// In en, this message translates to:
  /// **'Signature - tap a page to place it'**
  String get tbTipSignature;

  /// Tooltip for the snapshot capture tool.
  ///
  /// In en, this message translates to:
  /// **'Snapshot - drag a region to capture it (paste back as vector)'**
  String get tbTipSnapshot;

  /// Label for the page-content editing tool.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get tbToolContent;

  /// Label for the form-fields editing tool.
  ///
  /// In en, this message translates to:
  /// **'Form'**
  String get tbToolForm;

  /// Label for the redaction tool.
  ///
  /// In en, this message translates to:
  /// **'Redact'**
  String get tbToolRedact;

  /// Label for the snapshot (region capture) tool.
  ///
  /// In en, this message translates to:
  /// **'Snapshot'**
  String get tbToolSnapshot;

  /// Label on the mobile handle that opens the tools bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tbTools;

  /// Label for the button opening the measurement takeoff totals panel.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get tbTotals;

  /// Stamp menu option: prompt for stamp text on each placement instead of a saved stamp.
  ///
  /// In en, this message translates to:
  /// **'Type text each time'**
  String get tbTypeTextEachTime;

  /// Tooltip for the whole-box underline toggle.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get tbUnderline;

  /// Tooltip for the Undo button, including its keyboard shortcut.
  ///
  /// In en, this message translates to:
  /// **'Undo (⌘Z)'**
  String get tbUndoShortcut;

  /// Label for the font row in the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get textStyleFont;

  /// Label for the font-size slider in the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get textStyleFontSize;

  /// Shown in place of a font-size value when the size override is left untouched (keeps the run's existing size).
  ///
  /// In en, this message translates to:
  /// **'keep'**
  String get textStyleKeep;

  /// Label for the bold/italic style row in the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get textStyleStyle;

  /// Label for the text field in the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textStyleText;

  /// Label for the text-fill colour row in the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Text fill'**
  String get textStyleTextFill;

  /// Title of the styled-text editor dialog.
  ///
  /// In en, this message translates to:
  /// **'Edit text & style'**
  String get textStyleTitle;

  /// Footer button that appends a blank page in the thumbnail strip/grid.
  ///
  /// In en, this message translates to:
  /// **'Add page'**
  String get thumbAddPage;

  /// Tooltip: clear the current multi-page selection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get thumbClearSelection;

  /// Page context-menu entry: copy the target page(s) to the clipboard, counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Copy page} other{Copy {count} pages}}'**
  String thumbCopyPages(int count);

  /// Tooltip: copy the selected pages to the page clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy selected pages'**
  String get thumbCopySelectedPages;

  /// Page context-menu entry: cut the target page(s) to the clipboard, counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Cut page} other{Cut {count} pages}}'**
  String thumbCutPages(int count);

  /// Tooltip: cut the selected pages to the page clipboard.
  ///
  /// In en, this message translates to:
  /// **'Cut selected pages'**
  String get thumbCutSelectedPages;

  /// Page context-menu entry (and per-tile delete accessibility label): delete the target page(s), counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete page} other{Delete {count} pages}}'**
  String thumbDeletePages(int count);

  /// Tooltip: delete the selected pages from the document.
  ///
  /// In en, this message translates to:
  /// **'Delete selected pages'**
  String get thumbDeleteSelectedPages;

  /// Page context-menu entry: duplicate the target page(s), counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Duplicate page} other{Duplicate {count} pages}}'**
  String thumbDuplicatePages(int count);

  /// Menu entry that opens the export page-range dialog.
  ///
  /// In en, this message translates to:
  /// **'Export pages…'**
  String get thumbExportPagesEllipsis;

  /// Page context-menu entry: export the target page(s) to a standalone PDF, counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Export page…} other{Export {count} pages…}}'**
  String thumbExportPagesMenu(int count);

  /// Tooltip: export the selected pages to a standalone PDF.
  ///
  /// In en, this message translates to:
  /// **'Export selected pages'**
  String get thumbExportSelectedPages;

  /// Page context-menu entry: insert a blank page after the right-clicked page.
  ///
  /// In en, this message translates to:
  /// **'Insert blank page after'**
  String get thumbInsertBlankAfter;

  /// Page context-menu entry: insert a blank page before the right-clicked page.
  ///
  /// In en, this message translates to:
  /// **'Insert blank page before'**
  String get thumbInsertBlankBefore;

  /// Snackbar shown when a picked file can't be inserted (non-PDF, corrupt, or password-protected).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t insert that file.'**
  String get thumbInsertFileFailed;

  /// Menu entry that inserts all pages of another picked PDF after the current page.
  ///
  /// In en, this message translates to:
  /// **'Insert PDF…'**
  String get thumbInsertPdf;

  /// Tooltip for the page-actions menu button (insert PDF, export pages, paste).
  ///
  /// In en, this message translates to:
  /// **'Page actions'**
  String get thumbPageActions;

  /// A single page's 1-based label, e.g. on a thumbnail tile footer or drag feedback.
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String thumbPageNumber(int number);

  /// Header label above the page thumbnail strip/grid.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get thumbPages;

  /// Menu label to paste the page clipboard's pages, counted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Paste page} other{Paste {count} pages}}'**
  String thumbPastePages(int count);

  /// Page context-menu entry: rotate the page 180 degrees.
  ///
  /// In en, this message translates to:
  /// **'Rotate 180°'**
  String get thumbRotate180;

  /// Page context-menu entry: rotate the page 90 degrees counter-clockwise.
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get thumbRotateLeft;

  /// Accessibility label for the per-tile rotate-right button.
  ///
  /// In en, this message translates to:
  /// **'Rotate page right'**
  String get thumbRotatePageRight;

  /// Page context-menu entry: rotate the page 90 degrees clockwise.
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get thumbRotateRight;

  /// Tooltip: rotate the selected pages 90 degrees counter-clockwise.
  ///
  /// In en, this message translates to:
  /// **'Rotate selected pages left'**
  String get thumbRotateSelectedLeft;

  /// Tooltip: rotate the selected pages 90 degrees clockwise.
  ///
  /// In en, this message translates to:
  /// **'Rotate selected pages right'**
  String get thumbRotateSelectedRight;

  /// Count of pages currently selected in the thumbnail strip/grid.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} selected} other{{count} selected}}'**
  String thumbSelectedCount(int count);

  /// Generic button/tooltip to undo the last change.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Toast shown when the selected text's font or encoding cannot be edited safely.
  ///
  /// In en, this message translates to:
  /// **'This PDF font or encoding cannot be edited safely.'**
  String get viewerEditFontUnsafe;

  /// Toast shown when the user tries to edit text whose selection spans more than one page.
  ///
  /// In en, this message translates to:
  /// **'Editing requires a selection on one page.'**
  String get viewerEditNeedsSinglePage;

  /// Toast shown when the selection cannot be resolved to a single editable page-content text run.
  ///
  /// In en, this message translates to:
  /// **'This selection is not one editable page-content text run.'**
  String get viewerEditNotEditableRun;

  /// Toast shown when the selected text's font allows re-typing but not style changes.
  ///
  /// In en, this message translates to:
  /// **'This PDF font can be re-typed, but its style cannot be changed.'**
  String get viewerEditStyleUnchangeable;

  /// Menu item and chip tooltip to edit selected page-content text together with its style.
  ///
  /// In en, this message translates to:
  /// **'Edit text & style'**
  String get viewerEditTextStyle;

  /// Tooltip for the text-markup menu button on the text selection chip.
  ///
  /// In en, this message translates to:
  /// **'Markup'**
  String get viewerMarkup;

  /// Markup menu item that applies a highlight to the selected text.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get viewerMarkupHighlight;

  /// Markup menu item that applies a squiggly underline to the selected text.
  ///
  /// In en, this message translates to:
  /// **'Squiggly'**
  String get viewerMarkupSquiggly;

  /// Markup menu item that applies a strikethrough to the selected text.
  ///
  /// In en, this message translates to:
  /// **'Strike out'**
  String get viewerMarkupStrikeOut;

  /// Markup menu item that applies an underline to the selected text.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get viewerMarkupUnderline;

  /// Menu/chip action that selects all text on the current page.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get viewerSelectAll;
}

class _DartPdfEditorLocalizationsDelegate
    extends LocalizationsDelegate<DartPdfEditorLocalizations> {
  const _DartPdfEditorLocalizationsDelegate();

  @override
  Future<DartPdfEditorLocalizations> load(Locale locale) {
    return SynchronousFuture<DartPdfEditorLocalizations>(
        lookupDartPdfEditorLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'id',
        'it',
        'ja',
        'ko',
        'nl',
        'pl',
        'pt',
        'ru',
        'th',
        'tr',
        'uk',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_DartPdfEditorLocalizationsDelegate old) => false;
}

DartPdfEditorLocalizations lookupDartPdfEditorLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return DartPdfEditorLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return DartPdfEditorLocalizationsAr();
    case 'de':
      return DartPdfEditorLocalizationsDe();
    case 'en':
      return DartPdfEditorLocalizationsEn();
    case 'es':
      return DartPdfEditorLocalizationsEs();
    case 'fr':
      return DartPdfEditorLocalizationsFr();
    case 'hi':
      return DartPdfEditorLocalizationsHi();
    case 'id':
      return DartPdfEditorLocalizationsId();
    case 'it':
      return DartPdfEditorLocalizationsIt();
    case 'ja':
      return DartPdfEditorLocalizationsJa();
    case 'ko':
      return DartPdfEditorLocalizationsKo();
    case 'nl':
      return DartPdfEditorLocalizationsNl();
    case 'pl':
      return DartPdfEditorLocalizationsPl();
    case 'pt':
      return DartPdfEditorLocalizationsPt();
    case 'ru':
      return DartPdfEditorLocalizationsRu();
    case 'th':
      return DartPdfEditorLocalizationsTh();
    case 'tr':
      return DartPdfEditorLocalizationsTr();
    case 'uk':
      return DartPdfEditorLocalizationsUk();
    case 'vi':
      return DartPdfEditorLocalizationsVi();
    case 'zh':
      return DartPdfEditorLocalizationsZh();
  }

  throw FlutterError(
      'DartPdfEditorLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
