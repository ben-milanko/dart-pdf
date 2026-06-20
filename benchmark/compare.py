#!/usr/bin/env python3
"""Line up benchmark JSON files (PDFium + dart-pdf) into a comparison table.

    python3 benchmark/compare.py benchmark/out/pdfium.json \
        benchmark/out/dart-render.json

Each input is a payload from pdfium_benchmark.py, benchmark_interpret.dart, or
benchmark_render_test.dart. The first file is the baseline; speedup columns are
baseline_ms / tool_ms (>1 means the tool is faster than the baseline). Files
that errored in a tool are shown as `err`. A totals row aggregates throughput
(pages per second) over every page both tools rendered successfully.

Pass --md for a GitHub-flavored Markdown table, --per-file to list every file
(default shows only the slowest 25 by baseline render time plus totals).
"""
import argparse
import json
import sys


def load(path):
    with open(path) as fh:
        payload = json.load(fh)
    by_file = {}
    for r in payload["results"]:
        if r is not None:
            by_file[r["file"]] = r
    return payload, by_file


def fmt_ms(r):
    if r is None:
        return "—"
    if r.get("error"):
        return "err"
    return f"{r['renderMs']:.1f}"


def per_page(r):
    if r is None or r.get("error") or not r.get("pagesRendered"):
        return None
    return r["renderMs"] / r["pagesRendered"]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("json", nargs="+", help="benchmark JSON files; first = baseline")
    ap.add_argument("--md", action="store_true", help="Markdown table")
    ap.add_argument("--per-file", action="store_true", help="every file, not top 25")
    args = ap.parse_args()

    payloads = [load(p) for p in args.json]
    labels = [pl[0]["tool"] for pl in payloads]
    maps = [pl[1] for pl in payloads]
    base_label = labels[0]

    # Union of files, ordered by baseline render time (slowest first).
    all_files = []
    seen = set()
    for _pl, m in payloads:
        for f in m:
            if f not in seen:
                seen.add(f)
                all_files.append(f)
    base_map = maps[0]
    all_files.sort(
        key=lambda f: -(base_map.get(f, {}).get("renderMs", 0)
                        if not base_map.get(f, {}).get("error") else 0))

    print(f"# dart-pdf vs PDFium — render benchmark")
    print()
    for head, _m in payloads:
        print(f"- **{head['tool']}**: {head.get('engine', '?')}  "
              f"(scale {head.get('scale')}, max {head.get('maxPages')} pages/file)")
    print()

    cols = ["file", "pages"] + [f"{l} ms" for l in labels]
    # speedup of each non-baseline tool vs baseline
    for l in labels[1:]:
        cols.append(f"{base_label}/{l}")

    rows = []
    for f in all_files:
        recs = [m.get(f) for m in maps]
        base = recs[0]
        cells = [f, str((base or recs[0] or {}).get("pages", "?"))]
        for r in recs:
            cells.append(fmt_ms(r))
        for r in recs[1:]:
            bp, tp = per_page(base), per_page(r)
            cells.append(f"{bp / tp:.2f}x" if (bp and tp) else "—")
        rows.append(cells)

    shown = rows if args.per_file else rows[:25]

    # totals: aggregate over files every tool rendered without error
    totals_pages = [0] * len(maps)
    totals_ms = [0.0] * len(maps)
    for f in all_files:
        recs = [m.get(f) for m in maps]
        if any(r is None or r.get("error") for r in recs):
            continue
        # only count pages all tools agree they rendered
        common = min(r["pagesRendered"] for r in recs)
        if common <= 0:
            continue
        for i, r in enumerate(recs):
            # scale this file's time to the common page count
            pp = per_page(r)
            if pp is None:
                continue
            totals_pages[i] += common
            totals_ms[i] += pp * common

    def width(i):
        return max(len(cols[i]), max((len(r[i]) for r in shown), default=0))

    if args.md:
        print("| " + " | ".join(cols) + " |")
        print("|" + "|".join("---" for _ in cols) + "|")
        for r in shown:
            print("| " + " | ".join(r) + " |")
    else:
        ws = [width(i) for i in range(len(cols))]
        print("  ".join(c.ljust(ws[i]) for i, c in enumerate(cols)))
        print("  ".join("-" * ws[i] for i in range(len(cols))))
        for r in shown:
            print("  ".join(c.ljust(ws[i]) for i, c in enumerate(r)))

    print()
    print("## Totals (pages all tools rendered without error)")
    for i, label in enumerate(labels):
        if totals_pages[i] == 0:
            print(f"- {label}: no comparable pages")
            continue
        pps = totals_pages[i] / (totals_ms[i] / 1000) if totals_ms[i] else float("inf")
        print(f"- {label}: {totals_pages[i]} pages in {totals_ms[i] / 1000:.2f}s "
              f"= {pps:.1f} pages/s ({totals_ms[i] / totals_pages[i]:.1f} ms/page)")
    if len(labels) > 1 and totals_ms[0] and all(totals_ms[1:]):
        base_pps = totals_pages[0] / (totals_ms[0] / 1000)
        for i in range(1, len(labels)):
            tool_pps = totals_pages[i] / (totals_ms[i] / 1000)
            ratio = base_pps / tool_pps if tool_pps else float("inf")
            faster = "faster" if ratio < 1 else "slower"
            print(f"- {labels[i]} is {max(ratio, 1 / ratio):.2f}x {faster} "
                  f"than {base_label}")


if __name__ == "__main__":
    main()
