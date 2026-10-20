#!/usr/bin/env python3
"""Append perf-history NDJSON lines from <src-dir> into <dest-dir>, skipping any
(rev.sha, scenario) pair already present so re-running the backfill is
idempotent (no duplicate points on the dashboard).

Usage: merge_backfill.py <src-history-dir> <dest-history-dir>
"""
import json
import os
import sys


def merge(src_dir, dest_dir):
    os.makedirs(dest_dir, exist_ok=True)
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".ndjson"):
            continue
        src = os.path.join(src_dir, name)
        dest = os.path.join(dest_dir, name)
        seen = set()
        if os.path.exists(dest):
            for line in open(dest):
                if line.strip():
                    d = json.loads(line)
                    seen.add((d.get("rev", {}).get("sha"), d.get("scenario")))
        added = 0
        with open(dest, "a") as out:
            for line in open(src):
                if not line.strip():
                    continue
                d = json.loads(line)
                key = (d.get("rev", {}).get("sha"), d.get("scenario"))
                if key in seen:
                    continue
                seen.add(key)
                out.write(line if line.endswith("\n") else line + "\n")
                added += 1
        print(f"{name}: +{added} backfill points ({len(seen)} total)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: merge_backfill.py <src-history-dir> <dest-history-dir>")
    merge(sys.argv[1], sys.argv[2])
