# Release maintenance

Maintainer reference for app packaging, signing and icon generation. For running the app or its command-line interface, see [usage](usage.md).

## Build an app bundle

Run the packaging script from the repository:

```sh
./scripts/build-app.sh
```

It builds the release executable, assembles a fresh temporary bundle with the icon and bundle metadata, then signs and verifies it before replacing `build/MSI Firmware Updater.app`. Old bundle resources are not carried forward, and a signing or verification failure leaves the previous output in place. Build output is excluded from source control. The script does not access the monitor.

The release command-line binary is `.build/release/MSIUpdater`. Its packaged copy is `build/MSI Firmware Updater.app/Contents/MacOS/MSIUpdater`; quote that path because the bundle name contains spaces. Open the GUI with `open "build/MSI Firmware Updater.app"`. All paths are relative to the repository directory.

The default signature is ad-hoc. Set `SIGNING_IDENTITY` to an available Developer ID identity when preparing a signed distribution; the script then enables hardened runtime and requests a secure timestamp. Notarization and ticket stapling are separate steps. Developer ID signing and notarization have not been validated by the local ad-hoc checks. Do not label an ad-hoc package as notarized.

The bundle uses the project identifier `org.independent-tools.msi-firmware-updater`. Changing a bundle identifier can affect operating-system recognition of an installed app; replace earlier preview bundles rather than assuming they share an application identity.

## Icon

The icon is an original geometric monitor/download design. It does not use MSI's logo. Regenerate the assets with:

```sh
swift scripts/generate-icon.swift
iconutil --convert icns --output Resources/AppIcon.icns build/AppIcon.iconset
```

## Distribution contents

Include only application assets, source and product/protocol documentation. Do not distribute vendor binaries, raw USB records, monitor backups or device-specific information. Firmware is obtained separately from MSI.

Retain the supported model/image restriction, accurate progress phases, private backup handling and failure behavior in distributed packages. Signing does not expand hardware support or provide interrupted-update recovery. The repository does not grant a redistribution license for proprietary MSI artifacts.
