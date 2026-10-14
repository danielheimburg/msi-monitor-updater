# Boot selection and metadata

The locally tested 32 MiB flash contains two 16 MiB halves at `00000000` and `01000000`. A2 selects the volatile 24-bit address window. Physical flash addressing and firmware selection are separate operations.

Both 5,120-byte known boot-code copies must match the supported loader with SHA-256:

```text
e03120960d3ade1934a6b50b6361d5a0907e201bf9f339478c8d4fc710bc2b22
```

This covers bytes through `13FF`, not every possible ROM or boot stage.

## Selector

The supported loader selects table `7000` when `7FFF == AA`; otherwise it selects `6000`. It does not check `6FFF` in this selector or choose the newest version. Descriptor address/length fields are copied to hardware/scratch registers, with extended addressing when the first descriptor's high byte is nonzero.

Vendor erase-selection logic prefers `6FFF`, while boot selection prefers `7FFF`. Both-AA and neither-AA marker combinations are therefore rejected rather than treated as ordinary retry states. Dual firmware banks do not imply automatic fallback or damaged-image recovery.

## Update plans

| Destination | FW046 image blocks | New metadata | Previous-marker clear | Total operations |
|---|---|---|---|---:|
| Lower | 605 at `00008000..00264FFF`; skip image `0000..7FFF` | Unrelocated table at lower `6000` | Lower `7E00` page | 609 |
| Upper | 611 at `01000000..01005FFF` and `01008000..01264FFF`; skip image `6000..7FFF` | Relocated table at `7000` in both banks | Both `6E00` pages | 617 |

FW046 is the reference in this table. Releases033/035 use602 lower or608 upper image blocks;040/041 use604/610;044/046 use605/611. Counts derive from padded image length and the same asymmetric skip policy.

The totals include two destination-marker clears. Each clear programs 512 zero bytes and verifies a zero sum. The final image block contains 1,024 image bytes and 3,072 `FF` padding bytes.

Metadata copies image `6000..6FFF`, adds the destination base to the addresses in nine descriptors and sets the last byte to `AA`. Lengths remain unchanged. Planning requires four full physical sectors at `6000`, `7000`, `01006000` and `01007000`, plus both boot copies. Unknown layouts are rejected. Repeated normal-mode reads supply installed identity/version; active metadata is structurally validated independently of the target. The table does not itself encode model/version. Expected final sectors are derived by applying ordered marker/table writes to the preserved originals, so untouched predecessor tables remain byte-identical.

## Ordering

Destination markers are invalidated before image programming. Every block passes completion and checksum checks before advancement. New metadata is written before clearing the previous marker.

Upper selection can begin during the lower-bank `7000` metadata write. Lower selection begins when the old lower `7FFF` marker is cleared. Activation is not guaranteed atomic. An interrupted transaction cannot be resumed by blindly repeating the normal update sequence.

## Capacity-derived additional layouts

For 8 MiB and 16 MiB flash, the image slot base is 4 MiB and 8 MiB respectively. Both directions skip image `0000..7FFF`; there is one base metadata pair and no 16 MiB high-bank mirror. For 32 MiB, the recovered upper path also writes the first six image blocks and mirrors `7000` metadata. The app derives physical addresses from the verified capacity rather than reusing the MEG bank size.

Additional loaders are pinned through `5FFF` because reachable code extends beyond `1400`. Zero-length table entries are kept at their original indices and relocated exactly as the native nine-record loop does. Active metadata validation checks normalized slot addresses, bounds, alignment and reserved padding without a release hash lookup. Exact blank or erased-and-marker-cleared inactive sectors can be preserved; arbitrary unknown sectors or ambiguous active markers cannot.
