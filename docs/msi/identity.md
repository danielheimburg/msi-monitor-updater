# Device identity

The monitor, USB bridge, scaler and flash are separate components. Their firmware images and identity fields are not interchangeable.

| Component | Supported identity | Meaning |
|---|---|---|
| Monitor | MEG 342C QD-OLED; model byte `90` hex | The vendor model enum is 96 decimal; adding 48 yields the compatibility byte. This is not authentication. |
| USB controller | MSI `1462:3FA4`; supported HID descriptor and 64-byte input/output reports | Shared VID/PID values do not establish compatibility with another model. |
| Nuvoton bridge | Part ID `01812610`, mapped by MSI to NUC1261LE4AE | APROM and LDROM are separate from scaler firmware. The app does not update either component. |
| Scaler | ISP identity `A500` | Image strings `NT68501` and `NT68500` do not uniquely identify every physical silicon revision. |
| SPI flash | JEDEC `C8 40 19`, 32 MiB | The supported programming profile uses vendor descriptor `4E`; exact chip revision is not uniquely identified by JEDEC alone. |
| Scaler image | Six exact reviewed official MEG342C releases | Image identity is distinct from the installed version string or complete physical flash contents. |

## Flash profile

The vendor lookup chooses the first matching descriptor, including a wildcard in one field. For `C8 40 19`, descriptor `4E` specifies 65,536 units of 512 bytes, or 32 MiB. The local hardware evidence establishes this profile. Additional inferred policies are listed in [support expansion](support-expansion.md); the full vendor flash table is not enabled.

Physical program pages are 256 bytes; vendor checksum units are 512 bytes; staged update blocks are 4,096 bytes. These granularities serve different operations. A chip name alone is insufficient to select protection commands or programming timings.

## Connection

The supported USB-C connection carries monitor video and USB controller data. MSI's [firmware guide](https://www.msi.com/blog/msi-monitor-firmware-upgrade-guide) describes DisplayPort plus USB-B. A host-side video-input check is separate from the HID programming transport; it must not be treated as a scaler compatibility check.

Use a reliable data-capable cable and release competing USB ownership before updating. Video output alone does not establish that the controller data connection is healthy.
