# Programming sequence

This reference describes the supported A500 / 32 MiB / FW046 transaction. It is not a set of independent commands to send manually. Staging packets rely on surrounding register and bank state for their destination.

## Preparation and entry

Acquire and durably save normal-mode model, firmware, calibration and serial information before mutation. Vendor backup mask `C0` covers twelve calibration and thirteen serial bytes. Optional EDID retention is a separate branch.

Scaler entry uses report 1 ASCII `580040:\r`, followed by 200 ms, E0 selection of interface 1 and a two-second delay. E0 acknowledges local controller mode selection; it does not establish scaler readiness. A500 identification, initialized JEDEC/status reads, supported boot/metadata bytes and the derived plan gate programming.

The A500 sequencer uses scratch base `A700`. Physical reads configure F0C1–F0C6, place a SPI descriptor/command in scratch, execute AF and retrieve each result byte with an AA register exchange. Four-byte opcode `0C` reads distinguish physical banks independently of EAR-relative `0B` reads.

## 4 KiB programming

The I2C path stages `58 + 67 × 60 + 18 = 4,096` bytes:

1. Select mailbox page `FF=F2`; BD writes six address/setup bytes at register 00: `address24BE 10 00 00`.
2. Select `FF=F3`, write `E2=87`, then select `FF=D0`.
3. Send BF with the first 58 bytes, 67 C0 fragments of 60 bytes and C1 with the last 18 bytes.
4. Submit C2 commit and wait 200 ms.
5. Select `FF=F2` and poll C3 within the bounded completion policy. Status `55` is success; `05` is failure.
6. Query eight 512-byte B5 checksums and compare their expected sums before advancing.

C1/C2 acknowledgements do not replace completion and checksum checks. Addressing combines a 24-bit window with volatile A2 bank selection for the upper 16 MiB. Data staging without that address state is incomplete.

## Marker programming

Marker clearing programs 512 zero bytes; it is not a generic sector erase. B6 supplies address/setup and the first 48 bytes, seven B7 fragments supply 60 bytes each, and B8 supplies the final 44 bytes and rolling XOR. A command-specific acknowledgement and B5 page checksum gate success.

The [boot and metadata plan](../firmware/boot-and-metadata.md) determines image, metadata and marker order. Neither a stage acknowledgement nor a dual-slot flag provides atomic activation.

## Protection and finalization

The supported protection sequence changes SPI status `C2/02` to `40/02`, or accepts the already prepared `40/02` state. JEDEC and status checks precede the write-enable/status-write sequence; resulting status is checked before programming. Unknown protection states are rejected.

After programming and critical readback, A1 exits ISP and resets the monitor. The updater handles the resulting USB removal without requiring a final reset reply. Reacquire the matching monitor, select normal interface 0 and check readiness.

Preservation restoration consists of unlock, calibration write, serial write and relock. Each requires the normal acknowledgement `01 35 36 30 30 2B 0D` followed by zeros. Fresh normal-mode reads must match the expected model/version and preserved data before completion.

Uncertain destructive submissions stop without automatic replay, reset or rollback.
