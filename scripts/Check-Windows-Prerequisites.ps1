[CmdletBinding()]
param(
    [string]$AppDirectory = $PSScriptRoot
)

$ErrorActionPreference = "Continue"
$failures = 0
$warnings = 0

function Write-Check([bool]$Passed, [string]$Description, [string]$Remediation) {
    if ($Passed) {
        Write-Host "[PASS] $Description" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Description" -ForegroundColor Red
        if ($Remediation) { Write-Host "       $Remediation" }
        $script:failures++
    }
}

function Write-CheckWarning([bool]$Passed, [string]$Description, [string]$Remediation) {
    if ($Passed) {
        Write-Host "[PASS] $Description" -ForegroundColor Green
    } else {
        Write-Host "[WARN] $Description" -ForegroundColor Yellow
        if ($Remediation) { Write-Host "       $Remediation" }
        $script:warnings++
    }
}

if ($env:OS -ne "Windows_NT") {
    Write-Check $false "Windows operating system" "Move this bundle to a 64-bit Windows PC."
} else {
    Write-Check ([Environment]::Is64BitOperatingSystem) "64-bit Windows" "Use a 64-bit Windows 10 or Windows 11 computer."
    $windowsVersion = [Environment]::OSVersion.Version
    Write-Check ($windowsVersion.Major -ge 10) "Windows 10 or newer" "Upgrade Windows before running Church Streamer."
}

$requiredItems = @(
    "streamer_reboot.exe",
    "flutter_windows.dll",
    "data\flutter_assets",
    "ffmpeg.exe"
)
foreach ($relativePath in $requiredItems) {
    Write-Check (Test-Path (Join-Path $AppDirectory $relativePath)) "Bundle contains $relativePath" "Re-extract the complete ZIP; do not copy only the EXE."
}

$vcRuntimeKeys = @(
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
)
$vcRuntimeInstalled = $false
foreach ($key in $vcRuntimeKeys) {
    $runtime = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($runtime -and $runtime.Installed -eq 1) { $vcRuntimeInstalled = $true }
}
$appLocalRuntime = Test-Path (Join-Path $AppDirectory "vcruntime140.dll")
Write-Check ($vcRuntimeInstalled -or $appLocalRuntime) "Microsoft Visual C++ 2015-2022 x64 runtime" "Install the current x64 Visual C++ Redistributable from Microsoft: https://aka.ms/vs/17/release/vc_redist.x64.exe"

$ffmpeg = Join-Path $AppDirectory "ffmpeg.exe"
if (Test-Path $ffmpeg) {
    $encoderOutput = & $ffmpeg -hide_banner -encoders 2>&1 | Out-String
    Write-Check ($LASTEXITCODE -eq 0) "Bundled FFmpeg starts" "Rebuild the transfer package with a working Windows x64 FFmpeg executable."
    Write-Check ($encoderOutput -match "\bh264_mf\b") "FFmpeg includes the h264_mf encoder" "Use a full Windows FFmpeg build that includes Media Foundation support."
}

Write-CheckWarning (Test-Path (Join-Path $AppDirectory "client_secrets.json")) "YouTube OAuth client file is present" "This is only required for YouTube. Place client_secrets.json beside streamer_reboot.exe."
Write-CheckWarning ([bool](Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue)) "Windows detects an audio device" "Connect and enable the intended audio input."
Write-CheckWarning ([bool](Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPClass -eq "Camera" })) "Windows detects a camera" "Connect the camera and install its manufacturer driver if needed."

Write-Host ""
if ($failures -gt 0) {
    Write-Host "$failures required check(s) failed; $warnings warning(s)." -ForegroundColor Red
    exit 1
}
Write-Host "All required checks passed; $warnings warning(s). Flutter and Dart are not required on this PC." -ForegroundColor Green
exit 0
