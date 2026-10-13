# Usage

## Connection

Use a reliable USB-C data/video cable directly between the Mac and monitor. MSI's official instructions describe DisplayPort plus USB-B; this utility also supports USB-C on its specified monitor profile. Release the controller from virtual-machine USB passthrough and close other monitor-control applications.

## GUI

1. Connect exactly one supported controller and refresh discovery.
2. Read monitor information. The app requires the MEG 342C model response and valid preservation-data checksums.
3. Select the supported official FW046 image. The app checks size, digest, model marker and partition bounds.
4. Choose an existing private backup folder and confirm the update.
5. Keep power and USB connected until restart, restoration and final verification finish.

The display goes blank and USB disconnects during the intended final reset. A full programming indicator or device reappearance alone does not establish success. Completion requires reacquiring the matching monitor, restoring its preservation data and checking fresh firmware, calibration and serial responses.

Only FW046 reinstallation from recognized installed layouts is supported. Other installed versions may fail preflight. If an update stops after a possible mutation, keep the monitor connected and preserve its complete record. Restarting the app or rerunning the command is not a resume procedure. Automatic continuation, rollback and damaged-firmware recovery are unavailable.

## Command line

The GUI and CLI share the same update implementation. Run the following from the repository directory after building:

```sh
.build/debug/MSIUpdater --inspect-monitor
.build/debug/MSIUpdater --prepare /path/to/FW046.bin /path/to/private-records
.build/debug/MSIUpdater --update-fw046 /path/to/FW046.bin /path/to/private-records
```

`--inspect-monitor` performs active normal-mode reads. Its JSON contains monitor-specific serial and calibration values; do not publish the output.

`--prepare` saves normal-mode preservation data, enters diagnostic scaler ISP, reads both known boot copies and four metadata sectors, derives a plan, then resets and checks normal communication. It does not change flash protection or program flash-array data. It changes controller/scaler interface state and is not passive discovery.

`--update-fw046` performs an actual update. Invocation is the write request; there is no additional interactive CLI confirmation. Failures exit with status 1; unsupported arguments exit with status 2. Progress goes to stderr and the successful result goes to stdout.

## Privacy

Each operation creates an owner-only directory containing device identity, calibration/serial backups, boot/metadata bytes, physical plan and raw HID exchanges. Keep the whole directory after failure; partial logs may omit the uncertain command boundary.

Records are not executable resume plans or a full 32 MiB backup. Before sharing diagnostic material, remove serial and calibration values, raw reports containing them, local filesystem paths and other identifying fields. No telemetry or upload feature is provided.
