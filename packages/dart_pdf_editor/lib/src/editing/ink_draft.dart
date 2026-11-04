import 'edit_history.dart';

/// Drawn strokes waiting to commit as Ink annotations: a [PdfHistoryDraft]
/// whose undo steps take back one stroke at a time, newest first.
class PdfInkDraft implements PdfHistoryDraft {
  final Map<int, List<List<(double, double)>>> _strokes = {};
  final Map<int, List<List<double>?>> _pressures = {};

  /// Page of each buffered stroke, oldest first - the undo order.
  final List<int> _order = [];

  final List<
          ({int page, List<(double, double)> stroke, List<double>? pressures})>
      _undone = [];

  /// Whether any stroke is buffered.
  bool get isNotEmpty => _order.isNotEmpty;

  /// Whether undone strokes are waiting for a redo.
  bool get hasUndone => _undone.isNotEmpty;

  List<List<(double, double)>> strokesOn(int pageIndex) =>
      List.unmodifiable(_strokes[pageIndex] ?? const []);

  List<List<double>?> pressuresOn(int pageIndex) =>
      List.unmodifiable(_pressures[pageIndex] ?? const []);

  /// Buffers [stroke] on [pageIndex]; drawing forgets anything undone.
  void add(int pageIndex, List<(double, double)> stroke,
      {List<double>? pressures}) {
    _undone.clear();
    _push(pageIndex, List.of(stroke),
        pressures == null ? null : List.of(pressures));
  }

  /// Hands over the buffered strokes per page and empties the draft, undone
  /// strokes included.
  ({
    Map<int, List<List<(double, double)>>> strokes,
    Map<int, List<List<double>?>> pressures,
  }) take() {
    final taken = (strokes: Map.of(_strokes), pressures: Map.of(_pressures));
    _strokes.clear();
    _pressures.clear();
    _order.clear();
    _undone.clear();
    return taken;
  }

  /// Empties the draft. Whether there was anything to throw away.
  bool discard() {
    final had = _strokes.isNotEmpty || _undone.isNotEmpty;
    take();
    return had;
  }

  @override
  bool get canUndo => isNotEmpty;

  @override
  bool get canRedo => hasUndone;

  @override
  bool undo() {
    if (_order.isEmpty) return false;
    final page = _order.removeLast();
    _undone.add((
      page: page,
      stroke: _strokes[page]!.removeLast(),
      pressures: _pressures[page]!.removeLast(),
    ));
    return true;
  }

  @override
  bool redo() {
    if (_undone.isEmpty) return false;
    final ink = _undone.removeLast();
    _push(ink.page, ink.stroke, ink.pressures);
    return true;
  }

  @override
  void dropRedo() => _undone.clear();

  void _push(int page, List<(double, double)> stroke, List<double>? pressures) {
    _order.add(page);
    _strokes.putIfAbsent(page, () => []).add(stroke);
    _pressures.putIfAbsent(page, () => []).add(pressures);
  }
}
