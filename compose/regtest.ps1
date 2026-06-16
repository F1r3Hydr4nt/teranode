<#
.SYNOPSIS
  Spin up / drive a single-node private regtest chain (from genesis).

.DESCRIPTION
  Wraps compose/docker-compose-regtest.yml. The chain runs on `network = regtest`
  with P2P and legacy sync disabled, so it never talks to any other network.

  Commands:
    up [-Build]      Start the stack (optionally build teranode:latest first)
    down             Stop and remove containers (keeps chain data)
    reset            Stop, remove containers, and WIPE chain data (back to genesis)
    restart          Restart the teranode container
    status           Show container status
    logs [svc]       Tail logs (default: teranode1)
    mine [N]         Mine N blocks via RPC (default: 1)
    info             getinfo via RPC (height, etc.)
    rpc <method> [json-params]   Raw RPC call, e.g. rpc generate '[5]'

  Override RPC connection via env vars: RPC_URL, RPC_USER, RPC_PASS.

.EXAMPLE
  .\compose\regtest.ps1 up -Build     # build teranode:latest, then start
  .\compose\regtest.ps1 mine 10        # mine 10 blocks
  .\compose\regtest.ps1 info           # getinfo (height, etc.)
  .\compose\regtest.ps1 rpc getbestblockhash
  .\compose\regtest.ps1 reset          # stop + wipe data -> fresh genesis
#>

[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string]$Command = "help",

  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Rest,

  [switch]$Build
)

$ErrorActionPreference = "Stop"

# Resolve paths relative to this script so it works from any CWD.
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptDir
$ComposeFile = Join-Path $ScriptDir "docker-compose-regtest.yml"
$DataDir     = Join-Path $RepoRoot "data\regtest"

$RpcUrl  = if ($env:RPC_URL)  { $env:RPC_URL }  else { "http://localhost:19292" }
$RpcUser = if ($env:RPC_USER) { $env:RPC_USER } else { "bitcoin" }
$RpcPass = if ($env:RPC_PASS) { $env:RPC_PASS } else { "bitcoin" }

function Invoke-Dc {
  # Paramless on purpose: $args passes flags like -d/-v/-f straight through to
  # the native docker exe (a declared [string[]] param mangles them).
  & docker compose -f $ComposeFile @args
  if ($LASTEXITCODE -ne 0) { throw "docker compose failed (exit $LASTEXITCODE)" }
}

function New-LfMounts {
  # The repo's shell scripts / settings files may be CRLF on a Windows checkout
  # (core.autocrlf=true). CRLF corrupts config values and #!/bin/sh shebangs
  # inside the Linux containers, so we write LF-normalized copies that the
  # compose file bind-mounts. Regenerated on every `up` so they never go stale.
  $mounts = Join-Path $DataDir "mounts"
  New-Item -ItemType Directory -Force -Path $mounts | Out-Null
  $map = @{
    "settings.conf"       = (Join-Path $RepoRoot  "settings.conf")
    "settings_test.conf"  = (Join-Path $ScriptDir "settings_test.conf")
    "generate-blocks.sh"  = (Join-Path $ScriptDir "scripts\generate-blocks.sh")
  }
  foreach ($name in $map.Keys) {
    $src = $map[$name]
    if (-not (Test-Path $src)) { throw "source file not found: $src" }
    $text = (Get-Content -Raw -LiteralPath $src) -replace "`r`n", "`n" -replace "`r", "`n"
    $dst = Join-Path $mounts $name
    # Write LF, UTF-8 without BOM (a BOM would break the shebang / first setting).
    [System.IO.File]::WriteAllText($dst, $text, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Test-Image {
  & docker image inspect teranode:latest *> $null
  if ($LASTEXITCODE -ne 0) {
    throw "teranode:latest image not found. Run 'make build' (from $RepoRoot) or '.\compose\regtest.ps1 up -Build'."
  }
}

function Invoke-Rpc {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [string]$Params = "[]"
  )
  # Build the Basic auth header manually so this works on Windows PowerShell 5.1
  # (Invoke-RestMethod -Credential over plain HTTP is 7+ only).
  $pair    = "{0}:{1}" -f $RpcUser, $RpcPass
  $token   = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
  $headers = @{ Authorization = "Basic $token" }
  $body    = "{`"method`":`"$Method`",`"params`":$Params}"
  $resp = Invoke-RestMethod -Uri $RpcUrl -Method Post -ContentType "application/json" `
            -Headers $headers -Body $body
  $resp | ConvertTo-Json -Depth 10
}

function Show-Help {
  Get-Help $PSCommandPath -Detailed
}

switch ($Command.ToLower()) {
  "up" {
    if ($Build) {
      Write-Host "Building teranode:latest..."
      Push-Location $RepoRoot
      try { & make build; if ($LASTEXITCODE -ne 0) { throw "make build failed" } }
      finally { Pop-Location }
    }
    Test-Image
    New-LfMounts
    Invoke-Dc up -d
    Write-Host ""
    Write-Host "Private regtest is starting (from genesis)."
    Write-Host "  RPC:       $RpcUrl  (user/pass $RpcUser/$RpcPass)"
    Write-Host "  Dashboard: http://localhost:18090"
    Write-Host "  Mine:      .\compose\regtest.ps1 mine 10"
    Write-Host "  Logs:      .\compose\regtest.ps1 logs"
  }

  "down" { Invoke-Dc down }

  "reset" {
    try { Invoke-Dc down -v } catch { Write-Warning $_ }
    Write-Host "Wiping $DataDir ..."
    if (Test-Path $DataDir) { Remove-Item -Recurse -Force $DataDir }
    Write-Host "Chain data wiped. Next 'up' starts a brand-new chain from genesis."
  }

  "restart" { Invoke-Dc restart teranode1 }

  "status" { Invoke-Dc ps }

  "logs" {
    $svc = if ($Rest -and $Rest.Count -ge 1) { $Rest[0] } else { "teranode1" }
    Invoke-Dc logs -f $svc
  }

  "mine" {
    $n = if ($Rest -and $Rest.Count -ge 1) { $Rest[0] } else { "1" }
    Write-Host "Mining $n block(s)..."
    Invoke-Rpc -Method "generate" -Params "[$n]"
  }

  "info" { Invoke-Rpc -Method "getinfo" }

  "rpc" {
    if (-not $Rest -or $Rest.Count -lt 1) {
      Write-Error "usage: .\compose\regtest.ps1 rpc <method> [json-params]"
      exit 1
    }
    $params = if ($Rest.Count -ge 2) { $Rest[1] } else { "[]" }
    Invoke-Rpc -Method $Rest[0] -Params $params
  }

  { $_ -in @("help", "-h", "--help", "") } { Show-Help }

  default {
    Write-Error "Unknown command: $Command. Run '.\compose\regtest.ps1 help' for usage."
    exit 1
  }
}
