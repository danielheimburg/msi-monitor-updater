# MSI Firmware Updater for macOS

<img src="Resources/AppIcon.png" width="80" height="80" alt="MSI Firmware Updater icon">

A native macOS utility for installing the supported official **FW046** firmware on the **MSI MEG 342C QD-OLED**. Built with Swift and SwiftUI, with no third-party package dependencies. This is an independent utility and is not developed or endorsed by MSI.

**Status: preview.** The supported operation is FW046 reinstallation from recognized firmware layouts. Other firmware versions, upgrades, downgrades, modified images and other monitor models are unsupported. Automatic resume, rollback and damaged-firmware recovery are unavailable.

## Compatibility

- macOS 14 or later; compatibility with every Mac and macOS release is not guaranteed.
- One directly connected MEG 342C QD-OLED controller (`1462:3FA4`) with the supported HID descriptor.
- Scaler identity `A500` and the `C8 40 19` / 32 MiB flash profile.
- Official FW046 image, 2,507,776 bytes, with SHA-256:

```text
03db338acefd86cd41aa05539a69d8fff5708423e4896912f677cebb81ac7c8a
```

The updater rejects unsupported images, hardware and installed layouts before programming. Obtain firmware separately from [MSI's support page](https://www.msi.com/Monitor/MEG-342C-QD-OLED/support#firmware). Proprietary firmware and MSI software are not distributed in this repository.

## Use

Connect the monitor directly with a reliable USB-C data/video cable. Release any virtual-machine USB passthrough and close other monitor-control applications. Select the official firmware and an existing private backup folder, then start the update.

Keep the Mac and monitor powered and connected throughout the operation. The display will go blank and USB will reconnect during the final restart. Completion requires firmware verification and restoration of the monitor's calibration and serial data.

If an update stops, keep the monitor connected and preserve its complete record. Restarting the utility is not a resume procedure. Backup records and inspection output contain device-specific information and must remain private.

See [usage](docs/app/usage.md) for GUI and command-line details, [reliability and failure handling](docs/app/reliability.md) for interruption behavior, and the [documentation index](docs/README.md) for protocol and firmware references.

## Build

Swift 6 and the macOS SDK are required.

```sh
/usr/sbin/taskpolicy -c utility nice -n 10 swift build
.build/debug/MSIUpdater

# Create an app bundle with its icon and a local signature:
./scripts/build-app.sh
```

The packaging script uses an ad-hoc signature by default. Developer ID signing and notarization are separate distribution requirements; see [packaging](docs/app/release.md).
