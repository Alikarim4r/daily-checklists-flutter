#!/usr/bin/env python3
"""Record verified native downloads, preserving legacy macOS bytes only from Pages."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = {"entry": "Entry", "viewer": "Viewer", "admin": "Admin"}


def version():
    versions = {
        re.search(r"^version:\s*(\S+)", (ROOT / f"apps/checklist_{app}/pubspec.yaml").read_text(), re.M)[1]
        for app in PRODUCTS
    }
    if len(versions) != 1:
        raise ValueError("Flutter app versions disagree")
    return versions.pop()


def location(platform, app):
    filename = (f"inspection-{app}.apk" if platform == "android"
                else f"Inspection-{PRODUCTS[app]}-macOS.zip")
    return f"downloads/{platform}/{filename}"


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preserve = commands.add_parser("preserve-macos")
    preserve.add_argument("--git-ref", default="origin/gh-pages")
    preserve.add_argument("--directory", type=Path, default=ROOT / "dist/legacy-macos")
    initialize = commands.add_parser("init")
    initialize.add_argument("output", type=Path)
    record = commands.add_parser("record")
    record.add_argument("output", type=Path)
    record.add_argument("platform", choices=["android", "macos"])
    record.add_argument("app", choices=PRODUCTS)
    restore = commands.add_parser("restore-macos")
    restore.add_argument("output", type=Path)
    restore.add_argument("--directory", type=Path, default=ROOT / "dist/legacy-macos")
    args = parser.parse_args()

    if args.command == "preserve-macos":
        # A remote-tracking ref is mandatory: arbitrary local build directories
        # are not evidence that a package was previously published.
        if not args.git_ref.startswith("origin/"):
            raise ValueError("Legacy source must be a verified origin/* Pages ref")
        commit = subprocess.check_output(["git", "rev-parse", args.git_ref], cwd=ROOT, text=True).strip()
        files = set(subprocess.check_output(["git", "ls-tree", "-r", "--name-only", commit], cwd=ROOT, text=True).splitlines())
        records = {}
        for app, product in PRODUCTS.items():
            relative = location("macos", app)
            if relative not in files:
                continue
            data = subprocess.check_output(["git", "show", f"{commit}:{relative}"], cwd=ROOT)
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                info = plistlib.loads(archive.read(f"Inspection{product}.app/Contents/Info.plist"))
            actual = f"{info['CFBundleShortVersionString']}+{info['CFBundleVersion']}"
            if not re.fullmatch(r"[0-9][0-9A-Za-z.-]*\+[0-9]+", actual):
                raise ValueError(f"Invalid legacy package version for {app}")
            destination = args.directory / Path(relative).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            records[f"macos-{app}"] = {
                "platform": "macos", "app": app, "path": relative,
                "status": "legacy", "version": actual,
                "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                "verification": "previously-published-not-revalidated",
                "sourceCommit": commit,
            }
        write_json(args.directory / "preserved.json", records)
        print(f"Preserved {len(records)} macOS downloads from {commit}; absent packages remain unavailable.")
        return

    manifest_path = args.output / "downloads/release-manifest.json"
    if args.command == "init":
        manifest = {"schemaVersion": 1, "webVersion": version(), "artifacts": {}}
        for platform in ("android", "macos"):
            for app in PRODUCTS:
                manifest["artifacts"][f"{platform}-{app}"] = {
                    "platform": platform, "app": app, "path": location(platform, app),
                    "status": "unavailable", "version": None,
                    "reason": "Verified distribution package not available",
                }
    else:
        manifest = read_json(manifest_path)
        if args.command == "record":
            relative = location(args.platform, args.app)
            data = (args.output / relative).read_bytes()
            manifest["artifacts"][f"{args.platform}-{args.app}"] = {
                "platform": args.platform, "app": args.app, "path": relative,
                "status": "current", "version": version(),
                "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
                "verification": ("android-release-signature" if args.platform == "android"
                                 else "developer-id-and-stapled-notarization"),
            }
        else:
            for key, record in read_json(args.directory / "preserved.json").items():
                if manifest["artifacts"][key]["status"] == "current":
                    continue
                source = args.directory / Path(record["path"]).name
                if hashlib.sha256(source.read_bytes()).hexdigest() != record["sha256"]:
                    raise ValueError(f"Preserved package changed: {source.name}")
                shutil.copy2(source, args.output / record["path"])
                manifest["artifacts"][key] = record
    write_json(manifest_path, manifest)


if __name__ == "__main__":
    main()
