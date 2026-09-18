<#
  copy-cuda-dlls.ps1 - make build\bin self-contained for the CUDA toolkit it was built against.

  Why: the machine PATH only carries CUDA v13.3, so a binary built against CUDA 12.8 fails to
  start with "cublas64_12.dll was not found" unless the v12.8 runtime DLLs sit next to the exes.

  How: read the real import table of every DLL in build\bin with dumpbin /DEPENDENTS, and for each
  import that is neither in build\bin nor a Windows system DLL, look it up anywhere under the CUDA
  toolkit root and copy it into build\bin.

  Usage:
    .\copy-cuda-dlls.ps1
    .\copy-cuda-dlls.ps1 -CudaRoot "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8" -WhatIf
#>
[CmdletBinding()]
param(
    [string] $CudaRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8",
    [string] $BinDir   = (Join-Path $PSScriptRoot 'build\bin'),
    [switch] $WhatIf
)

$ErrorActionPreference = 'Continue'

if (-not (Test-Path $BinDir)) { throw "bin dir not found: $BinDir" }
if (-not (Test-Path $CudaRoot)) { throw "CUDA root not found: $CudaRoot" }

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VSP = (& $vswhere -latest -products * -property installationPath)
$dumpbin = "$VSP\VC\Tools\MSVC\$((Get-ChildItem "$VSP\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name)\bin\Hostx64\x64\dumpbin.exe"
if (-not (Test-Path $dumpbin)) { throw "dumpbin.exe not found at $dumpbin" }

$systemDir = "$env:SystemRoot\System32"
$local     = @(Get-ChildItem $BinDir -Filter *.dll | ForEach-Object { $_.Name.ToLower() })

# one pass over the CUDA toolkit so lookups are cheap
Write-Host "indexing $CudaRoot ..."
$cudaIndex = @{}
Get-ChildItem $CudaRoot -Recurse -Filter *.dll -ErrorAction SilentlyContinue | ForEach-Object {
    $k = $_.Name.ToLower()
    if (-not $cudaIndex.ContainsKey($k)) { $cudaIndex[$k] = $_.FullName }
}
Write-Host "  $($cudaIndex.Count) CUDA dlls indexed"

$copied  = @()
$missing = @()

foreach ($dll in Get-ChildItem $BinDir -Filter *.dll) {
    $deps = & $dumpbin /nologo /DEPENDENTS $dll.FullName 2>&1 |
            Select-String -Pattern '^\s+([A-Za-z0-9_.+-]+\.dll)\s*$' |
            ForEach-Object { $_.Matches[0].Groups[1].Value }
    foreach ($dep in $deps) {
        $k = $dep.ToLower()
        if ($local -contains $k) { continue }
        if (Test-Path (Join-Path $systemDir $dep)) { continue }
        if ($cudaIndex.ContainsKey($k)) {
            $src = $cudaIndex[$k]
            if (-not $WhatIf) { Copy-Item $src -Destination (Join-Path $BinDir $dep) -Force }
            $copied += "$dep  <-  $src"
            $local  += $k
        } else {
            $missing += "$dep  (needed by $($dll.Name))"
        }
    }
}

Write-Host ''
if ($copied.Count) {
    Write-Host "copied into $BinDir ($($copied.Count)):"
    $copied | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
} else { Write-Host 'nothing to copy - build\bin already resolves every non-system import' }

if ($missing.Count) {
    Write-Host ''
    Write-Host "WARNING - unresolved imports (not in System32, not in the CUDA toolkit):"
    $missing | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
}
Write-Host ''
Write-Host "bin\bin content:"
Get-ChildItem $BinDir -Filter *.dll | ForEach-Object { Write-Host ("  " + $_.Name + "  " + [math]::Round($_.Length/1MB,1) + " MB") }
