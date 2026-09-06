import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("site_builder", Path(__file__).resolve().parents[1] / "script/build_site.py")
site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(site)


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.url = site.REPO_URL + "/releases/download/v0.3.0/TableViewer-0.3.0-macOS-arm64.dmg"
        self.release = {"tag_name": "v0.3.0", "assets": [{"name": "appcast.xml", "state": "uploaded", "browser_download_url": site.REPO_URL + "/releases/download/v0.3.0/appcast.xml", "size": 200},
            {"name": "TableViewer-0.3.0-macOS-arm64.dmg", "state": "uploaded", "browser_download_url": self.url, "size": 100}]}
        self.feed = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>4</sparkle:version><sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
        <enclosure url="{self.url}" length="100" sparkle:edSignature="fixture-signature" />
        </item></channel></rss>'''.encode()

    def test_preserves_signed_metadata(self):
        # Cryptographic archive validation is performed by Sparkle, not this site builder.
        self.assertEqual(site.update_feed(self.release, self.feed), self.feed)

    def test_legacy_release_has_empty_feed(self):
        self.release["assets"] = self.release["assets"][1:]
        self.assertEqual(site.ET.fromstring(site.update_feed(self.release, None)).findall("./channel/item"), [])

    def test_advertised_missing_feed_is_not_silently_erased(self):
        with self.assertRaises(ValueError): site.update_feed(self.release, None)

    def test_wrong_release_version(self):
        with self.assertRaises(ValueError): site.update_feed(self.release, self.feed.replace(b"0.3.0</", b"0.4.0</"))

    def test_wrong_download_size(self):
        with self.assertRaises(ValueError): site.update_feed(self.release, self.feed.replace(b'length="100"', b'length="99"'))

    def test_unsigned_archive(self):
        with self.assertRaises(ValueError): site.update_feed(self.release, self.feed.replace(b'sparkle:edSignature="fixture-signature"', b""))

    def test_other_repository_cannot_supply_archive(self):
        release = copy.deepcopy(self.release)
        foreign = "https://github.com/other/repository/releases/download/v0.3.0/app.dmg"
        release["assets"][1]["browser_download_url"] = foreign
        with self.assertRaises(ValueError): site.update_feed(release, self.feed.replace(self.url.encode(), foreign.encode()))

    def test_empty_or_malformed_published_feed(self):
        for feed in [b"<rss><channel/></rss>", b"<rss>", b"<rss><channel><item/></channel></rss>"]:
            with self.assertRaises((ValueError, site.ET.ParseError)): site.update_feed(self.release, feed)


if __name__ == "__main__":
    unittest.main()
