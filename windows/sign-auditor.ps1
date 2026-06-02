param(
  [Parameter(Mandatory = $true)][string]$ExePath,
  [Parameter(Mandatory = $true)][string]$PfxPath,
  [Parameter(Mandatory = $true)][string]$PfxPassword,
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

$signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if (-not $signtool) {
  throw "No se encontro signtool.exe. Instala Windows SDK y vuelve a intentar."
}

& $signtool.Source sign `
  /f $PfxPath `
  /p $PfxPassword `
  /fd SHA256 `
  /tr $TimestampUrl `
  /td SHA256 `
  /v `
  $ExePath

Write-Host "Firma aplicada: $ExePath" -ForegroundColor Green
