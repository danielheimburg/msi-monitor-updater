# Usage

## Connection

Use a reliable USB-C data/video cable directly between the Mac and monitor. MSI's official instructions describe DisplayPort plus USB-B; this utility also supports USB-C on its specified monitor profile. Release the controller from virtual-machine USB passthrough and close other monitor-control applications.

## GUI

1. Connect exactly one supported controller and refresh discovery.
2. Read monitor information. The app requires the MEG 342C model response and valid preservation-data checksums.
3. Select an exact reviewed official MEG342C image: 033, 035, 040, 041, 044 or 046. The app checks size, digest, model marker and partition bounds; it shows the model, version, firmware family, applicable partition checks, checksum and compatibility status.
4. Choose an existing private backup folder and confirm the update.
5. Keep power and USB connected until restart, restoration and final verification finish.

The display goes blank and USB disconnects during the intended final reset. A full programming indicator or device reappearance alone does not establish success. Completion requires reacquiring the matching monitor, restoring its preservation data and checking fresh firmware, calibration and serial responses.

Six reviewed installed versions are recognized independently of the selected target. Upgrade and reinstall planning is verified offline; actual transitions remain untested on hardware. Downgrades are disabled before ISP entry and require separate explicit approval for any future experiment. If an update stops after a possible mutation, keep the monitor connected and preserve its complete record. Restarting the app or rerunning the command is not a resume procedure. Automatic continuation, rollback and damaged-firmware recovery are unavailable.

## Command line

The GUI and CLI share the same update implementation. Run the following from the repository directory after building:

```sh
.build/debug/MSIUpdater --inspect-monitor
.build/debug/MSIUpdater --inspect-image /path/to/reviewed-image.bin
.build/debug/MSIUpdater --plan /path/to/MEG342C-image.bin /path/to/private-snapshot
.build/debug/MSIUpdater --update /path/to/MEG342C-image.bin /path/to/private-records
.build/debug/MSIUpdater --prepare /path/to/FW046.bin /path/to/private-records
.build/debug/MSIUpdater --update-fw046 /path/to/FW046.bin /path/to/private-records
```

`--inspect-monitor` performs active normal-mode reads. Its JSON contains monitor-specific serial and calibration values; do not publish the output.

`--inspect-image` performs file inspection only. It recognizes fourteen exact artifacts across eight models, reporting model, version, firmware family, size and applicable partitions. Other-model artifacts cannot enter the writer. Realtek and MediaTek images remain opaque, without Novatek partition parsing.

`--plan` produces a hypothetical offline MEG342C plan from one snapshot's `monitor.json`, four 4KiB `physical-00006000.bin`, `physical-00007000.bin`, `physical-01006000.bin`, `physical-01007000.bin` files, and two 5,120-byte `physical-00000000.bin`, `physical-01000000.bin` files. It never discovers hardware or executes the plan. Lower-version previews do not bypass the writer's downgrade restriction; live updates always acquire fresh state.

`--prepare` saves normal-mode preservation data, enters diagnostic scaler ISP, reads both known boot copies and four metadata sectors, derives a plan, then resets and checks normal communication. It does not change flash protection or program flash-array data. It changes controller/scaler interface state and is not passive discovery.

`--update` performs an actual update after fresh source/target validation. `--update-fw046` remains a compatibility alias restricted to FW046. Both block downgrades. Invocation is the write request; there is no additional interactive CLI confirmation. Failures exit with status 1; unsupported arguments exit with status 2. Progress goes to stderr and the successful result goes to stdout.

## Privacy

Each operation creates an owner-only directory containing device identity, calibration/serial backups, boot/metadata bytes, physical plan and raw HID exchanges. Keep the whole directory after failure; partial logs may omit the uncertain command boundary.

Records are not executable resume plans or a full 32 MiB backup. Before sharing diagnostic material, remove serial and calibration values, raw reports containing them, local filesystem paths and other identifying fields. No telemetry or upload feature is provided.
