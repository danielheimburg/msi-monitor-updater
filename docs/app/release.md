# Packaging and distribution

The application is a preview with a restricted hardware profile and reviewed image catalog. The support expansion is validated through offline catalog inspection, modeled plans, release builds and local signature checks; it does not add hardware validation. The previous FW046 build supplies the existing hardware evidence. Developer ID signing, notarization and compatibility with every Mac or macOS release are not implied by a local build.

## Build an app bundle

Run the packaging script from the repository:

```sh
./scripts/build-app.sh
```

It builds the release executable, copies the icon and bundle metadata into `build/MSI Firmware Updater.app`, signs the bundle and verifies the signature. Build output is excluded from source control. The script does not access the monitor.

The default signature is ad-hoc. Set `SIGNING_IDENTITY` to an available Developer ID identity when preparing a signed distribution. Notarization and ticket stapling are separate steps. Do not label an ad-hoc package as notarized.

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
