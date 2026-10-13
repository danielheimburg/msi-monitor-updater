# Support expansion and evidence boundaries

This phase extends exact-artifact inspection and MEG342C source/target planning. **No device was accessed or flashed for this expansion.** The previously published run-loop build physically demonstrated only FW046 reinstallations in both bank directions. New code has passed offline validation; actual cross-version transitions remain untested; the table below is a catalog, not a list of hardware-proven transitions.

## Exact MEG342C catalog

All six archives were obtained from the rendered official [MEG342C firmware page](https://www.msi.com/Monitor/MEG-342C-QD-OLED/support#firmware); their archive hashes matched MSI's displayed hashes. Exact BIN identity, size, marker offset and nine-descriptor table are checked before planning or writing.

| Release | BIN bytes | BIN SHA-256 |
|---|---:|---|
| 033 | 2,498,048 | `4cceb247b768578e983531f5127234be6a9c9886fd91291b778898097de68d9d` |
| 035 | 2,498,048 | `33cec452cde01723c76470a670b70cd16d4c8ee4e4f178df4a4d5e73195d3f34` |
| 040 | 2,506,240 | `850012925fc66d65e6c3e9911618f6574a4b8bd5bbcc1911123f760110325e46` |
| 041 | 2,506,240 | `50ef94cae78a8e301f114f1f1c4adf6f2ec1b799f797a3db43520a852f9b07f8` |
| 044 | 2,507,776 | `64835b7b344258608ca5a6ddb70e59e156470523afe3d66b9f9a90728ab2f6bc` |
| 046 | 2,507,776 | `03db338acefd86cd41aa05539a69d8fff5708423e4896912f677cebb81ac7c8a` |

The complete boot area and auxiliary USB/ISP partition match across these artifacts. Nine partition offsets match; lengths differ and all ranges fit without overlap. Primary 8051/application data differs in older releases. Shared literals for entry/calibration/serial are supporting static evidence, not proof of preservation semantics or persistent-settings migration. FW023 and every other unlisted image remain unsupported.

The writer permits reviewed same-version reinstalls and higher-version targets after fresh preflight. Installed version and active metadata are validated independently of the target. Known loader/boot-tail identities remain pinned; final-sector expectations apply the ordered writes to original sectors, retaining untouched predecessor tables. See [boot and metadata](../firmware/boot-and-metadata.md).

**Downgrades remain disabled in the GUI and writer, before ISP entry.** A later downgrade experiment requires separate explicit approval and new evidence. The version-agnostic vendor algorithm and shared boot bytes make investigation plausible; they do not prove safe downgrade or setting migration.

## Offline cross-model inspection

`--inspect-image` accepts fourteen exact artifacts across eight models: six MEG342C images and the eight entries below. Model, version and backend are digest-bound reviewed metadata. This command performs no hardware discovery or writes. `flashEligibleModel` means eligible for the guarded MEG342C writer profile, not hardware validation or authorization.

| Model | Catalog release(s) | Inspection interpretation |
|---|---|---|
| MAG 273QP QD-OLED X24 | 033, 120 | Two distinct MediaTek artifacts in one archive; opaque, no Novatek-table parsing. |
| MAG 341CQP QD-OLED | 041 | Novatek-layout artifact; model marker `99`, nine-descriptor inspection. |
| MPG 271QRX QD-OLED | 111 | Realtek artifact; opaque. The marketed model has backend variants. |
| MPG 321URX QD-OLED | 021 | Novatek-layout artifact; model marker `9F`. |
| MPG 322URX QD-OLED | 024 | Realtek artifact; opaque. |
| MPG 341CQPX QD-OLED | 037 | Novatek-layout artifact; model marker `A5`. |
| MPG 491CQP QD-OLED | 030 | Novatek-layout artifact; model marker `9B`. |

No other-model writer is enabled. Shared table shape, MSI VID/PID, a marker, or a Windows managed class does not establish scaler ID, flash capacity, installed loader, preservation, or compatible mutation policy.

`--plan IMAGE SNAPSHOT_DIRECTORY` is a hypothetical offline MEG342C plan using `monitor.json` and six exact physical files. It neither executes the plan nor supplies a resume path. A lower-version hypothetical target is not a live downgrade permission. `--prepare` is an active diagnostic using fresh hardware; `--update` is the guarded live writer; `--update-fw046` remains an alias restricted to 046. Full contracts and file names are in [usage](../app/usage.md).

## Windows method comparison

The retained Gaming Intelligence **0.1.4.9** / FWUpdaterDll **1.0.0.0** has 57 scaler dictionary profiles, not 57 validated Mac targets. Its defaults span legacy Nuvoton (14), NT68500_I2C/UART (7), NT68500/UART (1), NT68500_I2C/I2C (24), Realtek (10), and MediaTek (1). MPG271QRX additionally selects NT versus Realtek from installed firmware's leading digit. Placeholder enums and monitor-control discovery are not compatibility proof.

- NT-family flat-image programming relocates 9 descriptors for A500/A300, 13 for A580, 5 for A100, and 18 for A511. Returned scaler and internal UART/I2C mode select behavior; external USB-C is a separate dimension.
- Legacy Nuvoton uses single-image policy (`DualFwEnable=false`), with different EDID/preservation handling.
- Realtek launches a separate WinISPTool with its communication plugin and programming policy. MediaTek resolves separate native entry/program/exit exports. Neither is the A500 writer with another allowlist entry.
- Controller MCU, joystick, and AI sensor updates are distinct firmware targets. They are not scaler support.

The Windows DisplayPort check examines display topology in the UI, not the USB flashing transport. Prior Windows and native MEG342C USB-C captures establish that connection for the observed target; they do not prove every backend/topology.

## Provenance and remaining work

Private local records are under `msi-firmware-research/evidence/support-expansion-20261013`, outside this repository. They contain original URLs, archive/image hashes, comparison results and source-bound Windows methods; no vendor image or decompiled source is redistributed here.

| Local authored record | SHA-256 |
|---|---|
| `same-model-design.md` | `a0abb4541d0e9c39506b082ec8550f5fe2543907721db49ef96019c6e4dbf743` |
| `same-model-images.json` | `c2dde165716a0dc9fbedb21a58dfd597cd5eb2ba18af9ad12fbd0a3d4790ed7c` |
| `same-model-layout-comparison.json` | `c2810beae31bb894c81bacde673075b9de7fd9191419a8580ce53b3bf0085598` |
| `cross-model-images.json` | `c9dd9df2b2167c40d62b92c6436a86ff6a91eb4f03dd3fa893f2469918cf9533` |
| `windows-methods.md` | `44babe7ee1e206f3ab1ca4a67610deb14706f78eda8ff945052b93a86a271c13` |

The Windows report binds original GamingIntelligence SHA-256 `f0b6f727ca5ac3cd3270c0274e4cb1d27db4b55752d90d11e47ec1531efa9ceb` and FWUpdaterDll `2eac8b72232afd3c247e89150c537607e5e4a3399c975b79086daedeba337a9f`. REA metadata Evidence IDs are `ev_ca570a6bc0fced9a89cf5d150aadab282c9bb213486e2c5a6b0b81c7c029b198` and `ev_4c71728bcc76962b28d0020b82579a67ce0c5ad0cb60b5e37df468d7ee1f4753`; source-bound IL/native traces supply behavior beyond metadata. Coverage applies to these artifacts, not every current Windows installer.

Offline checks passed for all fourteen catalog artifacts and twelve target plans against the two recorded FW046 bank states. Both FW046 plans match the recorded operations and metadata exactly; expected critical-sector hashes match actual final reads. An independent application of planned writes agrees with every derived successor. A modeled FW044 successor can plan the return to FW046, but is not a device observation. Modified-image, legacy-alias and other-model writer/planner rejection checks passed before discovery.

Debug and release builds passed. The version0.3.0 package passed local ad-hoc signature verification; all fourteen packaged inspections and a packaged snapshot plan matched debug output. The executable SHA-256 is `12c2cd90d0aac2ba2772a25187a71b631b706a332a3eb14db019f63ec38c8099`; private `offline-verification/packaged-provenance.json` binds its source/resource hashes. No automated tests were added, and no device access or flash occurred. Static review found no correctness/maintainability blockers in the changed source boundaries; it supplies no hardware proof.

Actual cross-version startup, preservation restoration, settings migration, broader hardware coverage, and other backends require separate proof. This is an implementation and investigation result, not Windows parity or production readiness.
