# Security

Primary Paste can read selected text and control paste in apps you authorize. Privacy mistakes deserve careful handling.

Use [GitHub private vulnerability reporting](https://github.com/machineyearningengineer/primary-paste/security/advisories/new) if available. If it is unavailable while the repository is private, contact the maintainer through the existing private repository channel and ask for a private reporting route. Do not put captured content, credentials or an exploit involving private data in a public issue.

Include the version/build, macOS version, affected target app, a synthetic reproduction and the suspected privacy or security boundary. A report does not need a working patch. AI-assisted findings must be verified and clearly distinguish observed behavior from speculation.

During preview, security fixes target the current development branch. No published release line or guaranteed response time exists yet. Distribution must use verified signatures, checksums and notarization; do not work around Gatekeeper by disabling it or stripping quarantine.

See [security architecture](Docs/Security.md) for capture, clipboard, diagnostics and dormant backend boundaries.
