#!/usr/bin/env python3
"""Validate local portal links and release-state invariants."""

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import sys


ROOT = Path(__file__).resolve().parents[1]
PORTAL = ROOT / "web_portal"
errors: list[str] = []


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

if errors:
    print("Portal checks failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"Validated {len(html_paths)} portal pages and signed-download guards.")
