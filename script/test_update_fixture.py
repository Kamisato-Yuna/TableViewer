#!/usr/bin/env python3
"""Prepare isolated, sandboxed native clients and serve signed update fixtures on localhost.

The initial feed intentionally points at a tampered archive. After verifying rejection,
copy feed/appcast-valid.xml to feed/appcast.xml and retry from the client. This uses the
real app/updater with a separate bundle ID; no production credential is read or exported.
"""
import argparse
import functools
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "dist/TableViewer.app")
    parser.add_argument("--identity", default="-")
    parser.add_argument("--automatic", action="store_true", help="Use a separate client with automatic checking/downloading enabled and a valid feed")
    args = parser.parse_args()
    os.umask(0o077)
    (ROOT / ".build").mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="update-e2e-", dir=ROOT / ".build"))
    feed = folder / "feed"; feed.mkdir()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(feed)))
    base = f"http://127.0.0.1:{server.server_port}"
    key = folder / "fixture.key"
    code = '''import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
'''
    public = run("xcrun", "swift", "-", key, input=code, text=True, capture_output=True).stdout.strip()
    identifier = "local.yuna.TableViewer.AutomaticUpdateFixture" if args.automatic else "local.yuna.TableViewer.UpdateFixture"
    entitlement = folder / "entitlements.plist"
    entitlements = plistlib.loads((ROOT / "TableViewer/Resources/TableViewer.entitlements").read_bytes())
    entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = [identifier + "-spks", identifier + "-spki"]
    entitlement.write_bytes(plistlib.dumps(entitlements))
    clients = []
    for kind, version, build in [("old", "0.2.99", "3"), ("new", "0.3.0", "4")]:
        app = folder / kind / "TableViewer Update Test.app"
        app.parent.mkdir()
        run("ditto", args.source, app)
        info = app / "Contents/Info.plist"
        settings = plistlib.loads(info.read_bytes())
        settings.update(CFBundleIdentifier=identifier, CFBundleName="TableViewer Update Test", CFBundleDisplayName="TableViewer Update Test",
                        CFBundleShortVersionString=version, CFBundleVersion=build, SUFeedURL=base + "/appcast.xml", SUPublicEDKey=public,
                        SUEnableAutomaticChecks=args.automatic, SUAutomaticallyUpdate=args.automatic,
                        NSAppTransportSecurity={"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True})
        info.write_bytes(plistlib.dumps(settings))
        options = ["--timestamp", "--options", "runtime"] if args.identity != "-" else []
        run("codesign", "--force", "--sign", args.identity, *options, "--entitlements", entitlement, app)
        run("codesign", "--verify", "--deep", "--strict", app)
        clients.append(app)
    archive = feed / "update.zip"
    run("ditto", "-c", "-k", "--keepParent", clients[1], archive)
    signer = ROOT / ".build/Xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    try:
        signature = run(signer, "--ed-key-file", key, "-p", archive, capture_output=True, text=True).stdout.strip()
        run(signer, "--verify", "--ed-key-file", key, archive, signature)
        tampered = feed / "tampered.zip"
        shutil.copy2(archive, tampered)
        with tampered.open("ab") as file: file.write(b"tampered-fixture")
        result = subprocess.run([str(signer), "--verify", "--ed-key-file", str(key), str(tampered), signature], capture_output=True)
        if result.returncode == 0: raise RuntimeError("Tampered archive unexpectedly passed verification")
        print("PASS: signed archive accepted; tampered archive rejected", flush=True)
    finally:
        key.unlink(missing_ok=True)
    namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", namespace)
    for name, asset in [("appcast-valid.xml", archive), ("appcast-bad.xml", tampered)]:
        rss = ET.Element("rss", version="2.0")
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "TableViewer isolated update test"
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = "0.3.0"
        ET.SubElement(item, f"{{{namespace}}}version").text = "4"
        ET.SubElement(item, f"{{{namespace}}}shortVersionString").text = "0.3.0"
        ET.SubElement(item, f"{{{namespace}}}minimumSystemVersion").text = "26.0"
        ET.SubElement(item, "enclosure", {"url": base + "/" + asset.name, "length": str(asset.stat().st_size), "type": "application/octet-stream", f"{{{namespace}}}edSignature": signature})
        ET.ElementTree(rss).write(feed / name, encoding="utf-8", xml_declaration=True)
    shutil.copy2(feed / ("appcast-valid.xml" if args.automatic else "appcast-bad.xml"), feed / "appcast.xml")
    print(f"Fixture directory: {folder}\nOld client: {clients[0]}\nFeed: {base}/appcast.xml", flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()


if __name__ == "__main__":
    main()
