# Annotation grouping

The annotation context menu offers Group for a selection of two or more
annotations on one page, and Ungroup for existing groups. Both operations are
single undo steps. Grouping preserves geometry, appearances, names, and paint
order, and saves standard `/RT /Group` links to an indirect `/IRT` leader.

`PdfAnnotationGroups` resolves page groups by dictionary identity, including
foreign groups without `/NM`, chains, and cycles. The editor promotes inline
leaders to indirect objects through `_PdfPageAnnotationList`. Group edits report
annotation metadata impact without repainting the page. Comment threads ignore
group links so grouping never turns a shape into a comment reply.

Controller click, modifier-click, marquee, and sidebar range selection expand
group members together. Existing multi-selection move, restyle, arrange, and
delete operations then act on the group. A locked or host-protected member
protects the whole group from selection; locking a member clears its group's
selection. Ungroup keeps the annotations selected in place. Clipboard payloads
carry detached member indices, so each paste or Apply to pages makes independent
groups with fresh names.

Tests cover PDF round trips, direct and indirect annotation arrays with inline
leaders, foreign links, group merging, undo/redo, selection entry paths,
permissions, cross-document paste, Apply to pages, and the right-click and drag
flows. Existing menu, multi-selection, clipboard, read-only, metadata, and
comment tests also pass.
