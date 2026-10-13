# Preservation and verification

Vendor firmware is not a complete monitor backup. Before programming, the updater acquires calibration, serial information, current metadata and known loader bytes from the selected device and saves them privately.

## Preserved data

- Twelve calibration bytes and thirteen serial bytes, with their additive byte checksums.
- USB serial, location and service identity for transaction binding and reset reacquisition.
- Both 5,120-byte known boot copies and all four 4 KiB metadata sectors.
- Image digest, ordered physical plan, durable phase intent and raw exchanges.
- The remaining upper boot-area bytes when required by the destination plan.

Optional vendor EDID retention is a separate operation. These records do not contain a full 32 MiB flash backup and are not damaged-firmware recovery images.

## Verification scope

| Check | Establishes | Limit |
|---|---|---|
| Exact image SHA-256 | Input matches the supported official byte sequence. | Does not establish compatibility of other images or complete installed-flash identity. |
| Report length/ID/opcode/status/XOR | Response meets its command-specific framing contract. | Does not prove complete flash integrity. |
| 512-byte additive checksum | Returned sum matches expected page data. | Not collision-resistant byte identity or authentication. |
| Critical physical readback | Acquired boot/metadata/sample bytes match expected values. | Not a cryptographic comparison of every installed byte. |
| Restore acknowledgement | Restore exchange meets its response contract. | Must be followed by fresh preservation reads. |
| Post-restart normal reads | Identity, model, version, calibration and serial match expectations. | Does not establish recovery or all display/power behavior. |

Missing replies are errors, not zero-valued data. An uncertain commit is not automatically repeated. Final success requires critical readback, reset/reacquisition, restoration and fresh normal-mode verification.

## Record privacy

Backup directories and files use owner-only permissions. Raw reports can contain serial and calibration data even when a log does not label those fields. Keep records local and redact identifying values, local paths and raw payloads before sharing. The app provides no telemetry or upload feature.
