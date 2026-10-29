# NOTICE

This repository is a patch set and build recipe. It contains no upstream source tree,
no NVIDIA firmware and no VBIOS images.

## Upstream and third-party work

| Project | Licence | What is used here |
|---|---|---|
| [craftingmod/rtx30-unlock](https://github.com/craftingmod/rtx30-unlock) @ `5c076dc4` (`v0.1.0`) | GPL-2.0-only | The Windows/UEFI unlock application this project patches |
| [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) @ `0ebdb1c6` | GPL-2.0-only | Original Linux technique, reused by upstream |
| [rough2515-hub/rtx3080-unlock-public](https://github.com/rough2515-hub/rtx3080-unlock-public) | GPL-2.0-only | The MSI RTX 3080 port that upstream derives from |
| [Siselea/rtx30-unlock-windows-toolkit](https://github.com/Siselea/rtx30-unlock-windows-toolkit) | GPL-2.0-only | `patches/0000-gop-single-display-child.patch`, vendored verbatim |

`patches/0000-gop-single-display-child.patch` is reproduced unchanged, including its
author and date header. It relaxes `GfPrepare()` so a single vendor child is accepted
instead of exactly two.

`patches/0001-headless-dual-card.patch` is original work in this repository, applied on
top of the above.

Derived code (the patches, the launcher, the build script) is distributed under
GPL-2.0-only, matching upstream. See `LICENSE`.

## What is deliberately **not** in this repository

- **NVIDIA firmware assets.** `gsp_ga10x.bin`, `booter_load_ga102.bin`,
  `gsp_boot_ga102.bin`, `gsp_boot_desc_ga102.bin` and `v67-ga102-610.43.03.bin` are
  extracted from NVIDIA packages under the NVIDIA Driver License Agreement. The build
  documentation explains how to generate them locally with upstream's
  `firmware-assets.exe`; they are not redistributed here.
- **`PROFILE.BIN`.** It encodes per-card PCI identity, PROM hash and selector values, and
  must be captured on the target machine.
- **VBIOS / ROM images.** The tool never writes them; `ROMIMAGE.BIN` and `PROM.BIN`
  produced by a probe run stay on the operator's USB stick.
- **`RUNnn` / `PROBEnn` logs.** They contain per-machine data.

## Statement

No NVIDIA source code, firmware or driver binary is redistributed. The patches only
modify host-side code from the GPL-2.0-only projects listed above. Anyone redistributing
a built `BOOTX64.EFI` must also make the corresponding source available under GPL-2.0,
which means this repository plus the pinned upstream commit.
