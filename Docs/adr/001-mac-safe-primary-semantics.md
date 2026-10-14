# ADR 001: Mac-safe PRIMARY semantics

## Status

Accepted.

## Context

X11 PRIMARY captures selected text broadly. macOS Accessibility can also report app-created selections, including browser URL bars, focus changes, framework selections, and web/Electron edge cases. A literal clone would be easy to explain but too easy to distrust as a background macOS utility.

## Decision

Primary Paste defaults to a macOS-safe PRIMARY model:

- Drag-selected text fills Primary by default.
- Middle-click pastes only into editable targets.
- Non-editable middle-clicks pass through to the current app.
- The normal macOS clipboard stays separate unless the user explicitly links it.
- Secure or protected content is never captured.
- Sensitive-looking selections are refused and not stored after inspection by the local filter.
- Broader capture is opt-in through Custom Gestures or Everything.

## Consequences

The default product promise is "drag-select text, middle-click an editable field, normal clipboard stays normal." Power users can move closer to X11 behavior, but the first-run experience stays conservative.
