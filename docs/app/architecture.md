# App architecture

The executable uses Swift 6, Foundation, CryptoKit, IOKit HID, AppKit and SwiftUI. macOS 14 is the deployment minimum. GUI and CLI share the same transport and update implementation; there are no third-party runtime dependencies.

## Responsibilities

| Component | Responsibility |
|---|---|
| `MonitorDevice` | Discover the supported controller and bind its HID descriptor and USB identity. |
| `FirmwareImage` | Validate reviewed catalog identities, applicable partitions and update policy; generate padded blocks and metadata. |
| `HIDSession` / `HIDChannel` | Own one device and serialize asynchronous output, input, removal and timeout handling. |
| `MonitorProtocol` | Read normal-mode information and restore calibration and serial data. |
| `ScalerISP` | Identify the scaler and flash; perform physical reads, bank selection, protection changes, programming and checksums. |
| `UpdatePlan` | Recognize installed metadata independently of the target; derive ordered operations and exact expected final regions. |
| `UpdateRecord` | Save private backups and durable transaction intent and results. |
| `UpdatePreparation` | Prepare a plan without programming flash, then restart and check normal communication. |
| `FirmwareUpdate` | Preserve, plan, program, verify, restart, reacquire and restore. |
| `MSIUpdaterApp` | Present GUI/CLI controls, progress, errors and update ownership. |

## Transaction boundaries

Image and device validation precede programming. The plan uses fresh physical bytes; saved records cannot be decoded into executable resume plans. Unknown metadata, ambiguous markers and unsupported hardware are rejected.

The active metadata must match the reported installed release, independently of the selected target. Expected final sectors apply the planned writes to preserved source sectors, retaining untouched predecessor tables. Final verification checks this successor rather than deriving a new plan from target-only assumptions. Each model’s known boot code is pinned. Additional models compare the entire immutable 24 KiB boot area; the existing MEG path preserves its measured 5 KiB copies and separately checks the upper boot tail before overwriting it.

Offline image inspection and snapshot planning perform file operations only. Catalogs explicitly distinguish inferred writer profiles from inspection-only backends. GUI, CLI and offline planning reject wrong models, hardware branches, required panels and downgrades. FirmwareCatalog owns reviewed artifact data; FirmwareImage owns parsing and policy.

Only one exchange is outstanding at a time. Output completion and input arrival are independent events and may arrive in either order. A successful output callback means host submission completed; it does not establish a flash commit or a valid response. Framing and command-specific checks gate each dependent operation.

Each native channel owns an exclusive device handle, input buffer, dedicated HID run loop and serial transaction queue. Native callbacks copy reports promptly. The queue owns request state, response validation and record ordering. Kernel timestamps older than the active request are rejected. Closing stops and unschedules native events before releasing the device and buffer.

Intent is flushed before destructive submissions. Failed or missing programming responses stop the transaction without replay. Reopening a host channel differs from restarting the monitor. Following the intended reset, reacquisition requires the matching USB serial/location and fresh normal-mode checks.

The app prevents a second update from its own window and rejects ordinary quit while an update is active. It cannot prevent cable removal, forced termination, system failure or interference from another application.

## Progress and records

Programming progress advances only after an operation's required completion and verification checks. Final readback, restart and preservation restoration remain separate phases. A full programming bar is not overall completion.

Failures carry the record directory so the GUI can reveal it directly. Records contain sensitive monitor data and remain local. They are diagnostic records, not rollback images or a full flash backup.
