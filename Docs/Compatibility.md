# Compatibility

This matrix records observed behavior, not a universal compatibility guarantee. Runtime checks used a disposable Apple Silicon macOS VM on 2026-10-11. [The audit](PhaseAudit.md) retains build boundaries; [readiness](Phase6Readiness.md) covers deeper acceptance.

| App / area | Observed | Limits |
| --- | --- | --- |
| Chrome 155.0.8059.39 | Selection, Unicode, clicked-caret/repeated paste, input/textarea/contenteditable, native link/tab middle-click | Local synthetic browser fixtures |
| Edge 155.0.4283.45 | Same browser journey | Local synthetic browser fixtures |
| Safari 27.0.1 | Same journey, including WebKit selection markers | Local synthetic browser fixtures |
| Codex local composer | Cross-app capture and repeated Unicode/tab paste at the clicked caret | API-key mode with an invalid disposable fixture; authenticated account mode unverified |
| Maccy 2.7.1 / CopyQ 17.0.0 | Ordinary copies retained; temporary paste transports excluded | Rich lazy formats and identical-item history deduplication are not guaranteed |
| TextEdit / Terminal | Native text selection and paste/capture journeys | Earlier build boundary before final browser fixes |
| Finder / Notes | Rename text, optional file capture, actual one/two attachments | Earlier build boundary; target acceptance depends on the app |
| Arc 1.168.0 | Fresh guest install reached account gate | Full signed-in journey unverified |
| Onboarding / permissions | Local practice, continuation, revoke/recover, relaunch and reboot | Guest observation; physical mouse/trackpad mappings unverified |
| Intel Macs | Universal build target | Runtime acceptance unverified |

Browser contenteditable whitespace follows that browser's ordinary plain-text paste behavior. Protected selections are refused; this does not establish every target's protected-field behavior. Available rich clipboard representations were tested; unavailable lazy representations remain best-effort.

## Report an app issue

Include Primary Paste/macOS/app versions, a small synthetic example, the capture and clipboard modes, permission state and app rules. Say whether selection failed, the wrong field received paste, paste was absent, or native middle-click changed. These are different failures. Do not upload your actual clipboard history.
