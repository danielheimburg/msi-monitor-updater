# Shared-backend compatibility

The current Gaming Intelligence 0.1.4.9 registers 32 profiles in the NT68500 backend family: 24 internal-I2C profiles and eight UART profiles. The published installer hash matches the analyzed binary. This family name is a host API grouping; it does not establish the physical scaler, flash part or update policy.

The analyzed native `MSIISPDll.dll` has SHA-256 `3ff33b66eaff310754200234923fe0dfd1f53f6a851108806f422471fcd35e67`. Its returned scaler ID selects the descriptor count; its flash table uses a bounded first-match lookup. The backend name alone does not select either.

The app parses firmware identity and structure without a whole-image hash allowlist. The 74 investigated images are a reference corpus, not the permitted-release list. Additional writers are inferred from matching Windows/native contracts, actual image layouts and boot selectors, plus independent source code. This project has physically verified MEG 342C FW046 reinstalls over USB-C. Other models, actual version transitions and UART flashing remain untested by this project. No monitor command or flash was performed for this expansion.

## Every profile

The table separates implemented guarded writers from unresolved or excluded profiles. An available writer accepts other versions in its supported model/branch/boot family when structural and device compatibility checks pass. Installed tables are validated from their own geometry; they do not need release-specific hashes.

| Model / Windows profile | Model code | Internal path | Investigated releases | Disposition and boundary |
|---|---|---|---|---|
| MPG 341QR | `71` | UART | 037 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 321QRF-QD | `76` | UART | 041 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 321UR-QD | `77` | UART | 037 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 321UR-QD Xbox Edition | `83` | UART | 117 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 281URF | `80` | UART | 045 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 273CQRX-QD | `5C` | UART | 016 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 274QRX | `7C` | UART | 015 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG321QR_QD | `8E` | UART | — | Writer excluded. No scaler payload; distinct single-image/backup0 contract. |
| MEG 342C QD-OLED | `90` | I2C | 033, 035, 040, 041, 044, 046 | Guarded writer; FW046 reinstall hardware-tested. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 325CQRF-QD | `92` | I2C | 017 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 275CQRF-QD | `93` | I2C | 018 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 274UPF | `95` | I2C | 021 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 325CQRXF | `91` | I2C | 013 | Guarded writer; inferred. Official CDN image has the same reviewed LCD boot region and nine-record layout. |
| MAG 275CQRXF | `8F` | I2C | 015 | Guarded writer; inferred. Common reviewed LCD boot; valid installed metadata required. |
| MAG 323UPF | `94` | I2C | 027, 107 | Guarded writer; inferred. Distinct 0xx/1xx boot code; bundled MSI branch rule is enforced. |
| MAG 341CQP QD-OLED | `99` | I2C | 028, 031, 035, 041 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 491CQP QD-OLED | `9B` | I2C | 017, 020, 022, 027, 030 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MAG 322UPF | `98` | I2C | 017, 107 | Guarded writer; inferred. Distinct 0xx/1xx boot code; bundled MSI branch rule is enforced. |
| MPG 274URF QD | `9D` | I2C | 009, 011 | Guarded writer; inferred. Same reviewed boot code; valid installed metadata required. |
| MPG 271QRX QD-OLED | `9E` | I2C | 010, 011, 012, 015, 016, 018, 019, 203, 204 | Guarded writer; inferred. Same 0xx or 2xx branch; 1xx Realtek excluded. |
| MPG 321URX QD-OLED | `9F` | I2C | 010, 011, 012, 015, 016, 020, 021 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 341CQPX QD-OLED | `A5` | I2C | 020, 023, 024, 025, 029, 034, 037 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG275CQRXF | `A2` | I2C | — | Writer excluded pending authentic firmware. No public matching payload found; current support offers drivers/utilities only. |
| MAG275CQRF_QD_E2 | `A7` | I2C | — | Writer excluded pending authentic firmware. No public matching payload found; current support offers drivers/utilities only. |
| MPG345CQR_QD | `A8` | I2C | — | Writer excluded pending authentic firmware. Exact vendor profile found, but no matched public payload or justified retail alias. |
| MAG325CQRF_QD_E2 | `AB` | I2C | — | Writer excluded pending authentic firmware. No public matching payload found; current support offers drivers/utilities only. |
| MPG325CQRXF | `A3` | I2C | — | Writer excluded pending authentic firmware. No public matching payload found; current support offers drivers/utilities only. |
| MPG 491CQPX QD-OLED | `AC` | I2C | 013, 015, 016, 017, 022, 023, 024 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG 321CURX QD-OLED | `AD` | I2C | 016, 017, 018, 020, 025, 106, 112 | Guarded writer; inferred. Same 0xx/1xx branch and exact AA01/AA02 panel. |
| MPG 321URXW QD-OLED | `B0` | I2C | 007, 008, 012, 013 | Guarded writer; inferred. Structural installed metadata and matching boot code; downgrade warning. |
| MPG346CQRFX24 | `B3` | I2C | — | Writer excluded. Retail MPG346CQRF X24; current support has no firmware; its no-backup helper is not selected by GI0.1.4.9 GUI. |
| MEG_X | `C1` | I2C | — | Writer excluded. Retail MEG X; verified US support has no scaler download. |

## Runtime admission

The selected file must have 512-byte alignment, a size derived from descriptor extents, FF tail padding and zero reserved metadata. One model marker, consistent length-prefixed FW.xxx records and consistent panel records must identify a supported model/branch. Optional binary version records must agree. Normal mode independently supplies the installed model/version/panel; the image panel must match exactly. Leading-digit hardware branches cannot be crossed; MPG321CURX also requires the target panel name. URX and URXW remain distinct models despite shared boot bytes. Compatible downgrades are allowed: the GUI warns before confirmation, the CLI warns before ISP entry, and offline plans include a warning. Structural validation cannot authenticate origin or detect arbitrary application-code corruption.

Returned scaler ID must be A500 or A300, the recovered nine-record native branch. Zero-length records are retained in their original positions during relocation; they are not compacted or mistaken for missing data. Other returned chip IDs require separate descriptor/setup contracts and are rejected.

Supported SPI policies are C84017/18/19 (GigaDevice 8/16/32 MiB), EF4017/18/19 (Winbond 8/16/32 MiB). Macronix C22017 is excluded: its first matched vendor row has inconsistent capacity; the separate index10 override is selected by C22015, not C22017. Winbond individual-lock mode is refused; 32 MiB parts also require ordinary three-byte addressing after reset, using supplier-specific status bits. [Winbond W25Q256JV manufacturer datasheet](https://cdn.sparkfun.com/assets/c/2/9/2/6/W25Q256JV.pdf) establishes the EF4019 explicit-address 0C read and lock/address-mode fields. Status bits and resulting protection are checked, with unknown/busy/suspended or unsupported protection states refused. JEDEC does not uniquely identify silicon revision. An advertised model with another flash or controller descriptor can therefore be refused rather than forced through an assumed policy.

Flash capacity sets the inactive image base to half capacity. The 8/16 MiB layouts use one metadata pair and preserve the base boot region; the 32 MiB layout retains the recovered asymmetric mirror/marker order and both physical boot regions. Active metadata must have valid normalized descriptors and reserved padding, independently of the selected target; the table does not encode the installed version. Exact blank inactive sectors are admissible; unknown bytes and ambiguous markers are refused.

Additional models bind the complete immutable 0000..5FFF boot region because their reachable loader code extends beyond the MEG's measured 5 KiB prefix. The loader must match its model's reviewed images before programming, and preserved boot/metadata regions must match planned final hashes afterward.

## Transport differences

I2C uses report04, ASCII580040: entry and the recovered 4 KiB BF/C0/C1/C2 transfer. UART uses report02, A0 #nvtISP_MODE_ON#$$ entry, explicit B2 sector erase and eight 512-byte B6/B7/B8 programs per sector. UART reply bridge status is zero; inner opcode/XOR and page sums still gate each operation. Each UART sector has durable erase/program intent. The implementation erases one planned sector immediately before its pages rather than using the vendor's larger erase batches. On a 32 MiB upper-slot plan, this includes boot sectors corresponding to image offsets `0000..5FFF`: the updater erases and rewrites their pinned contents. Preservation means matching final contents; it does not mean those physical sectors remain untouched. Interruption safety and recovery for that interval remain unverified. Metadata likewise gets one explicit erase then eight pages; marker clearing has no erase.

Two exact HID descriptors are accepted: the measured newer descriptor and the report1–4 descriptor from official MPG321UR MCU5.6/Xbox5.2. Controller MCU images corroborate scaler transport but are not accepted as scaler payloads or offered as controller updates. Internal UART/I2C does not impose DisplayPort versus USB-C; USB-C success is established only on the locally tested MEG connection.

A missing or malformed mutation reply stops without replay/reset. UART A1 can leave the USB bridge enumerated, so final verification waits for the scaler and checks fresh normal identity/preservation; the tested I2C path requires its observed re-enumeration. Recovery, rollback and damaged-firmware flashing remain unavailable.

## Independent source code and evidence

- [SergeyZh scaler/board research](https://github.com/SergeyZh/mpg-341cqpx-qd-oled-re/tree/4d04c2c16326a37e26da3ffdc47b54905e1702c5) supplies independent MPG341CQPX board, stock loader, 32 MiB flash and captured ISP analysis. Its modified controller/recovery extensions are not stock MSI commands.
- [phfroidmont Linux updater](https://github.com/phfroidmont/msi-monitor-flash/tree/c0b58d8275d1ba8e2749ded82884a327661f8581) reports a successful MPG321URX FW021 reinstall with A500/C84018, 8 MiB slots and verified pages. Its source corroborates the smaller-capacity path; this report was not independently reproduced here.
- [msigd](https://github.com/couriersud/msigd/tree/737a84fcfeb487226309e0cd585a05a08db6014a), [491CQP control](https://github.com/hamishmorgan/msi-mpg-491cqp-control/tree/4d9a6ed8e14893ff6cc216055ea3b8986e09cdf5) and [341C control](https://github.com/joshrzemien/msi-mpg341c/tree/a273bdf7d372d99a5483fe833120aa2babb971ba) contribute ordinary HID/model/KVM evidence. Their settings code does not implement this scaler updater or prove recovery.
- [ASUS Novatek research](https://github.com/schlarpc/asus-pg42uq-firmware-re/tree/9007c5309c462fb577053cfe589f428acf4af7a5) independently recovers the same scaler register/sequencer and 4 KiB staging commands. Its VIA USB bridge differs from MSI HID and is not reused here.
- [fwupd source](https://github.com/fwupd/fwupd/tree/54306abafafba4f3a7698164fd704e2487e4351a/plugins) contains no matching MSI monitor backend in the inspected plugin inventory. Its Novatek plugin is for touchscreens.
- [MSI branch FAQ](https://www.msi.com/faq/12469) and bundled QRX/CURX firmware PDFs require staying in the hardware branch; [URXW FAQ](https://www.msi.com/faq/11177) distinguishes white and standard models.

Per-model investigation includes official and regional firmware listings, GitHub repositories/issues/source, firmware collections, hardware/repair reports and update outcomes. Full vendor/decompiled material and raw captures stay outside this repository. Conflicting owner success/failure reports are contextual evidence, not proof of the failure mechanism or safe downgrade. Unseen releases can be parsed without registration if they retain a supported model, hardware branch and known boot contract. Opaque Realtek/MediaTek formats remain unsupported rather than identified by whole-file hashes.

## Verification and remaining work

The research corpus contains 74 scaler images for 24 models. Offline validation checks 444 modeled plans across both slot directions and three capacities, plus 92 forward-version plans using independently modeled installed tables. Checks cover complete metadata relocation, bounded destinations and preservation hashes. Local MEG FW046 plans retain the preceding verified operation order and final critical-sector expectations. Builds and local signatures validate packaging, not hardware compatibility.

Eight profiles remain excluded. Five newer LCD support pages currently expose drivers and utilities but no scaler firmware; the exact MPG345CQRQD profile has no matched payload or justified retail alias. MAG321QR-QD has a distinct single-image/backup contract, and MEG X has no public scaler payload. Per-model regional, repository, code, archive, mirror, repair and owner-report searches recovered no admissible missing image. These are bounded search results, not proof that unpublished firmware does not exist. New artifacts or vendor contracts can change these exclusions.
