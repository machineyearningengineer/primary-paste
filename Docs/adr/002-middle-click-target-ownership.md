# ADR 002: Middle-click target ownership

## Status

Accepted.

## Context

Middle-click already has useful native meanings in many apps: closing browser tabs, opening links, panning, or triggering browser extensions. Primary Paste should not steal those behaviors outside places where paste is expected.

## Decision

Target class decides who owns middle-click:

- Editable target: Primary Paste owns middle-click.
- Editable target with empty Primary: Primary Paste consumes the click as a no-op.
- Non-editable target: the current app owns middle-click.
- Pass-through app rule: the current app always owns middle-click.
- Secure or protected field: Primary Paste does not paste into it.

## Consequences

Browser tabs, links, pages, and extension gestures stay native outside editable fields. Inputs and editors get deterministic Primary paste behavior without app-specific middle-click hacks.
