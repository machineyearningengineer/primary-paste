# Contributing

**Issues welcome. External PRs closed during the initial preview.** Please wait for an invitation before preparing a patch. Unsolicited PRs may be closed without review.

You may inspect, build and fork the project under [GPL-3.0-only](LICENSE). Maintainer and automated dependency PRs are reviewed internally.

## Report a bug

Search existing issues, then use the bug form. Include:

- App version/build, macOS version and target app/version.
- Minimal steps with synthetic text; expected and actual result.
- Capture mode, clipboard mode, relevant app rules and permission state.

Inspect reports and recordings before uploading. Remove private text, clipboard history, filenames, tokens and unrelated windows. Report vulnerabilities through [SECURITY.md](SECURITY.md).

## AI-assisted reports

AI help is welcome. Reproduce the issue, check the claims and distinguish observations from guesses. Mention substantial AI help and what you verified; no chat transcript is needed.

Avoid speculative vulnerability lists, duplicates and large generated patches. There is no CLA, DCO bot, bounty or response-time promise.

## Maintainers

- Read [developer setup](Docs/Developing.md), [architecture](Docs/Architecture.md) and [security](Docs/Security.md).
- Run `make check`; use real-app checks for gestures, focus and attachments.
- Keep changes reviewable. Record user-visible changes, evidence and limits.
- Preserve bundle identity and conservative capture defaults.
- Verify licenses before importing code or media. Keep secrets, builds and guest profiles out of Git.

Contribution requirements will be documented before external PRs open.
