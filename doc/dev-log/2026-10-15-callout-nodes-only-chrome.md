# Callouts get the nodes-only selection chrome

Follow-up to 2026-10-14-polyline-placement-navigation.md, which gave a lone
selected line/polyline/polygon nodes-only chrome. A lone selected callout now
matches (`_selectedCalloutNodesOnly` in `editing_overlay.dart`): its leader
nodes (terminus + base per leader) plus the text box's eight resize handles,
but no tinted box outline and no rotate knob - `_hitsRotateHandle` refuses it,
since dragging a leader node re-aims the arrow directly.

Unlike a line, a callout keeps its resize handles: the text box still has to
be resizable. So the selection rect stays (it positions those handles) and the
painter's new `selectionOutline` flag drops just the box. Groups and
multi-selections containing a callout keep the full chrome.

Test: `editing_callout_test.dart` ("a selected callout shows nodes only").
