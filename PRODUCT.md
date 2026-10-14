# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS — native SwiftUI/AppKit desktop application. Impeccable's web/mobile platform labels do not represent this app.

## Users

Expert MSI monitor owners who want to inspect firmware and update one directly connected display from a Mac. Technical detail is a priority, explicitly confirmed by Daniel.

## Product Purpose

Inspect a separately obtained firmware image, check it against the connected monitor, preserve device-specific data, install compatible firmware and verify the resulting monitor state.

## Operating Context

Users connect one supported MSI controller directly, release VM passthrough, select official firmware and a private records folder, then confirm a write. Power and USB must remain connected. The display can go blank during the intended restart.

## Capabilities and Constraints

Swift 6, SwiftUI, AppKit and IOKit; macOS 14 minimum. No third-party runtime packages. Structural image admission, model/panel/branch checks and known bootloaders are required; whole-file hashes identify records but do not allowlist or authenticate releases. Downgrades are permitted with a warning. Only MEG 342C FW046 reinstalls over USB-C have been hardware-tested. Additional models and version transitions remain inferred/offline-validated. No automatic resume, rollback or damaged-firmware recovery. Successful completion requires post-reset firmware and preservation verification. Backup and inspection records contain private device data. The quit guard must remain active during updates.

## Brand Commitments

MSI Firmware Updater is independent and not endorsed by MSI. Preserve that distinction and the app's actual preview status. No prescribed visual identity; Daniel authorized a full redesign.

## Evidence on Hand

Protocol, model and reliability documentation under docs/. Firmware corpus and hardware transaction evidence are retained outside this repository in the adjacent research workspace. The redesign walkthrough included a successful FW046 reinstall, all 609 operations, and exact postflight calibration/serial preservation. Final UI evidence includes native production captures and explicitly synthetic minimum-size/light/stopped/completed previews; synthetic screens are not hardware evidence.

## Product Principles

- Make source, target, compatibility and the write boundary inspectable.
- Describe uncertainty and failures precisely; do not suggest recovery guarantees.
- Preserve the native desktop interaction model and keyboard accessibility.
- Keep routine status concise and technical evidence readily available.
