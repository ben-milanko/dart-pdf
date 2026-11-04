import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays its children out in runs (rows along a horizontal [direction],
/// columns along a vertical one) like [Wrap], but **first-fit**: each child
/// goes into the first run that still has room for it, not only the last
/// one. A long child that wraps no longer strands the space left on the run
/// before it - a shorter child after it back-fills that space instead.
///
/// Within a run, children keep their order. A child only moves *up* to an
/// earlier run, never ahead of an earlier child on its own run. Each run is
/// as thick as its thickest child, and children are centred across it. A
/// child longer than the whole main axis takes a run of its own, laid out
/// with the main-axis constraint, so it should scroll or clip itself.
///
/// The docked toolbar area uses it so a window's toolbar rows pack tighter.
/// At 800px, Edit back-fills beside Shapes, which saves a row.
class FirstFitWrap extends MultiChildRenderObjectWidget {
  const FirstFitWrap({
    super.key,
    this.direction = Axis.horizontal,
    super.children,
  });

  /// The main axis: the direction a run fills before the next run starts.
  final Axis direction;

  @override
  RenderFirstFitWrap createRenderObject(BuildContext context) =>
      RenderFirstFitWrap(direction: direction);

  @override
  void updateRenderObject(
      BuildContext context, RenderFirstFitWrap renderObject) {
    renderObject.direction = direction;
  }
}

class FirstFitWrapParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object behind [FirstFitWrap]. Runs stack from the top (or
/// left), and children fill each run from the left (or top), in physical
/// order whatever the reading direction, like a toolbar's edges.
class RenderFirstFitWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, FirstFitWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FirstFitWrapParentData> {
  RenderFirstFitWrap({Axis direction = Axis.horizontal})
      : _direction = direction;

  Axis get direction => _direction;
  Axis _direction;
  set direction(Axis value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  bool get _horizontal => _direction == Axis.horizontal;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! FirstFitWrapParentData) {
      child.parentData = FirstFitWrapParentData();
    }
  }

  double _main(Size size) => _horizontal ? size.width : size.height;
  double _cross(Size size) => _horizontal ? size.height : size.width;

  /// Packs [sizes] first-fit into runs no longer than [mainLimit]. Returns
  /// each child's run index and its main-axis offset in that run, plus each
  /// run's thickness.
  static ({List<int> run, List<double> offset, List<double> thickness}) _pack(
      List<Size> sizes, double mainLimit, bool horizontal) {
    final runLength = <double>[];
    final thickness = <double>[];
    final run = <int>[];
    final offset = <double>[];
    for (final size in sizes) {
      final main = horizontal ? size.width : size.height;
      final cross = horizontal ? size.height : size.width;
      var target = -1;
      for (var i = 0; i < runLength.length; i++) {
        // a hair of slack, so fractional widths that exactly fill a run
        // are not pushed to the next one
        if (runLength[i] + main <= mainLimit + 0.01) {
          target = i;
          break;
        }
      }
      if (target < 0) {
        target = runLength.length;
        runLength.add(0);
        thickness.add(0);
      }
      run.add(target);
      offset.add(runLength[target]);
      runLength[target] += main;
      thickness[target] = math.max(thickness[target], cross);
    }
    return (run: run, offset: offset, thickness: thickness);
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) => _horizontal
      ? BoxConstraints(maxWidth: constraints.maxWidth)
      : BoxConstraints(maxHeight: constraints.maxHeight);

  double _mainLimit(BoxConstraints constraints) =>
      _horizontal ? constraints.maxWidth : constraints.maxHeight;

  Size _sizeFor(BoxConstraints constraints, List<Size> sizes) {
    final packed = _pack(sizes, _mainLimit(constraints), _horizontal);
    var mainExtent = 0.0;
    final lengths = List<double>.filled(packed.thickness.length, 0);
    for (var i = 0; i < sizes.length; i++) {
      lengths[packed.run[i]] = packed.offset[i] + _main(sizes[i]);
    }
    for (final length in lengths) {
      mainExtent = math.max(mainExtent, length);
    }
    final crossExtent = packed.thickness.fold(0.0, (a, b) => a + b);
    return constraints.constrain(_horizontal
        ? Size(mainExtent, crossExtent)
        : Size(crossExtent, mainExtent));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final childConstraints = _childConstraints(constraints);
    final sizes = <Size>[
      for (var child = firstChild; child != null; child = childAfter(child))
        child.getDryLayout(childConstraints),
    ];
    return _sizeFor(constraints, sizes);
  }

  @override
  void performLayout() {
    final childConstraints = _childConstraints(constraints);
    final children = <RenderBox>[];
    final sizes = <Size>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(childConstraints, parentUsesSize: true);
      children.add(child);
      sizes.add(child.size);
    }
    final packed = _pack(sizes, _mainLimit(constraints), _horizontal);
    final runStart = <double>[];
    var cursor = 0.0;
    for (final thickness in packed.thickness) {
      runStart.add(cursor);
      cursor += thickness;
    }
    for (var i = 0; i < children.length; i++) {
      final run = packed.run[i];
      final cross =
          runStart[run] + (packed.thickness[run] - _cross(sizes[i])) / 2;
      final main = packed.offset[i];
      (children[i].parentData! as FirstFitWrapParentData).offset =
          _horizontal ? Offset(main, cross) : Offset(cross, main);
    }
    size = _sizeFor(constraints, sizes);
  }

  // Intrinsics: the whole length along the main axis at most, the longest
  // child at least; across it, the runs the children would pack into.

  double _sumMain(double Function(RenderBox) extent) {
    var sum = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      sum += extent(child);
    }
    return sum;
  }

  double _maxOf(double Function(RenderBox) extent) {
    var most = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      most = math.max(most, extent(child));
    }
    return most;
  }

  double _crossFor(double mainLimit) {
    final sizes = <Size>[
      for (var child = firstChild; child != null; child = childAfter(child))
        _horizontal
            ? Size(
                math.min(
                    child.getMaxIntrinsicWidth(double.infinity), mainLimit),
                child.getMaxIntrinsicHeight(double.infinity))
            : Size(
                child.getMaxIntrinsicWidth(double.infinity),
                math.min(
                    child.getMaxIntrinsicHeight(double.infinity), mainLimit)),
    ];
    return _pack(sizes, mainLimit, _horizontal)
        .thickness
        .fold(0.0, (a, b) => a + b);
  }

  @override
  double computeMinIntrinsicWidth(double height) => _horizontal
      ? _maxOf((c) => c.getMinIntrinsicWidth(double.infinity))
      : _crossFor(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _horizontal
      ? _sumMain((c) => c.getMaxIntrinsicWidth(double.infinity))
      : _crossFor(height);

  @override
  double computeMinIntrinsicHeight(double width) => _horizontal
      ? _crossFor(width)
      : _maxOf((c) => c.getMinIntrinsicHeight(double.infinity));

  @override
  double computeMaxIntrinsicHeight(double width) => _horizontal
      ? _crossFor(width)
      : _sumMain((c) => c.getMaxIntrinsicHeight(double.infinity));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
