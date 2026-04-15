Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RuntimeDir = Join-Path $RootDir '.phoneshop-runtime'
$PidFile = Join-Path $RuntimeDir 'server.pid'
$PortFile = Join-Path $RuntimeDir 'server.port'
$LogFile = Join-Path $RuntimeDir 'server.log'
$ErrorLogFile = Join-Path $RuntimeDir 'server-error.log'

if (-not (Test-Path -LiteralPath $PidFile)) {
    Write-Host 'PhoneShop is not running.'
    exit 0
}

$pidText = (Get-Content -LiteralPath $PidFile -Raw).Trim()
if (-not $pidText) {
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PortFile -Force -ErrorAction SilentlyContinue
    Write-Host 'Removed stale PID file.'
    exit 0
}

$targetPid = [int] $pidText
$process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped PhoneShop server (PID $targetPid)."
} else {
    Write-Host 'PhoneShop was not running. Cleaning up stale state.'
}

Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PortFile -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $LogFile) {
    Write-Host "Log file kept at $LogFile"
}
if (Test-Path -LiteralPath $ErrorLogFile) {
    Write-Host "Error log kept at $ErrorLogFile"
}
