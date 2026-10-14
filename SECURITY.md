# Security

Primary Paste can read selected text and control paste in apps you authorize. Privacy mistakes deserve careful handling.

Use [GitHub private vulnerability reporting](https://github.com/machineyearningengineer/primary-paste/security/advisories/new). Do not put captured content, credentials or an exploit involving private data in a public issue.

Include the version/build, macOS version, affected target app, a synthetic reproduction and the suspected privacy or security boundary. A report does not need a working patch. AI-assisted findings must be verified and clearly distinguish observed behavior from speculation.

Security fixes target `main` during the preview. There is no guaranteed response time. Published preview downloads are unsigned and not notarized; checksums verify their bytes, not Apple trust. Keep Gatekeeper enabled. A signed, notarized installer is still pending.

See [security architecture](Docs/Security.md) for capture, clipboard, diagnostics and dormant backend boundaries.
