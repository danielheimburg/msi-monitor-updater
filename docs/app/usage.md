# Usage

## Connection

Use a reliable USB-C data/video cable directly between the Mac and monitor. MSI's official instructions describe DisplayPort plus USB-B; this utility also supports USB-C on its specified monitor profile. Release the controller from virtual-machine USB passthrough and close other monitor-control applications.

## GUI

1. Connect exactly one supported controller and refresh discovery.
2. Read monitor information. The app requires an exact recognized model response and valid preservation-data checksums. The panel is read for every supported model and must match the selected image.
3. Select firmware for that model and hardware branch. The app derives identity from firmware records and checks size, padding, version consistency, known bootloader and partition bounds; it shows the model, version, firmware family, applicable partition checks, checksum and compatibility status.
4. Choose an existing private backup folder and confirm the update.
5. Keep power and USB connected until restart, restoration and final verification finish.

The display goes blank and USB disconnects during the intended final reset. A full programming indicator or device reappearance alone does not establish success. Completion requires reacquiring the matching monitor, restoring its preservation data and checking fresh firmware, calibration and serial responses.

Installed model/version come from repeated normal-mode reads; installed metadata is structurally checked independently of the destination image. Releases do not need catalog entries. The GUI displays downgrade warnings in the firmware panel and confirmation dialog; the CLI prints one before ISP entry. Downgrades and other version transitions remain untested on hardware. If an update stops after a possible mutation, keep the monitor connected and preserve its complete record. Restarting the app or rerunning the command is not a resume procedure. Automatic continuation, rollback and damaged-firmware recovery are unavailable.

## Command line

The GUI and CLI share the same update implementation. Run the following from the repository directory after building:

```sh
.build/debug/MSIUpdater --inspect-monitor
.build/debug/MSIUpdater --inspect-image /path/to/firmware.bin
.build/debug/MSIUpdater --plan /path/to/MEG342C-image.bin /path/to/private-snapshot
.build/debug/MSIUpdater --update /path/to/MEG342C-image.bin /path/to/private-records
.build/debug/MSIUpdater --prepare /path/to/FW046.bin /path/to/private-records
.build/debug/MSIUpdater --update-fw046 /path/to/FW046.bin /path/to/private-records
```

`--inspect-monitor` performs active normal-mode reads. Its JSON contains monitor-specific serial and calibration values; do not publish the output.

`--inspect-image` performs file inspection only. It parses the supported Novatek envelope for 24 models, reporting model, version, panel, transport, size, partitions and the computed SHA-256. The hash is for records, not release admission or authenticity. Opaque Realtek and MediaTek files are rejected because they have no supported structural parser.

`--plan` produces an offline plan from a snapshot’s `monitor.json`, `hardware.json` and physical boot/metadata ranges. The 32 MiB layout needs four 4 KiB metadata files and both boot copies; 8/16 MiB layouts need only metadata `6000`/`7000` and the base boot copy. Boot length is 24 KiB for additional models, or 5,120 bytes for historical MEG records. Historical MEG snapshots may omit `hardware.json`; other snapshots must include the verified scaler and JEDEC identity. All snapshots now need a panel value in `monitor.json`; missing values require a fresh inspection rather than inferring the panel from the target file. Wrong model, panel and branch plans are refused. Downgrade plans include a warning. This never discovers hardware or executes the plan; live updates acquire fresh state.

`--prepare` saves normal-mode preservation data, enters diagnostic scaler ISP, reads the capacity-specific boot copies and metadata sectors, derives a plan, then resets and checks normal communication. It does not change flash protection or program flash-array data. It changes controller/scaler interface state and is not passive discovery.

`--update` performs an actual update after fresh source/target validation. `--update-fw046` remains a compatibility alias restricted to MEG342C FW046. Both permit compatible downgrades and emit a warning before writing. Invocation is the write request; there is no additional interactive CLI confirmation. Failures exit with status 1; unsupported arguments exit with status 2. Progress goes to stderr and the successful result goes to stdout.

## Privacy

Preparation and update operations create owner-only transaction directories for device identity, calibration/serial backups, boot/metadata bytes, the physical plan and raw HID exchanges. Inspection and offline planning print their results to stdout without creating a private transaction directory. Protect redirected output yourself; monitor inspection and plans can contain device-specific information. Keep the whole directory after failure; partial logs may omit the uncertain command boundary.

Records are not executable resume plans or a complete flash backup. Before sharing diagnostic material, remove serial and calibration values, raw reports containing them, local filesystem paths and other identifying fields. No telemetry or upload feature is provided.
