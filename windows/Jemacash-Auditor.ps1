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

# ── Notification helper ────────────────────────────────────────────────────────

function Show-Notification([string]$title, [string]$message, [string]$type = "Info") {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $icon = switch ($type) {
      "Error"   { [System.Windows.Forms.MessageBoxIcon]::Error }
      "Warning" { [System.Windows.Forms.MessageBoxIcon]::Warning }
      default   { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    [System.Windows.Forms.MessageBox]::Show(
      $message, $title,
      [System.Windows.Forms.MessageBoxButtons]::OK,
      $icon
    ) | Out-Null
  } catch {
    # Fallback if no GUI available
    Write-Host "[${type}] ${title}: ${message}"
  }
}

# ── Self-cleanup ───────────────────────────────────────────────────────────────

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

# ── Config loading ─────────────────────────────────────────────────────────────

function Read-EmbeddedConfig {
  # Reads config appended to the exe binary after a sentinel marker
  try {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not $exePath -or -not (Test-Path -LiteralPath $exePath)) { return }

    $sentinelStr   = "###JEMACASH_CONFIG###"
    $sentinelBytes = [System.Text.Encoding]::UTF8.GetBytes($sentinelStr)
    $fileBytes     = [System.IO.File]::ReadAllBytes($exePath)

    for ($i = $fileBytes.Length - $sentinelBytes.Length; $i -ge 0; $i--) {
      $match = $true
      for ($j = 0; $j -lt $sentinelBytes.Length; $j++) {
        if ($fileBytes[$i + $j] -ne $sentinelBytes[$j]) { $match = $false; break }
      }
      if ($match) {
        $jsonStart = $i + $sentinelBytes.Length
        $jsonBytes = $fileBytes[$jsonStart..($fileBytes.Length - 1)]
        $jsonStr   = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
        $cfg       = $jsonStr | ConvertFrom-Json
        if (-not $script:ApiUrl      -and $cfg.ApiUrl)      { $script:ApiUrl      = [string]$cfg.ApiUrl }
        if (-not $script:GuaranteeId -and $cfg.GuaranteeId) { $script:GuaranteeId = [string]$cfg.GuaranteeId }
        if (-not $script:AccessToken -and $cfg.AccessToken) { $script:AccessToken = [string]$cfg.AccessToken }
        return
      }
    }
  } catch { }
}

function Load-ConfigIfExists([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $cfg = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if (-not $script:ApiUrl)      { $script:ApiUrl      = [string]$cfg.ApiUrl }
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

# Priority 1: config embedded in exe binary
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Read-EmbeddedConfig
}
# Priority 2: config file next to exe
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigIfExists $configPath
}
# Priority 3: config file in Downloads
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigIfExists $downloadsConfigPath
}
# Priority 4: any config file in same dir or Downloads
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigFromPattern $selfDir
}
if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Load-ConfigFromPattern $downloadsDir
}

if (-not $ApiUrl -or -not $GuaranteeId -or -not $AccessToken) {
  Show-Notification "Jemacash Auditor - Error" "No se encontró la configuración necesaria. Descargue el auditor nuevamente desde la plataforma Jemacash." "Error"
  exit 1
}

# ── Main audit ─────────────────────────────────────────────────────────────────

try {
  $bios  = Get-CimInstance Win32_BIOS
  $cpu   = Get-CimInstance Win32_Processor | Select-Object -First 1
  $os    = Get-CimInstance Win32_OperatingSystem
  $board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
  $gpu   = Get-CimInstance Win32_VideoController | Select-Object -First 1
  $disk  = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
  $cs    = Get-CimInstance Win32_ComputerSystem

  $totalRamGb = [math]::Round(($cs.TotalPhysicalMemory / 1GB), 0)
  $diskGb     = if ($disk.Size) { [math]::Round(($disk.Size / 1GB), 0) } else { 0 }

  $payload = @{
    serial_number    = [string]$bios.SerialNumber
    brand            = [string]$cs.Manufacturer
    model            = [string]$cs.Model
    manufacture_year = [string](Get-Date).Year
    specs            = @{
      processor            = [string]$cpu.Name
      cpu_name             = [string]$cpu.Name
      ram                  = "$totalRamGb GB"
      total_ram_gb         = [string]$totalRamGb
      storage              = "$diskGb GB"
      primary_disk_size_gb = [string]$diskGb
      primary_disk         = [string]$disk.Model
      gpu_name             = [string]$gpu.Name
      motherboard          = [string]$board.Product
      os_name              = [string]$os.Caption
      os_version           = [string]$os.Version
    }
  } | ConvertTo-Json -Depth 6

  $headers = @{
    Authorization  = "Bearer $AccessToken"
    "Content-Type" = "application/json"
  }

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

  Show-Notification "Jemacash Auditor" "Auditoria completada exitosamente.`n`nSu dispositivo ha sido verificado y los datos enviados a Jemacash. Puede continuar con el registro de su garantia en la plataforma."

} catch {
  $errMsg = $_.Exception.Message
  Show-Notification "Jemacash Auditor - Error" "Error al completar la auditoria: $errMsg`n`nIntente ejecutar el auditor nuevamente. Si el problema persiste, contacte a soporte de Jemacash." "Error"
} finally {
  Remove-Self
}
