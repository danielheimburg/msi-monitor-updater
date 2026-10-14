# Reviewed image layouts

Six retained official MEG342C releases supplied the reference corpus; [support expansion](../msi/support-expansion.md) lists the investigated versions. All six share the complete boot area, USB/ISP auxiliary payload and nine partition offsets. Their sizes and partition lengths differ. FW046 is the reference below.

The FW046 official image is 2,507,776 bytes (`0x264400`). Its padded 4 KiB extent is `0x265000`.

| Property | Value |
|---|---|
| Image SHA-256 | `03db338acefd86cd41aa05539a69d8fff5708423e4896912f677cebb81ac7c8a` |
| Official archive SHA-256 | `74ee854e1afdb93e801268f1157193b90fd70ee8c1bd5772bd27d13875e8643d` |
| Unsigned file sum16 | `A841` |
| Version text at `0x1FE479` | `FW.046 20251104` |
| Scaler text at `0x1FE489` | `NT68501` |

Obtain the archive from [MSI's firmware listing](https://www.msi.com/Monitor/MEG-342C-QD-OLED/support#firmware). Image text is distinct from a live installed-version response.

## Partitions

Nine big-endian address/length descriptors start at `0x6000`. All offsets and lengths below are hexadecimal.

| Offset | Length | Content |
|---:|---:|---|
| `10000` | `FB3C` | 8051-compatible MCU code. |
| `20000` | `E552` | 8051-compatible USB/ISP auxiliary code. |
| `D0000` | `75C0` | SPARC-compatible code. |
| `EC000` | `5B78` | Configuration/data candidate. |
| `108000` | `15C2AC` | LEON2M application/data region. |
| `50000` | `52230` | SPARC/LEON2S code. |
| `A6000` | `27B0` | Auxiliary region with unresolved role. |
| `30000` | `D7DC` | Tensilica/Xtensa-compatible payload. |
| `B0000` | `1D590` | Auxiliary payload containing RSA3 text. |

The loader at zero is 8051 code. Other regions contain SPARC/LEON and Tensilica code and data. A single CPU architecture cannot describe the complete image; exact Xtensa configuration and runtime mapping remain unspecified.

Code, strings, erased space and zero-filled regions are visible. Custom compression and ROM-controlled authentication are not excluded. Build-environment strings do not establish the monitor's runtime operating system.

## Model and EDID

The compatibility marker `55 AA 66 99 55 41 52 54 90` is at `0x254628`. It identifies the model and is not an authenticity signature. The updater reads this record from the application partition and cross-checks version/panel records and structural bounds; whole-image SHA-256 is recorded, not matched to a catalog.

Thirty-two EDID templates begin at `0x118000` with `0x200` spacing through `0x11BE00`. Firmware templates are distinct from the EDID currently exposed by the monitor. Optional vendor EDID retention uses a fixed 64 KiB window at `0x118000`; backup mask `C0` does not select that branch.

File sum16, packet XOR, EDID block sums and flash-page sum16 have different scopes. They do not establish cryptographic firmware authentication. RSA3 text alone does not identify update signing. Structural checks do not establish authenticity or correctness of modified application code.
