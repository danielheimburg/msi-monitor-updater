# Reliability and failure handling

The updater serializes communication with one supported controller and stops on uncertain programming outcomes. It does not automatically resume or roll back an interrupted update.

## Event delivery

A dedicated native HID run loop receives device events. Input callbacks copy reports before handing them to the serial transaction queue. Output completion and input arrival are tracked separately because they can occur in either order. A response with a kernel timestamp preceding the active request is rejected.

Private record initialization finishes before acquiring HID. Subsequent journal encoding, writes and synchronization run on a separate serial utility queue. HID callbacks only enqueue bounded wire events; filesystem work cannot block the HID watchdog or close queue. Each exchange waits for ordered evidence before submission and before returning to its caller. Phase intents still require full storage synchronization before destructive commands. At most eight record operations may be pending; queue overflow, storage failure or a ten-second storage deadline permanently stops further admission and fails dependent work. A blocked kernel write may finish later, but cannot authorize another command.

Every response must satisfy its report length, ID, command status and checksum requirements before dependent work continues. One successful output callback does not prove that the device received, executed or acknowledged a command.

Apple's [published macOS 26.4 run-loop implementation](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/hid.subproj/IOHIDDevice.c) explicitly aborts pending output callbacks when unscheduling. On the tested macOS 27.0.1 host, eight immediate-close read trials delivered eight aborted callbacks and released all eight output buffers and sessions. Older inspected sources lack that abort path: closing with output still pending may retain its context/session until process exit. Runtime behavior on those older systems remains unverified. The macOS 14 deployment minimum is not an all-version lifecycle guarantee; the app keeps native buffers alive until their callback rather than freeing them on a Swift timeout.

## Timeouts and retries

A missing application reply can originate at the monitor, USB link, driver, competing consumer or application boundary. The error alone does not identify packet loss or prove that a command had no effect.

A bounded I2C physical read may reopen the host channel once, re-identify the scaler/flash and repeat that independent read chunk. UART reads stop on a lost reply because their A0 identity command would re-enter ISP. This policy does not apply to protection changes, programming fragments, commits, bank selection or activation. Uncertain destructive commands are never automatically replayed.

Mailbox writes also stop on a missing acknowledgement, including volatile page selection. Their generic acknowledgement does not identify the selected page or value, so host reopen and replay cannot distinguish a late response from the current operation.

If an update fails after a destructive command may have been submitted, the app preserves the stopped state and record rather than resetting or repeating the command. Keep the monitor powered and connected. Relaunching the utility is not a recovery procedure.

## Expected restart

After programming and critical readback finish, the intended ISP exit resets the monitor. The tested I2C path removes its USB service; the UART path can retain the bridge and waits 30 seconds before normal-mode verification. The app reacquires a matching monitor by USB serial and location, waits for readiness, restores preservation data and checks fresh normal-mode responses.

Before restoration, readiness and fresh model/version/panel must match the verified destination. The app does not require current calibration or serial to be readable at that point: the Windows updater restores its saved originals after readiness without those getters. Original backups must still have passed full validation before programming, every restore acknowledgement must match, and fresh checksum-valid calibration/serial must exactly match the originals afterward.

The expected reset differs from an unexpected removal during programming. A full programming indicator, reset submission or USB reappearance is insufficient to report completion.

## Limits

Only MEG 342C FW046 reinstalls have been hardware-tested by this project. Additional model/branch profiles use inferred compatibility from their Windows callers, native backend, loaders and firmware. Runtime checks can refuse a unit with an unreviewed flash, controller descriptor or installed layout. Downgrades are permitted with a warning but remain untested on hardware. Structural acceptance cannot authenticate an image or guarantee valid application code; use MSI downloads. Damaged-firmware recovery is unavailable. macOS 14 is the deployment minimum; compatibility with every hardware, OS and cable combination is not guaranteed.

The quit guard protects ordinary application exit only. Forced termination, power loss, cable removal and other monitor-control software can interrupt the transaction. Dual firmware banks do not establish a recovery guarantee.
