# App architecture

The executable uses Swift 6, Foundation, CryptoKit, IOKit HID, AppKit and SwiftUI. macOS 14 is the deployment minimum. GUI and CLI share the same transport and update implementation; there are no third-party runtime dependencies.

## Responsibilities

| Component | Responsibility |
|---|---|
| `MonitorDevice` | Discover the supported controller and bind its HID descriptor and USB identity. |
| `FirmwareImage` | Validate FW046 size, digest, model marker and partitions; generate padded blocks and relocated metadata. |
| `HIDSession` / `HIDChannel` | Own one device and serialize asynchronous output, input, removal and timeout handling. |
| `MonitorProtocol` | Read normal-mode information and restore calibration and serial data. |
| `ScalerISP` | Identify the scaler and flash; perform physical reads, bank selection, protection changes, programming and checksums. |
| `UpdatePlan` | Derive ordered physical operations from freshly read supported boot and metadata bytes. |
| `UpdateRecord` | Save private backups and durable transaction intent and results. |
| `UpdatePreparation` | Prepare a plan without programming flash, then restart and check normal communication. |
| `FirmwareUpdate` | Preserve, plan, program, verify, restart, reacquire and restore. |
| `MSIUpdaterApp` | Present GUI/CLI controls, progress, errors and update ownership. |

## Transaction boundaries

Image and device validation precede programming. The plan uses fresh physical bytes; saved records cannot be decoded into executable resume plans. Unknown metadata, ambiguous markers and unsupported hardware are rejected.

Only one exchange is outstanding at a time. Output completion and input arrival are independent events and may arrive in either order. A successful output callback means host submission completed; it does not establish a flash commit or a valid response. Framing and command-specific checks gate each dependent operation.

Each native channel owns an exclusive device handle, input buffer, dedicated HID run loop and serial transaction queue. Native callbacks copy reports promptly. The queue owns request state, response validation and record ordering. Kernel timestamps older than the active request are rejected. Closing stops and unschedules native events before releasing the device and buffer.

Intent is flushed before destructive submissions. Failed or missing programming responses stop the transaction without replay. Reopening a host channel differs from restarting the monitor. Following the intended reset, reacquisition requires the matching USB serial/location and fresh normal-mode checks.

The app prevents a second update from its own window and rejects ordinary quit while an update is active. It cannot prevent cable removal, forced termination, system failure or interference from another application.

## Progress and records

Programming progress advances only after an operation's required completion and verification checks. Final readback, restart and preservation restoration remain separate phases. A full programming bar is not overall completion.

Failures carry the record directory so the GUI can reveal it directly. Records contain sensitive monitor data and remain local. They are diagnostic records, not rollback images or a full flash backup.
