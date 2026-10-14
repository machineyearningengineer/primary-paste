# ADR 003: Selection capture modes

## Status

Accepted.

## Context

"Intentional selection" is not one behavior. Drag-selecting text, double-clicking a word, triple-clicking a paragraph, extending with Shift-arrow, and pressing Cmd+A have different user intent and different capture risk.

## Decision

Selection capture is tiered:

- Safe Drag: default. Only drag selections fill Primary.
- Custom Gestures: drag stays on, and users can independently add double-clicked words, triple-clicked lines or paragraphs, Shift-arrow ranges, and Cmd+A select-all.
- Everything: captures any selected text macOS exposes, subject to privacy and cap rules.

Double-click and triple-click are capture gestures. Middle-click remains a paste trigger and is not part of selection capture settings.

## Consequences

Users can compose the PRIMARY feel they actually want. The app avoids a coarse "intentional" bundle that would force someone who wants double-click capture to also accept Shift-arrow or Cmd+A capture.
