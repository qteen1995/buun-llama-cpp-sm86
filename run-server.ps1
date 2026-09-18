<#
  run-server.ps1 - start llama-server from the buun-llama-cpp build with the
  fork's KV-cache codecs (VBR / TurboQuant / TCQ) and the shipped codebooks.

  Examples:
    .\run-server.ps1 -Model E:\LM_models\Qwen3-8B-Q4_K_M.gguf
    .\run-server.ps1 -Model model.gguf -Kv turbo3_tcq -Ctx 32768
    .\run-server.ps1 -Model model.gguf -Kv vbr -VbrVram 8G -VbrEntry t8
    .\run-server.ps1 -Model model.gguf -Kv auto -ListenHost 0.0.0.0 -ApiKey secret

  KV modes (-Kv):
    vbr        explicit VBR, opens the full ladder down to t1   -> -ct vbr
    auto       implicit VBR (fork default, ladder floor t4)     -> no -ctk/-ctv
    <type>     a fixed tier, e.g. f16, q8_0, turbo4, turbo3_tcq, turbo2_tcq
               or a VBR tier alias t8 / t4 / t3 / t2 / t1       -> -ctk <t> -ctv <t>

  VBR requires flash attention; -fa on is passed unless -NoFlashAttn is given.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Model,
    [string] $Kv        = 'vbr',
    [int]    $Ctx       = 8192,
    [int]    $Ngl       = 99,
    [int]    $Threads   = 8,
    [int]    $Port      = 8080,
    [string] $ListenHost = '127.0.0.1',
    [string] $ApiKey    = '',
    [string] $VbrVram   = '',
    [string] $VbrEntry  = '',
    [string] $VbrFloor  = '',
    [string] $VbrCodec  = '',
    [switch] $NoFlashAttn,
    [string[]] $ExtraArgs = @()
)

# llama-server writes INFO logs to stderr; with 'Stop' PowerShell treats the first
# stderr line of a native exe as a terminating error and would kill the process.
$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$Exe  = Join-Path $Root 'build\bin\llama-server.exe'
if (-not (Test-Path $Exe)) { throw "llama-server.exe not found: $Exe  (run build-cuda.ps1 first)" }
if (-not (Test-Path $Model)) { throw "model not found: $Model" }

# Shipped TCQ codebooks. Without them the build falls back to its built-in codebook.
$cb3 = Join-Path $Root 'codebooks\3bit\cb_50iter_finetuned.bin'
$cb2 = Join-Path $Root 'codebooks\2bit\tcq_2bit_100iter_s99.bin'
if (Test-Path $cb3) { $env:TURBO_TCQ_CB  = $cb3; Write-Host "TURBO_TCQ_CB  = $cb3" }
if (Test-Path $cb2) { $env:TURBO_TCQ_CB2 = $cb2; Write-Host "TURBO_TCQ_CB2 = $cb2" }

$kvArgs = @()
switch ($Kv.ToLower()) {
    'vbr'  { $kvArgs = @('-ct', 'vbr') }
    'auto' { $kvArgs = @() }
    default { $kvArgs = @('-ctk', $Kv, '-ctv', $Kv) }
}

$srvArgs = @(
    '-m', $Model,
    '-ngl', "$Ngl",
    '-c', "$Ctx",
    '-t', "$Threads",
    '--port', "$Port",
    '--host', $ListenHost
)
if (-not $NoFlashAttn) { $srvArgs += @('-fa', 'on') }
$srvArgs += $kvArgs
if ($VbrVram)  { $srvArgs += @('--vbr-vram',  $VbrVram) }
if ($VbrEntry) { $srvArgs += @('--vbr-entry', $VbrEntry) }
if ($VbrFloor) { $srvArgs += @('--vbr-floor', $VbrFloor) }
if ($VbrCodec) { $srvArgs += @('--vbr-codec', $VbrCodec) }
if ($ApiKey)   { $srvArgs += @('--api-key',   $ApiKey) }
$srvArgs += $ExtraArgs

Write-Host ("`n" + $Exe)
Write-Host ($srvArgs -join ' ')
if ($ListenHost -ne '127.0.0.1' -and -not $ApiKey) {
    Write-Warning 'Listening on a non-loopback address without --api-key. Anyone on the network can call this server.'
}
Write-Host ''

& $Exe @srvArgs
