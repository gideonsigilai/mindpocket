#!/usr/bin/env python3
"""Package MindPocket release artifacts for one platform.

Every output lands in dist/ with a unique, OS-and-architecture-qualified name so
release assets can never collide. Versions come from pubspec.yaml, never from an
argument, so a tag can only publish the version the source actually declares.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIST = ROOT / "dist"
BINARY = "mindpocket"
BUNDLE_ID = "com.mindpocket.mindpocket"
APP_NAME = "MindPocket"


class PackagingError(RuntimeError):
    """A required build output or tool is missing; fail loudly rather than ship partial.""" 


def version() -> tuple[str, str]:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$", text, re.MULTILINE)
    if not match:
        raise PackagingError("pubspec.yaml has no semantic version.")
    return match.group(1), (match.group(2) or "0")


def target_arch() -> str:
    """Architecture of the artifact being built on this runner."""
    machine = os.environ.get("PROCESSOR_ARCHITECTURE", "").lower()
    if machine == "amd64":
        return "x64"
    if machine == "arm64":
        return "arm64"
    if hasattr(os, "uname"):
        return "arm64" if os.uname().machine in ("arm64", "aarch64") else "x64"
    return "x64"


def fresh(path: Path) -> Path:
    if path.exists():
        shutil.rmtree(path) if path.is_dir() else path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def record(path: Path) -> None:
    print(f"{path.name}\t{path.stat().st_size}\t{sha256(path)}")


def zip_tree(source: Path, destination: Path, arc_root: str | None = None) -> Path:
    """Zip a tree without dereferencing symlinks into absolute host paths."""
    output = fresh(destination)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for entry in sorted(source.rglob("*")):
            if entry.is_symlink():
                continue
            if not entry.is_file():
                continue
            arcname = entry.relative_to(source)
            if arc_root:
                arcname = Path(arc_root) / arcname
            archive.write(entry, arcname.as_posix())
    record(output)
    return output


def require_binary(directory: Path, name: str) -> None:
    if not (directory / name).exists():
        raise PackagingError(f"{name} is missing from {directory}")


def package_android() -> None:
    semver, build = version()
    apk_dir = ROOT / "build" / "app" / "outputs" / "flutter-apk"
    aab_dir = ROOT / "build" / "app" / "outputs" / "bundle" / "release"
    apks = sorted(apk_dir.glob("app-*-release.apk")) or sorted(
        apk_dir.glob("app-release.apk")
    )
    if not apks:
        raise PackagingError("No release APK was produced.")
    for apk in apks:
        abi = "universal"
        match = re.match(r"app-(.+)-release\.apk", apk.name)
        if match and match.group(1) != "release":
            abi = match.group(1)
        output = DIST / f"MindPocket-{semver}+{build}-android-{abi}.apk"
        fresh(output).write_bytes(apk.read_bytes())
        record(output)
    bundle = aab_dir / "app-release.aab"
    if bundle.exists():
        output = DIST / f"MindPocket-{semver}+{build}-android-release.aab"
        fresh(output).write_bytes(bundle.read_bytes())
        record(output)


def package_windows() -> None:
    """The PowerShell packager owns the installer; this verifies its output."""
    semver, build = version()
    release = ROOT / "build" / "windows" / "x64" / "runner" / "Release"
    require_binary(release, f"{BINARY}.exe")
    expected = [
        DIST / f"MindPocket-{semver}+{build}-windows-installer.exe",
        DIST / f"MindPocket-{semver}+{build}-windows-x64.zip",
    ]
    missing = [str(path) for path in expected if not path.exists()]
    if missing:
        raise PackagingError(
            "Windows packaging produced no installer/portable archive: "
            + ", ".join(missing)
        )
    for path in expected:
        record(path)


def linux_dependencies() -> list[str]:
    """Runtime packages the release genuinely needs.

    Debian trixie and Ubuntu 24.04 renamed the GTK and libsecret packages for
    the 64-bit ``time_t`` transition; the unversioned names no longer resolve
    there, so both spellings are listed as alternatives.
    """
    return [
        "libgtk-3-0t64 | libgtk-3-0",
        "libsecret-1-0t64 | libsecret-1-0",
        "liblzma5",
        "libstdc++6",
        "libmpv2 | libmpv1",
        "ffmpeg",
        "pulseaudio-utils",
        "tesseract-ocr",
        "tesseract-ocr-eng",
    ]


def package_linux() -> None:
    semver, build = version()
    release = ROOT / "build" / "linux" / "x64" / "release" / "bundle"
    require_binary(release, BINARY)
    arch = "amd64" if target_arch() == "x64" else "arm64"

    payload = fresh(ROOT / "build" / "release-linux" / "payload")
    shutil.copytree(release, payload / "opt" / "mindpocket", symlinks=True)
    desktop_dir = payload / "usr" / "share" / "applications"
    desktop_dir.mkdir(parents=True, exist_ok=True)
    (desktop_dir / "mindpocket.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=MindPocket\n"
        "Comment=Screenshots and voice notes in one offline, searchable collection\n"
        "Exec=/opt/mindpocket/mindpocket\n"
        "Icon=mindpocket\n"
        "Terminal=false\n"
        "Categories=Utility;Office;\n"
        "StartupWMClass=com.mindpocket.mindpocket\n",
        encoding="utf-8",
    )
    icon_dir = payload / "usr" / "share" / "icons" / "hicolor" / "512x512" / "apps"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon_source = ROOT / "assets" / "images" / "brand_mark.png"
    if icon_source.exists():
        shutil.copy2(icon_source, icon_dir / "mindpocket.png")

    installed_size = max(
        1,
        sum(
            path.stat().st_size
            for path in (payload / "opt").rglob("*")
            if path.is_file()
        )
        // 1024,
    )
    control_dir = payload / "DEBIAN"
    control_dir.mkdir(parents=True, exist_ok=True)
    (control_dir / "control").write_text(
        "Package: mindpocket\n"
        f"Version: {semver}+{build}\n"
        f"Architecture: {arch}\n"
        "Maintainer: MindPocket <noreply@mindpocket.dev>\n"
        f"Installed-Size: {installed_size}\n"
        f"Depends: {', '.join(linux_dependencies())}\n"
        "Section: utils\n"
        "Priority: optional\n"
        "Description: Offline screenshot organizer and voice notebook\n"
        " MindPocket groups screenshots, extracts their text on device, transcribes\n"
        " voice notes offline, and makes everything searchable without an account.\n",
        encoding="utf-8",
    )
    deb = DIST / f"mindpocket_{semver}+{build}_{arch}.deb"
    fresh(deb)
    subprocess.run(
        ["dpkg-deb", "--build", "--root-owner-group", str(payload), str(deb)],
        check=True,
    )
    record(deb)

    tree_tar = DIST / f"MindPocket-{semver}+{build}-linux-{arch}.tar.gz"
    fresh(tree_tar)
    with tarfile.open(tree_tar, "w:gz") as archive:
        archive.add(release, arcname=f"{APP_NAME}-{semver}")
    record(tree_tar)


def is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            magic = handle.read(4)
    except OSError:
        return False
    return magic in (
        b"\xca\xfe\xba\xbe",
        b"\xcf\xfa\xed\xfe",
        b"\xce\xfa\xed\xfe",
        b"\xfe\xed\xfa\xce",
        b"\xfe\xed\xfa\xcf",
    )


def package_macos() -> None:
    semver, build = version()
    candidates = sorted(
        (ROOT / "build" / "macos-release").glob("Build/Products/Release/*.app")
    ) or sorted((ROOT / "build" / "macos").glob("Build/Products/Release/*.app"))
    if not candidates:
        raise PackagingError("No macOS .app bundle was produced.")
    app = candidates[0]
    # The macOS target sets PRODUCT_NAME = MindPocket, so the executable is
    # "MindPocket" rather than the CMake/BINARY_NAME used on Windows/Linux.
    bundle_executable = app / "Contents" / "MacOS" / (app.stem)
    if not bundle_executable.exists():
        raise PackagingError(f"{bundle_executable} is missing from {app.name}")
    if not is_macho(bundle_executable):
        raise PackagingError(f"{bundle_executable.name} is not a Mach-O executable.")
    if not (app / "Contents" / "Frameworks").is_dir():
        raise PackagingError("The macOS bundle has no Frameworks directory.")

    # Ad-hoc sign nested code bottom-up; the bundle signature must be last so
    # later changes cannot invalidate it.
    for entry in sorted(
        (
            path
            for path in app.rglob("*")
            if path.is_file() and not path.is_symlink() and is_macho(path)
        ),
        key=lambda path: len(path.parts),
        reverse=True,
    ):
        subprocess.run(
            ["codesign", "--force", "--sign", "-", "--timestamp=none", str(entry)],
            check=True,
        )
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

    staged = fresh(ROOT / "build" / "release-macos")
    shutil.copytree(app, staged / app.name, symlinks=True)

    output = DIST / f"MindPocket-{semver}+{build}-macos-{target_arch()}.zip"
    fresh(output)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as handle:
        # Only the bundle goes in the archive: the same directory also holds a
        # .dSYM. Frameworks rely on relative symlinks (Versions/Current), so
        # they are written as symlink entries rather than dereferenced copies.
        for entry in sorted(app.rglob("*")):
            arcname = (Path(app.name) / entry.relative_to(app)).as_posix()
            if entry.is_symlink():
                info = zipfile.ZipInfo(arcname)
                info.create_system = 3
                info.external_attr = 0o120777 << 16
                handle.writestr(info, os.readlink(entry))
            elif entry.is_file():
                handle.write(entry, arcname)
    record(output)


def package_ios() -> None:
    semver, build = version()
    app = ROOT / "build" / "ios" / "iphoneos" / "Runner.app"
    if not app.exists():
        raise PackagingError(f"iOS compilation output not found: {app}")
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if str(info.get("CFBundleIdentifier", "")).strip() != BUNDLE_ID:
        raise PackagingError(
            "iOS bundle identifier does not match com.mindpocket.mindpocket."
        )
    output = DIST / f"MindPocket-{semver}+{build}-ios-unsigned-app.zip"
    zip_tree(app, output, arc_root="Runner.app")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "platform", choices=["android", "windows", "linux", "macos", "ios"]
    )
    platform = parser.parse_args().platform
    DIST.mkdir(parents=True, exist_ok=True)
    {
        "android": package_android,
        "windows": package_windows,
        "linux": package_linux,
        "macos": package_macos,
        "ios": package_ios,
    }[platform]()


if __name__ == "__main__":
    try:
        main()
    except PackagingError as error:
        print(f"packaging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
