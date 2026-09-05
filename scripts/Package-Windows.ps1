[CmdletBinding()]
param(
    [string]$OutputDirectory = "dist",
    [string]$FfmpegPath,
    [switch]$SkipBuild,
    [switch]$IncludeClientSecrets,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($env:OS -ne "Windows_NT") {
    throw "This script must run on Windows because Flutter Windows builds cannot be cross-compiled."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDirectory = Join-Path $projectRoot "build\windows\x64\runner\Release"
$destinationRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $projectRoot $OutputDirectory
}
$bundleDirectory = Join-Path $destinationRoot "ChurchStreamer-Windows-x64"

if (-not $SkipBuild) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter is required on this build computer. Install Flutter, or use -SkipBuild with an existing release build."
    }
    Push-Location $projectRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

$requiredBuildItems = @(
    (Join-Path $releaseDirectory "streamer_reboot.exe"),
    (Join-Path $releaseDirectory "flutter_windows.dll"),
    (Join-Path $releaseDirectory "data\flutter_assets")
)
foreach ($item in $requiredBuildItems) {
    if (-not (Test-Path $item)) {
        throw "Incomplete Windows release build: missing $item. Run without -SkipBuild first."
    }
}

if (-not $FfmpegPath) {
    $ffmpegCommand = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($ffmpegCommand) { $FfmpegPath = $ffmpegCommand.Source }
}
if (-not $FfmpegPath -or -not (Test-Path -LiteralPath $FfmpegPath -PathType Leaf)) {
    throw "FFmpeg was not found. Install a Windows x64 FFmpeg build or pass -FfmpegPath C:\path\to\ffmpeg.exe."
}

$ffmpegInfo = & $FfmpegPath -hide_banner -encoders 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "FFmpeg could not be executed: $FfmpegPath" }
if ($ffmpegInfo -notmatch "\bh264_mf\b") {
    throw "This FFmpeg build does not provide the h264_mf encoder required by Church Streamer."
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
if (Test-Path $bundleDirectory) {
    Remove-Item -LiteralPath $bundleDirectory -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $bundleDirectory | Out-Null
Copy-Item -Path (Join-Path $releaseDirectory "*") -Destination $bundleDirectory -Recurse -Force
Copy-Item -LiteralPath $FfmpegPath -Destination (Join-Path $bundleDirectory "ffmpeg.exe") -Force
$ffmpegDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $FfmpegPath)
Get-ChildItem -LiteralPath $ffmpegDirectory -Filter "*.dll" -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $bundleDirectory -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Check-Windows-Prerequisites.ps1") -Destination $bundleDirectory

$secretsPath = Join-Path $projectRoot "client_secrets.json"
if ($IncludeClientSecrets) {
    if (-not (Test-Path $secretsPath -PathType Leaf)) {
        throw "-IncludeClientSecrets was specified, but client_secrets.json is missing from the project root."
    }
    Copy-Item -LiteralPath $secretsPath -Destination $bundleDirectory
    Write-Warning "The bundle contains Google OAuth client credentials. Transfer and store it securely."
} elseif (Test-Path $secretsPath) {
    Write-Warning "client_secrets.json was not included. Use -IncludeClientSecrets if the destination needs YouTube sign-in."
}

$manifest = [ordered]@{
    application = "Church Streamer"
    architecture = "x64"
    packagedAtUtc = [DateTime]::UtcNow.ToString("o")
    appVersion = (Get-Item (Join-Path $bundleDirectory "streamer_reboot.exe")).VersionInfo.ProductVersion
    ffmpegVersion = (& (Join-Path $bundleDirectory "ffmpeg.exe") -version | Select-Object -First 1)
    includesClientSecrets = [bool]$IncludeClientSecrets
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundleDirectory "package-manifest.json") -Encoding UTF8

& (Join-Path $bundleDirectory "Check-Windows-Prerequisites.ps1") -AppDirectory $bundleDirectory
if ($LASTEXITCODE -ne 0) { throw "The packaged bundle failed its prerequisite check." }

if (-not $NoZip) {
    $zipPath = "$bundleDirectory.zip"
    if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path (Join-Path $bundleDirectory "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "Transfer package created: $zipPath"
} else {
    Write-Host "Transfer folder created: $bundleDirectory"
}

Write-Host "On the destination PC, extract the entire archive, run Check-Windows-Prerequisites.ps1, then streamer_reboot.exe."
