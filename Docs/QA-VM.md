# Disposable macOS acceptance VM

The VM gives native input and clipboard testing its own macOS desktop. Background build and unit checks still run on the host. Input automation runs inside the guest, so ordinary host work can continue. Global input checks remain serial within that guest.

## Owned environment

This machine uses UTM 4.7.5 from its official GitHub release, verified against the published SHA-256 and accepted by macOS as notarized. The portable app, Apple restore image, sparse VM disk, transfer files, private test SSH key, and logs live in:

`~/Library/Application Support/Primary Paste QA`

The manifest records ownership, the VM UUID and path, and the UTM support folders that did not exist before installation. No Homebrew package, global symlink, launch agent, or host SSH server is installed. The VM has 4 CPUs, 16 GiB memory, and a 100 GiB sparse disk. Sound and clipboard sharing are off. Its sole shared directory is `Share`, read-only. Personal home folders and the repository are not shared.

## First guest setup

Installation is provisioned; guest setup and acceptance are separate steps. In the UTM window, complete Apple's setup yourself: accept the terms, create a disposable local administrator (`qa` is a suggested name), and skip Apple Account sign-in. Do not reuse a personal password. Credential creation and acceptance of legal terms require the user's direct involvement.

Finder normally mounts the transfer folder at **My Shared Files → Share** (`/Volumes/My Shared Files/Share`). If it is not mounted, use the guest Terminal:

```sh
mkdir -p "$HOME/QA-Share"
mount_virtiofs share "$HOME/QA-Share"
open "$HOME/QA-Share"
```

Open the `Share` directory in that mounted volume and run `SetupGuest.command`. It refuses to run on the physical host. It verifies and installs the signed Primary Paste app, copies disposable fixtures and the input helper, and adds the public test key for this guest account. It also asks for guest administrator authentication to install `/etc/sudoers.d/primary-paste-qa`. That rule permits only `/sbin/shutdown -h now` for this guest account, so background shutdown works at the login screen. It stores no password and grants no general sudo access. The private SSH key remains in the managed host folder.

Enable **System Settings → General → Sharing → Remote Login** inside the guest, allowing only the disposable guest account. Use its actual username if it differs from `qa`. This is the one-time guest access grant for background orchestration. Do not enable it on the host. Provide the displayed guest IP, username, and public SSH host-key fingerprint for the first connection; no guest password needs to be shared. The host's SSH known-hosts file and connection logs must also stay inside the managed folder.

Grant Primary Paste its requested Accessibility and Input Monitoring access in the guest. Grant the native test helper its guest Accessibility access when needed. macOS 27 presents these controls under **Device Control and Data Access**. Finder Automation is only needed for the file-capture lane. These guest settings disappear with the VM disk.

UTM's Apple virtualization backend does not offer its QEMU input scripting interface. Use SSH to invoke guest-local input tooling; repeatedly clicking the VM window from the host would still interrupt host work. [UTM macOS guest documentation](https://docs.getutm.app/guest-support/macos/) explains VirtioFS mounting and guest support.

## Daily commands

Run these from the repository:

```sh
python3 Scripts/qa_vm.py status
python3 Scripts/qa_vm.py up --headless
python3 Scripts/qa_vm.py down
```

`up --headless` saves the windowless runner choice in the owned manifest. Subsequent `up`, `down`, `reset`, `status`, and `teardown` use that choice. `qa_vm_runner.swift` opens the existing Apple-backend UTM package through Apple's Virtualization framework, preserving its disk, hardware identity and network address. It creates no host window, mouse-input view, clipboard bridge or sound device. The controller compiles and signs the runner inside the owned `Tools` directory with only the virtualization entitlement. No host Automation grant, screen viewer, launch agent or system service is required.

`down` requests an orderly macOS shutdown over the pinned guest SSH connection, including at login. If SSH is unavailable, it requests a normal guest power-button shutdown; that fallback can require guest confirmation. It refuses to force-kill the VM. The controller verifies the recorded owner, guest UUID, process executable and idle disk before restart/reset/removal. A reused PID, another registered guest or open storage stops the operation. `status` reports the selected runner and guest state.

UTM remains available for initial provisioning and manual recovery. Its CLI can fail with Apple Events `OSStatus -10004` after a cold app restart. That error is rejected even if the CLI returns exit code zero; it cannot be mistaken for an empty VM registry. The headless runner avoids this host Automation dependency.

Once the guest SSH account and host key are verified, record `guest.user` and `guest.host` in the owned manifest. Keep the private key and `known_hosts` in `Keys`. SSH's configuration parser needs quotes around a known-hosts filename containing spaces; `qa_guest.py` handles that quoting.

Install `Primary Paste QA Helper.app` into the guest-owned support folder and grant that app access. Keep its bundle identifier and development signing identity stable when rebuilding; replacing an ad-hoc signature can invalidate its Accessibility grant. Launch it through LaunchServices rather than executing its binary under `sshd`: the latter has a different permission context. The runner uses a background app launch with isolated output files, checks for a result, and removes its temporary files. Its inspector omits non-finite Accessibility frames so an expanded settings surface cannot crash JSON serialization. Native input allows time for a fresh Chromium page tree to activate; repeatedly setting AXManualAccessibility during input would restart that delay. `clipboard-types` reports only type names and hashes of available byte/string representations. Compare those available representations rather than treating a lazy macOS alias with no bytes as empty data.

```sh
python3 Scripts/qa_guest.py permissions
python3 Scripts/qa_guest.py clipboard
python3 Scripts/qa_guest.py --relaunch
python3 Scripts/qa_guest.py com.apple.TextEdit inspect
python3 Scripts/qa_guest.py com.apple.TextEdit drag 110,84 420,84
python3 Scripts/qa_guest.py com.apple.TextEdit middle 112,113 112,113
```

Use fresh inspected bounds for each named test window. Chrome, Edge, Safari and Arc are allowed targets. The inspector observes the exposed tree without enabling Chromium Accessibility itself, so inspection cannot hide a production startup failure. It includes non-secure selected ranges for checking the clicked caret. The helper refuses other windows and protected-field contents. Input completion means events were sent; inspect the actual field afterward and allow at least one second for the clipboard restore before comparing its representations or history. Browser reloads can open password-save dialogs for synthetic password fixtures; dismiss them and verify the named page again before sending more input.

`--shell 'command'` runs setup or diagnostic commands after checking the guest VM and ownership markers. Both modes require the pinned guest SSH host key. Close or minimize UTM after setup; the headless runner and these commands do not activate or send input to host windows. The Codex inspector accepts its generic “ChatGPT” window title only when the bundle is the exact disposable guest installation; other test windows still require their named fixtures. Inspection remains bounded and omits secure contents.

For guest login screens, permission dialogs, or apps outside the scoped helper, enable **Screen Sharing** inside the guest under General → Sharing. Allow only the disposable account. If it was enabled from the command line but produces black frames, turn it off and back on in the guest UI to complete macOS's screen-control grant. Keep the service confined to the VM; no host service is needed.

`qa_screen.py` connects to the guest's loopback Screen Sharing service through the same pinned SSH connection. It opens no host forwarding port, launches no host screen viewer, and leaves UTM minimized. It requires Python with Pillow and cryptography (the Codex bundled Python supplies both); missing dependencies now stop with an actionable message before any password prompt or SSH connection. Use that interpreter instead of a system Python missing these packages. It prompts for the existing guest password without echo and retains it only during authentication. Never pass credentials in arguments, environment variables, or files.

```sh
python3 Scripts/qa_screen.py
```

The interactive session accepts one JSON action per line: `{"action":"screenshot","name":"guest-check.png"}`, `{"action":"pointer","x":100,"y":100,"mask":0}`, `{"action":"key","code":65293,"down":true}`, or `{"action":"quit"}`. Pointer masks are 1 for left, 2 for middle, 4 for right; release with mask 0. Keys use X11 keysyms and require a matching release; the tested macOS Command mapping is Super_L (`65515`). Wait for every action result before sending dependent input. Take a fresh screenshot after window changes and verify the resulting UI before continuing. Screenshot responses include current width and height because login, reboot, and display changes can resize the guest. Pointer coordinates use screenshot pixels, which can be twice the helper's logical Retina coordinates. Screenshot files stay under the owned `Screens` folder. A connection established before login can retain an obsolete login frame after the desktop unlocks. Quit and reconnect after login, then verify a fresh desktop image before using coordinates. Never drive a window from a stale frame. Clipboard messages are discarded. Quit before stopping or resetting the VM; the client closes its SSH child and restores terminal echo. Timeouts fail the session rather than leaving a blocked reader indefinitely.

`--relaunch` waits for the correctly named **Primary Paste** process to exit and prints the new PID and executable digest. Run it only between idle tests; it does not force-kill the app. Replacing files on disk without restarting the running process does not test the new build.

Keep the guest display mode stable throughout an input run. After changing between Retina and non-Retina modes, restart the browser and inspect fresh bounds before testing. Safari retained stale Accessibility hit-testing after a display change even though its rendered fields looked correct; restarting Safari restored correct targeting. Do not reuse coordinates from a previous resolution or accept a screenshot alone as proof of the targeted field.

One host-side CUA scroll caused UTM to crash in Apple's Virtualization HID scroll path. Guest-local mouse input avoids that path. CUA also dropped Shift modifiers when typing into this VM; use SSH for commands and fixtures so case, Unicode, and punctuation remain exact.

After the clean guest account, permissions, and tools are ready, shut down and save one baseline:

```sh
python3 Scripts/qa_vm.py baseline
```

Restore that baseline between acceptance runs:

```sh
python3 Scripts/qa_vm.py down
python3 Scripts/qa_vm.py reset
python3 Scripts/qa_vm.py up
```

Baseline/reset use APFS clones. Reset prepares the new copy before replacing the existing package. It requires a stopped VM and preserves the working copy if preparation fails. An interrupted reset leaves staging paths for inspection rather than silently discarding them. Baseline creation refuses to overwrite an existing baseline. To refresh an old baseline, validate its package identity and stopped guest first, remove only that owned `Baseline.utm`, then save the new baseline. A full teardown removes the baseline too; a fresh environment then needs UTM and macOS provisioning again.

## Additional guest apps

Maccy 2.7.1 and CopyQ 17.0.0 are installed only inside the guest. Their official release archives were checked against the published SHA-256 values. Maccy passed vendor signature verification. The official CopyQ macOS archive failed strict verification on a bundled Qt TLS plug-in; the documented [CopyQ macOS signing workaround](https://github.com/hluk/CopyQ#macos) was applied only to the disposable guest copy, which then verified and launched. Neither manager is installed or launched on the physical host.

Codex uses a fresh guest profile. Its real local composer can be exercised in API-key mode with a clearly disposable, invalid fixture key. Do not copy a host profile or real credential, submit a model request, or describe this as authenticated ChatGPT-account coverage. Clear unsent drafts after testing.

## Teardown

```sh
python3 Scripts/qa_vm.py down
python3 Scripts/qa_vm.py teardown --preview
python3 Scripts/qa_vm.py teardown
```

Preview performs no writes or UTM actions. Teardown unregisters only the owned VM, exits only this managed UTM executable, checks for open managed files, and removes the owned folder and recorded external support files. In headless mode, it reads UTM registration without Apple Events and removes registration data only when its container was created for this environment and contains exactly this VM. UTM import can leave two registration UUIDs for one relocated package. An additional UUID belongs to this environment only if its recorded path resolves to the exact owned package; matching display names are insufficient. Other registrations still prevent removal. Pre-existing registration data is preserved by refusing removal; no live preference database is edited. It rejects a mismatched ownership record, symlinked VM location, other registered VMs, or another conventional UTM installation that could share support data. Existing UTM paths recorded before provisioning are preserved. Cleanup can be retried after a partial run.

No OS permission database is edited or globally reset. macOS may retain its own permission records or recent-item metadata for removed apps. Those small OS-managed records are distinct from running processes, installed helpers, or VM disk files. Teardown does not remove host Primary Paste, its settings, or the repository's audit evidence.

## Evidence boundary

The lifecycle guard tests run in `Scripts/tests` as part of `Scripts/check.sh`. They exercise cleanup ownership, non-mutating preview, busy files, other VMs, isolation checks, running-guest rejection, reset preparation failure, shutdown fallback, screen/input cleanup, reused runner PIDs, malformed state, and rejected foreign or forced-stop commands. These tests do not establish guest app compatibility.

On 2026-10-11, actual shutdown/start and APFS baseline/reset were verified. A disposable marker created after the baseline disappeared after reset; the pinned SSH identity and installed signed app survived. Full teardown has guard-test and preview evidence; the usable baseline was preserved rather than deleting it to claim a live cleanup pass. The VM is kept stopped between runs. Use the matrix in [Phase6Readiness](Phase6Readiness.md) and the dated results in [PhaseAudit](PhaseAudit.md) for app compatibility and remaining boundaries.
