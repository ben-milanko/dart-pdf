#!/usr/bin/env python3
"""List merged tickets in a nightly, relative to the latest published release."""

import re
import subprocess
import sys
from urllib.parse import quote


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def release_base(head, tag):
    released = git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    ancestry = subprocess.run(
        ["git", "merge-base", "--is-ancestor", released, head], check=False
    ).returncode
    if ancestry == 0:
        return released
    if ancestry != 1:
        raise RuntimeError("Could not check release ancestry")
    # Releases can tag the tested candidate before its squash merge. Match the
    # complete tree, not patch IDs or dates, so already-released PRs stay out.
    tree = git("rev-parse", f"{released}^{{tree}}")
    for line in git("log", "--first-parent", "--format=%H %T", head).splitlines():
        commit, candidate_tree = line.split()
        if candidate_tree == tree:
            return commit
    return None


def main():
    head_arg, tag, repo_url = sys.argv[1:]
    head = git("rev-parse", "--verify", f"{head_arg}^{{commit}}")
    version = tag.removeprefix("app-v")
    print(
        f"## Tickets since [DartPDF {version}]"
        f"({repo_url}/releases/tag/{quote(tag, safe='')})\n"
    )
    base = release_base(head, tag)
    if base is None:
        print("This nightly and the latest release have different histories; "
              "a reliable ticket comparison is unavailable.")
        return
    subjects = git("log", "--format=%s", f"{base}..{head}").splitlines()
    tickets = {}
    for subject in subjects:
        match = re.search(r" \(#(\d+)\)$", subject)
        if match:
            number = match.group(1)
            title = subject[:match.start()].replace("[", "\\[").replace("]", "\\]")
            tickets.setdefault(number, title)
    if tickets:
        for number, title in tickets.items():
            print(f"- {title} ([#{number}]({repo_url}/pull/{number}))")
    else:
        print("No new merged tickets since this release.")
    print(f"\n[Full comparison]({repo_url}/compare/{base}...{head}).")


if __name__ == "__main__":
    main()
