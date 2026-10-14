#!/usr/bin/env python3
"""Inspectable native packaging. No repository, registry or Homebrew publication."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.abel.primarypaste"
REPO = "https://github.com/machineyearningengineer/primary-paste"


def run(*args: str, cwd: Path = ROOT, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def validate_version(version: str, build: int) -> None:
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version):
        raise ValueError("Use a numeric major.minor.patch version; no prefixes or prerelease suffixes.")
    if any(int(part) > 65535 for part in version.split(".")) or not 1 <= build <= 999999:
        raise ValueError("Version components must fit macOS metadata; build must be 1–999999.")


def state(root: Path = ROOT) -> tuple[str, int]:
    version = (root / "VERSION").read_text().strip()
    build = int((root / "BUILD_NUMBER").read_text().strip())
    validate_version(version, build)
    return version, build


def release_label(version: str, build: int, unsigned: bool) -> str:
    validate_version(version, build)
    return (f"Primary-Paste-{version}-build-{build}-macOS-universal-UNSIGNED-PREVIEW"
            if unsigned else f"Primary-Paste-{version}-macOS-universal")


def source_information(version: str, build: int, commit: str, dirty: bool) -> str:
    validate_version(version, build)
    if not re.fullmatch(r"(?:[a-f0-9]{40}|[a-f0-9]{64})", commit):
        raise ValueError("Corresponding source requires an exact Git commit.")
    return (f"Primary Paste {version} build {build}\nGPL-3.0-only\nCommit: {commit}\n"
            f"Working tree modified: {dirty}\nCorresponding source: {REPO}/tree/{commit}\n"
            "Source archive accompanies this release.\n")


def set_version(version: str, build: int, root: Path = ROOT) -> None:
    validate_version(version, build)
    old_version, old_build = state(root)
    if tuple(map(int, version.split("."))) < tuple(map(int, old_version.split("."))):
        raise ValueError("Version numbers must not decrease.")
    if build < old_build:
        raise ValueError("Build numbers must not decrease.")
    if version != old_version and build == old_build:
        raise ValueError("Changing the version requires a new build number.")
    project = root / "PrimaryPaste.xcodeproj/project.pbxproj"
    text = project.read_text()
    text, vcount = re.subn(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {version};", text)
    text, bcount = re.subn(r"CURRENT_PROJECT_VERSION = [^;]+;", f"CURRENT_PROJECT_VERSION = {build};", text)
    if (vcount, bcount) != (2, 2):
        raise ValueError("Expected two app build configurations; no version files changed.")
    package_path = root / "Packaging/npm/package.json"
    package = json.loads(package_path.read_text())
    package["version"] = version
    project.write_text(text)
    package_path.write_text(json.dumps(package, indent=2) + "\n")
    (root / "VERSION").write_text(version + "\n")
    (root / "BUILD_NUMBER").write_text(str(build) + "\n")


def check(root: Path = ROOT, links: bool = True) -> None:
    version, build = state(root)
    project = (root / "PrimaryPaste.xcodeproj/project.pbxproj").read_text()
    if re.findall(r"MARKETING_VERSION = ([^;]+);", project) != [version, version]:
        raise ValueError("Xcode marketing version drift; run the version command.")
    if re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project) != [str(build), str(build)]:
        raise ValueError("Xcode build number drift; run the version command.")
    info = plistlib.loads((root / "PrimaryPaste/Info.plist").read_bytes())
    if info["CFBundleShortVersionString"] != "$(MARKETING_VERSION)" or info["CFBundleVersion"] != "$(CURRENT_PROJECT_VERSION)":
        raise ValueError("Info.plist must use the checked Xcode version variables.")
    if info.get("LicensingEnabled") or info.get("LicensingEnforcementEnabled"):
        raise ValueError("Preview distribution must not enable unverified licensing.")
    package = json.loads((root / "Packaging/npm/package.json").read_text())
    if package["version"] != version or package["license"] != "GPL-3.0-only" or package.get("private") is not True:
        raise ValueError("npm source template version/license/private state drift.")
    if any(name in package.get("scripts", {}) for name in ("preinstall", "install", "postinstall", "prepare")):
        raise ValueError("npm must not have implicit installation or preparation hooks.")
    if "GNU GENERAL PUBLIC LICENSE" not in (root / "LICENSE").read_text():
        raise ValueError("GPL license missing.")
    if links:
        files = [root / name for name in ("README.md", "CONTRIBUTING.md", "SECURITY.md", "SUPPORT.md", "CHANGELOG.md")]
        files += list((root / "Docs").rglob("*.md"))
        for file in files:
            for target in re.findall(r"\]\(([^\s)]+)(?:\s+[^)]*)?\)", file.read_text()):
                parsed = urlparse(target.strip("<>"))
                if parsed.scheme or target.startswith("#"):
                    continue
                if not (file.parent / unquote(parsed.path)).exists():
                    raise ValueError(f"Broken relative link: {file.relative_to(root)} -> {target}")
    print(f"Release metadata and documentation passed: {version} ({build}).")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def cask(version: str, sha: str) -> str:
    validate_version(version, 1)
    if not re.fullmatch(r"[a-f0-9]{64}", sha):
        raise ValueError("Cask requires an actual SHA-256.")
    return f'''cask "primary-paste" do
  version "{version}"
  sha256 "{sha}"

  url "{REPO}/releases/download/v#{{version}}/Primary-Paste-#{{version}}-macOS-universal.zip"
  name "Primary Paste"
  desc "Select text and middle-click to paste while keeping your clipboard"
  homepage "{REPO}"

  depends_on macos: ">= :sonoma"
  app "Primary Paste.app"
  binary "#{{appdir}}/Primary Paste.app/Contents/MacOS/primary-paste"

  zap trash: "~/Library/Preferences/com.abel.primarypaste.plist"
end
'''


def verify_app(app: Path, version: str, build: int) -> None:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), str(info.get("CFBundleVersion"))) != (BUNDLE_ID, version, str(build)):
        raise ValueError("Built app identity/version drift.")
    for name in ("Primary Paste", "primary-paste"):
        architectures = set(run("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS" / name), capture=True).split())
        if architectures != {"arm64", "x86_64"}:
            raise ValueError(f"{name} is not the expected universal binary: {sorted(architectures)}")
    for key in ("LicensingEnabled", "LicensingEnforcementEnabled"):
        if info.get(key):
            raise ValueError("Built app unexpectedly enables licensing.")


def notarize(path: Path, profile: str) -> None:
    result = json.loads(run("xcrun", "notarytool", "submit", str(path), "--keychain-profile", profile,
                            "--wait", "--output-format", "json", capture=True))
    if result.get("status") != "Accepted":
        raise ValueError(f"Apple notarization failed with status {result.get('status')!r}; inspect its submission log.")


def build_release(args: argparse.Namespace) -> None:
    check()
    version, build = state()
    if sys.platform != "darwin":
        raise ValueError("App packaging requires macOS and full Xcode.")
    dirty = bool(run("git", "status", "--porcelain", capture=True))
    commit = run("git", "rev-parse", "HEAD", capture=True)
    if not args.unsigned:
        if dirty:
            raise ValueError("Signed distribution requires a clean committed tree.")
        if not args.identity or not args.identity.startswith("Developer ID Application:") or not args.notary_profile:
            raise ValueError("Distribution requires a Developer ID Application identity and notary Keychain profile.")
    elif args.identity or args.notary_profile:
        raise ValueError("Unsigned previews must not accept signing/notarization credentials.")
    label = release_label(version, build, args.unsigned)
    output = (ROOT / ".artifacts/releases" / label)
    output.mkdir(parents=True, exist_ok=False)
    log_path = output / "build.log"
    with log_path.open("w") as log:
        subprocess.run(["xcodebuild", "-project", str(ROOT / "PrimaryPaste.xcodeproj"), "-scheme", "Primary Paste",
                        "-configuration", "Release", "-derivedDataPath", str(output / "DerivedData"),
                        "CODE_SIGNING_ALLOWED=NO", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", "build"],
                       cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    app = output / "Primary Paste.app"
    run("/usr/bin/ditto", str(output / "DerivedData/Build/Products/Release/Primary Paste.app"), str(app))
    source = output / "cli.swift"
    source.write_text((ROOT / "Scripts/primary_paste_cli.swift").read_text().replace("__RELEASE_VERSION__", version))
    binaries = []
    for arch in ("arm64", "x86_64"):
        binary = output / f"cli-{arch}"
        run("xcrun", "swiftc", "-O", "-target", f"{arch}-apple-macosx14.0", str(source), "-o", str(binary))
        binaries.append(str(binary))
    cli = app / "Contents/MacOS/primary-paste"
    run("/usr/bin/lipo", "-create", *binaries, "-output", str(cli))
    resource = app / "Contents/Resources"
    resource.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "LICENSE", resource / "LICENSE.txt")
    source_info = source_information(version, build, commit, dirty)
    (resource / "SOURCE.txt").write_text(source_info)
    verify_app(app, version, build)
    if not args.unsigned:
        run("/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp", "--sign", args.identity, str(cli))
        run("/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp", "--entitlements",
            str(ROOT / "PrimaryPaste/PrimaryPaste.entitlements"), "--sign", args.identity, str(app))
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        submission = output / "notarization.zip"
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submission))
        notarize(submission, args.notary_profile)
        run("xcrun", "stapler", "staple", str(app))
        run("xcrun", "stapler", "validate", str(app))
        run("/usr/sbin/spctl", "--assess", "--type", "execute", str(app))
        submission.unlink()
    archive = output / f"{label}.zip"
    run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
    dmg_stage = output / "DMG"
    dmg_stage.mkdir()
    run("/usr/bin/ditto", str(app), str(dmg_stage / app.name))
    (dmg_stage / "Applications").symlink_to("/Applications")
    shutil.copy2(ROOT / "LICENSE", dmg_stage / "LICENSE.txt")
    (dmg_stage / "SOURCE.txt").write_text(source_info)
    dmg = output / f"{label}.dmg"
    run("/usr/bin/hdiutil", "create", "-quiet", "-volname", "Primary Paste", "-srcfolder", str(dmg_stage),
        "-format", "UDZO", str(dmg))
    if not args.unsigned:
        run("/usr/bin/codesign", "--timestamp", "--sign", args.identity, str(dmg))
        notarize(dmg, args.notary_profile)
        run("xcrun", "stapler", "staple", str(dmg))
        run("xcrun", "stapler", "validate", str(dmg))
    cli_archive = output / f"{label}-cli.tar.gz"
    with tarfile.open(cli_archive, "w:gz") as tar:
        tar.add(cli, arcname="primary-paste")
        tar.add(ROOT / "LICENSE", arcname="LICENSE")
        tar.add(resource / "SOURCE.txt", arcname="SOURCE.txt")
    source_archive = output / f"Primary-Paste-{version}-source.tar.gz"
    paths = run("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", capture=True).split("\0")
    with tarfile.open(source_archive, "w:gz") as tar:
        for name in sorted(set(filter(None, paths))):
            path = ROOT / name
            if name.startswith(("Design/", ".workflow/")):
                continue  # Historical reference/agent evidence is not corresponding build source.
            if path.is_symlink():
                raise ValueError(f"Source archive refuses symlink: {name}")
            if path.is_file():
                tar.add(path, arcname=f"primary-paste-{version}/{name}", recursive=False)
    npm = output / "npm"
    shutil.copytree(ROOT / "Packaging/npm", npm, ignore=shutil.ignore_patterns("test", "node_modules"))
    (npm / "payload").mkdir()
    shutil.copy2(archive, npm / "payload/Primary-Paste.zip")
    shutil.copy2(ROOT / "LICENSE", npm / "LICENSE")
    (npm / "SOURCE.txt").write_text(source_info)
    manifest = dict(schema=1, version=version, build=build, commit=commit, dirty=dirty, bundleID=BUNDLE_ID,
                    architectures=["arm64", "x86_64"], notarized=not args.unsigned,
                    developerID=not args.unsigned, zipFile="Primary-Paste.zip", zipSHA256=digest(archive),
                    sourceArchive=source_archive.name, sourceSHA256=digest(source_archive))
    (npm / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    package = json.loads((npm / "package.json").read_text())
    package["private"] = args.unsigned
    package.pop("scripts", None)
    (npm / "package.json").write_text(json.dumps(package, indent=2) + "\n")
    npm_readme = npm / "README.md"
    status = ("This is a private unsigned inspection package. Its installer deliberately refuses this payload; "
              "use source development for a local preview." if args.unsigned else
              "This package includes the notarized universal app ZIP and its exact SHA-256. "
              "Installation is explicit and offline; it never overwrites an existing app.")
    text, count = re.subn(r"<!-- release-status:start -->.*?<!-- release-status:end -->", status,
                         npm_readme.read_text(), flags=re.DOTALL)
    if count != 1:
        raise ValueError("npm README status marker missing; refusing misleading package documentation.")
    npm_readme.write_text(text)
    packed = json.loads(run("npm", "pack", "--json", cwd=npm, capture=True))
    npm_name = packed[0]["filename"]
    if args.unsigned:
        npm_name = npm_name.removesuffix(".tgz") + "-UNSIGNED-PREVIEW.tgz"
    npm_archive = output / npm_name
    shutil.move(npm / packed[0]["filename"], npm_archive)
    artifacts = [archive, dmg, cli_archive, source_archive, npm_archive]
    if not args.unsigned:
        cask_file = output / "primary-paste.rb"
        cask_file.write_text(cask(version, digest(archive)))
        artifacts.append(cask_file)
    manifest["artifacts"] = {file.name: {"sha256": digest(file), "bytes": file.stat().st_size} for file in artifacts}
    (output / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "SHA256SUMS.txt").write_text("".join(f"{digest(file)}  {file.name}\n" for file in artifacts))
    for disposable in (output / "DerivedData", dmg_stage):
        shutil.rmtree(disposable)
    source.unlink()
    for binary in binaries:
        Path(binary).unlink()
    print(f"Prepared {'unsigned inspection' if args.unsigned else 'notarized distribution'} artifacts: {output}")
    print("Nothing was published or installed. The repository visibility is unchanged.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    version = sub.add_parser("version")
    version.add_argument("value")
    version.add_argument("--build", type=int, required=True)
    build = sub.add_parser("build")
    build.add_argument("--unsigned", action="store_true")
    build.add_argument("--identity")
    build.add_argument("--notary-profile")
    args = parser.parse_args()
    try:
        if args.command == "check":
            check()
        elif args.command == "version":
            set_version(args.value, args.build)
            check()
        else:
            build_release(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release preparation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
