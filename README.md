<p align="center"><img src="https://raw.githubusercontent.com/machineyearningengineer/primary-paste/main/Docs/Media/icon.png" width="80" height="80" alt="Primary Paste app icon"></p>
<h1 align="center">Primary Paste</h1>
<p align="center"><strong>Select text. Middle-click to paste.</strong><br>A separate selection clipboard for macOS.</p>
<p align="center">
  <a href="Docs/Install.md"><img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-222222?style=flat-square"></a>
  <a href="Docs/ReleaseReadiness.md"><img alt="Unsigned preview" src="https://img.shields.io/badge/status-unsigned_preview-4f9f84?style=flat-square"></a>
  <a href="LICENSE"><img alt="GPL-3.0-only" src="https://img.shields.io/badge/license-GPL--3.0--only-222222?style=flat-square"></a>
  <a href="CONTRIBUTING.md"><img alt="Issues welcome" src="https://img.shields.io/badge/issues-welcome-4f8068?style=flat-square"></a>
</p>

![Real selection in Safari, cursor movement and middle-click paste into TextEdit.](Docs/Media/Explainer/Primary-Paste.gif)

[Download the demo](https://raw.githubusercontent.com/machineyearningengineer/primary-paste/main/Docs/Media/Explainer/Primary-Paste.mp4) · [Set up](Docs/GettingStarted.md) · [Compatibility](Docs/Compatibility.md) · [Report an issue](https://github.com/machineyearningengineer/primary-paste/issues/new/choose)

Drag-select text in one app, then middle-click an editable field in another. Your normal ⌘C/⌘V clipboard stays separate.

- Selections stay in memory. No account or subscription.
- Links and tabs keep their normal middle-click behavior.
- Pause capture, clear selections or exclude apps from the menu bar.
- Keep the latest selection, or use Queue, Stack or Cycle for several items.

## Install

**0.1.0, build 3: unsigned preview.** Requires macOS 14+. The app and CLI include Apple Silicon and Intel builds.

[App ZIP](https://github.com/machineyearningengineer/primary-paste/releases/download/v0.1.0-preview.3/Primary-Paste-0.1.0-build-3-macOS-universal-UNSIGNED-PREVIEW.zip) · [DMG](https://github.com/machineyearningengineer/primary-paste/releases/download/v0.1.0-preview.3/Primary-Paste-0.1.0-build-3-macOS-universal-UNSIGNED-PREVIEW.dmg) · [CLI](https://github.com/machineyearningengineer/primary-paste/releases/download/v0.1.0-preview.3/Primary-Paste-0.1.0-build-3-macOS-universal-UNSIGNED-PREVIEW-cli.tar.gz) · [Checksums](https://github.com/machineyearningengineer/primary-paste/releases/download/v0.1.0-preview.3/SHA256SUMS.txt)

These downloads are for inspection. They have no Developer ID signature or notarization. For local use, build from source. Homebrew and npm installers are not published. [Release details](https://github.com/machineyearningengineer/primary-paste/releases/tag/v0.1.0-preview.3).

Build locally with full Xcode:

```sh
git clone https://github.com/machineyearningengineer/primary-paste.git
cd primary-paste
make build
```

To install your build, follow [developer setup](Docs/Developing.md). The app runs without Node.js; development checks need it.

## First paste

1. Open Primary Paste and follow Setup to grant the required permissions.
2. Choose **Try It in Your Browser**. Select the sentence, then middle-click the field.
3. Choose **Continue in Menu Bar**.

Trackpad? Enable the optional **⌃⌥⌘V** shortcut in Paste, or map a gesture to middle-click.

![The native Primary Paste Setup window.](Docs/Media/onboarding.png)

VM checks cover Chrome, Edge, Safari, Maccy, CopyQ and Codex's local composer. Intel GUI, authenticated Codex and signed-in Arc still need testing. [Tested versions and app rules](Docs/Compatibility.md).

## Developers

```sh
make check     # Complete local quality gate
make build     # Compile without signing or opening windows
```

[Setup](Docs/Developing.md) · [Architecture](Docs/Architecture.md) · [Release process](Docs/Releasing.md) · [Changelog](CHANGELOG.md)

GitHub Actions is disabled. Run checks locally.

Issues are welcome; external PRs are closed during the initial preview. Verify AI-assisted reports before submitting. [Contributing](CONTRIBUTING.md).

GPL-3.0-only. Commercial forks are allowed; distributions must provide corresponding source under the GPL. [License and branding](Docs/Licensing.md) · [Privacy](Docs/Security.md) · [Media rights](Docs/Media/Rights.md).
