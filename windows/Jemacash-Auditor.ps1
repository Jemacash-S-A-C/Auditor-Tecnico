param(
  [string]$ApiUrl,
  [string]$GuaranteeId,
  [string]$AccessToken
)

$ErrorActionPreference = "Stop"
$selfPath = $MyInvocation.MyCommand.Path
$selfDir = if ($selfPath) { Split-Path -Parent $selfPath } else { (Get-Location).Path }
$configPath = Join-Path $selfDir "Jemacash-Auditor.config.json"
$downloadsConfigPath = Join-Path (Join-Path $env:USERPROFILE "Downloads") "Jemacash-Auditor.config.json"
$downloadsDir = Join-Path $env:USERPROFILE "Downloads"

function Remove-Self {
  if ($selfPath) {
    $escaped = $selfPath.Replace('"', '""')
    Start-Process -WindowStyle Hidden -FilePath "cmd.exe" -ArgumentList "/c ping 127.0.0.1 -n 3 >nul & del /f /q ""$escaped"""
  }
  if (Test-Path -LiteralPath $configPath) {
    $cfgEscaped = $configPath.Replace('"', '""')
    Start-Process -WindowStyle Hidden -FilePath "cmd.exe" -ArgumentList "/c ping 127.0.0.1 -n 3 >nul & del /f /q ""$cfgEscaped"""
  }
}

function Load-ConfigIfExists([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $cfg = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if (-not $script:ApiUrl) { $script:ApiUrl = [string]$cfg.ApiUrl }
  if (-not $script:GuaranteeId) { $script:GuaranteeId = [string]$cfg.GuaranteeId }
  if (-not $script:AccessToken) { $script:AccessToken = [string]$cfg.AccessToken }
}

function Load-ConfigFromPattern([string]$dirPath) {
  if (-not (Test-Path -LiteralPath $dirPath)) { return }
  $candidates = Get-ChildItem -LiteralPath $dirPath -File -Filter "Jemacash-Auditor.config*.json" | Sort-Object LastWriteTime -Descending
  foreach ($file in $candidates) {
    if ($ApiUrl -and $GuaranteeId -and $AccessToken) { return }
    Load-ConfigIfExists $file.FullName
  }
}

if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigIfExists $configPath
}
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigIfExists $downloadsConfigPath
}
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigFromPattern $selfDir
}
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigFromPattern $downloadsDir
}

if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  throw "Faltan ApiUrl, GuaranteeId o AccessToken. Busque un config tipo Jemacash-Auditor.config*.json en la carpeta del EXE o en Descargas."
}

$bios = Get-CimInstance Win32_BIOS
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disk = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
$cs = Get-CimInstance Win32_ComputerSystem

$totalRamGb = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 0)
$diskGb = if ($disk.Size) { [math]::Round(($disk.Size / 1GB), 0) } else { 0 }

$payload = @{
  serial_number = [string]$bios.SerialNumber
  brand = [string]$cs.Manufacturer
  model = [string]$cs.Model
  manufacture_year = [string](Get-Date).Year
  specs = @{
    processor = [string]$cpu.Name
    cpu_name = [string]$cpu.Name
    ram = "$totalRamGb GB"
    total_ram_gb = [string]$totalRamGb
    storage = "$diskGb GB"
    primary_disk_size_gb = [string]$diskGb
    primary_disk = [string]$disk.Model
    gpu_name = [string]$gpu.Name
    motherboard = [string]$board.Product
    os_name = [string]$os.Caption
    os_version = [string]$os.Version
  }
} | ConvertTo-Json -Depth 6

$headers = @{
  Authorization = "Bearer $AccessToken"
  "Content-Type" = "application/json"
}

try {
  $base = $ApiUrl.TrimEnd('/')
  $uri1 = "$base/guarantees/$GuaranteeId/audit-report"
  $uri2 = "$base/api/guarantees/$GuaranteeId/audit-report"
  try {
    Invoke-RestMethod -Method Patch -Uri $uri1 -Headers $headers -Body $payload | Out-Null
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match "404|Not Found|Cannot PATCH") {
      Invoke-RestMethod -Method Patch -Uri $uri2 -Headers $headers -Body $payload | Out-Null
    } else {
      throw
    }
  }
} finally {
  Remove-Self
}
