# Research sources and third-party notices

The app uses Apple system frameworks and Swift; it has no third-party package dependencies. The [MIT license](LICENSE) covers this project's original code, documentation and geometric icon. It does not relicense MSI firmware, MSI software, trademarks or the upstream works below. Firmware and vendor binaries must be obtained separately and are not included in source or app downloads.

## Research attribution

Protocol documentation and model support combine analysis of MSI artifacts and local observations with independent research. The [support investigation](docs/msi/support-expansion.md#independent-source-code-and-evidence) describes what each source establishes and its limits. These projects are references, not bundled runtime components. A protocol fact or corroborating update report is not a claim that the upstream project's implementation is included here.

| Source and reviewed revision | Attribution and upstream license |
|---|---|
| [SergeyZh/mpg-341cqpx-qd-oled-re](https://github.com/SergeyZh/mpg-341cqpx-qd-oled-re/tree/4d04c2c16326a37e26da3ffdc47b54905e1702c5) | © 2026 Sergey Zhukov and contributors. Code: MIT. Research documentation, photos and manual function names: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), as described in [LICENSE-docs](https://github.com/SergeyZh/mpg-341cqpx-qd-oled-re/blob/4d04c2c16326a37e26da3ffdc47b54905e1702c5/LICENSE-docs). Our documentation summarizes its board/loader/ISP findings in our own organization and wording; no photographs are included. Upstream research retains its own license. |
| [phfroidmont/msi-monitor-flash](https://github.com/phfroidmont/msi-monitor-flash/tree/c0b58d8275d1ba8e2749ded82884a327661f8581) | Copyright (c) 2026 msi-monitor-flash contributors. MIT. Independent Linux update report and smaller-capacity corroboration. |
| [couriersud/msigd](https://github.com/couriersud/msigd/tree/737a84fcfeb487226309e0cd585a05a08db6014a) | couriersud and contributors; upstream GPLv2 license text. Ordinary HID/model evidence. |
| [hamishmorgan/msi-mpg-491cqp-control](https://github.com/hamishmorgan/msi-mpg-491cqp-control/tree/4d9a6ed8e14893ff6cc216055ea3b8986e09cdf5) | Copyright (c) 2025 Hamish Morgan. MIT. Ordinary HID/KVM evidence. |
| [joshrzemien/msi-mpg341c](https://github.com/joshrzemien/msi-mpg341c/tree/a273bdf7d372d99a5483fe833120aa2babb971ba) | joshrzemien and contributors; upstream GPLv3 license text. Model and normal-control evidence. |
| [schlarpc/asus-pg42uq-firmware-re](https://github.com/schlarpc/asus-pg42uq-firmware-re/tree/9007c5309c462fb577053cfe589f428acf4af7a5) | schlarpc. No root license found at the reviewed revision. Corroborating Novatek register/sequencer research; its VIA USB transport is not included. Public availability alone is not a reuse license. |
| [fwupd](https://github.com/fwupd/fwupd/tree/54306abafafba4f3a7698164fd704e2487e4351a) | fwupd contributors. Root COPYING contains LGPLv2.1; individual files have their own notices. Plugin inventory comparison found no matching MSI monitor backend. |

Retain upstream notices for any future copied or adapted material and check its license before incorporation; this attribution list is not permission to copy GPL or unlicensed code into an MIT project.

## MIT notices

The MIT-licensed sources listed above carry these copyright notices, retained here with the common permission text:

- Copyright (c) 2026 Sergey Zhukov and contributors
- Copyright (c) 2026 msi-monitor-flash contributors
- Copyright (c) 2025 Hamish Morgan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
