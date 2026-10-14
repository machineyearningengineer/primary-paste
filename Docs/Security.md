# Privacy and security

## App defaults

- Selections stay in memory; captured text and clipboard contents are excluded from diagnostics.
- Secure fields and protected Accessibility elements are refused.
- Sensitive-text filtering is a heuristic. Block apps that must never be captured.
- Private Mode stops new capture/imports; retained items can still be pasted. Clear Primary removes them.
- Finder file capture is optional and off. Payments and license enforcement are disabled.
- No remote analytics, crash upload or account is required for ordinary use.

## Clipboard restoration

Some targets need a normal paste command. The app briefly stages the selection, then restores the previous available clipboard representations. A newer user copy wins. Cooperating clipboard managers recognize temporary transport markers; lazy app-specific formats remain best-effort.

## Permissions and reports

Grant permissions to one stable installed copy. [Setup](GettingStarted.md) explains each permission. Inspect support reports and screenshots before sharing them; remove private data and unrelated windows.

[Vulnerability reports](../SECURITY.md) go privately to the maintainer.

## Developer rules

- Keep secrets and signing keys out of Git; use Keychain for app credentials.
- Never log captured content, private paths, tokens or payment identifiers.
- Diagnostics are bounded and content-free. New remote collection needs clear disclosure and an explicit opt-in.
- Serialize temporary clipboard operations; check ownership before restoring. Preserve newer user changes and selections.
- Keep backend secrets server-side; bind D1 parameters, verify raw Stripe webhook signatures and make processing idempotent.
- Verify entitlement signatures, device binding, audience and expiry before storing them. Online revocation removes cached entitlements.
