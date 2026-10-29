# Changelog

All notable changes to this project. Versioning follows [SemVer](https://semver.org/):
the major/minor numbers track this patch set, not upstream.

## v0.1.0 — 2026-10-28

First public release. Verified on a dual RTX 3080 20 GB machine with an ASPEED
console and no monitor attached to either card.

### Added

- `patches/0001-headless-dual-card.patch` — the four changes that make upstream work
  on a multi-GPU, monitor-less machine:
  - per-BDF target filter in the probe and in `Target()`, so each build sees exactly
    one card (`-DGU_TARGET_BUS=<bus>`);
  - per-card payload directory (`RTX-UNLOCK-A` / `RTX-UNLOCK-B`) so profiles and logs
    never collide;
  - `GU_CHAIN`: return to the loader after a successful card instead of halting, so a
    second card can run in the same power cycle;
  - `GU_HEADLESS`: skip the GOP/console ownership dance and instead
    `DisconnectController` + exclusive-open the target card.
- `src/launcher/launcher.c` — a small EFI application that chainloads `RTX30-<bus>.EFI`
  once per bus and then returns to firmware.
- `scripts/build.ps1` — clone upstream at `v0.1.0`, apply both patches, build two
  per-card children plus the launcher. Reproducible with LLVM 20.x.
- `docs/VERIFICATION.md` — raw UEFI log excerpts and before/after GEMM numbers.

### Fixed

- **Secure Boot query aborts on boards without the variable.**
  `GetVariable(L"SecureBoot")` returns `EFI_NOT_FOUND` on some server boards; upstream
  treated that as `EFI_SECURITY_VIOLATION`. A missing variable now counts as "Secure
  Boot not enabled"; an existing variable with value 1 is still refused.
- **Exact selector match causes false failures.**
  `ColdCheck()` required `SS0 == PROFILE.SS0`, but these cards latch a slightly
  different value on every cold boot (observed `0x24156024` → `0x24156020`). The check
  now accepts any programmed selector that is neither `0xffffffff` nor the
  already-unlocked `0x88888888`. Chip id, PLM, WPR2, framebuffer size and layout values
  are still compared exactly.

### Verified

| cuBLAS GEMM 4096³, 15 iterations | GPU0 locked → unlocked | GPU1 locked → unlocked |
|---|---:|---:|
| FP32 (control) | 21.53 → 21.40 | 21.93 → 21.93 |
| TF32 | 29.55 → 52.62 (+78%) | 30.48 → 53.47 (+75%) |
| FP16 tensor | 61.74 → **116.68 (+89%)** | 62.85 → **118.90 (+89%)** |
| BF16 tensor | 61.83 → **118.17 (+91%)** | 62.86 → **120.48 (+92%)** |

Both cards reported `PATCH_STATE ... SS0=88888888 SS1=00000008 PLM=ffffffff matched=1`
in the same power cycle.

### Known issues

- The unlock is volatile: a power cut or reboot resets the selectors. Every cold boot
  needs the USB ritual again. Sleep/hibernate may also clear them.
- Only one hardware configuration has been verified. Monitors attached to the target
  cards, other card models, and other firmware are untested.
- `GU_HEADLESS` drops upstream's "display is fully detached" proof. It relies on
  `DisconnectController` plus an exclusive protocol claim instead. The transaction's own
  containment checks (`GxSafe()`, DMA accounting) are unchanged.

---

# 更新日志（中文）

## v0.1.0 — 2026-10-28

首个公开版本。在双 RTX 3080 20G、ASPEED 显示、目标卡未接显示器的机器上验证通过。

### 新增

- `patches/0001-headless-dual-card.patch`：四处改动，让上游能在“多卡 + 无显示器”环境工作
  —— 按 BDF 过滤目标卡、每卡独立 payload 目录、成功后返回以便跑第二张、以及跳过显示接管
  的 `GU_HEADLESS` 路径。
- `src/launcher/launcher.c`：依次 chainload 两个子程序的 launcher。
- `scripts/build.ps1`：拉取上游 `v0.1.0`、打两个补丁、编译两份子程序与 launcher。
- `docs/VERIFICATION.md`：原始 UEFI 日志与解锁前后基准数据。

### 修复

- 主板没有 `SecureBoot` 变量时被误判为安全违规 → 现视为未开启。
- `SS0` 冷启动漂移导致 `ColdCheck` 假失败 → 放宽为“已编程且未解锁”。

### 已知问题

- 解锁易失，断电/重启即失效，每次冷启动都要重跑 U 盘流程。
- 只验证了一种硬件组合。
- headless 路径少了上游“显示已完全隔离”的证明，改用 `DisconnectController` + 独占声明。
  事务内部的 containment 检查未改动。
