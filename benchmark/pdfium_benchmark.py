#!/usr/bin/env python3
"""Benchmark PDFium (via pypdfium2) rendering, for comparison with dart-pdf.

pypdfium2 bundles a prebuilt PDFium binary (the same engine Chrome uses), so
no system PDFium install is required:

    pip install pypdfium2
    python3 benchmark/pdfium_benchmark.py test_corpora/pdfjs --scale 2 \
        --out benchmark/out/pdfium.json

The output JSON schema is shared with the dart-pdf harnesses
(tool/benchmark_interpret.dart, test/benchmark_render_test.dart) so
compare.py can line the tools up file-by-file:

    {"tool": "pdfium", "scale": 2.0, "maxPages": 10,
     "engine": "...", "results": [
        {"file": "foo.pdf", "pages": 3, "pagesRendered": 3,
         "openMs": 1.2, "renderMs": 45.6, "error": null}, ...]}

`renderMs` is the wall time to rasterize `pagesRendered` pages to a bitmap at
`scale` (1.0 == 72 DPI == 1px/pt, matching dart-pdf's pixelRatio). `openMs` is
parse/load time. Both exclude file I/O (bytes are read up front).
"""
import argparse
import json
import multiprocessing as mp
import os
import sys
import time
import datetime
import platform
import subprocess

try:
    import pypdfium2 as pdfium
except ImportError:
    sys.exit("pypdfium2 not installed - run: pip install pypdfium2")


def find_pdfs(root):
    if os.path.isfile(root):
        return [root]
    out = []
    for dirpath, _dirs, files in os.walk(root):
        for name in sorted(files):
            if name.lower().endswith(".pdf"):
                out.append(os.path.join(dirpath, name))
    out.sort()
    return out


def bench_file(path, scale, max_pages, first_page=False, save_copy=False):
    """Returns (pages, pages_rendered, open_ms, render_ms, error, extra) -
    `extra` carries the optional Bluebeam-proxy metrics (firstPageMs: open ->
    first rendered page; saveMs: FPDF_SaveAsCopy round trip). Both are opt-in
    flags so the default renderMs stays comparable with the README's
    committed tables (a first-page pre-render warms page 0)."""
    extra = {}
    with open(path, "rb") as fh:
        data = fh.read()

    t0 = time.perf_counter()
    try:
        # autoclose=False: we hold `data` for the doc's lifetime.
        doc = pdfium.PdfDocument(data)
        n = len(doc)
    except Exception as exc:  # noqa: BLE001 - record, don't crash the sweep
        return (0, 0, (time.perf_counter() - t0) * 1000, 0.0, repr(exc), extra)
    open_ms = (time.perf_counter() - t0) * 1000

    if first_page and n > 0:
        try:
            page = doc[0]
            bitmap = page.render(scale=scale)
            _ = len(bitmap.buffer)
            bitmap.close()
            page.close()
            # Open-to-first-paint proxy: parse + first page rasterized,
            # measured from the same t0 the open was.
            extra["firstPageMs"] = round((time.perf_counter() - t0) * 1000, 3)
        except Exception:  # noqa: BLE001 - optional metric never fails a file
            pass

    limit = n if max_pages <= 0 else min(n, max_pages)
    rendered = 0
    error = None
    t1 = time.perf_counter()
    try:
        for i in range(limit):
            page = doc[i]
            bitmap = page.render(scale=scale)
            # Touch the buffer so the rasterization can't be optimized away
            # (FPDF_RenderPageBitmap is synchronous, but be explicit).
            _ = len(bitmap.buffer)
            bitmap.close()
            page.close()
            rendered += 1
    except Exception as exc:  # noqa: BLE001
        error = repr(exc)
    render_ms = (time.perf_counter() - t1) * 1000

    if save_copy:
        try:
            import io
            t2 = time.perf_counter()
            sink = io.BytesIO()
            doc.save(sink)
            extra["saveMs"] = round((time.perf_counter() - t2) * 1000, 3)
        except Exception:  # noqa: BLE001
            pass
    doc.close()
    return (n, rendered, open_ms, render_ms, error, extra)


def _bench_child(path, scale, max_pages, first_page, save_copy, q):
    q.put(bench_file(path, scale, max_pages, first_page, save_copy))


def bench_with_timeout(path, scale, max_pages, timeout, ctx,
                       first_page=False, save_copy=False):
    """bench_file, but render in a killable fork child so a single malformed
    PDF can't stall the sweep. A long native PDFium render ignores signals, so
    nothing short of killing the process works - hence a child, not SIGALRM.

    The child is forked AFTER pypdfium2 is imported in the parent, so it
    inherits the loaded native lib (no per-file re-import cost) and the timing
    brackets stay inside bench_file (fork/IPC overhead is excluded)."""
    if timeout <= 0:
        return bench_file(path, scale, max_pages, first_page, save_copy)
    q = ctx.Queue()
    p = ctx.Process(target=_bench_child,
                    args=(path, scale, max_pages, first_page, save_copy, q))
    p.start()
    p.join(timeout)
    if p.is_alive():
        p.terminate()
        p.join()
        return (0, 0, 0.0, 0.0, f"timeout>{timeout}s", {})
    try:
        return q.get_nowait()
    except Exception:  # noqa: BLE001 - child crashed (e.g. native abort)
        return (0, 0, 0.0, 0.0, "child died (native crash?)", {})


def _envelope_fields():
    """rev/env/ts envelope sections (tool/perf/SCHEMA.md); additive - the
    legacy fields keep their meaning so compare.py is unaffected."""
    def git(*args):
        try:
            return subprocess.run(("git",) + args, capture_output=True,
                                  text=True, check=False).stdout.strip()
        except OSError:
            return ""
    return {
        "schema": 1,
        "suite": "pdfium",
        "scenario": None,
        "rev": {
            "sha": git("rev-parse", "HEAD"),
            "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(git("status", "--porcelain")),
            "date": git("show", "-s", "--format=%cI", "HEAD"),
        },
        "env": {
            "os": f"{platform.system().lower()}-{platform.machine()}",
            "cpus": os.cpu_count(),
            "python": platform.python_version(),
            "ci": os.environ.get("CI") == "true",
            "runner": "github-actions" if os.environ.get("RUNNER_OS") else "local",
        },
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("corpus", help="PDF file or directory (searched recursively)")
    ap.add_argument("--scale", type=float, default=2.0,
                    help="render scale; 1.0 == 72 DPI == dart-pdf pixelRatio 1")
    ap.add_argument("--max-pages", type=int, default=10,
                    help="cap pages rendered per file (<=0 = all)")
    ap.add_argument("--repeat", type=int, default=1,
                    help="render the whole sweep N times; keep the fastest")
    ap.add_argument("--timeout", type=float, default=0.0,
                    help="per-file wall-clock budget in seconds (0 = none); a "
                         "file exceeding it is killed and recorded as a timeout "
                         "error. Needed for corpora with malformed PDFs that send "
                         "PDFium into a long native spin.")
    ap.add_argument("--first-page", action="store_true",
                    help="also record firstPageMs (open -> page 0 rendered), "
                         "the Revu-comparable time-to-first-paint proxy. Note: "
                         "warms page 0, so renderMs shifts slightly vs runs "
                         "without this flag.")
    ap.add_argument("--save", action="store_true",
                    help="also record saveMs (FPDF_SaveAsCopy to memory)")
    ap.add_argument("--out", default=None, help="write JSON here (else stdout)")
    args = ap.parse_args()

    files = find_pdfs(args.corpus)
    if not files:
        sys.exit(f"no PDFs under {args.corpus}")

    # fork (not the macOS default 'spawn') so the child inherits the imported
    # pypdfium2 - no per-file re-import, and no re-running this script's argv.
    ctx = mp.get_context("fork") if args.timeout > 0 else None

    # Per file, keep the fastest render time across repeats (warm-cache best).
    best = {}
    for r in range(args.repeat):
        for path in files:
            pages, rendered, open_ms, render_ms, error, extra = \
                bench_with_timeout(
                    path, args.scale, args.max_pages, args.timeout, ctx,
                    args.first_page, args.save)
            if error and str(error).startswith("timeout"):
                print(f"  TIMEOUT >{args.timeout}s  {os.path.basename(path)}",
                      file=sys.stderr, flush=True)
            prev = best.get(path)
            better = prev is None or (error is None and (
                prev["error"] is not None or render_ms < prev["renderMs"]))
            if better:
                best[path] = {
                    "file": os.path.relpath(path, args.corpus)
                            if os.path.isdir(args.corpus) else os.path.basename(path),
                    "pages": pages,
                    "pagesRendered": rendered,
                    "openMs": round(open_ms, 3),
                    "renderMs": round(render_ms, 3),
                    "error": error,
                    **extra,
                }
        print(f"  pdfium pass {r + 1}/{args.repeat} done ({len(files)} files)",
              file=sys.stderr)

    results = [best[p] for p in files]
    payload = {
        **_envelope_fields(),
        "tool": "pdfium",
        "scale": args.scale,
        "maxPages": args.max_pages,
        "engine": f"pypdfium2 {pdfium.version.PYPDFIUM_INFO} / "
                  f"libpdfium {pdfium.version.PDFIUM_INFO}",
        "results": results,
    }
    text = json.dumps(payload, indent=2)
    if args.out:
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        with open(args.out, "w") as fh:
            fh.write(text)
        print(f"wrote {args.out}", file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
