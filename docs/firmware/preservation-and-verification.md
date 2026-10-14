# Preservation and verification

Vendor firmware is not a complete monitor backup. Before programming, the updater acquires calibration, serial information, current metadata and known loader bytes from the selected device and saves them privately.

## Preserved data

- Twelve calibration bytes and thirteen serial bytes, with their additive byte checksums.
- USB serial, location and service identity for transaction binding and reset reacquisition.
- Capacity-specific boot/metadata copies: 32 MiB needs two boot copies and four metadata sectors; 8/16 MiB needs one boot copy and two sectors. Additional models bind 24 KiB boot regions; MEG retains its measured 5,120-byte copies with a separate upper-tail check.
- Image digest, ordered physical plan, durable phase intent and raw exchanges.
- The remaining upper boot-area bytes when required by the destination plan.

Optional vendor EDID retention is a separate operation. These records do not contain a complete flash backup and are not damaged-firmware recovery images.

## Verification scope

| Check | Establishes | Limit |
|---|---|---|
| Parsed image envelope | Model/version/panel records agree; file extent, alignment, descriptors and padding are valid. | Does not authenticate origin or validate every application instruction. |
| Computed image SHA-256 | Identifies bytes used in the transaction record. | Never used as a release allowlist or proof of authenticity. |
| Report length/ID/opcode/status/XOR | Response meets its command-specific framing contract. | Does not prove complete flash integrity. |
| 512-byte additive checksum | Returned sum matches expected page data. | Not collision-resistant byte identity or authentication. |
| Critical physical readback | Acquired boot/metadata/sample bytes match expected values. | Not a cryptographic comparison of every installed byte. |
| Restore acknowledgement | Restore exchange meets its response contract. | Must be followed by fresh preservation reads. |
| Post-restart normal reads | Identity, model, version, calibration and serial match expectations. | Does not establish recovery or all display/power behavior. |

Missing replies are errors, not zero-valued data. An uncertain commit is not automatically repeated. Final success requires critical readback, reset/reacquisition, restoration and fresh normal-mode verification.

Before restoring saved originals, the updater checks readiness and the reacquired monitor's model, panel and destination version. It does not first require valid current calibration/serial: retained Windows code and the official FW046 update capture show those saved fields being restored directly after readiness. This removes a circular dependency without weakening original backup validation or final checksum/equality checks. Actual invalid-current-field behavior after a different firmware transition remains untested on hardware.

## Record privacy

Backup directories and files use owner-only permissions. Raw reports can contain serial and calibration data even when a log does not label those fields. Keep records local and redact identifying values, local paths and raw payloads before sharing. The app provides no telemetry or upload feature.
