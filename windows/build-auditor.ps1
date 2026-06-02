param(
  [string]$OutputDir = ".\dist",
  [string]$ExeName = "Jemacash-Auditor.exe"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScript = Join-Path $scriptDir "Jemacash-Auditor.ps1"
$outDirAbs = Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path (Join-Path $scriptDir $OutputDir))
$outFile = Join-Path $outDirAbs $ExeName

if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
  Write-Host "PS2EXE no encontrado. Instalando modulo ps2exe..." -ForegroundColor Yellow
  Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

Invoke-PS2EXE `
  -InputFile $sourceScript `
  -OutputFile $outFile `
  -NoConsole `
  -Title "Jemacash Auditor" `
  -Description "Auditor local de hardware para Jemacash" `
  -Company "Jemacash" `
  -Product "Jemacash Auditor" `
  -Copyright "Jemacash"

Write-Host "EXE generado: $outFile" -ForegroundColor Green
