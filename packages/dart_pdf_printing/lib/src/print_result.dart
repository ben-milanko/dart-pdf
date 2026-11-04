/// How the system print flow ended.
///
/// This reports what the user did with the print dialog, not what the
/// printer did afterwards: [handedToSystem] makes no claim that paper came
/// out, only that the job left the app.
enum PrintDialogResult {
  /// The user confirmed the system print dialog (or a Windows destination
  /// was spooled without one) and the job was handed to the OS print system.
  handedToSystem,

  /// The print dialog - or the app's print preview in front of it - was
  /// dismissed without printing. Nothing was sent to a printer.
  cancelled,
}
