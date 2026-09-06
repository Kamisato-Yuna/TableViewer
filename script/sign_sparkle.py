#!/usr/bin/env python3
"""Re-sign Sparkle's nested installer code for the existing Developer ID workflow."""
import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("identity")
    args = parser.parse_args()
    framework = args.app / "Contents/Frameworks/Sparkle.framework"
    version = framework / "Versions/B"
    options = ["--timestamp", "--options", "runtime"] if args.identity != "-" else []
    for path in [version / "XPCServices/Installer.xpc", version / "XPCServices/Downloader.xpc",
                 version / "Autoupdate", version / "Updater.app", framework, args.app]:
        subprocess.run(["codesign", "--force", "--sign", args.identity, *options,
                        "--preserve-metadata=entitlements", str(path)], check=True)


if __name__ == "__main__":
    main()
