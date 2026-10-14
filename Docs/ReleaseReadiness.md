# Source preview readiness

**0.1.0, build 3.** [Public source and unsigned preview](https://github.com/machineyearningengineer/primary-paste/releases/tag/v0.1.0-preview.3) were published on 14 October 2026. There is no notarized installer.

| Area | Evidence and limits |
| --- | --- |
| Local checks | 114 tests: 60 XCTest, 5 backend, 40 Python and 9 npm. Formatting, architecture/privacy, metadata, CLI, dependency audit and preflight. |
| CI | GitHub Actions is disabled. Use `make check` locally. |
| Native behavior | Recorded development-signed guest setup, upgrade, reinstall, first paste and clipboard restoration. [Detailed checks](ReleaseChecks.md). |
| Compatibility | Recorded Chrome, Edge, Safari, Codex local composer, Maccy and CopyQ checks from their documented acceptance build. [Versions and limits](Compatibility.md). |
| Artifacts | Universal app/CLI, ZIP, DMG, source archive and private offline npm inspection package. Exact commit, sizes and SHA-256 recorded in `release.json` and `SHA256SUMS.txt`. |
| Media/history | Original product media and included font license. Public source starts from the reviewed tree; historical references and internal QA material remain in a private archive. [Rights](Media/Rights.md). |

## Beyond this source preview

- Paid Apple Developer membership, Developer ID signing and notarization.
- Clean, quarantined installation of notarized downloads; actual npm/Homebrew install journeys after those formats are published.
- Intel GUI, authenticated Codex, signed-in Arc and physical gesture checks before claiming that coverage.
- Payment/licensing journeys remain unverified and disabled.

The npm installer refuses unsigned packages. Its preview payload remains local.
