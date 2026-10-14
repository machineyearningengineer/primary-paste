# Release checks · 11 October 2026

Version **0.1.0 (2)**. Repository remains private; nothing published.

## Local verification

`./Scripts/check.sh` passes: **113 tests**, no failures. Xcode's result bundle confirms all 60 native tests passed, with no skips or runtime warnings. Dependency audit reports no vulnerabilities.

The Release archive compiles. App and CLI packaging targets both arm64 and x86_64. This verifies compilation and artifact structure, not Intel GUI behavior.

## Development-signed guest

| Journey | Observed result |
| --- | --- |
| Fresh install | Reset only Primary Paste preferences and permission approvals. Setup reports missing permissions; guest grants bring capture and middle-click services to ready. |
| Upgrade | Replacement retains the app identity, settings and permission grants; signature verification and CLI doctor pass. |
| Remove/reinstall | Doctor rejects a missing installation. Reinstall verifies correctly and preserves the deliberately changed queue setting. Setup returns to ready. |
| First paste | The final development build opens a fresh local Safari practice URL. Selecting `Meet at 10:30.` and middle-clicking the field produces that exact value. Available clipboard representations match after restoration. |
| Demo | Real Safari → TextEdit interaction produces `Hi Sam,\n\nMeet at 10:30.\n`; available clipboard representations match. [Footage and edit](Media/README.md). |

Final development executable SHA-256:

```text
af203425f3e5ed3feff1a7f4f3ed401107e658a8d2cc671358419acb530d16b4
```

Clean-install and upgrade journeys used earlier development candidates from this same build-2 work. The final candidate was then rechecked for ready services, removal/reinstall with preserved settings and first-paste behavior. Demo footage predates only the About tagline and optional icon drawing changes.

Guest input runs over pinned SSH/RFB in a headless VM. No host window is opened or activated. Diagnostic trees and clipboard hashes are local, ignored evidence; no selection text is placed in production logs.

## Distribution limits

**Developer ID/notarization blocked:** the maintainer has no paid Apple Developer membership. An Apple Development certificate is available; the release notarization profile is absent. No Apple submission was made.

Development installation does not establish Gatekeeper trust for downloaded ZIP/DMG files. Authenticated Codex, signed-in Arc, Intel GUI and physical gesture mappings remain unverified. Earlier browser/clipboard-manager acceptance is documented separately in [Compatibility](Compatibility.md).

Unsigned artifacts are inspection packages. Their manifest, checksums and source archive establish what was built; they cannot substitute for notarization or actual published install checks.
