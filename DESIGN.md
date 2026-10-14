---
name: MSI Firmware Updater
description: A native macOS service worksheet for inspectable firmware transactions.
spacing:
  tight: "4px"
  related: "8px"
  field: "12px"
  detail: "16px"
  section: "20px"
  header: "24px"
---

# Design System: MSI Firmware Updater

## Overview

**Creative North Star: "Native service worksheet"**

An expert desktop utility with explicit device and image identities, readable evidence and a deliberate write boundary. Use macOS conventions and factual status rather than decorative instrumentation. Technical detail belongs in the manifest and activity views, close to the claims it supports.

Key characteristics: paired source/target facts, persistent readiness/action footer, native navigation and controls, and an activity ledger driven by actual backend events.

## Colors

Use dynamic SwiftUI semantic colors: primary text, secondary supporting text, system window background and the native bar material for the footer. The system accent marks the primary action and active phase; orange marks compatibility/downgrade warnings, red marks errors and green marks verified completion. Always pair color with text or an SF Symbol. Appearance follows the Mac; no fixed light/dark palette or custom contrast ramp is defined.

## Typography

Use system text styles: semibold title2 for the window heading and review action, medium title3 for identities, headline for section labels and callout for facts and supporting copy. Versions and operation counts use monospaced digits. Only hashes use a monospaced font. Preserve selectable technical values and wrapping warnings/paths; do not use truncation to hide decisions.

## Layout

Default content size is 940 × 840 points; minimum is 860 × 800. SwiftUI dimensions are points, corresponding to the numeric spacing scale above. Main content is centered with a maximum width of 1080; the footer has a maximum width of 1120. Header padding is 24, workspace/footer padding 20, detail groups 8–16. Installed and selected identities have equal width. Four native tabs separate Update, Image details, Activity and Help. Review replaces the workspace with protected focus and explicit Cancel/confirm actions. Do not reintroduce an outer ScrollView without verifying native accessibility: the previous composition crashed the computer-use accessibility reader on the development host.

## Elevation & Depth

Use native GroupBox surfaces for the paired identities and dividers for major regions. The footer uses system bar material for functional separation. No custom shadow, texture, glow or ornamental animation is defined.

## Shapes

System controls own corner geometry, borders, focus and hover treatment. Use SF Symbols consistently; retain the existing app icon. Do not synthesize additional icon families or fake physical materials.

## Components

- **Primary action:** native bordered-prominent button in the persistent footer. Disabled until readiness passes; names the actual update, downgrade or reinstall. Confirmation rechecks readiness before invoking the shared writer.
- **Identity pair:** installed facts beside parsed image facts. Read/refresh and image selection stay within their respective GroupBox; compatibility warnings remain visible below.
- **Manifest:** aligned native grids for panel, transport, sizes and partitions; full selectable hashes with an explanation of their limits.
- **Activity ledger:** Preserve, Write, Verify, Restart, Restore. Backend events determine state. A determinate writing bar shows verified operation counts, followed by separate final phases. Failures retain context and expose the private record; completion requires the backend's verified result.
- **Help:** segmented topic selection with ordinary in-window content. Recovery limits and privacy are product truth, not optional fine print.
- **File dialogs:** native NSOpenPanel for a single `.bin` file or an existing record directory. Image parsing remains separate from extension filtering.

## Do's and Don'ts

- Do keep source, target, record destination and write consequences inspectable.
- Do preserve native keyboard focus, disabled states, semantic colors and selectable evidence.
- Do label synthetic previews explicitly and keep them outside shipping code.
- Don't equate 100% writing or USB reconnection with successful completion.
- Don't imply whole-file hash admission, authenticity, automatic resume or recovery guarantees.
- Don't replace real backend phases with timers, guessed completion or decorative motion.
