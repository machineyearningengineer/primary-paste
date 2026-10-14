# Developer setup

Native Swift, AppKit and SwiftUI. The compiled app needs no Node.js runtime or cloud service.

## Prerequisites

- macOS 14+ and full Xcode; check `xcode-select -p`.
- Node.js 22.13+ and npm for backend/packaging checks.
- Python 3.11+ for release and QA tooling.
- `rg` (`brew install ripgrep`).

GitHub CLI, Gitleaks, FFmpeg and Tesseract are optional maintainer tools. Automatic CI is paused; run the local gate before committing.

```sh
make build     # Unsigned compilation; no installation or windows
make check     # Formatting, architecture, metadata, packaging, backend and XCTest
```

## Install a development copy

Choose your own team in Xcode or pass signing overrides to the installer. For a disposable ad-hoc copy:

```sh
DEVELOPMENT_TEAM='' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  OPEN_AFTER_INSTALL=0 ./Scripts/install_dev_app.sh
```

Open `/Applications/Primary Paste.app` and grant permissions to that copy. Keep its path and signing identity stable. Ad-hoc builds are for local development; grants may change after rebuilding.

The installer verifies the signature, quits normally and keeps recovery copies in ignored `.artifacts/dev-install-backups/`.

## Structure

| Path | Purpose |
| --- | --- |
| `PrimaryPaste/App` | Lifecycle and service wiring |
| `PrimaryPaste/Features` | Capture, paste, clipboard, permissions and UI |
| `PrimaryPaste/Infrastructure` | Preferences and launch at login |
| `PrimaryPasteTests` | Behavioral tests |
| `Scripts` | Build, release and isolated QA |
| `Packaging/npm` | Explicit installer and launcher |
| `Backend/Licensing` | Dormant experimental backend; disabled in app |
| `Docs` | Product, developer and release guides |

Read [Architecture](Architecture.md) and [Security](Security.md) before changing capture, clipboard or diagnostics. [Releasing](Releasing.md) explains version metadata.

## Real-app checks

Use the optional [headless QA VM](QA-VM.md) for gestures, clicked-caret paste, attachments and permission journeys. It never takes over the host cursor.

Serialize GUI checks within a guest: apps share its focus and clipboard. Compilation and analysis can run alongside them. Ordinary builds do not create a VM or change host permissions.
