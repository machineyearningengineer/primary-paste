# Installation

**No notarized installer is available yet.** Build from source for local use. [Unsigned preview downloads](https://github.com/machineyearningengineer/primary-paste/releases) are inspection artifacts. The release includes SHA-256 checksums and corresponding source.

Requires macOS 14+. Artifacts target Apple Silicon and Intel; real-app checks currently cover Apple Silicon.

## Source preview

Install full Xcode and follow [developer setup](Developing.md), then:

```sh
OPEN_AFTER_INSTALL=0 ./Scripts/install_dev_app.sh
```

This builds and installs a development-signed app without opening it. Open the installed copy when ready and follow Setup. Development signing does not establish notarization.

## Planned release formats

| Format | Installation | Status |
| --- | --- | --- |
| ZIP / DMG | Move Primary Paste.app to Applications | Packaging checked; signing and notarization blocked |
| Homebrew cask | Install the reviewed cask from a release | Generated only from a notarized artifact |
| `@machineyearn/primary-paste` | Install launcher, then explicitly install app | Offline payload prepared; unpublished |

The npm installer has no install hook, network fetch or automatic launch. It verifies the payload and macOS trust, requires a writable `/Applications` and refuses to overwrite an existing app.

## Upgrade or remove

- **ZIP/DMG upgrade:** quit normally, then replace the app in Applications. Keep its path and signing identity stable.
- **Homebrew upgrade:** use the release's cask. Updating the npm launcher does not update the app; its installer refuses existing copies, so use the reviewed ZIP/DMG for an app upgrade.
- **Remove:** disable launch at login, quit normally and remove the app through its installer or move it to Trash.
- **npm uninstall:** removes the launcher only; the app and preferences stay.
- **Preferences:** keep them for reinstall, or explicitly remove them. Homebrew zap will be an optional destructive cleanup.
- **Permissions:** remove obsolete entries in System Settings if needed.

## Troubleshooting

Use one installed copy. A new signing identity can require renewed permissions. If a future official download fails macOS trust checks, stop and report the version and error. Keep Gatekeeper enabled.

The developer [QA VM](QA-VM.md) is separate and has guarded teardown. Installing the app does not create a VM.
