#!/usr/bin/env python3
"""Publish one GitHub release from the aggregated build artifacts.

The release is created as a draft, every asset is attached, and only then is the
draft published. A failed or cancelled run therefore never leaves a public
release with a partial set of platform downloads.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

DIST = Path("dist")


class ReleaseError(RuntimeError):
    pass


def run(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, check=check, text=True, capture_output=True)


def declared_version() -> str:
    text = Path("pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", text, re.MULTILINE)
    if not match:
        raise ReleaseError("pubspec.yaml has no version with a build number.")
    return f"{match.group(1)}+{match.group(2)}"


def main() -> int:
    tag = os.environ.get("RELEASE_TAG", "").strip()
    if not tag.startswith("v"):
        raise ReleaseError("RELEASE_TAG must be a v* tag.")
    version = declared_version()
    if tag.lstrip("v") not in (version, version.split("+")[0]):
        raise ReleaseError(
            f"Tag {tag} does not match pubspec version {version}; bump pubspec before tagging."
        )

    # Debian packages follow `mindpocket_<version>_<arch>.deb`; everything else
    # uses the `MindPocket-<version>-...` scheme.
    prefixes = (f"MindPocket-{version}-", f"mindpocket_{version}_")
    assets = sorted(
        path
        for path in DIST.rglob("*")
        if path.is_file()
        and path.name.startswith(prefixes)
        and not path.name.endswith(".sha256")
    )
    empty = [path.name for path in assets if path.stat().st_size == 0]
    if empty:
        raise ReleaseError(f"Empty artifacts: {', '.join(empty)}")



    platforms = {
        "android": ("-android-",),
        "ios": ("-ios-",),
        "linux": ("-linux-",),
        "macos": ("-macos-",),
        "windows": ("-windows-",),
    }
    absent = [
        name
        for name, markers in platforms.items()
        if not any(marker in path.name for path in assets for marker in markers)
    ]
    if absent:
        raise ReleaseError(f"Missing platform artifacts: {', '.join(absent)}")

    notes = (
        f"MindPocket {version}\n\n"
        "Every artifact is named with the version declared in pubspec.yaml and was\n"
        "built by the same workflow run; SHA256SUMS lists their digests.\n\n"
    )
    notes += (
        "Windows ships the bundled Tesseract OCR runtime. Linux packages declare\n"
        "their system libraries (libmpv2, ffmpeg, pulseaudio-utils, tesseract-ocr)\n"
        "as Debian dependencies.\n\n"
    )
    marker = DIST / "ANDROID-SIGNING.txt"
    signed_android = marker.exists() and marker.read_text(
        encoding="utf-8"
    ).strip() == "release-signed"
    if marker.exists():
        marker.unlink()
    notes += (
        "Android artifacts are store-signed; the App Bundle is the one to upload.\n\n"
        if signed_android
        else "Android artifacts are debug-signed and unsuitable for production distribution.\n\n"
    )
    notes += (
        "The iOS .ipa holds the compiled Payload/Runner.app and carries no code\n"
        "signature, so it needs signing with your own certificate and profile\n"
        "before it will install on a device.\n"
    )
    checksums = DIST / "SHA256SUMS"
    lines = []
    for asset in assets:
        digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        lines.append(f"{digest}  {asset.name}")
        print(f"{asset.name}\t{asset.stat().st_size}\t{digest}")
    checksums.write_text("\n".join(lines) + "\n", encoding="utf-8")
    assets.append(checksums)

    existing = run("gh", "release", "view", tag, "--json", "isDraft,assets", check=False)
    if existing.returncode == 0:
        state = json.loads(existing.stdout)
        if not state.get("isDraft"):
            raise ReleaseError(f"Release {tag} is already published; refusing to modify it.")
        run("gh", "release", "delete", tag, "--yes")
        print(f"Replaced stale draft release {tag}")

    run("gh", "release", "create", tag, *[str(path) for path in assets], "--draft",
        "--verify-tag", "--title", f"MindPocket {version}", "--notes", notes)
    run("gh", "release", "edit", tag, "--draft=false", "--latest")
    print(f"Published {tag} with {len(assets)} assets")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ReleaseError, subprocess.CalledProcessError) as error:
        print(f"publish failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stdout or "", file=sys.stderr)
            print(error.stderr or "", file=sys.stderr)
        raise SystemExit(1)
