import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [ListView] whose scroll metrics are exact, not estimated.
///
/// Stock [ListView] with an [ListView.itemExtentBuilder] lays children out
/// at exact offsets, but the sliver's *total* scroll extent still comes
/// from [RenderSliverBoxChildManager.estimateMaxScrollOffset], which
/// extrapolates the average extent of the currently built children over
/// the rest of the list. On long documents with mixed page sizes the
/// average swings as pages enter and leave the build window, so
/// `maxScrollExtent` oscillates by tens of thousands of pixels while
/// scrolling - and anything derived from it (the scrollbar thumb, end
/// clamping) leaps around. This subclass reports the exact sum of every
/// item's extent instead, so the metrics are constant.
class ExactExtentListView extends ListView {
  ExactExtentListView.builder({
    super.key,
    super.controller,
    super.physics,
    super.padding,
    required ItemExtentBuilder super.itemExtentBuilder,
    required super.itemBuilder,
    required int super.itemCount,
  }) : super.builder();

  @override
  Widget buildChildLayout(BuildContext context) => _ExactVariedExtentList(
      delegate: childrenDelegate, itemExtentBuilder: itemExtentBuilder!);
}

class _ExactVariedExtentList extends SliverVariedExtentList {
  const _ExactVariedExtentList(
      {required super.delegate, required super.itemExtentBuilder});

  @override
  RenderSliverVariedExtentList createRenderObject(BuildContext context) =>
      _ExactRenderSliverVariedExtentList(
          childManager: context as SliverMultiBoxAdaptorElement,
          itemExtentBuilder: itemExtentBuilder);
}

class _ExactRenderSliverVariedExtentList extends RenderSliverVariedExtentList {
  _ExactRenderSliverVariedExtentList(
      {required super.childManager, required super.itemExtentBuilder});

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    // computeMaxScrollOffset sums itemExtentBuilder over the full child
    // count - the precise value the framework only consults when layout
    // runs past the end of the list. The -1 argument is the deprecated
    // itemExtent placeholder performLayout itself passes.
    // ignore: invalid_use_of_visible_for_testing_member
    return computeMaxScrollOffset(constraints, -1);
  }
}
