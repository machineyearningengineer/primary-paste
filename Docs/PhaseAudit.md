# Primary Paste Phase Audit

This file defines what the project currently means by Phases 1-6.
Phases 1-5 are implementation-complete in the current app target; Phase 6 is the active product-readiness phase where the remaining work is trust, polish, and real-world verification.

## Phase 1 - Production App Foundation

Status: Complete.

Scope:

- Move from the prototype Swift Package wrapper to a real macOS app target.
- Establish stable app identity, signing, entitlements, icon assets, and install path.
- Run as a proper background Mac utility with menu bar presence and optional Dock presence.

Evidence:

- `PrimaryPaste.xcodeproj` is the supported app target.
- `PrimaryPaste/PrimaryPaste.entitlements` and `PrimaryPaste/Assets.xcassets/AppIcon.appiconset/Contents.json` exist.
- `/Applications/Primary Paste.app` uses bundle id `com.abel.primarypaste`.
- `Scripts/install_dev_app.sh` builds, installs, registers Launch Services, and opens the `/Applications` copy.
- `Scripts/phase6_verify.sh` verifies app identity, signing, entitlements, installed executable, Launch Services, and runtime presence.

Remaining risk:

- Developer-machine macOS permissions still need hands-on confirmation after signing or identity changes.

## Phase 2 - Primary Selection And Paste Core

Status: Complete with Phase 6 real-app verification still required.

Scope:

- Capture intentional text selections into a Primary buffer.
- Middle-click paste Primary into editable targets.
- Preserve normal left/right click behavior and avoid swallowing non-editable middle-clicks.
- Keep a small Primary queue with latest, stack, queue, and cycle paste modes.

Evidence:

- `SelectionEngine` uses AXObserver-first selection capture with fallback polling.
- `MouseEventTap` listens adaptively for drag intent, keyboard selection intent, and middle-click only when settings require them.
- `PasteController` gates paste through editable hit-testing and records pasted, consumed, and passed-through outcomes.
- `PrimarySelectionStore` owns Primary payload state and reversible snapshots for probes.
- Setup diagnostics show selection source apps, paste target apps, pass-through apps, and last paste/selection decisions.

Remaining risk:

- Actual middle-click paste and pass-through semantics must still be checked in real target apps because browsers, Electron apps, native fields, and terminal UIs expose different Accessibility behavior.

## Phase 3 - Onboarding, Permissions, And Recovery

Status: Complete.

Scope:

- Provide a first-run Setup surface inspired by modern native onboarding.
- Show exact permission status and only ask for permissions when current settings need them.
- Make recovery easy through reset/revoke tools, deep links, diagnostics, and menu actions.

Evidence:

- Setup has rows for Accessibility, Input Monitoring, and Finder Automation with current-state labels and System Settings actions.
- Permission need is conditional: Accessibility, Input Monitoring, and Finder Automation are optional when the enabled feature set does not require them.
- `primarypaste://show-setup` opens Setup for onboarding and support.
- The menu bar exposes setup, diagnostics, pause/private toggles, and permission health.
- `Scripts/phase6_smoke.sh` verifies setup deep-link opening, status item access, status labels, status-menu permission health, and diagnostics actions.

Remaining risk:

- macOS System Settings can delay or cache permission UI updates; the app refreshes state, but users may still need to reopen panes after OS-level changes.

## Phase 4 - Clipboard, Privacy, And App Rules

Status: Complete with Phase 6 real-app verification still required.

Scope:

- Keep Primary separate from the normal clipboard by default.
- Allow explicit Clipboard Link modes for importing Cmd+C copies or mirroring selections.
- Preserve the normal clipboard after paste on a best-effort basis for arbitrary rich multi-item clipboards; plain text and common file payloads are the primary supported cases.
- Suppress Primary's own programmatic clipboard writes.
- Protect private mode, blocked apps, secure fields, sensitive-looking text, and locked-screen sessions.

Evidence:

- `ClipboardLinkMode` defaults to `Separate`.
- `ClipboardObserver` checks programmatic suppression before reading payloads, and backs off in Private Mode or locked-screen sessions before payload reads.
- `PrivacyFilter` provides structured denial reasons shared by selection and clipboard diagnostics.
- Setup has Clipboard Link mode probes, a self-capture guard probe, and a sensitive-text privacy self-test.
- Diagnostics reports include clipboard mode, self-capture, privacy, source-app, target-app, and pass-through evidence.

Remaining risk:

- Private Mode, blocked apps, and secure fields still need real-world manual confirmation because those protections depend on live app and OS behavior.

## Phase 5 - Finder, Rich Payloads, Toasts, And Settings Polish

Status: Complete with Phase 6 real-app verification still required.

Scope:

- Support non-text payload flows where they fit the Primary model.
- Add optional Finder file selection capture with multi-select support.
- Add compact notch-style capture and warning toasts.
- Make text and Finder caps user-tunable while avoiding silent partial captures.
- Keep settings understandable without reading docs.

Evidence:

- Finder file capture is optional, off by default, and gated by Finder Automation.
- Finder selections are stored as pasteboard payloads so middle-click can paste or attach files into apps that accept file paste.
- Normal clipboard-copy import can capture richer pasteboard payloads when Clipboard Link is set to Import Copies and plain-text-only is off.
- Text selection caps are configurable from 500 to 250,000 characters, with an explicit unlimited mode.
- Finder file caps are configurable from 1 to 500 items.
- Over-limit text and Finder selections are refused as a whole and shown as subtle warning toasts.
- Toasts support source icon, one-line preview, source-label toggle, warning state, payload-aware continuation, and count/cap badges.

Remaining risk:

- Target apps decide whether file paste becomes an attachment, a file path, or nothing; that final acceptance has to be checked by hand.

## Phase 6 - Product Trust And Native Feel

Status: Active.

Scope:

- Make the app feel calm, native, and trustworthy under daily use.
- Prove that permission state, capture, paste, clipboard linking, Finder payloads, cap warnings, privacy, and browser pass-through behave correctly in real apps.
- Keep the app diagnosable without exposing selected content.

Evidence already in place:

- `Docs/Phase6Readiness.md` defines the Phase 6 product bar, automated gates, and manual gates.
- `Support -> Guided Troubleshooting` mirrors the remaining hands-on checks with proof labels, runtime evidence, target coverage, guided actions, fresh-run reset, app probes, and a copyable report.
- `Scripts/phase6_verify.sh` and `Scripts/phase6_smoke.sh` cover identity, signing, runtime, setup, menu bar, diagnostics, probes, and key source hooks.

Remaining Phase 6 gates:

- Browser URL-bar auto-selection must not pollute Primary.
- Browser link/tab middle-click behavior must remain native.
- Middle-click paste must be confirmed in native fields, web inputs, and Codex composer.
- Cross-app text capture must be confirmed in Safari/Arc, Codex, Terminal, TextEdit, and Finder name fields.
- Cmd+C/Cmd+V defaults and opt-in Clipboard Link modes must be checked with real clipboard-manager behavior.
- Finder file payloads, over-limit toasts, Private Mode, blocked apps, secure fields, and sensitive-looking text must be confirmed in live use.

## Bottom Line

Phases 1-5 are done as implementation milestones in the signed Xcode app.
Phase 6 is not a new feature bucket; it is the proof and polish layer that turns those features into a utility that feels safe to leave running all day.

## 2026-10-10 reliability and maintainability pass

The app and dormant backend were reviewed across capture, clipboard transport, paste ordering, preferences, privacy, input, startup, settings, diagnostics, licensing, and local verification. Regression fixes cover payload identity, rich multi-item replay, exact text whitespace, delayed-paste cancellation, stale capture work, retention limits, Queue/Cycle previews, toast cleanup, clipboard-check recovery, activation seats, claim/refresh retries, and out-of-order refunds. Backend dependencies were patched after the previous quality gate failed its vulnerability audit.

The quality gate now includes backend SQLite/cryptography integration tests. Preflight was reduced to structural and installed-app checks; hundreds of source-string assertions were removed because they could not prove behavior and had drifted from capability-owned source locations. Signed installation verifies the staged build and retains a recoverable previous app.

Local automated checks and observed signed-app journeys are reported separately. They do not complete the remaining cross-app acceptance, OS permission, attachment, or live payment gates merely by passing.

Verification on 2026-10-10: the complete `Scripts/check.sh` gate passed, with 56 XCTest tests, five backend SQLite/cryptography integration tests, zero dependency vulnerabilities, and 14 structural preflight checks. The final signed development app was installed with recovery backup; all 22 installed-app preflight checks passed, including an executable comparison with the verified build.

Observed native UI checks confirmed settings navigation and keyboard tab shortcuts, healthy live-engine status, clipboard Separate behavior, temporary-payload self-capture isolation, and the sensitive-text self-test. Support was temporarily shown for verification and returned to its previous hidden setting. The existing manual App Checks completion record was not changed. Mouse-drag automation repeatedly failed with a `noWindowsAvailable` error, and an accessibility middle-click action produced no input evidence, so neither gesture capture nor native middle-click pass-through was credited as verified. Cross-app text/input journeys, file attachment acceptance, permission revocation/recovery, clipboard-manager interactions, and live Stripe flows remain acceptance work.

## 2026-10-11 onboarding and compatibility follow-up

Setup now teaches selection and paste with three brief steps, opens a local browser practice page, and offers a one-click exit into quiet menu-bar use. New-install defaults keep repeat Setup windows off while preserving existing saved choices. Permission guidance stays beside its action; advanced details stay folded. Readiness now checks actual enabled-service startup and licensing availability rather than declaring intentional clipboard-link choices broken. A failed service can be retried without changing settings. Practice guidance names the actual blocker when paused, private, unlicensed, disabled, or awaiting a service. The signed installed layout and the practice-page launch/rendering were observed. The page includes trackpad/shortcut guidance, a local native-link check, and no scripts, forms, or outbound resources.

Selection capture now performs one settled read just after a deliberate gesture. This closes the gap where an editor emits no AX selection notification and the fallback poll runs after the short gesture-settle window. Capture remains gated by the current app, gesture scope, permissions, privacy, and enabled source.

The complete quality gate passed again: 56 XCTest tests and five backend integration tests, zero dependency vulnerabilities, and successful build/structural checks. The signed update was installed with a recoverable previous copy. Runtime history contained multiple Arc captures from the benign practice page; that establishes observed browser capture, but not a completed automated selection/paste journey. CUA drag attempts in both Primary Paste and TextEdit failed before usable input evidence. CUA keyboard select-all worked inside TextEdit, but did not produce matching capture or shortcut-paste evidence; temporary gesture and shortcut settings were restored. No unrelated app acceptance or manual checklist completion was inferred. The user subsequently authorized the scoped native input fallback. No macOS grants were changed. The fallback was limited to named disposable test windows and rechecked the frontmost app before sending events.


The native input follow-up established actual TextEdit drag capture, middle-click insertion at the clicked caret, and two repeated native pastes. A content-free fingerprint of available normal-clipboard representations remained unchanged. Native Chrome captured the exact practice sentence and accepted a middle-click paste into the textarea; the clipboard fingerprint was restored after the Cmd+V transport. Focusing Chrome's address bar selected its URL without replacing Primary.

Browser dragging exposed a real queue regression: AX notifications during one drag retained several intermediate strings. Capture now waits for drag completion before scheduling or committing a retained item. After the signed patch was installed, the same Chrome gesture retained exactly one complete sentence. The final follow-up also clears completed debounce work when it is skipped during a drag, so it cannot suppress a later settled read.

A two-trigger browser repeat run ended with one copy in the field. Window activation was initially unreliable in the test harness, so repeat browser delivery remains unresolved and is not recorded as passed. Native link/tab behavior, browser input/contenteditable, Codex, terminal and Finder targets, real attachments, live privacy/cap boundaries, clipboard-manager interaction, and permission revocation/recovery still require isolated interactive acceptance. Existing manual App Checks records were not altered.

Further desktop input was stopped when the user asked about testing without interfering with their work. Hostless XCTest, backend tests, formatting, dependency auditing, source review, and preflight can continue on the host without global mouse input. The native harness is a local test tool, not a shipped app feature.

## 2026-10-11 isolated VM provisioning

At the user's request, UTM 4.7.5 was installed as a portable app under `~/Library/Application Support/Primary Paste QA`, with its official release digest verified, its signature checked, and macOS notarization acceptance confirmed. Apple's Virtualization framework supplied the compatible macOS 27.0.1 restore image (26A434); the downloaded Apple CDN archive was validated before installation. UTM was not installed through Homebrew, and no host launch agent or SSH server was created.

The Apple-backend VM is registered from the managed `VM` folder with four CPUs, 16 GiB RAM, and a 100 GiB ASIF sparse disk. `diskutil image info` confirmed the virtual capacity independently of the four-megabyte initial allocation. Sound and clipboard sharing are disabled. Sharing settings show only the dedicated QA `Share` folder, read-only. macOS installed successfully and reached first-boot Setup. The user was asked to take over for Apple legal terms and creation of the disposable guest account; credentials were not entered by the agent.

`Scripts/qa_vm.py` provides status, start, graceful stop, clean baseline, reset, and teardown. Eight lifecycle safety tests passed against disposable fixtures, covering ownership, symlink boundaries, non-mutating preview, package identity and clipboard isolation, other registered VMs, busy-file preservation and retry, running-guest rejection, and failed reset preparation. The real CLI returned the owned VM's `started` state. Teardown preview lists the managed root and six newly created UTM application/group containers or application-script folders. The live working VM was not deleted to claim cleanup proof. Baseline/reset and full live teardown remain unverified until guest setup is complete and a disposable lifecycle run is available.

The signed Primary Paste bundle, local browser fixtures, compiled guest-only scoped input helper, and a public test SSH key are prepared in the read-only transfer folder. The private key remains in the owned host folder. Guest setup and native input refuse to run on the physical host; both refusal paths were verified without sending input. The input helper additionally rechecks the exact test window and bounds before every event. Guest account setup, Remote Login access limited to that account, guest app/helper permissions, and the remaining real-app matrix are still pending. No existing manual App Checks record was changed and no all-working commit was made.

The [QA VM guide](QA-VM.md) documents the setup handoff and lifecycle commands. Cleanup preserves pre-existing UTM files and refuses shared-data removal if another conventional UTM installation or other registered VM is present. It removes owned disk, installer, keys, transfer data, support folders, and app processes; it does not edit macOS's permission database or claim removal of OS-managed recent-item metadata.

The complete quality gate passed after VM tooling was added: eight lifecycle safety tests, 56 XCTest tests, five backend integration tests, zero dependency vulnerabilities, successful build, and 14 structural preflight checks. The log is `.artifacts/quality-audit-2026-10-11/vm-preparation-check.log`. The earlier agent-owned host practice HTTP server on port 8127 was stopped normally; the guest fixtures use local files and do not require that host process.

The user subsequently completed the macOS setup handoff, and the guest Finder desktop was observed. Guest-only SSH provisioning and test permissions are still pending. CUA's guest-window coordinate clicks initially worked for Finder navigation, then repeatedly returned `noWindowsAvailable`; refreshing the binding and raising only the VM window did not restore input routing. No alternative host input was sent to bypass that failure. The prepared guest setup command and account-limited Remote Login handoff are the next step toward guest-local automation.

### Guest-local testing follow-up

The user authorized guest app/helper grants and account-limited SSH setup. The setup command installed the signed app and public key. A guest-only guarded command enabled SSH with `com.apple.access_ssh` containing only the disposable guest account. The host connected using the dedicated key; its pinned host-key record is inside the managed `Keys` directory. No host SSH server or new host permissions were enabled. The guest app reports capture Running and middle-click Listening. The helper's LaunchServices permission check reports Accessibility true; directly executing it under sshd reports false, so the runner deliberately uses its approved GUI app identity.

CUA coordinate input remained intermittent, and its shifted characters were not delivered correctly to the virtual keyboard. A scoped, previously authorized native fallback completed the guest setup. One CUA scroll was followed by an actual UTM crash: the report at 16:11:40 names `EXC_BREAKPOINT/SIGTRAP` in `_VZHIDEventMonitor getHIDReportsFromHIDEvent:`, `_VZPointingDevice sendScrollWheelEventsHIDReport:pointingDeviceIndex:`, and `VZVirtualMachineView scrollWheel:`. The guest booted again successfully. Input now runs inside the guest over SSH, avoiding this host scroll path; UTM stays minimized.

The first guest-local background run captured exactly `Primary Paste native selection check.` in TextEdit and accepted two middle-click insertions. The resulting field contained the source plus two complete copies, and content-free normal-clipboard fingerprints matched. These were native guest interactions, not DOM edits or command-delivery-only evidence. Temporary runner result files are removed automatically. An SSH filename quoting issue was corrected, and its sole misplaced test host-key file was moved into the managed root with no remaining stray file.

A fresh Chrome process exposed only its toolbar Accessibility tree. Dragging the page did not replace Primary; a native paste still produced the prior TextEdit sentence. Primary Paste now requests Chromium's page accessibility mode once per process before observation/targeting. Repeated requests would restart Chrome's two-second activation delay. This behavior is documented in Chromium's [application accessibility implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm). Browser acceptance of the signed fix is being checked; no browser pass is inferred from this source change.


## 2026-10-11 completed guest acceptance and background testing

The final signed host/guest executable SHA-256 is `3010a2070c6280f6dd145ac7e278c9af4d78b7f4f79d609877dd804523413b48`. The final complete gate passed: 56 XCTest tests, five backend SQLite/cryptography integration tests, 18 lifecycle/screen tests, formatting and architecture checks, zero audited dependency vulnerabilities, build, and 14 structural preflight checks. Installed-app preflight passed 21 checks with one warning because the host app was intentionally not running during background work. No remote CI, push, release, or live payment activation was performed.

Chrome page Accessibility now activates once per process. Actual input, textarea and contenteditable journeys accepted Unicode, tabs, clicked-caret insertion and repeated paste. A contenteditable surface normalized boundary spaces to non-breaking spaces as part of its native editing behavior; the source selection and restored normal clipboard remained intact. Native link opening, native tab middle-click closure, and address-bar automatic-selection exclusion were observed. A focus-race fixture moved focus during a delayed paste: neither field received the cancelled insertion, and a subsequent stable paste worked. Rich clipboard fingerprints were compared after the transport settled, rather than while its temporary payload was still installed.

Safari exposed selection through `AXSelectedTextMarkerRange` instead of the usual selected-text/string-range attributes. Selection reads now request only `AXStringForTextMarkerRange` after checking that the element is not secure or protected. This fixes Safari page capture without issuing a copy command or reading the whole page. The underlying attributes are defined in WebKit's [macOS Accessibility wrapper](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm). On the final signed build, Safari source capture and input/textarea insertion passed, including Unicode, tabs and newlines. Chrome and Safari protected-field selection rechecks retained the prior safe Primary item and accepted that safe item in the intended editable field. Chrome's second paste used the clicked caret at offset one; its expected string was computed from that observed caret, not assumed to append at the start or end.

Safari initially mis-targeted a textarea after the guest changed from Retina to non-Retina display mode. Inspection showed an Accessibility hit outside the returned element's frame. Restarting Safari restored correct hit-testing; no speculative production targeting workaround was added. The QA guide now requires stable display mode, a browser restart after mode changes, and fresh coordinates.

TextEdit drag capture and repeated clicked-caret paste, Terminal deliberate selection, ordinary Cmd+C/Cmd+V in Separate, Import Copies and Mirror Selections were observed. Blocked-app and synthetic-sensitive selections retained the preceding safe item. Text and Finder caps rejected an over-limit selection as a whole. Private Mode prevented new capture. Finder rename text had been overwritten by file polling; the observer now skips file capture while an editable Finder field has focus. The corrected rename selection remained text across the poll, while normal file selection still worked. Notes accepted one and two actual file attachments, including the expected two attachment cards; command delivery alone was not used as acceptance evidence.

These native journeys used the signed preceding executable beginning `1e4edd5e`, before the Safari-only selected-marker fix. Earlier ambiguous runs that replaced files without exiting the correctly named `Primary Paste` process are not credited as final-build proof. The runner now waits for that process to exit and reports the new PID and executable digest. Final Chrome and Safari rechecks used the exact final SHA above.

Setup's three steps, practice action and Continue in Menu Bar were observed in the guest. Continue closed Setup, left the app running, and saved quiet startup. Permission loss stopped the affected capture/input services; restoring guest access and relaunching recovered healthy services and native paste. Reboot/reset preserved the pinned SSH identity and signed installation. Temporary Support visibility, clipboard mode, private mode and selection caps were restored. The manual App Checks record was not marked complete by these external tests.

The reported VM crash was UTM in Apple's Virtualization HID scroll path (`_VZHIDEventMonitor` / `VZVirtualMachineView scrollWheel:`), rather than a Primary Paste crash. Testing moved to guest-local input over pinned SSH and guest Screen Sharing over that SSH connection; no host cursor input or foreground UTM activation was used for these remaining runs. A separate QA inspector failure came from non-finite Accessibility frames when Support was expanded. The helper now filters those frames and the expanded Support inspection returned valid JSON. Its development signature and guest Accessibility grant were verified.

Normal guest shutdown works over SSH even before desktop login, using a guest-only sudo rule permitting exactly `/sbin/shutdown -h now`. Actual start/shutdown and APFS baseline/reset passed. A post-baseline marker disappeared on reset; the final signed executable, helper signature, SSH identity and narrow shutdown rule survived. The baseline contains the final app and restored settings. The VM is left stopped, with its recovery baseline retained. Teardown has guard-test and non-mutating preview evidence; the usable environment was not destroyed to claim a live full-removal pass.

Detailed local evidence is under `.artifacts/quality-audit-2026-10-11/`: `safari-final-check.log`, `final-runtime-preflight.log`, `guest-final-secure-proof.json`, `guest-final-safari-secure-proof.json`, `guest-safari-stable-display-proof.json`, `guest-focus-cancellation-proof.json`, `guest-finder-rename-after-fix.json`, `guest-file-cap-proof.json`, `guest-permission-recovery-ui.json`, `guest-final-support-inspect.json`, and `guest-final-baseline-reset-proof.txt`. Guest screenshots remain in the managed VM environment's `Screens` folder, including `guest-notes-two-current-result.png` and `guest-onboarding-resized.png`. Logs and guest credentials are excluded from the commit.

Authenticated Codex composer remains unverified: its fresh guest installation reached sign-in, and no host profile or credentials were copied. A real third-party clipboard manager, complete final-build Arc journey, physical-host mouse/trackpad mappings, and live Stripe/licensing flows remain acceptance boundaries. Payments and enforcement stay disabled. The existing design audit images show intermediate layouts, not a substitute for the final runtime observations.


## 2026-10-11 Codex, clipboard managers and windowless acceptance

The current signed host/guest executable SHA-256 is `f34f7e1ea4400aaad1119b78ed6ef502019865320c7e62d69b56c7576d789670`. The final gate passed 58 XCTest tests, five backend integration tests and 30 lifecycle/screen tests, plus formatting, architecture/privacy checks, dependency auditing with zero vulnerabilities, build and 14 structural preflight checks. Installed-app preflight passed 21 checks with one warning because the host app remained intentionally stopped. There was no remote CI run, push or release.

CopyQ 17.0.0 captured a temporary Primary Paste transport into history even though it carried the existing transient and autogenerated markers. Publishing Apple's concealed UTI alone also failed the native repro. CopyQ's [macOS clipboard implementation](https://github.com/hluk/CopyQ/blob/v17.0.0/src/platform/mac/macclipboard.mm) checks the concealed MIME name; its [Qt converter](https://github.com/hluk/CopyQ/blob/v17.0.0/src/platform/mac/copyqpasteboardmime.mm) does not map the Apple UTI to that name. Temporary text and snapshot transports now carry both the Apple concealed UTI and the Qt UTI encoding of that MIME type. Explicit user copies remain ordinary. Import also excludes a clipboard carrying only the Qt concealed marker.

A native probe established the Qt marker fix before app rechecks. Actual repeated Chrome and Codex pastes subsequently left CopyQ's history count unchanged. Maccy 2.7.1's visible history contained ordinary copies and rich fixture items without the temporary Unicode payload. Both managers replayed an ordinary history item, which ordinary Cmd+V inserted into Chrome's actual textarea. Their official archives were digest-verified. Maccy's original signature verified; CopyQ's bundled Qt TLS plug-in failed strict vendor verification and its initial launch failed. The official [macOS signing workaround](https://github.com/hluk/CopyQ#macos) was applied only to the guest CopyQ copy, which then verified and ran. No clipboard manager was installed or launched on the host.

Codex opened its real local composer in API-key mode with an invalid disposable fixture key, following the app's alternative authentication UI. No real credential or host profile was copied, and no model request was submitted. This establishes the local editor behavior, not authenticated ChatGPT-account or API-service coverage. The [OpenAI authentication documentation](https://learn.chatgpt.com/docs/auth#openai-authentication) describes the alternative API-key entry point.

The first Codex paste exposed a production bug: its web area was 22 ancestors above the composer, beyond the ten-ancestor classification limit. AXValue on the empty editor exposed its placeholder. Treating that editor as native inserted the placeholder into the draft. Web classification now follows bounded ancestry through deeply nested editors; an unfinished or cyclic ancestry uses normal paste. The regression test covers the observed deep tree, a genuine native tree, an unfinished tree and a cycle. On the final signed build, the empty composer accepted the exact Unicode/tab sample, a second paste inserted it at the observed clicked caret, and the placeholder was absent from the draft. A deliberate Codex drag then became the exact text inserted into Chrome's clicked textarea caret.

These final Codex journeys ran with both managers active and a two-item clipboard containing plain text, RTF, HTML, PNG and a file URL. All originally available raw-byte and string representations survived. A coarse fingerprint initially differed because `public.utf16-external-plain-text` had no bytes before the paste and became materialized afterward. The inspector now records content-free hashes for available representations separately; the original strings and every originally available byte representation matched after restoration. This is not evidence of preserving unavailable lazy representations. The QA helper also stopped resetting Chromium's Accessibility activation delay during every input command, waits for a fresh page tree, and inspects the deeper tree without reading secure content. Unsent Codex drafts and both managers' disposable histories were cleared after testing.

UTM's CLI returned Apple Events `OSStatus -10004` on a cold app restart, even with exit code zero. The lifecycle now rejects that error rather than interpreting it as an empty registry. `up --headless` selects a native Apple Virtualization runner for the existing UTM disk and platform identity. It has no host window, input view, clipboard bridge or audio device. Guest input and display remain behind the pinned SSH connection. No host Automation permission was granted and no host cursor input was sent. Screen Sharing connections established before login can retain a stale login image; the guide requires reconnecting after unlock before using coordinates.

The cold-start guard found an obsolete original registration and UTM's imported registration UUID for the same relocated package. It now recognizes an import alias only when the recorded package path resolves to the exact owned package. Other guests, reused process IDs, malformed state, open storage, and forced-stop requests remain rejected. The exclusively owned registration container can be removed during teardown without editing a live preferences database or requiring Apple Events.

Actual headless cold start, orderly shutdown at login, APFS baseline refresh and reset passed. A post-baseline marker disappeared after reset. The current app digest, app/helper/manager signatures, quiet-startup choice, pinned SSH connection and exact shutdown-only sudo rule survived. The final Setup still showed Ready to Use, Running capture, Listening middle-click and Separate clipboard mode; Continue in Menu Bar closed it. The refreshed baseline retains the signed app and guest tools. The VM was left stopped, with no live owned UTM, runner or screen-client process. A read-only foreground check still reported the host's Chrome. Full teardown retains guard-test and preview evidence; the usable baseline was not destroyed to claim full live removal.

Current local evidence includes `managers-codex-final-check.log`, `managers-codex-runtime-preflight.log`, `final-codex-manager-proof.json`, `final-codex-capture-proof.json`, `guest-maccy-replay-result.json`, `guest-copyq-replay-result.json`, `guest-rich-manager-proof.json`, `headless-cold-start-proof.txt`, `headless-baseline-reset-proof.txt`, and `headless-lifecycle.log` under `.artifacts/quality-audit-2026-10-11/`. Screenshots remain in the owned VM environment. These fixtures and logs are excluded from Git; the manual App Checks records remain unchanged.

Authenticated ChatGPT-account Codex mode, a complete final-build Arc journey, physical-host input mappings and live payment/licensing remain unverified. Payments and enforcement remain disabled. Other native, browser, privacy and attachment evidence retains the earlier executable boundaries documented above; no universal app compatibility is implied.

## 2026-10-11 final background browser acceptance

The final signed executable remained `f34f7e1ea4400aaad1119b78ed6ef502019865320c7e62d69b56c7576d789670`. All GUI input and display checks ran inside the windowless VM through pinned SSH; no host window was opened or activated, and no host cursor input was sent. The final local gate passed 58 Swift tests, five backend integration tests and 31 QA lifecycle/screen tests, with zero audited dependency vulnerabilities, a successful build and 14 structural checks. Installed-app preflight passed 21 checks with one warning for the intentionally stopped host app. No remote CI, push or release was performed.

Chrome 155.0.8059.39, Edge 155.0.4283.45 and Safari 27.0.1 each captured the exact local Unicode/tab sample from a deliberate page drag. Two native middle-clicks inserted it at the clicked input caret; the textarea preserved its existing newline content. Each browser's contenteditable accepted the sample. Chromium and WebKit represent some inserted spaces as non-breaking spaces; each result matched that browser's ordinary Cmd+V using the same plain-text clipboard sample. Exact input/textarea values, contenteditable control values and originally available clipboard representations were compared rather than inferring acceptance from a sent event.

In all three browsers, selecting a synthetic protected field left the previous Primary intact. Protected-field middle-clicks were exercised, followed by a textarea paste that still used the previous Primary; protected values were excluded from inspection. Automatic address-bar selection also left Primary unchanged. Middle-clicking the local link opened a second native tab, and middle-clicking that tab closed it. The password fixture caused Safari to offer its native password-save dialog on reload; it was declined, and the named page was rechecked before the plain-paste control continued. No password was saved or sample submitted.

These journeys ran with Maccy 2.7.1 and CopyQ 17.0.0 active. The two-item rich fixture retained every originally available byte and string representation across the text transports, including RTF, HTML, PNG and a file URL. CopyQ's history count stayed unchanged during each journey. A separate final check began with one ordinary text item in both managers, then performed two real Edge pastes: both histories still contained only that ordinary item, and the normal clipboard representations matched. Maccy's visible before/after history was inspected. Both disposable histories were cleared afterward; Maccy's empty history and CopyQ's zero count were observed. This does not claim preservation of initially unavailable lazy formats or identical rich-history deduplication behavior in every manager.

Edge came from [Microsoft's official update feed](https://edgeupdates.microsoft.com/api/products?view=enterprise), with its package digest compared to the published SHA-256 and its installer signature/notarization verified. Only the browser app was transferred into the guest; no host Edge installation or profile import occurred. Browser-created update services remain inside the VM disk. Chrome's running framework mapped version 155.0.8059.39, confirming the runtime version after its guest update. Chrome, Edge and Safari signatures verified.

Arc's app binary was copied without its host profile. Omitting Finder/resource metadata allowed the original transferred vendor bundle to verify. Arc updated itself to 1.168.0 and stopped at account creation/sign-in in the fresh guest; no account was created or host credentials copied. Its post-update strict verification also reported Finder metadata, which was not changed after macOS refused that metadata edit. A complete Arc journey remains unverified. Chrome, Edge and Safari provide the completed browser acceptance requested as alternatives.

The QA inspector now allows Edge, records non-secure selected ranges, and observes the browser tree without enabling Accessibility itself. Its earlier inspection-time request could restart Chromium's activation delay and obscure the production behavior. Clipboard comparisons now wait for the restore to settle; an early Chrome comparison saw the temporary one-item transport, while the settled comparison confirmed the original two-item clipboard. The optional screen tool now reports missing Pillow/cryptography before asking for credentials or connecting; its regression test verifies both boundaries. No new production app regression surfaced in this browser pass.

Quiet guest defaults were restored, including Separate clipboard mode, hidden Support, no repeat Setup and no launch-at-login. The app was restarted with its stable signature and digest intact. The Screen Sharing transport was closed before orderly guest shutdown. The owned baseline was refreshed with the current app/helper and guest browsers, preparing and validating its APFS clone before replacing the previous baseline. A subsequent cold start created a disposable marker; normal shutdown, reset and cold start removed that marker while preserving the current app/helper/browser signatures and quiet defaults. This lifecycle check ran at the guest login screen without opening a host window. The VM was left stopped with no owned runner, UTM executable or guest SSH transport remaining. Teardown still has lifecycle-test and non-mutating preview evidence rather than a claim of deleting the usable VM.

Evidence is retained under `.artifacts/quality-audit-2026-10-11/`: `browser-current-proof.json`, `browser-final-check.log`, `browser-xctest-summary.json`, `browser-runtime-preflight.log`, `browser-baseline-reset-proof.txt`, `browser-host-cleanup-proof.txt`, `browser-teardown-preview.txt`, the `chrome-current-*`, `edge-*` and `safari-current-*` inspections, and `browser-managers-plain-*`. Maccy before/after/empty history and Arc's account boundary screenshots remain in the owned VM's `Screens` folder. Evidence files, VM data and keys are excluded from Git. Native/attachment checks retain their earlier executable boundary; authenticated ChatGPT-account Codex mode, physical-host input mappings and live payments/licensing remain unverified. Manual App Checks completion records were not changed.
