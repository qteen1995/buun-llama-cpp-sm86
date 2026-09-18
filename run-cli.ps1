<#
  run-cli.ps1 - one-shot generation / smoke test on the buun build.

  NOTE: in this fork (as in current upstream) `-no-cnv` / `-cnv` are registered for
  llama-completion only, NOT for llama-cli - `llama-cli -no-cnv` fails with
  "invalid argument: -no-cnv". So this script drives llama-completion.exe.

  Examples:
    .\run-cli.ps1 -Model model.gguf -Prompt "hello"          # default: VBR KV
    .\run-cli.ps1 -Model model.gguf -Kv f16 -N 64
    .\run-cli.ps1 -Model model.gguf -Kv turbo3_tcq -Prompt "hi"
    .\run-cli.ps1 -Model model.gguf -Kv q8_0 -ExtraArgs '-v'

  TCQ codecs require 128 % nothing: their KV block is 128 values, so the model's
  n_embd_head_k must be a multiple of 128 (Qwen2.5-0.5B has 64 and will be rejected).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Model,
    [string] $Prompt    = 'hello',
    [string] $Kv        = 'vbr',
    [int]    $N         = 32,
    [int]    $Ctx       = 4096,
    [int]    $Ngl       = 99,
    [int]    $Threads   = 8,
    [switch] $NoFlashAttn,
    [string[]] $ExtraArgs = @()
)

# llama-* writes INFO logs to stderr; with 'Stop' PowerShell would treat the first stderr
# line of a native exe as a terminating error.
$ErrorActionPreference = 'Continue'

$Root = $PSScriptRoot
$Exe  = Join-Path $Root 'build\bin\llama-completion.exe'
if (-not (Test-Path $Exe)) { throw "llama-completion.exe not found: $Exe  (run build-cuda.ps1 first)" }
if (-not (Test-Path $Model)) { throw "model not found: $Model" }

# Shipped TCQ codebooks; without them the built-in codebook is used.
$cb3 = Join-Path $Root 'codebooks\3bit\cb_50iter_finetuned.bin'
$cb2 = Join-Path $Root 'codebooks\2bit\tcq_2bit_100iter_s99.bin'
if (Test-Path $cb3) { $env:TURBO_TCQ_CB  = $cb3 }
if (Test-Path $cb2) { $env:TURBO_TCQ_CB2 = $cb2 }

$kvArgs = @()
switch ($Kv.ToLower()) {
    'vbr'  { $kvArgs = @('-ct', 'vbr') }
    'auto' { $kvArgs = @() }
    default { $kvArgs = @('-ctk', $Kv, '-ctv', $Kv) }
}

$cliArgs = @('-m', $Model, '-ngl', "$Ngl", '-c', "$Ctx", '-t', "$Threads")
if (-not $NoFlashAttn) { $cliArgs += @('-fa', 'on') }
$cliArgs += $kvArgs
if ($Prompt) { $cliArgs += @('-p', $Prompt) }
$cliArgs += @('-n', "$N")
$cliArgs += $ExtraArgs

Write-Host ("`n" + $Exe)
Write-Host ($cliArgs -join ' ' + "`n")
& $Exe @cliArgs
