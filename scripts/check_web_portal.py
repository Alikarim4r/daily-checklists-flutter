#!/usr/bin/env python3
"""Validate local portal links and release-state invariants."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "web_portal"
errors: list[str] = []
APP_PUBSPECS = {
    "entry": ROOT / "apps/checklist_entry/pubspec.yaml",
    "viewer": ROOT / "apps/checklist_viewer/pubspec.yaml",
    "admin": ROOT / "apps/checklist_admin/pubspec.yaml",
}


def read_app_version(path: Path) -> str | None:
    """Read the Flutter package version without adding a YAML dependency."""
    match = re.search(
        r"^version:\s*([^\s#]+)",
        path.read_text(encoding="utf-8"),
        flags=re.MULTILINE,
    )
    if not match:
        errors.append(f"{path.relative_to(ROOT)} has no package version")
        return None
    return match.group(1)


app_versions = {
    app: version
    for app, path in APP_PUBSPECS.items()
    if (version := read_app_version(path)) is not None
}
release_version: str | None = None
cache_bust: str | None = None
release_display: str | None = None
if len(app_versions) == len(APP_PUBSPECS):
    unique_versions = set(app_versions.values())
    if len(unique_versions) != 1:
        details = ", ".join(
            f"{app}={version}" for app, version in sorted(app_versions.items())
        )
        errors.append(f"Flutter app versions must match: {details}")
    else:
        release_version = unique_versions.pop()
        match = re.fullmatch(r"([^+]+)\+([0-9]+)", release_version)
        if not match:
            errors.append(
                f"Flutter release version must use name+numeric-build: {release_version}"
            )
        else:
            release_name, release_build = match.groups()
            # A hyphen is stable in query strings; unlike '+', it cannot be
            # decoded as a space by intermediaries.
            cache_bust = f"{release_name}-{release_build}"
            release_display = f"{release_name} ({release_build})"


class PortalParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.references: list[str] = []
        self.artifact_links: list[dict[str, str | None]] = []
        self.footer_targets: set[str] = set()

    def handle_starttag(
        self, tag: str, attrs_list: list[tuple[str, str | None]]
    ) -> None:
        attrs = dict(attrs_list)
        for key in ("href", "src"):
            if value := attrs.get(key):
                self.references.append(value)
        if tag == "a" and attrs.get("data-artifact"):
            self.artifact_links.append(attrs)
        if tag == "a" and attrs.get("href") in (
            "./privacy.html",
            "./support.html",
        ):
            self.footer_targets.add(attrs["href"] or "")


html_paths = sorted(PORTAL.glob("*.html"))
if not html_paths:
    errors.append("Portal has no HTML pages")

for path in html_paths:
    parser = PortalParser()
    content = path.read_text(encoding="utf-8")
    parser.feed(content)
    parser.close()

    required_footer = {"./privacy.html", "./support.html"}
    if not required_footer.issubset(parser.footer_targets):
        errors.append(f"{path.name} is missing privacy/support footer links")

    for reference in parser.references:
        parsed = urlsplit(reference)
        if parsed.scheme or reference.startswith(("#", "//")):
            continue
        clean = parsed.path
        is_release_resource = (
            clean.endswith((".css", ".js", ".png", ".apk", ".zip"))
            or clean.startswith(("./entry/", "./viewer/", "./admin/"))
        )
        if cache_bust and is_release_resource:
            versions = parse_qs(parsed.query, keep_blank_values=True).get("v", [])
            if versions != [cache_bust]:
                errors.append(
                    f"{path.name} must cache-bust {reference} with v={cache_bust}"
                )
        if clean in ("", "./", "/"):
            target = PORTAL / "index.html"
        elif clean.startswith(("./entry/", "./viewer/", "./admin/")):
            continue
        elif clean.startswith("./downloads/"):
            continue
        else:
            target = path.parent / clean
        if not target.exists():
            errors.append(f"{path.name} references missing local file: {reference}")

    if path.name == "downloads.html":
        if len(parser.artifact_links) != 6:
            errors.append("downloads.html must contain six signed artifact links")
        for attrs in parser.artifact_links:
            classes = (attrs.get("class") or "").split()
            if attrs.get("aria-disabled") != "true" or "is-disabled" not in classes:
                errors.append("Signed artifact links must fail closed until detected")

portal_script = (PORTAL / "portal.js").read_text(encoding="utf-8")
if "updateDownloadAvailability" not in portal_script:
    errors.append("Portal does not detect signed artifact availability")
if "Trial login is available" in portal_script or "الوضع التجريبي متاح" in portal_script:
    errors.append("Portal still advertises disabled demo login")
if release_display and portal_script.count(release_display) < 2:
    errors.append(
        "portal.js release labels must match the shared Flutter version "
        f"{release_version} in Arabic and English"
    )
downloads_content = (PORTAL / "downloads.html").read_text(encoding="utf-8")
if release_display and release_display not in downloads_content:
    errors.append(
        f"downloads.html fallback release label must match {release_version}"
    )

if errors:
    print("Portal checks failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(
    f"Validated {len(html_paths)} portal pages, release {release_version}, "
    "cache-busts, and signed-download guards."
)
