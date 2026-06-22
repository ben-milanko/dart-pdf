/// Tagged-PDF logical structure: the document structure tree
/// (§14.7), reading order, and the mapping from structure elements to the
/// marked content they tag (via /MCID) and to page objects (via /OBJR).
///
/// This is the read path. It is pure COS — it walks dictionaries and the
/// content-stream marked-content operators, and knows nothing about
/// rendering. Mapping structure elements to extracted *text runs* lives one
/// layer up, in pdf_graphics, which can join a [PdfStructElement]'s
/// [PdfStructElement.markedContent] against MCID-tagged runs.
library;

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'page.dart';

/// The document structure tree root (catalog /StructTreeRoot, §14.7.2).
class PdfStructTree {
  PdfStructTree._(this.document, this.dict);

  /// The structure tree of [document], or null when it carries none.
  static PdfStructTree? of(PdfDocument document) {
    final dict = document.cos.resolve(document.catalog['StructTreeRoot']);
    return dict is CosDictionary ? PdfStructTree._(document, dict) : null;
  }

  final PdfDocument document;

  /// The raw /StructTreeRoot dictionary.
  final CosDictionary dict;

  CosDocument get _cos => document.cos;

  /// The /RoleMap: custom structure types mapped onto standard ones
  /// (§14.7.3). Keys and values are names without the leading slash.
  Map<String, String> get roleMap {
    final map = _cos.resolve(dict['RoleMap']);
    if (map is! CosDictionary) return const {};
    final out = <String, String>{};
    map.entries.forEach((key, value) {
      final v = _cos.resolve(value);
      if (v is CosName) out[key] = v.value;
    });
    return out;
  }

  /// Resolves a structure type to its standard type by following the role
  /// map transitively (a custom role may map onto another custom role).
  /// Returns [type] unchanged when it is already standard or unmapped.
  String resolveRole(String type) {
    final map = roleMap;
    var current = type;
    final seen = <String>{};
    while (seen.add(current)) {
      final next = map[current];
      if (next == null) return current;
      current = next;
    }
    return current; // cycle: stop at the first repeat
  }

  /// The top-level structure elements (the tree root's /K children that are
  /// themselves structure elements).
  List<PdfStructElement> get children =>
      _childElements(dict['K'], parent: null, inheritedPage: null);

  /// Every structure element in document (reading) order — a depth-first
  /// pre-order walk of the tree. The order of /K within each element is the
  /// authored reading order (§14.7.2).
  List<PdfStructElement> elementsInReadingOrder() {
    final out = <PdfStructElement>[];
    void visit(PdfStructElement e) {
      out.add(e);
      for (final c in e.children) {
        visit(c);
      }
    }

    for (final root in children) {
      visit(root);
    }
    return out;
  }

  /// Builds the structure elements among an /K value's entries. [parent] and
  /// [inheritedPage] thread context down (a child without /Pg inherits its
  /// parent's page, §14.7.4.4).
  List<PdfStructElement> _childElements(CosObject? rawK,
      {required PdfStructElement? parent, required CosDictionary? inheritedPage}) {
    final out = <PdfStructElement>[];
    for (final entry in _kidEntries(rawK)) {
      final resolved = _cos.resolve(entry);
      if (resolved is CosDictionary && _isStructElem(resolved)) {
        out.add(PdfStructElement._(
            this, resolved, parent, inheritedPage));
      }
    }
    return out;
  }

  /// Normalises an /K value (single entry or array) into a flat list of the
  /// raw (possibly indirect) entries, in order.
  List<CosObject> _kidEntries(CosObject? rawK) {
    if (rawK == null) return const [];
    final resolved = _cos.resolve(rawK);
    if (resolved is CosArray) return resolved.items;
    if (resolved is CosNull) return const [];
    return [rawK];
  }

  bool _isStructElem(CosDictionary d) {
    final type = d.typeName;
    if (type == 'StructElem') return true;
    if (type == 'MCR' || type == 'OBJR') return false;
    // Lenient: a dict with /S and no marked-content shape is a struct elem.
    return d.containsKey('S');
  }
}

/// Where a structure element's content lives: a marked-content sequence on a
/// page (a /MCID, §14.7.4.3) or an integer /K referencing one.
class PdfMarkedContentRef {
  PdfMarkedContentRef._(this.element, this.mcid, this.page, this.stream);

  /// The structure element this content belongs to.
  final PdfStructElement element;

  /// The marked-content identifier within [page]'s (or [stream]'s) content.
  final int mcid;

  /// The page whose content stream carries the marked-content sequence, or
  /// null when the reference targets a non-page content stream ([stream]).
  final CosDictionary? page;

  /// The content stream carrying the sequence when it is not the page's own
  /// /Contents (a /MCR with /Stm, e.g. an annotation appearance). Null means
  /// the marked content is in [page]'s content stream.
  final CosStream? stream;

  /// Zero-based index of [page] in the document's page tree, or -1.
  int get pageIndex {
    final p = page;
    return p == null ? -1 : element.tree.document.pageIndexOf(p);
  }
}

/// A reference from a structure element to a whole object — typically an
/// annotation or form field — rather than a marked-content sequence (/OBJR,
/// §14.7.4.3).
class PdfObjectRef {
  PdfObjectRef._(this.element, this.object, this.page);

  final PdfStructElement element;

  /// The referenced object (e.g. a /Link annotation dictionary).
  final CosObject object;

  /// The page the object appears on, or null.
  final CosDictionary? page;
}

/// One element of the logical structure tree (/StructElem, §14.7.2).
class PdfStructElement {
  PdfStructElement._(this.tree, this.dict, this._parent, this._inheritedPage);

  /// The structure tree this element belongs to.
  final PdfStructTree tree;

  /// The raw /StructElem dictionary.
  final CosDictionary dict;

  final PdfStructElement? _parent;
  final CosDictionary? _inheritedPage;

  CosDocument get _cos => tree.document.cos;

  /// The raw structure type (/S) without the leading slash, e.g. 'H1', 'P',
  /// 'Figure', or a custom role. Empty when absent.
  String get structureType {
    final s = _cos.resolve(dict['S']);
    return s is CosName ? s.value : '';
  }

  /// The structure type mapped to a standard type through the tree's role
  /// map (§14.7.3). Equals [structureType] when already standard.
  String get standardType => tree.resolveRole(structureType);

  /// The element title (/T), a human-readable label, or null.
  String? get title => _text(dict['T']);

  /// Alternate description (/Alt) — required on figures and other
  /// non-text content for accessibility (§14.9.3). Null when absent.
  String? get alt => _text(dict['Alt']);

  /// Replacement text (/ActualText) for the tagged content (§14.9.4), e.g.
  /// the expansion of a ligature or the reading of an image of text.
  String? get actualText => _text(dict['ActualText']);

  /// Expansion of an abbreviation or acronym (/E, §14.9.5).
  String? get expandedText => _text(dict['E']);

  /// The natural language of the element's content (/Lang), inherited from
  /// an ancestor or the document when absent here.
  String? get language {
    final own = _text(dict['Lang']);
    if (own != null) return own;
    return _parent?.language;
  }

  /// The parent structure element, or null for a top-level element.
  PdfStructElement? get parent => _parent;

  /// The page object this element's content lives on (/Pg), inherited from an
  /// ancestor when this element does not state one (§14.7.4.4). Null when no
  /// ancestor sets it.
  CosDictionary? get page {
    final pg = _cos.resolve(dict['Pg']);
    if (pg is CosDictionary) return pg;
    return _inheritedPage;
  }

  CosDictionary? get _ownPageForChildren => page;

  /// Child structure elements, in reading order.
  List<PdfStructElement> get children => tree._childElements(dict['K'],
      parent: this, inheritedPage: _ownPageForChildren);

  /// The marked-content references this element directly tags (its integer
  /// /K entries and /MCR dictionaries), in order. Does not include children's.
  List<PdfMarkedContentRef> get markedContent {
    final out = <PdfMarkedContentRef>[];
    for (final entry in tree._kidEntries(dict['K'])) {
      final resolved = _cos.resolve(entry);
      if (resolved is CosInteger) {
        out.add(PdfMarkedContentRef._(this, resolved.value, page, null));
      } else if (resolved is CosDictionary && resolved.typeName == 'MCR') {
        final mcid = _cos.resolve(resolved['MCID']);
        if (mcid is! CosInteger) continue;
        final pg = _cos.resolve(resolved['Pg']);
        final stm = _cos.resolve(resolved['Stm']);
        out.add(PdfMarkedContentRef._(
          this,
          mcid.value,
          pg is CosDictionary ? pg : page,
          stm is CosStream ? stm : null,
        ));
      }
    }
    return out;
  }

  /// The whole-object references this element tags (/OBJR entries), in order.
  List<PdfObjectRef> get objectReferences {
    final out = <PdfObjectRef>[];
    for (final entry in tree._kidEntries(dict['K'])) {
      final resolved = _cos.resolve(entry);
      if (resolved is CosDictionary && resolved.typeName == 'OBJR') {
        final obj = _cos.resolve(resolved['Obj']);
        if (obj is CosNull) continue;
        final pg = _cos.resolve(resolved['Pg']);
        out.add(PdfObjectRef._(
            this, obj, pg is CosDictionary ? pg : page));
      }
    }
    return out;
  }

  /// All marked-content references at or below this element, in reading
  /// order (this element's own, then each child's recursively).
  List<PdfMarkedContentRef> markedContentInReadingOrder() {
    final out = <PdfMarkedContentRef>[];
    void visit(PdfStructElement e) {
      // Walk /K in document order, descending into element children inline so
      // content and sub-structure interleave in true reading order.
      for (final entry in e.tree._kidEntries(e.dict['K'])) {
        final resolved = e._cos.resolve(entry);
        if (resolved is CosInteger) {
          out.add(PdfMarkedContentRef._(e, resolved.value, e.page, null));
        } else if (resolved is CosDictionary) {
          final type = resolved.typeName;
          if (type == 'MCR') {
            final mcid = e._cos.resolve(resolved['MCID']);
            if (mcid is CosInteger) {
              final pg = e._cos.resolve(resolved['Pg']);
              final stm = e._cos.resolve(resolved['Stm']);
              out.add(PdfMarkedContentRef._(
                e,
                mcid.value,
                pg is CosDictionary ? pg : e.page,
                stm is CosStream ? stm : null,
              ));
            }
          } else if (e.tree._isStructElem(resolved)) {
            visit(PdfStructElement._(
                e.tree, resolved, e, e._ownPageForChildren));
          }
        }
      }
    }

    visit(this);
    return out;
  }

  String? _text(CosObject? raw) {
    final v = _cos.resolve(raw);
    return v is CosString ? v.text : null;
  }
}

/// Whether [document] declares its content tagged (catalog /MarkInfo
/// /Marked true, §14.7.1). A PDF/UA or fully-tagged file must set this.
bool pdfIsMarkedTagged(PdfDocument document) {
  final markInfo = document.cos.resolve(document.catalog['MarkInfo']);
  if (markInfo is! CosDictionary) return false;
  final marked = document.cos.resolve(markInfo['Marked']);
  return marked is CosBoolean && marked.value;
}

/// The /ParentTree (a number tree, §14.7.4.4) mapping each page's
/// /StructParents key — and each object's /StructParent key — back to the
/// structure element(s) that tag it. Built lazily; lets a reader go from a
/// marked-content id on a page to its owning structure element.
class PdfStructParentTree {
  PdfStructParentTree._(this.document, this._nums);

  /// The parent tree of [document]'s structure tree, or null when absent.
  static PdfStructParentTree? of(PdfDocument document) {
    final tree = PdfStructTree.of(document);
    if (tree == null) return null;
    final pt = document.cos.resolve(tree.dict['ParentTree']);
    if (pt is! CosDictionary) return null;
    final nums = <int, CosObject>{};
    _collectNums(document.cos, pt, nums, <CosDictionary>{});
    return PdfStructParentTree._(document, nums);
  }

  final PdfDocument document;
  final Map<int, CosObject> _nums;

  /// The raw value at number-tree key [key] (a struct element reference, or
  /// an array of them indexed by MCID), or null.
  CosObject? entry(int key) => _nums[key];

  /// The structure element tagging marked content [mcid] on the page with
  /// /StructParents [structParentsKey], or null. The number-tree entry for a
  /// page is an array indexed by MCID (§14.7.4.4).
  PdfStructElement? elementForMcid(int structParentsKey, int mcid) {
    final value = document.cos.resolve(_nums[structParentsKey]);
    if (value is! CosArray || mcid < 0 || mcid >= value.length) return null;
    return _wrap(document.cos.resolve(value[mcid]));
  }

  /// The structure element tagging the object whose /StructParent is [key]
  /// (the entry is a single element reference), or null.
  PdfStructElement? elementForObject(int key) =>
      _wrap(document.cos.resolve(_nums[key]));

  PdfStructElement? _wrap(CosObject? resolved) {
    if (resolved is! CosDictionary) return null;
    final tree = PdfStructTree.of(document);
    if (tree == null) return null;
    final pg = document.cos.resolve(resolved['Pg']);
    return PdfStructElement._(
        tree, resolved, null, pg is CosDictionary ? pg : null);
  }

  static void _collectNums(CosDocument cos, CosDictionary node,
      Map<int, CosObject> out, Set<CosDictionary> visited) {
    if (!visited.add(node)) return;
    final nums = cos.resolve(node['Nums']);
    if (nums is CosArray) {
      for (var i = 0; i + 1 < nums.length; i += 2) {
        final key = cos.resolve(nums[i]);
        if (key is CosInteger) out[key.value] = nums[i + 1];
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        final child = cos.resolve(kid);
        if (child is CosDictionary) _collectNums(cos, child, out, visited);
      }
    }
  }
}

/// Convenience: the /StructParents key declared on a page, or null. Pairs
/// with [PdfStructParentTree.elementForMcid].
int? pageStructParentsKey(PdfPage page) {
  final v = page.document.cos.resolve(page.dict['StructParents']);
  return v is CosInteger ? v.value : null;
}

/// Author-side description of one structure element to write — the input to
/// `PdfEditor.writeStructTree`. Build a tree of these, attach the
/// marked-content ids ([mcids], on page [pageIndex]) and object references
/// ([objects]) each element tags, then hand the roots to the editor.
///
/// [type] is the structure type, normally a standard one (Document, Part,
/// Sect, H1..H6, P, L, LI, LBody, Figure, Table, TR, TH, TD, Link, Span, …);
/// a custom type can be mapped to a standard one through the role map passed
/// to `writeStructTree`.
class PdfStructSpec {
  PdfStructSpec(this.type,
      {this.alt,
      this.actualText,
      this.lang,
      this.title,
      this.pageIndex = 0,
      List<int>? mcids,
      List<PdfStructSpec>? children})
      : mcids = mcids ?? <int>[],
        children = children ?? <PdfStructSpec>[];

  /// Structure type (/S), without the leading slash.
  final String type;

  /// Alternate description (/Alt) — required on figures for PDF/UA.
  String? alt;

  /// Replacement text (/ActualText).
  String? actualText;

  /// Natural language (/Lang) of this element's content.
  String? lang;

  /// Human-readable title (/T).
  String? title;

  /// The page (zero-based) whose content carries this element's [mcids] and
  /// the page its [objects] live on.
  int pageIndex;

  /// Marked-content ids on page [pageIndex] this element directly tags.
  final List<int> mcids;

  /// Whole-object references (e.g. annotations) this element tags, written as
  /// /OBJR entries. The object must already be an indirect object.
  final List<CosReference> objects = <CosReference>[];

  /// Child structure elements, in reading order.
  final List<PdfStructSpec> children;

  /// Appends and returns [child] for fluent construction.
  PdfStructSpec add(PdfStructSpec child) {
    children.add(child);
    return child;
  }
}
