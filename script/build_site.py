#!/usr/bin/env python3
"""Build the dependency-free Pages site from a GitHub release JSON response."""
import argparse
import html
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
REPO_URL = "https://github.com/Kamisato-Yuna/TableViewer"


def release_values(release):
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Pages downloads must use a published stable release")
    asset = next((asset for asset in release["assets"]
                  if re.fullmatch(r"TableViewer-[\w.+-]+-macOS-arm64\.zip", asset["name"])
                  and asset.get("state") == "uploaded"), None)
    if not asset:
        raise ValueError("The release does not contain a published macOS arm64 ZIP")
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
    args = parser.parse_args()
    values = release_values(json.loads(args.release_json.read_text()))
    template = (ROOT / "site/index.html").read_text()
    expected = set(re.findall(r"\{\{([A-Z_]+)\}\}", template))
    if expected - values.keys():
        raise ValueError(f"Unknown template fields: {expected - values.keys()}")
    rendered = re.sub(r"\{\{([A-Z_]+)\}\}", lambda match: values[match[1]], template)
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ("styles.css", "app.js"):
        shutil.copy2(ROOT / "site" / name, args.output / name)
    shutil.copytree(ROOT / "site/assets", args.output / "assets", dirs_exist_ok=True)
    shutil.copy2(ROOT / "docs/screenshots/workspace-zh-Hans.png", args.output / "assets/workspace-zh-Hans.png")
    (args.output / "index.html").write_text(rendered)
    (args.output / ".nojekyll").touch()
    print(f'Built {values["VERSION"]} product page: {args.output}')


if __name__ == "__main__":
    main()
