#!/usr/bin/env python3
"""Build the dependency-free Pages site from a GitHub release JSON response."""
import argparse
import html
import json
from pathlib import Path
import re
import shutil
import sqlite3
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/Kamisato-Yuna/TableViewer"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def update_feed(release, appcast):
    """Publish the release's signed update metadata without rewriting its contents."""
    if appcast is None:
        if any(asset["name"] == "appcast.xml" for asset in release["assets"]):
            raise ValueError("Release advertises an appcast but it was not downloaded")
        # Releases predating the updater have no automatically installable update.
        return b'<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>TableViewer</title></channel></rss>\n'
    root = ET.fromstring(appcast)
    items = root.findall("./channel/item")
    if not items:
        raise ValueError("Published appcast has no update items")
    assets = {a["browser_download_url"]: a for a in release["assets"] if a.get("state") == "uploaded"}
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            raise ValueError("Appcast item is missing its archive")
        asset = assets.get(enclosure.get("url"))
        if asset is None or not enclosure.get("url", "").startswith(REPO_URL + "/releases/download/"):
            raise ValueError("Appcast archive must be an uploaded asset of this release")
        if not enclosure.get(SPARKLE + "edSignature") or int(enclosure.get("length", "0")) != asset["size"]:
            raise ValueError("Appcast archive signature or size is missing/inconsistent")
        if item.findtext(SPARKLE + "shortVersionString") != release["tag_name"].removeprefix("v"):
            raise ValueError("Appcast version does not match the release")
    return appcast


def demo_projects_json():
    """Use the app's Studio seed, without opening any user's database."""
    source = (ROOT / "TableViewer/Services/ConnectionVault.swift").read_text()
    sql = re.search(r'let sql = """\n(.*?)\n\s*"""', source, re.S).group(1)
    with sqlite3.connect(":memory:") as db:
        db.row_factory = sqlite3.Row
        db.executescript(sql)
        projects = [dict(row) for row in db.execute("SELECT * FROM projects ORDER BY id")]
    # JSON embedded in a script data block must not be able to close that block.
    return json.dumps(projects, ensure_ascii=False).replace("<", "\\u003c").replace("&", "\\u0026")


def release_values(release):
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Pages downloads must use a published stable release")
    asset = next((asset for asset in release["assets"]
                  if re.fullmatch(r"TableViewer-[\w.+-]+-macOS-arm64\.dmg", asset["name"])
                  and asset.get("state") == "uploaded"), None)
    if not asset:
        raise ValueError("The release does not contain a published macOS arm64 DMG")
    urls = [release["html_url"], asset["browser_download_url"]]
    for url in urls:
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.netloc != "github.com" or not url.startswith(REPO_URL + "/releases/"):
            raise ValueError("Release links must belong to this GitHub repository")
    # Treat release notes as plain text, never HTML. Keep the complete notes linked.
    bullets = [line[2:].strip() for line in release.get("body", "").splitlines()
               if line.startswith("- ")][:3]
    notes = "".join(f"<li>{html.escape(line)}</li>" for line in bullets)
    date = release["published_at"][:10]
    return {
        "VERSION": html.escape(release["tag_name"]),
        "DOWNLOAD_URL": html.escape(urls[1], quote=True),
        "RELEASE_URL": html.escape(urls[0], quote=True),
        "SIZE": f'{asset["size"] / 1024 / 1024:.1f} MB',
        "DATE_ISO": date,
        "DATE": date.replace("-", "."),
        "RELEASE_NAME": html.escape(release.get("name") or release["tag_name"]),
        "RELEASE_NOTES": notes or "<li>版本详情请参阅完整发布说明。</li>",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "_site")
    parser.add_argument("--appcast", type=Path)
    args = parser.parse_args()
    release = json.loads(args.release_json.read_text())
    values = release_values(release)
    feed = update_feed(release, args.appcast.read_bytes() if args.appcast else None)
    values["DEMO_PROJECTS"] = demo_projects_json()
    template = (ROOT / "site/index.html").read_text()
    expected = set(re.findall(r"\{\{([A-Z_]+)\}\}", template))
    if expected - values.keys():
        raise ValueError(f"Unknown template fields: {expected - values.keys()}")
    rendered = re.sub(r"\{\{([A-Z_]+)\}\}", lambda match: values[match[1]], template)
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ("styles.css", "app.js"):
        shutil.copy2(ROOT / "site" / name, args.output / name)
    shutil.copytree(ROOT / "site/assets", args.output / "assets", dirs_exist_ok=True)
    shutil.copy2(ROOT / "docs/screenshots/workspace-zh-Hans.png", args.output / "assets/workspace-dark-zh-Hans.png")
    shutil.copy2(ROOT / "docs/screenshots/workspace-light-zh-Hans.png", args.output / "assets/workspace-light-zh-Hans.png")
    (args.output / "index.html").write_text(rendered)
    (args.output / "appcast.xml").write_bytes(feed)
    (args.output / ".nojekyll").touch()
    print(f'Built {values["VERSION"]} product page: {args.output}')


if __name__ == "__main__":
    main()
