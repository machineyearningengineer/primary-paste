# Releasing

[Unsigned preview 3](https://github.com/machineyearningengineer/primary-paste/releases/tag/v0.1.0-preview.3) is public. Local packaging creates files; publishing is a separate step. [Current checks and blockers](ReleaseReadiness.md).

## Versions

| File | Meaning |
| --- | --- |
| `VERSION` | Numeric Semantic Version; currently `0.1.0` |
| `BUILD_NUMBER` | Increasing macOS build number; currently `3` |

The version command updates Xcode and npm mirrors:

```sh
python3 Scripts/release.py version 0.1.0 --build 3
make check
make package-preview
```

Patch: compatible fixes. Minor: compatible features. Major: incompatible behavior. Below 1.0, document breaking changes in minor versions. Increase the build for rebuilt distributions; never replace published artifacts. Stable tags use `v<version>`; previews use `v<version>-preview.<build>`.

Unsigned artifacts are marked `UNSIGNED-PREVIEW`. Their npm package stays private and refuses installation; no cask is generated.

## Signing blocker

This Mac has a free Personal Team and an Apple Development certificate. The maintainer has no paid membership yet. **Developer ID signing and notarization cannot be completed.** The development-signed VM checks do not establish download trust.

When membership is available:

1. Add the paid team in Xcode → Settings → Accounts.
2. Create a **Developer ID Application** certificate through Manage Certificates.
3. Store notarization credentials locally with `xcrun notarytool store-credentials primary-paste-release`. Use its interactive prompts, not secrets in shell history or Git.
4. Confirm the identity with `security find-identity -v -p codesigning`.

[Apple’s signing and notarization instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev88332a81e.html).

```sh
python3 Scripts/release.py build \
  --identity 'Developer ID Application: Your Name (TEAMID)' \
  --notary-profile primary-paste-release
```

This requires a clean tree and submits artifacts to Apple. It signs the universal app/CLI with hardened runtime, waits for acceptance, staples and validates tickets, checks Gatekeeper, then packs ZIP, DMG, CLI, source and offline npm payloads. Failure stops assembly.

## Distribution review

1. Run `make check`; review real-app evidence for this build. Verify Intel runtime before claiming it.
2. Review [media rights](Media/Rights.md), the full-history secret scan, licenses and corresponding source.
3. Test notarized ZIP/DMG install, upgrade, uninstall, reinstall and permission recovery on a clean Mac/VM. Development checks cover only part of this journey.
4. Verify manifest, checksums, npm pack and generated cask. The cask pins the exact signed ZIP.
5. After authorization, create a tag and draft prerelease. Review uploads before publishing or changing visibility.
6. After publication approval, make corresponding source accessible, publish GitHub/npm (`--access public --tag next`) and the cask/tap. Verify each real install route.

Check npm authentication and scope access at publication time. The existing scope is `@machineyearn`; local authentication is currently unavailable. Do not claim npm provenance for a private local upload.

## History and CI

The initial public repository uses a clean source commit. The original repository and complete history remain private, including legacy media and internal QA records. Never mirror-push that private history into the public repository. Credentials need revocation as well as cleanup; rewriting commits does not revoke them.

GitHub Actions is disabled on both the public repository and private history archive. The workflow files use manual triggers for a future restart. Run `make check` locally.

## Source preview artifacts

Use prerelease tag `v0.1.0-preview.3`. Upload the app ZIP, DMG, standalone CLI, source archive, `release.json` and `SHA256SUMS.txt`. Keep the blocked npm inspection package local until notarized installation is supported. Mark the GitHub release as a prerelease, never a stable notarized download.
