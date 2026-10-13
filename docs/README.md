# Documentation

The updater supports the MEG 342C QD-OLED, its recognized installed layouts and the specified official FW046 image. The references below describe the app's behavior, supported protocol and firmware structure.

## App

- [Usage](app/usage.md): connection requirements, GUI, command line and private records.
- [Architecture](app/architecture.md): ownership, update flow and failure boundaries.
- [Reliability and failure handling](app/reliability.md): event delivery, timeouts and interruption limits.
- [Packaging](app/release.md): building, signing and distribution requirements.

## MSI protocol

- [Device identity](msi/identity.md): monitor, USB controller, bridge, scaler and flash identities.
- [USB transport](msi/usb-protocol.md): report framing, normal commands and response validation.
- [Programming sequence](msi/update-sequence.md): entry, staging, commit, checksums and restoration.

## Firmware

- [Image layout](firmware/layout.md): official image identity, partitions and model marker.
- [Boot and metadata](firmware/boot-and-metadata.md): bank selection and ordered activation.
- [Preservation and verification](firmware/preservation-and-verification.md): backups, integrity checks and their limits.
- [Modification and power behavior](firmware/modification-and-power.md): firmware code structure and unsupported modifications.
