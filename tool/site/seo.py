#!/usr/bin/env python3
"""Build the marketing sitemap and check source/deployed crawlability (stdlib only)."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date, datetime, timezone
from fnmatch import fnmatchcase
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import xml.etree.ElementTree as ET


ORIGIN = "https://dart-pdf.com"
NAMESPACE = "http://www.sitemaps.org/schemas/sitemap/0.9"
SITE = Path(__file__).resolve().parents[2] / "site"


class SeoError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise SeoError(message)


def blocked(value):
    return bool(re.search(r"\b(?:noindex|nofollow|none)\b", value, re.I))


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.in_head = False
        self.in_title = False
        self.title = ""
        self.description = ""
        self.canonicals = []
        self.robots = ""
        self.links = []
        self.h1 = False
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "head":
            self.in_head = True
        if self.in_head:
            if tag == "title":
                self.in_title = True
            if tag == "link" and "canonical" in attrs.get("rel", "").split():
                self.canonicals.append(attrs.get("href", ""))
            if tag == "meta":
                name = attrs.get("name", "").lower()
                if name in ("robots", "googlebot"):
                    self.robots += " " + (attrs.get("content") or "")
                if name == "description":
                    self.description = attrs.get("content") or ""
        elif tag == "h1":
            self.h1 = True
        elif tag == "a" and "nofollow" not in attrs.get("rel", "").split():
            if attrs.get("href"):
                self.links.append(attrs["href"])

    def handle_endtag(self, tag):
        if tag == "head":
            self.in_head = False
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title += data


def matches(pattern, path):
    # The site's Hosting rules use exact paths and ordinary * / ** globs.
    require(not re.search(r"[{}()!@+:]", pattern),
            f"Unsupported Hosting pattern {pattern!r}; extend the SEO checker before using it")
    return fnmatchcase(path.lstrip("/"), pattern.lstrip("/"))


def check_robots(text, urls):
    # Literal-prefix rules with Google's group merging, longest-match priority,
    # and allow-on-tie behavior. Refuse unsupported syntax rather than give a
    # false pass (stdlib robotparser instead uses the first matching rule).
    groups, agents, rules, sitemaps = [], [], [], []
    has_rules = False
    for line in text.lstrip("\ufeff").splitlines():
        field, _, value = line.split("#", 1)[0].partition(":")
        field, value = field.strip().lower(), value.strip()
        if field == "user-agent":
            if has_rules:
                groups.append((agents, rules))
                agents, rules, has_rules = [], [], False
            agents.append(value.lower())
        elif field in ("allow", "disallow") and agents:
            has_rules = True
            require(not re.search(r"[*$%]", value),
                    "Wildcard/encoded robots rules need a matching parser before deployment")
            if value:
                require(value.startswith("/"), f"Invalid robots path: {value}")
                rules.append((value, field == "allow"))
        elif field == "sitemap":
            sitemaps.append(value)
    groups.append((agents, rules))
    selected = [rules for agents, rules in groups if "googlebot" in agents]
    if not selected:
        selected = [rules for agents, rules in groups if "*" in agents]
    rules = [rule for group in selected for rule in group]
    require(ORIGIN + "/sitemap.xml" in sitemaps,
            "robots.txt must advertise the canonical sitemap")
    for url in urls:
        path = urlsplit(url).path
        applicable = [(len(prefix), allow) for prefix, allow in rules if path.startswith(prefix)]
        require(not applicable or max(applicable)[1], f"robots.txt blocks {url}")


class Site:
    def __init__(self, root=SITE):
        self.root = Path(root).resolve()
        self.hosting = json.loads((self.root / "firebase.json").read_text())["hosting"]
        require(self.hosting.get("public") == ".", "SEO checker expects site/ as the Hosting public directory")
        require(self.hosting.get("cleanUrls") is True, "Hosting cleanUrls must be true")
        require(self.hosting.get("trailingSlash") is False, "Hosting trailingSlash must be false")
        self.pages = {}
        self.sources = {}
        self.alternates = {}
        for source in sorted(self.root.rglob("*.html")):
            if not self.published(source):
                continue
            page = Page(source.read_text(encoding="utf-8"))
            if re.search(r"\b(?:noindex|none)\b", page.robots, re.I):
                continue
            label = str(source.relative_to(self.root))
            require(len(page.canonicals) == 1, f"{label}: expected one canonical in <head>")
            url = page.canonicals[0]
            parsed = urlsplit(url)
            require(parsed.scheme == "https" and parsed.netloc == "dart-pdf.com"
                    and not parsed.query and not parsed.fragment
                    and re.fullmatch(r"/(?:[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)?", parsed.path),
                    f"{label}: invalid canonical {url!r}")
            require(url not in self.pages, f"Duplicate canonical: {url}")
            require(not blocked(page.robots), f"{label}: robots meta blocks crawling/indexing")
            require(page.title.strip() and page.description.strip() and page.h1,
                    f"{label}: missing title, description, or H1")
            self.pages[url] = page
            self.sources[url] = source
        require(ORIGIN + "/" in self.pages, "The homepage must be indexable")
        self.check_routes()
        self.check_links()
        check_robots((self.root / "robots.txt").read_text(), self.pages)

    def published(self, path):
        relative = path.relative_to(self.root)
        if any(part.startswith(".") for part in relative.parts):
            return False
        return not any(matches(pattern, relative.as_posix())
                       for pattern in self.hosting.get("ignore", []))

    def redirect(self, path):
        return next((rule for rule in self.hosting.get("redirects", [])
                     if matches(rule["source"], path)), None)

    def check_redirect(self, path, url, required=False):
        rule = self.redirect(path)
        require(rule is not None or not required, f"Add a direct permanent redirect: {path} -> {url}")
        if rule:
            require(rule["type"] in (301, 308)
                    and urljoin(ORIGIN, rule["destination"]) == url,
                    f"{path}: redirect must go directly to {url}")
        self.alternates[path] = url

    def check_routes(self):
        for url, source in self.sources.items():
            path = urlsplit(url).path
            require(self.redirect(path) is None, f"Canonical URL redirects: {url}")
            for rule in self.hosting.get("headers", []):
                if matches(rule["source"], path):
                    for header in rule["headers"]:
                        require(header["key"].lower() != "x-robots-tag" or not blocked(header["value"]),
                                f"Hosting X-Robots-Tag blocks {url}")
            native = self.root / ("index.html" if path == "/" else path.lstrip("/") + ".html")
            if native.is_file():
                target = native
            else:
                rewrite = next((rule for rule in self.hosting.get("rewrites", [])
                                if matches(rule["source"], path)), {})
                target = self.root / rewrite.get("destination", "").lstrip("/")
            require(target.resolve() == source and self.published(source), f"Canonical route does not serve {source.name}: {url}")
            native_path = "/" + source.relative_to(self.root).with_suffix("").as_posix()
            if path == "/":
                self.check_redirect("/index", url)
                self.check_redirect("/index.html", url)
            else:
                # Rewritten routes do not get Hosting's automatic slash redirect.
                self.check_redirect(path + "/", url, required=not native.is_file())
                self.check_redirect(native_path + ".html", url, required=native_path != path)
                if native_path != path:
                    self.check_redirect(native_path, url, required=True)
                    self.check_redirect(native_path + "/", url, required=True)

    def check_links(self):
        edges = {}
        for url, page in self.pages.items():
            edges[url] = set()
            for href in page.links:
                target = urlsplit(urljoin(url, href))
                if target.hostname not in ("dart-pdf.com", "www.dart-pdf.com"):
                    continue
                require(target.scheme == "https" and target.netloc == "dart-pdf.com",
                        f"{url}: link uses a noncanonical host/scheme: {href}")
                linked = ORIGIN + target.path
                if linked in self.pages:
                    edges[url].add(linked)
                else:
                    path = (self.root / target.path.lstrip("/")).resolve()
                    require(path.is_relative_to(self.root) and path.is_file()
                            and path.suffix.lower() != ".html" and self.published(path),
                            f"{url}: broken or noncanonical internal link: {href}")
        seen = set()
        queue = [ORIGIN + "/"]
        while queue:
            url = queue.pop()
            if url not in seen:
                seen.add(url)
                queue.extend(edges[url] - seen)
        require(seen == set(self.pages), "Pages have no crawlable path from home: " + ", ".join(sorted(set(self.pages) - seen)))

    def sitemap(self, now=None):
        repo = self.root.parent
        shallow = subprocess.check_output(["git", "rev-parse", "--is-shallow-repository"], cwd=repo, text=True).strip()
        require(shallow == "false", "Sitemap dates require full Git history (checkout fetch-depth: 0)")
        now = now or datetime.now(timezone.utc)
        ET.register_namespace("", NAMESPACE)
        root = ET.Element(f"{{{NAMESPACE}}}urlset")
        for url, source in sorted(self.sources.items()):
            relative = source.relative_to(repo).as_posix()
            dirty = subprocess.check_output(["git", "status", "--porcelain", "--", relative], cwd=repo, text=True)
            require(not dirty, f"Commit {relative} before generating its sitemap date")
            timestamp = subprocess.check_output(["git", "log", "-1", "--format=%cI", "--", relative], cwd=repo, text=True).strip()
            require(timestamp, f"No committed Git date for {relative}")
            # Python 3.9 (the macOS system Python) does not accept a UTC "Z".
            committed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            require(committed <= now, f"Future Git timestamp for {relative}: {timestamp}")
            modified = committed.date().isoformat()
            entry = ET.SubElement(root, f"{{{NAMESPACE}}}url")
            ET.SubElement(entry, f"{{{NAMESPACE}}}loc").text = url
            ET.SubElement(entry, f"{{{NAMESPACE}}}lastmod").text = modified
        ET.indent(root, space="  ")
        return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def sitemap_entries(data):
    root = ET.fromstring(data)
    require(root.tag == f"{{{NAMESPACE}}}urlset", "Invalid sitemap namespace/root")
    entries = {}
    for entry in root:
        url = entry.findtext(f"{{{NAMESPACE}}}loc")
        modified = entry.findtext(f"{{{NAMESPACE}}}lastmod")
        require(url and url not in entries and modified, f"Invalid or duplicate sitemap entry: {url}")
        date.fromisoformat(modified)
        entries[url] = modified
    return entries


@dataclass
class Response:
    status: int
    headers: dict
    body: bytes


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def fetch(url):
    opener = build_opener(NoRedirect)
    try:
        response = opener.open(Request(url, headers={"User-Agent": "DartPDF-SEO-check"}), timeout=20)
    except HTTPError as error:
        response = error
    with response:
        return Response(response.status, {key.lower(): value for key, value in response.headers.items()}, response.read())


def check_live(site, expected_sitemap, get=fetch):
    sitemap = get(ORIGIN + "/sitemap.xml")
    require(sitemap.status == 200 and sitemap_entries(sitemap.body) == sitemap_entries(expected_sitemap),
            "Live sitemap does not match the generated sitemap")
    robots = get(ORIGIN + "/robots.txt")
    require(robots.status == 200, "Live robots.txt is not HTTP 200")
    check_robots(robots.body.decode("utf-8"), site.pages)

    def check(url):
        response = get(url)
        require(response.status == 200, f"Canonical page is not HTTP 200: {url} ({response.status})")
        page = Page(response.body.decode("utf-8"))
        require(page.canonicals == [url], f"Live canonical mismatch: {url}")
        require(page.title.strip() and page.description.strip() and page.h1,
                f"Live page is missing title, description, or H1: {url}")
        require(not blocked(page.robots + " " + response.headers.get("x-robots-tag", "")),
                f"Live page blocks indexing: {url}")
        # A cached pre-deploy guide can have the right canonical but lack its new links.
        require(set(page.links) == set(site.pages[url].links), f"Live internal links differ from source: {url}")
        return url

    with ThreadPoolExecutor(max_workers=4) as executor:
        for url in executor.map(check, site.pages):
            print(f"[ok] {url}")
    for path, target in site.alternates.items():
        response = get(ORIGIN + path)
        require(response.status in (301, 308) and urljoin(ORIGIN + path, response.headers.get("location", "")) == target,
                f"Live URL variant must redirect directly to {target}: {path} ({response.status})")
    for path in ("/__seo-check-missing-page__", "/firebase-debug.log"):
        require(get(ORIGIN + path).status == 404, f"Expected a real HTTP 404: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-sitemap", action="store_true", help="Regenerate sitemap.xml from canonical pages and their Git dates")
    parser.add_argument("--live", action="store_true", help="Also verify deployed HTTP responses, robots, sitemap, links, and redirects")
    args = parser.parse_args()
    try:
        site = Site()
        expected = site.sitemap()
        path = site.root / "sitemap.xml"
        if args.write_sitemap:
            path.write_bytes(expected)
        else:
            require(path.exists() and sitemap_entries(path.read_bytes()) == sitemap_entries(expected),
                    "sitemap.xml is stale; run python3 tool/site/seo.py --write-sitemap")
        print(f"[ok] {len(site.pages)} canonical pages: routes, metadata, links, robots, and sitemap")
        if args.live:
            for attempt in range(3):
                try:
                    check_live(site, expected)
                    break
                except (SeoError, OSError, ValueError, ET.ParseError) as error:
                    if attempt == 2:
                        raise
                    print(f"[retry] Waiting for Hosting propagation: {error}", flush=True)
                    time.sleep(5)
            print("[ok] Deployed crawlability and URL variants")
    except (SeoError, OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"[fail] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
