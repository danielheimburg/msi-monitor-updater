# MSI Firmware Updater for macOS

<img src="Resources/AppIcon.png" width="80" height="80" alt="MSI Firmware Updater icon">

A native macOS utility for installing structurally compatible firmware on supported **MSI monitors**. Built with Swift and SwiftUI, with no third-party package dependencies. This is an independent utility and is not developed or endorsed by MSI.

**Status: preview, with broader support inferred from firmware and Windows-backend analysis.** This project has demonstrated MEG 342C FW046 reinstalls over USB-C. Additional model profiles and version transitions have been verified offline, not flashed by this project. Downgrades are allowed with a warning; version transitions remain untested on hardware. Automatic resume, rollback and damaged-firmware recovery remain unavailable.

## Compatibility

- macOS 14 or later; compatibility with every Mac and macOS release is not guaranteed.
- One directly connected MSI Gaming Controller (`1462:3FA4`) with one of the two reviewed HID descriptors and a recognized model response.
- Returned scaler identity `A500` or `A300`, with reviewed `C8 40 17/18/19` or `EF 40 17/18/19` SPI flash: 8, 16 or 32 MiB. Unknown hardware is refused before programming.
- Parsed model, version, hardware branch, required panel, valid partition geometry and known bootloader, with independently acquired installed metadata and boot code. See [every model and its support limits](docs/msi/support-expansion.md). Releases do not need a catalog entry or matching whole-file hash. Changed bootloaders and unsupported programming families still require review.

The updater rejects unsupported images, hardware and installed layouts before programming. Obtain firmware separately from [MSI's support page](https://www.msi.com/support). Proprietary firmware and MSI software are not distributed in this repository.

## Use

Connect the monitor directly with a reliable USB data cable. USB-C flashing was demonstrated on the MEG 342C; internal UART versus I2C is a separate property of the model, not the external cable type. Release any virtual-machine USB passthrough and close other monitor-control applications. Select the official firmware and an existing private backup folder, then start the update.

The native workspace compares installed and selected identities, exposes a complete image manifest, and reviews the write before starting it. Activity separates preservation, writing, final verification, restart and restoration; Help explains compatibility, privacy and recovery limits. See [the design system](DESIGN.md) for UI conventions.

Keep the Mac and monitor powered and connected throughout the operation. The display will go blank and USB will reconnect during the final restart. Completion requires firmware verification and restoration of the monitor's calibration and serial data.

If an update stops, keep the monitor connected and preserve its complete record. Restarting the utility is not a resume procedure. Backup records and inspection output contain device-specific information and must remain private.

See [usage](docs/app/usage.md) for GUI and command-line details, [reliability and failure handling](docs/app/reliability.md) for interruption behavior, and the [documentation index](docs/README.md) for protocol and firmware references.

## Build

Swift 6 and the macOS SDK are required.

```sh
/usr/sbin/taskpolicy -c utility nice -n 10 swift build -c release
.build/release/MSIUpdater

# Create an app bundle with its icon and a local signature:
./scripts/build-app.sh
open "build/MSI Firmware Updater.app"
```

The packaging script uses an ad-hoc signature by default. Developer ID signing and notarization are separate distribution requirements; see [packaging](docs/app/release.md).
