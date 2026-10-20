"""Regression fixtures for failures that must stop a marketing-site deployment."""

import json
import os
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import tempfile
import unittest

import seo


def html(path, links="", robots="", canonical=None):
    url = canonical if canonical is not None else seo.ORIGIN + path
    return (f'<html><head><title>{path}</title><meta name="description" content="A page">'
            f'<link rel="canonical" href="{url}"><meta name="robots" content="{robots}">'
            f'</head><body><h1>A page</h1>{links}</body></html>')


class SeoTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.root = self.repo / "site"
        self.root.mkdir()
        self.hosting = {"public": ".", "cleanUrls": True, "trailingSlash": False,
                        "ignore": ["**/.*", "firebase-debug*.log"], "redirects": [], "rewrites": []}
        self.config()
        self.write("index.html", html("/", '<a href="/guide">Guide</a>'))
        self.write("guide.html", html("/guide", '<a href="/">Home</a>'))
        self.write("404.html", '<head><meta name="robots" content="noindex"></head>')
        self.write("robots.txt", f"User-agent: *\nAllow: /\nSitemap: {seo.ORIGIN}/sitemap.xml\n")
        self.git("init", "-q")
        self.git("config", "user.name", "SEO fixture")
        self.git("config", "user.email", "seo@example.invalid")
        self.commit("2020-03-01")

    def git(self, *args, env=None):
        return subprocess.check_output(["git", *args], cwd=self.repo, text=True, env=env, stderr=subprocess.STDOUT)

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def config(self):
        self.write("firebase.json", json.dumps({"hosting": self.hosting}))

    def commit(self, day):
        self.git("add", ".")
        timestamp = day + "T12:00:00+00:00" if len(day) == 10 else day
        env = dict(os.environ, GIT_AUTHOR_DATE=timestamp, GIT_COMMITTER_DATE=timestamp)
        self.git("commit", "-qm", "Fixture", env=env)

    def test_new_linked_page_is_added_automatically_and_noindex_is_excluded(self):
        self.write("index.html", html("/", '<a href="/guide">Guide</a><a href="/new">New</a>'))
        self.write("new.html", html("/new"))
        self.commit("2020-04-02")
        entries = seo.sitemap_entries(seo.Site(self.root).sitemap())
        self.assertEqual(entries, {seo.ORIGIN + "/": "2020-04-02",
                                   seo.ORIGIN + "/guide": "2020-03-01",
                                   seo.ORIGIN + "/new": "2020-04-02"})

    def test_unrelated_commit_does_not_make_all_page_dates_new(self):
        (self.repo / "README.md").write_text("Unrelated change")
        self.commit("2020-05-03")
        self.assertEqual(set(seo.sitemap_entries(seo.Site(self.root).sitemap()).values()), {"2020-03-01"})

    def test_local_commit_date_ahead_of_utc_is_not_a_future_timestamp(self):
        self.write("guide.html", html("/guide", "Updated"))
        self.commit("2020-03-02T09:00:00+14:00")
        now = datetime(2020, 3, 1, 20, tzinfo=timezone.utc)
        entries = seo.sitemap_entries(seo.Site(self.root).sitemap(now=now))
        self.assertEqual(entries[seo.ORIGIN + "/guide"], "2020-03-02")

    def test_shallow_checkout_cannot_generate_incomplete_dates(self):
        shallow = self.repo / "shallow"
        self.git("clone", "--depth", "1", self.repo.as_uri(), str(shallow))
        with self.assertRaisesRegex(seo.SeoError, "full Git history"):
            seo.Site(shallow / "site").sitemap()

    def test_uncommitted_content_cannot_publish_an_old_git_date(self):
        self.write("guide.html", html("/guide", "New content"))
        with self.assertRaisesRegex(seo.SeoError, "Commit site/guide.html"):
            seo.Site(self.root).sitemap()

    def test_orphan_page_stops_deployment(self):
        self.write("orphan.html", html("/orphan"))
        with self.assertRaisesRegex(seo.SeoError, "no crawlable path.*orphan"):
            seo.Site(self.root)

    def test_nofollow_link_does_not_make_an_orphan_discoverable(self):
        self.write("index.html", html("/", '<a href="/guide" rel="nofollow">Guide</a>'))
        with self.assertRaisesRegex(seo.SeoError, "no crawlable path"):
            seo.Site(self.root)

    def test_invalid_and_duplicate_canonicals_stop_deployment(self):
        for canonical in (seo.ORIGIN + "/", "https://www.dart-pdf.com/guide",
                          seo.ORIGIN + "/guide/", seo.ORIGIN + "/guide?lang=en"):
            with self.subTest(canonical=canonical):
                self.write("guide.html", html("/guide", canonical=canonical))
                with self.assertRaises(seo.SeoError):
                    seo.Site(self.root)

    def test_missing_canonical_stops_deployment(self):
        self.write("guide.html", '<head><title>Guide</title></head><h1>Guide</h1>')
        with self.assertRaisesRegex(seo.SeoError, "expected one canonical"):
            seo.Site(self.root)

    def test_html_alias_and_missing_internal_links_stop_deployment(self):
        for href in ("/guide.html", "/missing", "http://dart-pdf.com/guide"):
            with self.subTest(href=href):
                self.write("index.html", html("/", f'<a href="{href}">Guide</a>'))
                with self.assertRaises(seo.SeoError):
                    seo.Site(self.root)

    def test_canonical_redirect_and_noindex_header_stop_deployment(self):
        self.hosting["redirects"] = [{"source": "/guide", "destination": "/", "type": 301}]
        self.config()
        with self.assertRaisesRegex(seo.SeoError, "Canonical URL redirects"):
            seo.Site(self.root)
        self.hosting["redirects"] = []
        self.hosting["headers"] = [{"source": "**", "headers": [{"key": "X-Robots-Tag", "value": "noindex"}]}]
        self.config()
        with self.assertRaisesRegex(seo.SeoError, "X-Robots-Tag blocks"):
            seo.Site(self.root)

    def test_robots_block_and_missing_sitemap_advertisement_stop_deployment(self):
        for text in (f"User-agent: *\nDisallow: /guide\nSitemap: {seo.ORIGIN}/sitemap.xml\n",
                     "User-agent: *\nAllow: /\n"):
            with self.subTest(text=text):
                self.write("robots.txt", text)
                with self.assertRaises(seo.SeoError):
                    seo.Site(self.root)

    def test_robots_uses_google_longest_match_and_merged_specific_groups(self):
        sitemap = f"Sitemap: {seo.ORIGIN}/sitemap.xml\n"
        for rules in ("User-agent: *\nAllow: /\nDisallow: /guide\n",
                      "User-agent: *\nAllow: /\nUser-agent: Googlebot\nAllow: /\n"
                      "User-agent: Googlebot\nDisallow: /guide\n"):
            with self.subTest(rules=rules):
                with self.assertRaisesRegex(seo.SeoError, "blocks.*guide"):
                    seo.check_robots(rules + sitemap, [seo.ORIGIN + "/guide"])
        for rules in ("User-agent: *\nDisallow: /\nAllow: /guide\n",
                      "User-agent: *\nDisallow: /guide\nAllow: /guide\n",
                      "User-agent: *\nDisallow: /\nUser-agent: Googlebot\nAllow: /\n"):
            with self.subTest(rules=rules):
                seo.check_robots(rules + sitemap, [seo.ORIGIN + "/guide"])

    def test_unsupported_robots_syntax_cannot_silently_pass(self):
        with self.assertRaisesRegex(seo.SeoError, "matching parser"):
            seo.check_robots(f"User-agent: *\nDisallow: /*guide\nSitemap: {seo.ORIGIN}/sitemap.xml\n",
                             [seo.ORIGIN + "/guide"])

    def test_rewritten_route_requires_direct_slash_and_legacy_redirects(self):
        (self.root / "guide.html").rename(self.root / "sdk.html")
        self.hosting["rewrites"] = [{"source": "/guide", "destination": "/sdk.html"}]
        self.config()
        with self.assertRaisesRegex(seo.SeoError, "/guide/"):
            seo.Site(self.root)
        self.hosting["redirects"] = [{"source": path, "destination": "/guide", "type": 301}
                                    for path in ("/guide/", "/sdk", "/sdk/", "/sdk.html")]
        self.config()
        seo.Site(self.root)
        self.hosting["redirects"][-1]["destination"] = "/sdk"
        self.config()
        with self.assertRaisesRegex(seo.SeoError, "directly"):
            seo.Site(self.root)

    def live_responses(self, site):
        responses = {seo.ORIGIN + "/sitemap.xml": seo.Response(200, {}, site.sitemap()),
                     seo.ORIGIN + "/robots.txt": seo.Response(200, {}, (self.root / "robots.txt").read_bytes())}
        responses.update({url: seo.Response(200, {}, source.read_bytes()) for url, source in site.sources.items()})
        responses.update({seo.ORIGIN + path: seo.Response(301, {"location": url}, b"")
                          for path, url in site.alternates.items()})
        for path in ("/__seo-check-missing-page__", "/firebase-debug.log"):
            responses[seo.ORIGIN + path] = seo.Response(404, {}, b"")
        return responses

    def test_live_soft_404_and_hidden_noindex_header_are_detected(self):
        site = seo.Site(self.root)
        responses = self.live_responses(site)
        seo.check_live(site, site.sitemap(), get=responses.__getitem__)
        responses[seo.ORIGIN + "/guide"].headers["x-robots-tag"] = "noindex"
        with self.assertRaisesRegex(seo.SeoError, "blocks indexing"):
            seo.check_live(site, site.sitemap(), get=responses.__getitem__)
        responses = self.live_responses(site)
        responses[seo.ORIGIN + "/__seo-check-missing-page__"].status = 200
        with self.assertRaisesRegex(seo.SeoError, "real HTTP 404"):
            seo.check_live(site, site.sitemap(), get=responses.__getitem__)

    def test_live_stale_sitemap_and_multihop_redirect_are_detected(self):
        site = seo.Site(self.root)
        responses = self.live_responses(site)
        responses[seo.ORIGIN + "/sitemap.xml"].body = responses[seo.ORIGIN + "/sitemap.xml"].body.replace(b"2020-03-01", b"2020-02-01")
        with self.assertRaisesRegex(seo.SeoError, "Live sitemap"):
            seo.check_live(site, site.sitemap(), get=responses.__getitem__)
        responses = self.live_responses(site)
        responses[seo.ORIGIN + "/guide/"].headers["location"] = "/guide.html"
        with self.assertRaisesRegex(seo.SeoError, "redirect directly"):
            seo.check_live(site, site.sitemap(), get=responses.__getitem__)


if __name__ == "__main__":
    unittest.main()
