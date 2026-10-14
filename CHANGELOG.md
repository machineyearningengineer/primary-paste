# Changelog

Notable changes are recorded here for people using the app. Version numbers follow [Semantic Versioning](https://semver.org/). Dates describe publication, not when a local build first passed.

## Unreleased — 0.1.0 preview preparation

### Added

- A native macOS selection buffer: deliberately select text, then middle-click an editable field to paste it.
- Safe Drag capture, configurable selection gestures, Latest, Queue, Stack and Cycle paste modes.
- Separate clipboard behavior, optional clipboard import/mirroring, rich clipboard restoration and cooperating clipboard-manager transport markers.
- Three-step Setup, a local first-paste practice page, explicit permission guidance and a quiet menu bar continuation.
- Private Mode, blocked-app rules, protected-field exclusion, sensitive-text filtering and text/file limits.
- Optional Finder file capture and per-app compatibility settings.
- A windowless disposable macOS QA environment, with owned-resource cleanup guards and baseline reset.
- Product guides, issue forms, an issues-only initial contribution policy and inspectable release packaging for app, CLI, Homebrew and npm.

### Changed

- Automatic hosted CI is paused; local checks remain the release gate.
- Build 3 refreshes repository links and gives each unsigned rebuild a distinct artifact name and exact source-commit link.
- Public source preparation removes private design references and internal QA records, retaining the original history privately.
- Shorter product guides, native window screenshots and a real Safari-to-TextEdit demo with a visible cursor and clearer timing.
- Original window-transfer artwork replaces the optional platform-mascot icon.

### Fixed

- Practice reopening a stale Safari error tab after its cache file was removed. Fresh URLs and a bounded practice cache keep retrying reliable.
- Capture history filling with intermediate drag selections.
- Safari WebKit selections missing through ordinary Accessibility text attributes.
- Codex's deep editor ancestry being mistaken for a native text field and inserting placeholder text.
- Temporary paste content entering CopyQ history through Qt MIME representations.
- Delayed pastes losing their original target or replacing a newer user clipboard copy.

### Release status

No public release has been published. Current real-app evidence and remaining checks are listed in [Compatibility](Docs/Compatibility.md). Signing, notarization, installer validation and publication remain explicit release gates.
