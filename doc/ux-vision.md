# UX vision

dart-pdf should make working with a PDF feel direct, dependable, and native on
every supported platform. Its product goal is not merely to cover the same
feature list as established editors. It is to offer the best end-to-end PDF
editing experience.

This document is the product-quality charter for the SDK, the example shells,
and DartPDF. It complements the technical roadmap and the measured
[PDFium parity work](benchmarks/pdfium-parity.md).

## North star

Minimize the time from a user's intent to a result they trust.

A trusted result is correct, visibly complete, saved when the user expects,
reversible when possible, and preserved when reopened in dart-pdf or another
conforming PDF application. Speed without confidence is not good UX.

## Product principles

### Instant

Opening, scrolling, zooming, searching, selecting a tool, and seeing an edit
should feel immediate. Expensive work belongs off the interaction path. When
work cannot finish immediately, show useful content and honest progress rather
than a blank or frozen surface.

### Obvious

The next action, active tool, selection, save state, and result of an operation
should be clear without a manual. Prefer contextual controls and progressive
disclosure over a permanently crowded canvas. Labels, icons, cursors, previews,
and disabled states should agree.

### Forgiving

Users should be free to experiment. Edits need reliable undo and redo;
destructive operations need an escape path; interrupted sessions need recovery;
and cancel must leave the document unchanged. Avoid modes that silently trap
input or actions whose effect becomes clear only after saving.

### Precise

The preview must match the committed PDF. Hit targets, snapping, handles,
selection bounds, text placement, zoom, and page navigation must remain stable
at every scale. Mouse, keyboard, touch, trackpad, and stylus input should each
feel intentional rather than emulated.

### Coherent

Reader and editor shells, toolbars, panels, context menus, shortcuts, and public
widgets should share one interaction model. Follow platform conventions where
they help users, while keeping document behavior consistent across desktop,
mobile, and web.

### Inclusive

Accessibility is part of the interaction design, not a final audit. User-facing
work should account for keyboard-only use, focus order, screen-reader semantics,
contrast, text scaling, reduced motion, and sufficiently large touch targets.

## Journeys that define the product

These journeys matter more than isolated feature counts:

| Journey | Quality bar |
| --- | --- |
| Open or recover | Reach a useful first page quickly, explain failures clearly, and never lose a recoverable edit. |
| Read and navigate | Scrolling, zooming, page jumps, outlines, thumbnails, history, and links preserve orientation and never fight the user. |
| Find and understand | Search responds promptly, exposes useful context, follows the active result, and works for scanned documents when OCR is available. |
| Annotate and edit | Tools are easy to enter and leave; selection is predictable; live previews match commits; repeated work stays fast. |
| Fill and sign | Field state and signature consequences are clear before commitment, with validation results phrased for people rather than PDF internals. |
| Organize pages | Reorder, insert, extract, rotate, and delete operations provide strong spatial feedback and remain safely reversible. |
| Save, export, and share | Users know what is saved, where it went, what changed, and whether compatibility or signatures were affected. |

A feature that works in isolation but makes one of these journeys confusing,
slow, or fragile is not finished.

Text markup supports both natural orders of work: choose Highlight, Underline,
Strike out, or Squiggly and then select text, or select text and then choose the
markup. The chosen markup stays visibly armed for repeated passages until the
user clears it or switches tools.

## How quality is measured

Use matched, reproducible journeys on the same hardware, document, viewport,
and input sequence. Compare against the strongest relevant experience, which
may be Acrobat, Bluebeam, PDF Expert, Preview, a browser PDF viewer, or another
specialist tool. Record limitations instead of generalizing a result from one
platform to all platforms.

The scorecard for a user journey should include the measures that apply:

- task completion and error rate;
- time to first useful visual and time to stable visual;
- time to complete the task;
- p50 and p95 input latency or frame interval, including tail stalls;
- peak and steady-state memory;
- undo, recovery, save, and reopen correctness;
- keyboard, touch, stylus, focus, semantics, contrast, and text-scale coverage.

Prefer user-visible measurements over internal throughput. A faster decoder is
valuable when it improves the journey; it is not by itself proof of a faster
viewer. Performance claims and budgets belong in reproducible benchmark notes,
including [the current parity methodology](benchmarks/pdfium-parity.md).

## Prioritization

When two pieces of work compete, prefer the one that removes more frequent or
more severe friction from a core journey. Use this order to break close calls:

1. Prevent data loss, corruption, privacy failures, and inaccessible dead ends.
2. Fix incorrect, misleading, or incompatible document behavior.
3. Remove stalls, input conflicts, and unnecessary waiting from common work.
4. Reduce decisions, mode confusion, and repeated steps.
5. Improve consistency, polish, and visual density.
6. Add breadth that does not compromise the earlier qualities.

Evidence should move priorities. Reports from real use, journey traces,
accessibility findings, and reproducible documents outweigh feature-count
comparisons.

## Standing execution order

The ongoing UX program is:

1. Instrument complete user journeys with latency, frame-time, memory, and
   success criteria.
2. Audit friction on desktop, web, tablet, and phone with representative real
   documents.
3. Keep perfecting the core loop: open, find, edit, undo, save, and share.
4. Improve orientation and navigation, including outlines, page labels, recent
   locations, and search-result continuity.
5. Make advanced capability discoverable without crowding routine work.
6. Close accessibility gaps and make keyboard operation complete.
7. Turn every material interaction or visual regression into durable coverage.

This order is not a promise to build speculative features. Start from the
largest demonstrated gap in a core journey, make the smallest coherent change,
and measure the journey again.

## Definition of done for user-facing changes

Not every item applies to every change, but omissions should be deliberate and
called out in review.

- The entry point, active state, completion, cancellation, disabled state, and
  error path are understandable.
- Immediate feedback is shown, and any preview agrees with the committed and
  reopened PDF.
- Undo, redo, save, reopen, and crash recovery behave correctly where relevant.
- Relevant keyboard, mouse, trackpad, touch, and stylus paths have been checked.
- Focus, semantics, contrast, text scaling, reduced motion, and touch-target
  size have been considered.
- Loading, empty, malformed-document, long-document, and constrained-window
  states degrade gracefully.
- The change introduces no unexplained journey-level latency, frame-time, or
  memory regression.
- Behavior tests, visual tests, corpus cases, or performance traces protect the
  risk at the appropriate layer.
- Public APIs and host responsibilities are documented when they change.

The final review question is simple: does this shorten the path from intent to
a trusted result?
