# Firmware modification and power behavior

The updater validates firmware structure and compatibility without a whole-file allowlist. It cannot detect arbitrary application-code modifications or authenticate origin; matching a file size or additive checksum does not establish acceptance by the monitor or safe behavior. Automatic rollback and damaged-firmware recovery are unavailable.

## Application mapping

The FW046 LEON2M slice begins at image offset `0x108000`, length `0x15C2AC`. Its SHA-256 is `59285c76d081073c296a636a8b98d45f9ffbb46e0a233a43adcd696598ca4842`. Logical offsets in this slice map to image offsets by adding `0x108000`; they are not automatically complete runtime or physical-flash addresses.

| Code | Logical location | Role and limit |
|---|---|---|
| `APPSetPowerOff` | Function `0x20244`, reference `0x20364` | Application power-off path. |
| Fake-sleep exit | Function `0x208CC`, reference `0x209AC` | Clears shared state and calls other helpers. |
| `APPSetPowersaving` | Function `0x23350`, reference `0x238A0` | Application power-state flow. |
| Suspended-DPMS wake | Blocks `0x24390`, `0x24D84`, enclosing entry `0x23DD0` | Shared helpers; complete surrounding control flow is unspecified. |
| DPMS/fake sleep/thermal shutdown | Function `0xC111C` | Power and thermal protection share code. |
| `SYSAPI_PowerSaving` | Function `0xDCCA0` | Includes unresolved peripheral effects. |

The fake-sleep exit checks halfword `0xA802BEB0`, requires masked `0x6000` bits to equal `0x4000`, clears those bits and updates bytes `0xA802C6CE`, `0xA802C6C9` and `0xA802C6C8`. Exact hardware-state names require their complete consumers and runtime semantics. These locations do not identify a specific sleep/wake defect.

SPARC register windows, delay slots and tail calls require instruction-level interpretation; decompiled return conventions and interior labels are insufficient on their own.

## Integrity and compatibility

A routine at logical `0xDFE34` parses a four-character hexadecimal filename checksum and compares an additive 16-bit data sum. Its caller at `0xE0078` includes unresolved peripheral writes. This does not establish the report-4 update acceptance gate or a safe diagnostic command.

Equal-length edits avoid relocation but do not preserve semantic correctness. EDID edits require valid block checksums and timing semantics. Power, panel protection, thermal, timing and calibration changes can affect hardware behavior.

The Nuvoton bridge APROM/LDROM is a separate firmware component; scaler SPI data does not supply its code. Firmware changes require a compatible deployment and recovery method, not merely a writable transport.
