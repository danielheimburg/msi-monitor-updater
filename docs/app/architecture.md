# App architecture

The executable uses Swift 6, Foundation, CryptoKit, IOKit HID, AppKit and SwiftUI. macOS 14 is the deployment minimum. GUI and CLI share the same transport and update implementation; there are no third-party runtime dependencies.

## Responsibilities

| Component | Responsibility |
|---|---|
| `MonitorDevice` | Discover the supported controller and bind its HID descriptor and USB identity. |
| `FirmwareImage` | Parse model/version/panel records, validate the image envelope and boot contract; generate padded blocks and metadata. |
| `HIDSession` / `HIDChannel` | Own one device and serialize asynchronous output, input, removal and timeout handling. |
| `MonitorProtocol` | Read normal-mode information and restore calibration and serial data. |
| `ScalerISP` | Identify the scaler and flash; perform physical reads, bank selection, protection changes, programming and checksums. |
| `UpdatePlan` | Recognize installed metadata independently of the target; derive ordered operations and exact expected final regions. |
| `UpdateRecord` | Save private backups and durable transaction intent and results. |
| `UpdatePreparation` | Prepare a plan without programming flash, then restart and check normal communication. |
| `FirmwareUpdate` | Preserve, plan, program, verify, restart, reacquire and restore. |
| `MSIUpdaterApp` | Dispatch CLI commands, configure the native window and guard application quit during updates. |
| `UpdaterView` | Present source/target inspection, image manifest, protected review, lifecycle activity, help and stopped-state records. |

## Transaction boundaries

Image and device validation precede programming. The plan uses fresh physical bytes; saved records cannot be decoded into executable resume plans. Unknown metadata, ambiguous markers and unsupported hardware are rejected.

Normal-mode reads establish the installed model/version independently of the selected target; metadata validation establishes slot geometry, not a firmware version. Expected final sectors apply the planned writes to preserved source sectors, retaining untouched predecessor tables. Final verification checks this successor rather than deriving a new plan from target-only assumptions. Each model’s known boot code is pinned. Additional models compare the entire immutable 24 KiB boot area; the existing MEG path preserves its measured 5 KiB copies and separately checks the upper boot tail before overwriting it.

Offline image inspection and snapshot planning perform file operations only. GUI, CLI and offline planning reject wrong models, hardware branches and required panels. Downgrades are permitted with warnings. FirmwareModels owns model/branch/loader programming contracts rather than release hashes; FirmwareImage owns parsing and policy. A GUI update binds its confirmed installed version to a fresh read, so stale information cannot silently turn an upgrade into a downgrade.

Only one exchange is outstanding at a time. Output completion and input arrival are independent events and may arrive in either order. A successful output callback means host submission completed; it does not establish a flash commit or a valid response. Framing and command-specific checks gate each dependent operation.

Each native channel owns an exclusive device handle, input buffer, dedicated HID run loop and serial transaction queue. Native callbacks copy reports promptly. The HID queue owns request state and response validation. UpdateRecord owns ordered, bounded storage work on a separate queue; asynchronous barriers gate device exchanges on their wire records. Kernel timestamps older than the active request are rejected. Closing stops and unschedules native events before releasing the device and buffer.

ScalerTransport owns the internal UART/I2C selector, report ID and names. Controller normal-mode selection remains a separate wire operation even though its selector shares the UART byte value.

MonitorProtocol separates model/version/panel identity from full information. Preflight and final verification acquire all fields with preservation checksums; the pre-restore identity check does not depend on current preservation data.

Intent is flushed before destructive submissions. Failed or missing programming responses stop the transaction without replay. Reopening a host channel differs from restarting the monitor. Following the intended reset, reacquisition requires the matching USB serial/location and fresh normal-mode checks.

The app prevents a second update from its own window and rejects ordinary quit while an update is active. It cannot prevent cable removal, forced termination, system failure or interference from another application.

## Progress and records

Programming progress advances only after an operation's required completion and verification checks. Final readback, restart and preservation restoration remain separate phases. A full programming bar is not overall completion.

The GUI derives its five-stage ledger from `FirmwareUpdate.Progress`; it does not simulate progress or estimate remaining time. Review replaces the ordinary workspace until cancelled or confirmed. The write entry point rechecks readiness and binds the confirmed installed version to the backend's fresh read. Failure retains the last reported phase and blocks another operation in that window; only a returned successful result produces the completion state. The CLI and native transport remain independent of this presentation state.

Failures carry the record directory so the GUI can reveal it directly. Records contain sensitive monitor data and remain local. New record directories use owner-only modes and verified empty macOS ACLs before sensitive children are created; parent permissions are preserved. They are diagnostic records, not rollback images or a full flash backup.

## Diagnostic submission

`UpdateDiagnostics` observes the shared writer's typed progress in memory. GUI and CLI finalize its allowlisted report only after `FirmwareUpdate.run` returns. `DiagnosticSubmission` owns ephemeral, redirect-free, bounded HTTPS delivery and returns a separate nonthrowing status; it never calls monitor code or reads private records. The GUI clears its write guard before delivery, exposes the remembered opt-out on confirmation and Help, and keeps the report preview/export separate from the private record. Concurrent later attempts cannot have their delivery status overwritten by an older receipt. See [schema and privacy](diagnostics.md) and [service operation](../../reporting/README.md).
