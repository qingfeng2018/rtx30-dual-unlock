# Build the dual-card RTX 30 headless unlock package from a clean upstream checkout.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -LlvmBin C:\LLVM20\bin
param(
  [string]$WorkDir = "$PSScriptRoot\..\build",
  [string]$LlvmBin = $env:LLVM_BIN,
  [int[]]$Buses = @(2, 3),
  [string]$Out = "$PSScriptRoot\..\dist"
)
# Native tools (git/clang) write progress to stderr; do not let that abort the run.
$ErrorActionPreference = 'Continue'
$repo = Split-Path $PSScriptRoot -Parent

function Find-Tool([string]$name) {
  if ($LlvmBin) {
    $p = Join-Path $LlvmBin $name
    if (Test-Path $p) { return $p }
  }
  $c = Get-Command $name -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  throw "$name not found. Install LLVM 20.x or pass -LlvmBin <dir>."
}

$clang = Find-Tool 'clang.exe'
$lld = Find-Tool 'lld-link.exe'
Write-Host "clang   : $clang"
Write-Host "lld-link: $lld"

$src = Join-Path $WorkDir 'rtx30-unlock'
if (Test-Path $src) { Remove-Item $src -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
git clone --quiet --depth 1 --branch v0.1.0 https://github.com/craftingmod/rtx30-unlock.git $src 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
Push-Location $src
try {
  git apply (Join-Path $repo 'patches\0000-gop-single-display-child.patch') 2>&1 | Write-Host
  if ($LASTEXITCODE -ne 0) { throw "patch 0000 failed" }
  git apply (Join-Path $repo 'patches\0001-headless-dual-card.patch') 2>&1 | Write-Host
  if ($LASTEXITCODE -ne 0) { throw "patch 0001 failed" }
  Write-Host "patches applied at $(git rev-parse --short HEAD)"

  $sources = @(
    'src/gop/app', 'src/gop/full', 'src/unlock/runtime', 'src/unlock/format', 'src/gop/leaf',
    'src/gop/reset', 'src/gop/visual', 'src/unlock/app', 'src/unlock/app_io',
    'src/unlock/ownership', 'src/unlock/sha256', 'src/unlock/checks', 'src/unlock/port',
    'src/unlock/compat', 'src/unlock/vendor/unlock_610', 'src/unlock/vendor/prep_610',
    'src/unlock/vendor/layout_610', 'src/unlock/vendor/vbios_610', 'src/unlock/vendor/gfw_eval',
    'src/unlock/runtime_profile', 'src/probe/probe_app', 'src/probe/probe_core',
    'src/probe/probe_profile', 'src/unlock/profile_probe', 'src/gop/windows'
  )
  $flags = @(
    '-target', 'x86_64-pc-windows-msvc', '-std=c11', '-ffreestanding', '-fno-builtin',
    '-fno-stack-protector', '-mno-red-zone', '-fshort-wchar', '-Os', '-Wall', '-Wextra',
    '-DGC_FULL_FLR', '-DGC_FULL_UNLOCK', '-DGU_GOP_EXPERIMENT', '-D__KERNEL__', '-DGU_UEFI_PORT',
    '-DGU_RUNTIME_PROFILE_BUILD', '-DGU_AUTO_PROFILE', '-DGC_PRODUCTION', '-DGU_CHAIN',
    '-DGU_HEADLESS', '-Wno-unused-parameter', '-Wno-unused-function',
    '-I', 'src/unlock/compat', '-I', 'deps/edk2/MdePkg/Include', '-I', 'deps/edk2/MdePkg/Include/X64'
  )

  New-Item -ItemType Directory -Force -Path $Out | Out-Null
  $index = 0
  foreach ($bus in $Buses) {
    $index++
    $tag = if ($index -eq 1) { 'GU_DIR_A' } else { 'GU_DIR_B' }
    $name = "RTX30-$bus"
    $objDir = Join-Path $Out "obj-$name"
    New-Item -ItemType Directory -Force -Path $objDir | Out-Null
    $objs = @()
    foreach ($s in $sources) {
      $obj = Join-Path $objDir (($s -replace '[\\/]', '_') + '.obj')
      & $clang @flags "-DGU_TARGET_BUS=$bus" "-D$tag" -c "$s.c" -o $obj
      if ($LASTEXITCODE -ne 0) { throw "compile failed: $s (bus $bus)" }
      $objs += $obj
    }
    $efi = Join-Path $Out "$name.EFI"
    & $lld /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 `
      /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/out:$efi" @objs
    if ($LASTEXITCODE -ne 0) { throw "link failed: $name" }
    Write-Host "built $efi"
  }

  $lobj = Join-Path $Out 'launcher.obj'
  & $clang @flags -c 'src/launcher/launcher.c' -o $lobj
  if ($LASTEXITCODE -ne 0) { throw 'launcher compile failed' }
  & $lld /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 `
    /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/out:$(Join-Path $Out 'BOOTX64.EFI')" $lobj
  if ($LASTEXITCODE -ne 0) { throw 'launcher link failed' }

  Write-Host ""
  Write-Host "Dist ready: $Out"
  Write-Host "  BOOTX64.EFI  launcher"
  foreach ($bus in $Buses) { Write-Host "  RTX30-$bus.EFI  target bus $bus" }
  Write-Host ""
  Write-Host "Next: create RTX-UNLOCK-A / RTX-UNLOCK-B with ASSETS + DEBUG.ON,"
  Write-Host "      copy the three EFI files to <usb>\EFI\BOOT\, then boot it on the target machine."
} finally {
  Pop-Location
}
