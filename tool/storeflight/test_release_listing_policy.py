"""Regression gate for release/listing separation; no store access or secrets."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseListingPolicyTest(unittest.TestCase):
    def test_production_release_preserves_live_listing(self):
        # The release workflows already require Ruby/YAML. Use its actual YAML
        # parser rather than treating indentation or comments as configuration.
        script = """
require 'json'
require 'yaml'
c = YAML.load_file(ARGV.fetch(0))
d = c.fetch('profiles').fetch('production').fetch('destinations')
puts JSON.generate({
  schema: c.fetch('schema'),
  apple_policy: d.fetch('apple')['release_listing_policy'],
  apple_test_guard: d.fetch('apple')['protect_product_page_tests'],
  play_policy: d.fetch('google_play')['release_listing_policy']
})
"""
        result = subprocess.run(
            ["ruby", "-e", script, str(ROOT / "storeflight.yaml")],
            check=True, capture_output=True, text=True,
        )
        config = json.loads(result.stdout)
        self.assertEqual(config, {
            "schema": 2,
            "apple_policy": "preserve",
            "apple_test_guard": True,
            "play_policy": "preserve",
        })


if __name__ == "__main__":
    unittest.main()
