# Usage

## Install the release

[Download v0.6.2 for Apple Silicon](https://github.com/danielheimburg/msi-monitor-updater/releases/download/v0.6.2/MSI-Firmware-Updater-v0.6.2-macOS-arm64.zip), unzip it, and move **MSI Firmware Updater.app** to **Applications**. macOS 14 or later is required. Open the installed app with:

```sh
open "/Applications/MSI Firmware Updater.app"
```

See the [release notes](https://github.com/danielheimburg/msi-monitor-updater/releases/tag/v0.6.2) for known issues. No source checkout or build tools are needed.

## Connection

Use a reliable USB-C data/video cable directly between the Mac and monitor. MSI's official instructions describe DisplayPort plus USB-B; this utility also supports USB-C on its specified monitor profile. Release the controller from virtual-machine USB passthrough and close other monitor-control applications.

## GUI

1. Connect exactly one supported controller and refresh discovery.
2. In **Update**, click **Read identity**. The app requires an exact recognized model response and valid preservation-data checksums. Installed and selected model, version and panel appear side by side; the panel must match the image.
3. Choose an official `.bin` file for that model and hardware branch. **Image details** shows the parsed identity, internal transport, file and padded sizes, all partition offsets and lengths, image SHA-256 and bootloader SHA-256. Size, padding, version consistency, known bootloader and partition checks are required. Cancelling the file chooser preserves the existing selection.
4. Choose an existing private folder for backups and the update record. Review the source and target, panel, record destination and warnings on the in-window review screen. **Cancel** returns without writing. Same-version updates are explicitly labeled **Reinstall**.
5. Review the default-checked diagnostic submission option. Uncheck to opt out; the choice is remembered. **What is sent & privacy** explains fields, destination and retention.
6. Confirm the write, then follow **Activity** through Preserve, Write, Verify, Restart and Restore. Keep power and USB connected until final verification finishes. Normal quit is blocked while the operation is active.

**Help** explains compatibility, connection/restart behavior and private records/recovery. The window defaults to 940 × 840 points, with an 860 × 800 minimum, and follows macOS appearance. Long warnings and paths wrap. Firmware selection uses the native file chooser restricted to `.bin` files; structural validation still decides admission.

The display can go blank during the intended final reset. The tested I2C path disconnects and reconnects USB; UART profiles may keep the bridge attached. A full programming indicator or device reappearance alone does not establish success. Completion requires reacquiring the matching monitor, restoring its preservation data and checking fresh firmware, calibration and serial responses.

Installed model/version come from repeated normal-mode reads; installed metadata is structurally checked independently of the destination image. Releases do not need catalog entries. The GUI displays downgrade warnings in Update and the review screen; the CLI prints one before ISP entry. Downgrades and other version transitions remain untested on hardware.

On failure, Activity retains the last reported phase, explains the stop and offers **Show update record** when a record was created. A stopped window blocks further device commands and writes, including failures before programming; this conservative UI boundary does not imply that every failure changed firmware. Keep the monitor connected and preserve the complete record. Restarting the app or rerunning the command is not a resume procedure. Automatic continuation, rollback and damaged-firmware recovery are unavailable.

## Command line

The downloaded app includes the command-line interface. These commands use the copy installed in Applications and work from any directory:

Progress messages go to stderr on a best-effort basis: a failed console destination does not interrupt the transaction. If the final JSON result cannot be written to stdout, the command exits with status 1; an update may already have completed, so use its saved transaction record to establish the outcome. A blocked output destination can still stall the command; use reliable local output destinations.

```sh
msi_updater="/Applications/MSI Firmware Updater.app/Contents/MacOS/MSIUpdater"

"$msi_updater" --inspect-monitor
"$msi_updater" --inspect-image /path/to/firmware.bin
"$msi_updater" --plan /path/to/MEG342C-image.bin /path/to/private-snapshot
"$msi_updater" --update /path/to/MEG342C-image.bin /path/to/private-records
"$msi_updater" --prepare /path/to/FW046.bin /path/to/private-records
"$msi_updater" --update-fw046 /path/to/FW046.bin /path/to/private-records
```

If you keep the app elsewhere, change `msi_updater` to its `Contents/MacOS/MSIUpdater` path. Source-build paths are documented in [release maintenance](release.md).

`--inspect-monitor` performs active normal-mode reads. Its JSON contains monitor-specific serial and calibration values; do not publish the output.

`--inspect-image` performs file inspection only. It parses the supported Novatek envelope for 24 models, reporting model, version, panel, transport, size, partitions and the computed SHA-256. The hash is for records, not release admission or authenticity. Opaque Realtek and MediaTek files are rejected because they have no supported structural parser.

`--plan` produces an offline plan from a snapshot’s `monitor.json`, `hardware.json` and physical boot/metadata ranges. The 32 MiB layout needs four 4 KiB metadata files and both boot copies; 8/16 MiB layouts need only metadata `6000`/`7000` and the base boot copy. Boot length is 24 KiB for additional models, or 5,120 bytes for historical MEG records. Historical MEG snapshots may omit `hardware.json`; other snapshots must include the verified scaler and JEDEC identity. All snapshots now need a panel value in `monitor.json`; missing values require a fresh inspection rather than inferring the panel from the target file. Wrong model, panel and branch plans are refused. Downgrade plans include a warning. This never discovers hardware or executes the plan; live updates acquire fresh state.

`--prepare` saves normal-mode preservation data, enters diagnostic scaler ISP, reads the capacity-specific boot copies and metadata sectors, derives a plan, then resets and checks normal communication. It does not change flash protection or program flash-array data. It changes controller/scaler interface state and is not passive discovery.

`--update` performs an actual update after fresh source/target validation. `--update-fw046` remains a compatibility alias restricted to MEG342C FW046. Both permit compatible downgrades and emit a warning before writing. Invocation is the write request; there is no additional interactive CLI confirmation. Failures exit with status 1; unsupported arguments exit with status 2. Progress goes to stderr and the successful result goes to stdout.

Only update commands submit redacted reports, following the GUI preference (on by default). Append `--no-report` after the record-directory argument to opt out for one invocation. Reporting runs after writer cleanup, cannot change the firmware outcome and does not retry. A lost receipt leaves delivery unconfirmed. See [diagnostic reporting](diagnostics.md) for the schema and limits.

## Privacy

Preparation and update operations create owner-only transaction directories for device identity, calibration/serial backups, boot/metadata bytes, the physical plan and raw HID exchanges. Inspection and offline planning print their results to stdout without creating a private transaction directory. Protect redirected output yourself; monitor inspection and plans can contain device-specific information. Keep the whole directory after failure; partial logs may omit the uncertain command boundary.

Records are not executable resume plans or a complete flash backup. Before sharing diagnostic material, remove serial and calibration values, raw reports containing them, local filesystem paths and other identifying fields. A separate redacted report is submitted after update attempts unless opted out; see [diagnostic reporting](diagnostics.md). Private records are never uploaded.
