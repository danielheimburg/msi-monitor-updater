# USB HID transport

The supported programming path uses output reports and input callbacks. It does not use feature reports for update commands. Normal information and scaler ISP exchanges use different report IDs.

## Frames

Each report is 64 bytes: one report-ID byte and 63 payload bytes. Let `P` denote the payload after that ID and `R` the normalized response payload. Padding bytes are zero unless a command specifies otherwise.

| Report ID | Purpose |
|---|---|
| `01` | Normal ASCII information, preservation restoration and interface selection. |
| `02` | ISP through interface selector 0; the recovered internal UART path. |
| `04` | ISP through interface selector 1; the recovered internal I2C path. |

For this numbered-report device, the IOKit output API receives the nonzero ID both as its report-ID argument and as the first buffer byte. Input buffers likewise begin with the ID. Validate length and ID before normalizing once; do not produce a 65-byte transfer by adding an ID to an already complete report.

One owner serializes exchanges. Input may arrive before output completion. Buffers and callback context remain valid until completion or cancellation has drained.

## Normal commands

Normal request payloads are ASCII with a carriage return and zero padding. Replies have command-specific prefixes and terminators.

| Request | Reply | Validation |
|---|---|---|
| `5800140\r` | Model, prefix `5b00140` | Three bytes: `30 30` followed by a supported model code. |
| `58001<0\r` | Firmware, prefix `5b001<0` | Three ASCII digits. |
| `58001?0\r` | Panel, prefix `5b001?0` | Length-prefixed ASCII panel, required for CURX branches. |
| `580[000\r` | Calibration, prefix `5b00[` | Twelve bytes, additive byte checksum and CR. |
| `5800131\r` | Serial, prefix `5b00131` | Thirteen bytes, additive byte checksum and CR. |
| `5800100\r` | Readiness | Exact reply `5b00100001\r`. |
| `6800;30\r` | OLED panel-protection status | Separate from scaler firmware information. |

Calibration/serial responses must come from the selected monitor. Do not use another device's data as defaults. A successful calibration getter does not provide arbitrary EEPROM or memory access.

## ISP responses and timing

ISP handlers validate command-specific status, opcodes and XOR fields. An outer nonzero status is not universally the final operation result: C3 completion status `55` and failure status `05` have distinct meanings. An all-zero A0 failure does not identify scaler ID zero. UART replies have bridge status zero, so the interface-1 nonzero requirement does not apply; echoed outer command, report ID, inner complement and XOR checks remain mandatory.

Register-read/write spacing is 5 ms. Sequencer execution waits 100 ms before the response and 200 ms afterward. Message XOR, calibration sum8 and flash-page sum16 are different algorithms.

## Failure semantics

Completed host output without input differs from failed output submission, removal, malformed response and cancellation. None establishes whether an unacknowledged mutation executed. Retry and reset behavior is documented in [reliability and failure handling](../app/reliability.md).
