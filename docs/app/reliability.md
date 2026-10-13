# Reliability and failure handling

The updater serializes communication with one supported controller and stops on uncertain programming outcomes. It does not automatically resume or roll back an interrupted update.

## Event delivery

A dedicated native HID run loop receives device events. Input callbacks copy reports before handing them to the serial transaction queue. Output completion and input arrival are tracked separately because they can occur in either order. A response with a kernel timestamp preceding the active request is rejected.

Every response must satisfy its report length, ID, command status and checksum requirements before dependent work continues. One successful output callback does not prove that the device received, executed or acknowledged a command.

## Timeouts and retries

A missing application reply can originate at the monitor, USB link, driver, competing consumer or application boundary. The error alone does not identify packet loss or prove that a command had no effect.

A bounded physical read may reopen the host channel once, re-identify the scaler/flash and repeat that independent read chunk. This policy does not apply to protection changes, programming fragments, commits, bank selection or activation. Uncertain destructive commands are never automatically replayed.

If an update fails after a destructive command may have been submitted, the app preserves the stopped state and record rather than resetting or repeating the command. Keep the monitor powered and connected. Relaunching the utility is not a recovery procedure.

## Expected restart

After programming and critical readback finish, the intended ISP exit resets the monitor and removes its USB service. The app reacquires a matching monitor by USB serial and location, waits for readiness, restores preservation data and checks fresh normal-mode responses.

The expected reset differs from an unexpected removal during programming. A full programming indicator, reset submission or USB reappearance is insufficient to report completion.

## Limits

The supported profile is MEG 342C QD-OLED / A500 / 32 MiB flash / official FW046 reinstallation. Upgrade, downgrade, modified-image, other-model and damaged-firmware recovery support are unavailable. macOS 14 is the deployment minimum; compatibility with every hardware, OS and cable combination is not guaranteed.

The quit guard protects ordinary application exit only. Forced termination, power loss, cable removal and other monitor-control software can interrupt the transaction. Dual firmware banks do not establish a recovery guarantee.
