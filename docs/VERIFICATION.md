# Verification report

Reference machine, 2026-10-28. This is the only configuration that has been tested.

| | |
|---|---|
| Mainboard | server-class board with ASPEED AST1400/2400 video, no iGPU |
| GPU 0 | NVIDIA GeForce RTX 3080 20 GB, `10DE:2206`, subsystem `146D:10DE`, `0000:02:00.0` |
| GPU 1 | NVIDIA GeForce RTX 3080 20 GB, `10DE:2206`, subsystem `146D:10DE`, `0000:03:00.0` |
| VBIOS | `94.02.27.00.14` on both cards |
| GPU part number | `2206-200-A1` |
| OS / driver | Windows 11 26200, NVIDIA 610.88 (CUDA UMD 13.3) |
| Console | ASPEED; neither RTX card had a monitor attached |
| Secure Boot | not published by firmware (`Confirm-SecureBootUEFI` → `0xC0000100`) |
| Toolchain | clang / lld-link 20.1.8 |

## UEFI stage

Both passes ran inside one power cycle, about one minute apart. Log excerpts
(`RUNnn/GOP.TXT`, `DEBUG.ON` present):

### Card A — `RTX-UNLOCK-A/RUN02/GOP.TXT`

```
PROFILE v1 loaded: PCI=220610de subsystem=146d10de chip=b72000a1 FB=20480 MiB
                   PROM=1a7033551795b72cd92501831385c4238ab591361255dce5ddb1fb56e18ebde8
SECURE_BOOT_ABSENT: no SecureBoot variable; continuing as disabled
target=0x76cb5098 BDF=0:2:0.0
HEADLESS_DISCONNECT status=0
HEADLESS_CLAIM status=0 exclusive=1
HEADLESS_PATCH status=0 safe=1 released=0
PATCH_STATE phase=after-output SS0=88888888 SS1=00000008 PLM=ffffffff command=0x3
            read_ok=1 matched=1
PATCH_LOG_CLOSE status=0
```

### Card B — `RTX-UNLOCK-B/RUN00/GOP.TXT`

```
target=0x76cb2a18 BDF=0:3:0.0
HEADLESS_DISCONNECT status=0
HEADLESS_CLAIM status=0 exclusive=1
HEADLESS_PATCH status=0 safe=1 released=0
PATCH_STATE phase=after-output SS0=88888888 SS1=00000008 PLM=ffffffff command=0x3
            read_ok=1 matched=1
PATCH_LOG_CLOSE status=0
```

`matched=1` is evaluated after the PCIe FLR, so the selectors survived the reset.
`safe=1` means DMA bookkeeping was clean and no mapping was retained.

## Windows stage

Same power cycle (`LastBootUpTime` 11:40:50, benchmark at 11:43), cuBLAS GEMM 4096³,
15 iterations per case.

| | GPU0 locked | GPU0 unlocked | GPU1 locked | GPU1 unlocked |
|---|---:|---:|---:|---:|
| FP32 | 21.53 | 21.40 | 21.93 | 21.93 |
| TF32 | 29.55 | **52.62** | 30.48 | **53.47** |
| FP16 | 61.74 | **116.68** | 62.85 | **118.90** |
| BF16 | 61.83 | **118.17** | 62.86 | **120.48** |
| D2D copy | 684.8 GB/s | 673.7 GB/s | 684.9 GB/s | 683.8 GB/s |

Derived checks:

- FP32 is unchanged on both cards — the gain is not clock or bandwidth related.
- FP16/FP32 ratio: 2.87 before, 5.45 after (upstream reference on a single RTX 3080: 4.98).
- D2D bandwidth is unchanged within noise.
- FP16 reaches 98–100% of the GA102 dense FP16 tensor peak with FP32 accumulate (119 TFLOPS).

Grid size 8192³ on the locked card gave the same shape (21.55 / 31.99 / 64.98 / 64.97),
so the 4096³ result is not a size artefact.

## Selector drift

`SS0` is not stable across cold boots on this card family:

```
profile capture : SS0 = 0x24156024  SS1 = 0x4
later cold boot : SS0 = 0x24156020  SS1 = 0x4
```

Upstream's `ColdCheck()` compares for equality and therefore fails every subsequent
boot. v0.1.0 of this project accepts any value that is neither `0xffffffff` nor
`0x88888888`. The chip id (`0xb72000a1`), PLM (`0xffffff8f`), WPR2 high word, framebuffer
size (`0x5000`) and the six layout registers are still compared exactly.

## Reproducibility

`scripts/build.ps1` on a clean upstream checkout produced binaries byte-identical to the
ones used for the run above:

```
RTX30-2.EFI  d69ae7c5523f6462db1ce4502cb68225a8ed18c7edeae82963b9f003beaf49a0
RTX30-3.EFI  8ac06ce4144b117b80aaaa6165d2a003465da5570cd78bbe1ad40b2d26e4915b
BOOTX64.EFI  638b8d2a146a54ec2f465cdf9e92b06ac9e49c7163e5ec42c101c6df557747e5
```

(These hashes change whenever the patches change. Do not treat them as a compatibility
guarantee — they identify exactly the binaries behind the numbers above.)
