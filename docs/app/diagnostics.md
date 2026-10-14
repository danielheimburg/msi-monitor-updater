# Redacted diagnostic reports

The updater can send one small technical report after an update attempt returns, whether verified or stopped. The maintainer uses these reports to identify model/version combinations and failure phases. A GitHub account is not required. This service is independent of MSI.

**Submission is on by default.** Before confirming a write, uncheck **Send a redacted diagnostic report after this update** to opt out. The app remembers the choice; Help → Records & recovery also exposes it. The choice at the start of an update governs that attempt. Turning it off later does not recall a report already sent. CLI updates follow the saved preference; append `--no-report` to disable submission for that invocation. File inspection, monitor inspection, planning and diagnostic preparation do not submit reports.

## What is collected

Schema 1 contains only these fields:

| Field | Meaning |
| --- | --- |
| `schema`, `synthetic` | Format version and whether this is a synthetic validation report. Normal app reports set `synthetic` to false. |
| `id` | Fresh random UUID for this attempt; also echoed in the receipt. No persistent user or device ID. |
| `appVersion`, `osVersion` | Bundled app version and macOS version numbers. Standalone source executables without bundle metadata report app version `unknown`. |
| `modelCode`, `panel` | Selected image's model code and public panel designation; these are destination-image claims, not independently authenticated hardware observations. |
| `sourceVersion`, `targetVersion` | Confirmed installed version when available and selected version. CLI currently reports `unknown` for the source; it does not infer it from the image. |
| `transport` | Internal scaler transport, I2C or UART. This does not identify the external cable type. |
| `imageSHA256`, `imageBytes`, `partitionCount` | Selected file's computed digest, byte length and partition count. The digest identifies a file, not its authenticity. |
| `phase`, `completedOperations`, `totalOperations` | Last observed writer phase and verified operation counts. Zero total means the programming plan was not observed. |
| `outcome`, `durationSeconds` | `verified` only when the writer returned success, otherwise `stopped`; elapsed monotonic seconds. A stopped attempt may have written nothing or may have partially changed firmware. |

The report excludes serial numbers (including hashed serials), calibration data, USB serial/location/registry IDs, usernames, hostnames, paths, filenames, raw USB packets, firmware bytes, boot/metadata backups and free-form errors. It is constructed from an explicit typed allowlist; the private record directory is never scanned or uploaded.

After an attempt, Activity offers **View redacted report** and **Export redacted report** even when submission is off or fails. The preview shows the exact JSON submitted. Export saves a separate `.json` file to a location you choose. The preview remains available in that window; it is not a durable queue. The CLI prints delivery status on stderr and preserves its existing result JSON and firmware exit status.

## Processing and retention

Reports go over HTTPS to the maintainer's Google Cloud Run intake in `europe-north1` (Finland) and are stored in a private Google Cloud Storage bucket in that region. Google processes network metadata such as the sender's IP address. These are **redacted reports**, not a promise of anonymity. The intake does not store IP addresses in report objects, set tracking cookies or require an account. Its standard Cloud Run request logs are excluded from Cloud Logging storage. Platform/security/audit logs are separate and subject to Google's logging behavior and retention, including required audit logs; the report lifecycle does not delete those logs.

Report objects become eligible for automatic deletion at 90 days. Lifecycle deletion is asynchronous, so this is not an exact deletion deadline. Object versioning and soft delete are disabled. Authorized project administrators can read reports; the intake runtime can only create objects and cannot read, list, overwrite or delete them. No public report retrieval endpoint exists. Keep the receipt reference and operation ID if requesting removal through a private maintainer channel described in [security reporting](../../SECURITY.md); the reference locates the object and its ID confirms the match without identifying your monitor. Removing a local export or disabling future submission does not remove a submitted object.

Reports are untrusted client self-reports. Anyone can submit or forge one, including a synthetic marker. Deduplicate by `id` during analysis: infrastructure retries or an uncertain response can produce duplicate stored reports. Exclude synthetic reports from hardware-support evidence and do not treat aggregate reports as independent confirmation of compatibility or causality.

## Failure boundary

The writer and HID cleanup finish before encoding or HTTP submission. Reporting cannot authorize device commands, retry a flash or alter its verified/stopped outcome. The client uses an ephemeral session without stored credentials/cookies/cache, refuses redirects, limits the response body to 1 KiB and gives the upload an eight-second resource timeout. The app does not retry delivery or upload old reports after later opt-in. A lost receipt is **delivery unconfirmed**: the service may already have stored the report.

A crash, force quit or process kill before a terminal result produces no automatic report; it is not recorded as a fabricated success or failure. Closing the app while delivery is pending can prevent submission. Local private transaction records remain the evidence source for interrupted operations. Network-reporting validation does not establish firmware or recovery safety.

See [service operation](../../reporting/README.md) for deployment, limits, inspection and shutdown.
