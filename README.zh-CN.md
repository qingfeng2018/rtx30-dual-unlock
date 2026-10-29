# RTX 30 双卡解锁（Windows / UEFI，headless）

[English](README.md) | 简体中文

在一台**显示器不接在显卡上**的机器里，用一支 U 盘，一次性解锁**两张** RTX 30（GA10x）
显卡的 tensor 发射率限制。不刷 VBIOS、不换驱动、不需要 Linux。

本项目是 [craftingmod/rtx30-unlock](https://github.com/craftingmod/rtx30-unlock) v0.1.0 的
补丁集与构建脚本。上游只接受“系统里只有一张 NVIDIA 显示设备”，并且要求被解锁的那张卡
正好是当前的 console 输出。这里把两个限制都拆掉，再加一个 launcher，
在同一个通电周期内依次跑两张卡。

**已验证结果**（2× RTX 3080 20G，ASPEED 显示，两张卡都没接显示器）：

| cuBLAS GEMM 4096³ | 解锁前 | 解锁后 | 变化 |
|---|---:|---:|---:|
| FP32（对照组） | 21.53 | 21.40 | ±0 |
| TF32 | 29.55 | 52.62 | +78% |
| FP16 tensor | 61.74 | **116.68** | **+89%** |
| BF16 tensor | 61.83 | **118.17** | **+91%** |

FP16/FP32 比值从 2.87 变成 5.45。完整日志与每卡数据见
[docs/VERIFICATION.md](docs/VERIFICATION.md)。

---

## 修了什么问题

| 上游现象 | 原因 | 本项目的处理 |
|---|---|---|
| 双卡时报 `target ambiguous` / `EFI_NOT_READY` | 探测和 `Target()` 都要求 `matches == 1` | 按 PCI bus 分卡编译两份 EFI |
| `stage=full-prepare status=EFI_UNSUPPORTED`，且没有任何 `FULL_*` 日志 | `GcLeafPrepare()` 要求目标卡就是 console 输出 | 新增 `GU_HEADLESS` 路径：`DisconnectController` + 独占声明，完全不碰显示 |
| `stage=secure-boot status=EFI_SECURITY_VIOLATION` | 主板不发布 `SecureBoot` 变量，查询返回 `EFI_NOT_FOUND` | 变量缺失视为“未开启安全启动” |
| `PATCH_PREFLIGHT status=EFI_NOT_READY`，`SS0` 差一个 bit | `ColdCheck()` 要求选择器完全相等，但这批卡每次冷启动 `SS0` 会有轻微漂移（`0x24156024` → `0x24156020`） | 只要求是已编程值，且不是 `0xffffffff`、也不是已解锁的 `0x88888888` |
| 第二张卡永远跑不到 | 上游成功后直接 Halt 并跳转 Windows | `GU_CHAIN` 返回 + launcher 依次 chainload 两个子程序 |

## 前置条件

- **两张** GA10x 显卡。本项目在 2× RTX 3080 20G（`10DE:2206`，子系统 `146D:10DE`）上验证。
- UEFI 启动，**Secure Boot 关闭**（主板根本不发布该变量也可以）。
- console 必须**不在**被解锁的卡上：核显、ASPEED/BMC，或者第三张卡。解锁期间两张目标卡
  不要接显示器。
- 必须冷启动：显卡在本次通电后不能被系统驱动初始化过。
- 每张卡需要自己的 `PROFILE.BIN`，首次运行会自动采集（采集期间不要让机器跑别的东西）。
- 第一次改启动顺序前，准备好 BitLocker 恢复密钥。
- 构建环境：`git`、PowerShell 5.1+、`clang` + `lld-link` 20.x
  （用 `-LlvmBin` 或 `LLVM_BIN` 指定；便携版 LLVM 即可，不需要 Visual Studio）。

## 构建

```powershell
git clone https://github.com/<you>/rtx30-dual-unlock.git
cd rtx30-dual-unlock
powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -LlvmBin C:\LLVM20\bin
```

脚本会：拉取上游 `v0.1.0`（`5c076dc4`）→ 应用
`patches/0000-gop-single-display-child.patch`（来自
[Siselea](https://github.com/Siselea/rtx30-unlock-windows-toolkit)，GPL-2.0）和
`patches/0001-headless-dual-card.patch`（本项目）→ 编译出：

```
dist/BOOTX64.EFI    launcher（与目标无关）
dist/RTX30-2.EFI    目标 0000:02:00.0
dist/RTX30-3.EFI    目标 0000:03:00.0
```

构建是可复现的：`-base:0 /timestamp:0 /opt:icf` 让产物与
[docs/VERIFICATION.md](docs/VERIFICATION.md) 中验证过的二进制逐字节一致（同一套工具链）。

PCI bus 不是 2 和 3？用 `-Buses 1,3`。第一个 bus 对应 payload 目录 `RTX-UNLOCK-A`，
第二个对应 `RTX-UNLOCK-B`。用
`nvidia-smi --query-gpu=pci.bus_id --format=csv` 查（取 `00000000:` 后面那个数字）；
工具只支持 segment 0 / device 0 / function 0。

## 制作 U 盘

1. FAT32 U 盘，至少 1 GB（每张卡 85 MB 资源）。
2. 用上游的 `firmware-assets.exe` 生成 5 个固件资源
   （`bun run firmware:assets` 或发行版的 `firmware-fetch.zip`）。
   **这些是 NVIDIA 固件，本仓库不提供。**
3. 目录结构：

```
U盘:/
  EFI/BOOT/BOOTX64.EFI      launcher
  EFI/BOOT/RTX30-2.EFI      bus 2 的子程序
  EFI/BOOT/RTX30-3.EFI      bus 3 的子程序
  RTX-UNLOCK-A/ASSETS/      5 个 .bin + NVIDIA-LICENSE
  RTX-UNLOCK-A/DEBUG.ON     空文件：手动模式 + 完整日志
  RTX-UNLOCK-B/ASSETS/      同样的 5 个文件
  RTX-UNLOCK-B/DEBUG.ON     空文件
```

有 `DEBUG.ON` 时，每一趟都会等 `U`，并写 `RUNnn/GOP.TXT` 和 `UNLOCK.TXT`。
确认流程稳定后再删掉这两个文件，工具就会两趟全自动、不需要按键。

## 启动流程

1. **完全关机**（重新启动会被拒绝，这是设计如此）。
2. 开机进启动菜单，选 `UEFI: <U盘>`。
3. `pass 1 of 2` → 等 `READY` → 按一次 **U** → 等 `CARD DONE`。
4. launcher 自动继续：`pass 2 of 2` → `READY` → 按一次 **U** → `CARD DONE`。
5. 出现 `Both passes completed` 后选 **Windows Boot Manager**，**不要重启**。

某一趟打印 `STOP` 或 `pass N failed`：长按电源键关机，先把
`RTX-UNLOCK-A/RUNnn/GOP.TXT`（流程）和 `UNLOCK.TXT`（设备状态）拿出来再重试。

## 验证

```powershell
# cuBLAS GEMM 4096³，FP32 / TF32 / FP16 / BF16
.\cuda_gemm_bench.exe 0 4096 15
.\cuda_gemm_bench.exe 1 4096 15
```

| 读数 | 判定 |
|---|---|
| FP16 ≥ 100 TFLOPS | 已解锁 |
| FP16 ≤ 70 TFLOPS | 未解锁，重跑 U 盘流程 |
| FP16/FP32 ≥ 4.5 | 已解锁 |

`nvidia-smi`、GPU-Z、任务管理器**都看不到**这两个选择器。llama.cpp 跑量化模型大约只涨 7%，
不能作为判据。

## 限制

- **易失**：断电或重启后 `SS0`/`SS1` 复位，每次冷启动都要再走一遍一分钟的 U 盘流程。
  睡眠/休眠也可能清掉。
- **只验证了一台机器**：双 RTX 3080 20G + ASPEED 显示 + Windows 11 26200 + 驱动 610.88。
  换主板、换卡、显示器接在目标卡上，都未验证。
- 这批卡的 `SS0` 每次冷启动会轻微漂移，所以判据被放宽了；芯片 id、PLM、WPR2、
  显存大小和 layout 仍然精确比对。
- 没有长期稳定性数据。满载时请自己观察 `nvidia-smi` 的 Xid 和温度。
- 解锁只提升计算密集的 tensor 部分（prefill、出图/视频）；显存带宽瓶颈的 decode 基本不变。

## 原理

EFI 程序在 Windows 驱动绑定之前运行：通过 SEC2 boot ROM 启动 GPU 固件，用 V67 payload
解除固件保护，写入 `SS0 = 0x88888888` / `SS1 = 0x8`，做一次 PCIe FLR 并验证选择器仍然保持。
不写 VBIOS，也不替换 Windows 驱动。

本项目只改变“什么时候允许执行”和“对哪张卡执行”，事务本身是上游代码。

## 致谢与许可

- [craftingmod/rtx30-unlock](https://github.com/craftingmod/rtx30-unlock)（GPL-2.0-only）——
  本项目的上游。
- [Zagitta/gpu-unlock](https://github.com/Zagitta/gpu-unlock)（GPL-2.0-only）—— 原始 Linux 方案。
- [Siselea/rtx30-unlock-windows-toolkit](https://github.com/Siselea/rtx30-unlock-windows-toolkit)
  （GPL-2.0-only）—— 单显示补丁，以 `patches/0000-*.patch` 形式内置。
- [rough2515-hub/rtx3080-unlock-public](https://github.com/rough2515-hub/rtx3080-unlock-public)——
  上游所源自的 MSI RTX 3080 移植。

GPL-2.0-only，见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。本仓库不包含 NVIDIA 固件、
`PROFILE.BIN` 或任何 VBIOS 镜像。

**本工具会修改显卡运行状态，风险自负。**
