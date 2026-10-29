# RTX 30 Dual Unlock (Windows / UEFI, headless)

English | [简体中文](README.zh-CN.md)

Unlock the RTX 30 (GA10x) tensor issue-rate limit on **two cards at once**, from a
single USB stick, on a machine whose display is **not** connected to the GPUs.
No VBIOS flashing, no driver replacement, no Linux.

This is a patch set and build recipe on top of
[craftingmod/rtx30-unlock](https://github.com/craftingmod/rtx30-unlock) v0.1.0.
Upstream only accepts a single NVIDIA display device, and it requires the target
card to be the active console output. This project removes both constraints and
adds a launcher that runs one unlock pass per card in the same power cycle.

**Verified result** (2× RTX 3080 20 GB, ASPEED console, no monitor on the GPUs):

| cuBLAS GEMM 4096³ | locked | unlocked | delta |
|---|---:|---:|---:|
| FP32 (control) | 21.53 | 21.40 | ±0 |
| TF32 | 29.55 | 52.62 | +78% |
| FP16 tensor | 61.74 | **116.68** | **+89%** |
| BF16 tensor | 61.83 | **118.17** | **+91%** |

FP16/FP32 ratio goes from 2.87 to 5.45. Full logs and per-card numbers:
[docs/VERIFICATION.md](docs/VERIFICATION.md).

---

## What it fixes

| Symptom in upstream | Cause | Fix in this project |
|---|---|---|
| `Detail reads skipped: target ambiguous` / `EFI_NOT_READY` with 2 GPUs | probe and `Target()` require `matches == 1` | per-card build with a PCI bus filter |
| `stage=full-prepare status=EFI_UNSUPPORTED`, no `FULL_*` log lines | `GcLeafPrepare()` requires the target card to own the console output | `GU_HEADLESS` path: `DisconnectController` + exclusive claim, no GOP/console dance |
| `stage=secure-boot status=EFI_SECURITY_VIOLATION` | firmware has no `SecureBoot` variable, query returns `EFI_NOT_FOUND` | treat a missing variable as "Secure Boot not enabled" |
| `PATCH_PREFLIGHT status=EFI_NOT_READY` with `SS0` off by one bit | `ColdCheck()` requires an exact selector match, but these cards latch a slightly different `SS0` every cold boot (`0x24156024` → `0x24156020`) | accept any programmed selector that is not `0xffffffff` and not already `0x88888888` |
| second card never runs | upstream halts after one success and hands off to Windows | `GU_CHAIN` return + launcher EFI that chainloads both children |

## Requirements

- **Two** RTX 30 (GA10x) cards. Tested on 2× RTX 3080 20 GB, `10DE:2206`, subsystem `146D:10DE`.
- UEFI boot, **Secure Boot off** (a board that does not publish the variable at all is fine).
- Display / console on something **other than the cards being unlocked** — iGPU, ASPEED/BMC,
  or a third GPU. The cards must have no monitor attached while the tool runs.
- A cold boot: the cards must not have been initialised by an OS driver since power-on.
- Each card needs its own `PROFILE.BIN`; it is captured automatically on the first run
  (needs the card to be readable, so keep the machine idle during the UEFI stage).
- BitLocker recovery key at hand the first time you change boot order.
- Build tooling: `git`, PowerShell 5.1+, and `clang` + `lld-link` 20.x
  (`-LlvmBin` or `LLVM_BIN`; a portable LLVM install is enough, no Visual Studio needed).

## Build

```powershell
git clone https://github.com/qingfeng2018/rtx30-dual-unlock.git
cd rtx30-dual-unlock
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -LlvmBin C:\LLVM20\bin
```

The script clones upstream at `v0.1.0` (`5c076dc4`), applies
`patches/0000-gop-single-display-child.patch` (from
[Siselea](https://github.com/Siselea/rtx30-unlock-windows-toolkit), GPL-2.0) and
`patches/0001-headless-dual-card.patch` (this project), then builds:

```
dist/BOOTX64.EFI    launcher        (target independent)
dist/RTX30-2.EFI    target 0000:02:00.0
dist/RTX30-3.EFI    target 0000:03:00.0
```

Builds are reproducible: `-base:0 /timestamp:0 /opt:icf` make the output byte-identical
to the binaries verified in [docs/VERIFICATION.md](docs/VERIFICATION.md) when the same
toolchain is used.

Different PCI buses? Pass `-Buses 1,3` — the payload directory is `RTX-UNLOCK-A` for the
first bus and `RTX-UNLOCK-B` for the second. Check your buses with `nvidia-smi --query-gpu=pci.bus_id
--format=csv` (the number after `00000000:`); the tool itself needs segment 0, device 0,
function 0.

## Make the USB

1. FAT32 USB stick, at least 1 GB (the assets are ~85 MB per card).
2. Fetch the five firmware assets with upstream's `firmware-assets.exe`
   (`bun run firmware:assets` or the release `firmware-fetch.zip`). **They are NVIDIA
   firmware and are not distributed here.**
3. Layout:

```
USB:/
  EFI/BOOT/BOOTX64.EFI      launcher
  EFI/BOOT/RTX30-2.EFI      child for bus 2
  EFI/BOOT/RTX30-3.EFI      child for bus 3
  RTX-UNLOCK-A/ASSETS/      five .bin files + NVIDIA-LICENSE
  RTX-UNLOCK-A/DEBUG.ON     empty file: manual mode + full logs
  RTX-UNLOCK-B/ASSETS/      same five files
  RTX-UNLOCK-B/DEBUG.ON     empty file
```

`DEBUG.ON` makes each pass wait for `U` and write `RUNnn/GOP.TXT` + `UNLOCK.TXT`.
Remove both files only after you trust the flow — the tool then runs both passes
without a key press.

## Boot ritual

1. Shut down completely (power off; a warm reboot is refused by design).
2. Power on, open the boot menu, pick the `UEFI: <usb>` entry.
3. `pass 1 of 2` → wait for `READY` → press **U** once → wait for `CARD DONE`.
4. The launcher continues: `pass 2 of 2` → `READY` → **U** once → `CARD DONE`.
5. `Both passes completed` → choose **Windows Boot Manager**. Do **not** reboot.

If a pass prints `STOP` or `pass N failed`, power off physically and read
`RTX-UNLOCK-A/RUNnn/GOP.TXT` (flow) and `UNLOCK.TXT` (device state) before retrying.

## Verify

```powershell
# cuBLAS GEMM 4096^3, FP32 / TF32 / FP16 / BF16
.\cuda_gemm_bench.exe 0 4096 15
.\cuda_gemm_bench.exe 1 4096 15
```

| Reading | Verdict |
|---|---|
| FP16 ≥ 100 TFLOPS | unlocked |
| FP16 ≤ 70 TFLOPS | locked, rerun the USB ritual |
| FP16/FP32 ≥ 4.5 | unlocked |

`nvidia-smi`, GPU-Z and Task Manager cannot see the selectors. llama.cpp with
quantised weights moves only ~7% — it is not a valid check.

## Limitations

- **Volatile.** A power cut or reboot resets `SS0`/`SS1`. Every cold boot needs the
  one-minute USB ritual again. Sleep/hibernate may also clear them.
- **One machine verified.** Dual RTX 3080 20 GB, ASPEED console, Windows 11 26200,
  driver 610.88. Other boards, other cards, monitors attached to the GPUs: untested.
- `SS0` latches a slightly different value on each cold boot on these cards, which is why
  the selector gate is relaxed. The chip id, PLM, WPR2, framebuffer size and layout
  values are still compared exactly.
- No long-term stability data. Watch `nvidia-smi` for Xid and temperatures under load.
- The unlock only helps compute-bound tensor work (prefill, image/video generation).
  Decode-bound inference barely moves.

## How it works

The EFI application runs before the Windows driver binds. It boots the GPU firmware
through the SEC2 boot ROM, uses the V67 payload to lift firmware protection, writes
`SS0 = 0x88888888` / `SS1 = 0x8`, performs one PCIe FLR and verifies the values
survived. Nothing is written to the VBIOS and the Windows driver is untouched.

This project only changes *when* the transaction is allowed to run and *which* card it
targets; the transaction itself is upstream's code.

## Credits and licence

- [craftingmod/rtx30-unlock](https://github.com/craftingmod/rtx30-unlock) (GPL-2.0-only) —
  the Windows/UEFI port this builds on.
- [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock) (GPL-2.0-only) — original
  Linux technique.
- [Siselea/rtx30-unlock-windows-toolkit](https://github.com/Siselea/rtx30-unlock-windows-toolkit)
  (GPL-2.0-only) — single-display patch, vendored here as `patches/0000-*.patch`.
- [rough2515-hub/rtx3080-unlock-public](https://github.com/rough2515-hub/rtx3080-unlock-public) —
  the MSI RTX 3080 port upstream came from.

GPL-2.0-only, see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md). No NVIDIA firmware,
no `PROFILE.BIN`, no VBIOS images are redistributed in this repository.

**This modifies GPU runtime state. Use at your own risk.**
