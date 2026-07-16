/// Shared conformance-report model for the PDF/UA and PDF/A checkers.
library;

/// How serious a conformance finding is.
enum PdfConformanceSeverity {
  /// A violation that makes the document non-conformant.
  error,

  /// A likely problem or a requirement that cannot be checked mechanically
  /// (e.g. whether alt text is *meaningful*); does not by itself fail.
  warning,

  /// Informational note.
  info,
}

/// One finding against a conformance profile.
class PdfConformanceIssue {
  const PdfConformanceIssue({
    required this.rule,
    required this.severity,
    required this.message,
    this.pageIndex,
    this.objectNumber,
  });

  /// The clause id, e.g. 'UA1:7.1' or 'A2:6.1.3'.
  final String rule;

  final PdfConformanceSeverity severity;

  /// Human-readable description of the problem.
  final String message;

  /// Zero-based page the problem is on, when applicable.
  final int? pageIndex;

  /// The offending object number, when applicable.
  final int? objectNumber;

  @override
  String toString() {
    final where = [
      if (pageIndex != null) 'page ${pageIndex! + 1}',
      if (objectNumber != null) 'obj $objectNumber',
    ].join(', ');
    final loc = where.isEmpty ? '' : ' ($where)';
    return '[${severity.name.toUpperCase()}] $rule: $message$loc';
  }
}

/// The result of validating a document against a conformance profile.
class PdfConformanceReport {
  PdfConformanceReport(this.profile, this.issues);

  /// The profile checked, e.g. 'PDF/UA-1' or 'PDF/A-2b'.
  final String profile;

  /// Every finding, in check order.
  final List<PdfConformanceIssue> issues;

  /// Findings of [PdfConformanceSeverity.error] severity.
  List<PdfConformanceIssue> get errors =>
      [for (final i in issues) if (i.severity == PdfConformanceSeverity.error) i];

  /// Findings of [PdfConformanceSeverity.warning] severity.
  List<PdfConformanceIssue> get warnings => [
        for (final i in issues)
          if (i.severity == PdfConformanceSeverity.warning) i
      ];

  /// True when there are no error-level findings. Warnings do not fail -
  /// they flag things a machine cannot fully judge.
  bool get isCompliant => errors.isEmpty;

  /// A multi-line human-readable summary.
  String summary() {
    final b = StringBuffer()
      ..writeln('$profile conformance: '
          '${isCompliant ? 'PASS' : 'FAIL'} '
          '(${errors.length} error(s), ${warnings.length} warning(s))');
    for (final issue in issues) {
      b.writeln('  $issue');
    }
    return b.toString();
  }

  @override
  String toString() => summary();
}
