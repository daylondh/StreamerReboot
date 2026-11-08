[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Archive,
    [Parameter(Mandatory = $true)]
    [string]$Destination,
    [Parameter(Mandatory = $true)]
    [int]$WaitForProcessId,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,
    [Parameter(Mandatory = $true)]
    [string]$StateDirectory
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
$logPath = Join-Path $StateDirectory "update.log"
Start-Transcript -Path $logPath -Append | Out-Null

try {
    Get-Process -Id $WaitForProcessId -ErrorAction SilentlyContinue | Wait-Process

    if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
        throw "The staged update archive is missing: $Archive"
    }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        throw "The application directory is missing: $Destination"
    }

    $workDirectory = Join-Path $StateDirectory "installing"
    $payloadDirectory = Join-Path $workDirectory "payload"
    $backupDirectory = Join-Path $workDirectory "backup"
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $payloadDirectory | Out-Null
    New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $payloadDirectory -Force

    $manifestPath = Join-Path $payloadDirectory "package-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The update does not contain package-manifest.json."
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $packagedVersion = [regex]::Match([string]$manifest.appVersion, '^\d+\.\d+\.\d+').Value
    if ($packagedVersion -ne $ExpectedVersion) {
        throw "The update version '$($manifest.appVersion)' does not match '$ExpectedVersion'."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $payloadDirectory "streamer_reboot.exe") -PathType Leaf)) {
        throw "The update does not contain streamer_reboot.exe."
    }

    $createdFiles = [System.Collections.Generic.List[string]]::new()
    $payloadFiles = Get-ChildItem -LiteralPath $payloadDirectory -File -Recurse
    try {
        foreach ($sourceFile in $payloadFiles) {
            $relativePath = $sourceFile.FullName.Substring($payloadDirectory.Length).TrimStart('\', '/')
            if ($relativePath -ieq "client_secrets.json") { continue }

            $destinationFile = Join-Path $Destination $relativePath
            $destinationParent = Split-Path -Parent $destinationFile
            New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null

            if (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
                $backupFile = Join-Path $backupDirectory $relativePath
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
                Copy-Item -LiteralPath $destinationFile -Destination $backupFile -Force
            } else {
                $createdFiles.Add($destinationFile)
            }
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationFile -Force
        }
    } catch {
        foreach ($createdFile in $createdFiles) {
            Remove-Item -LiteralPath $createdFile -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem -LiteralPath $backupDirectory -File -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($backupDirectory.Length).TrimStart('\', '/')
            $restorePath = Join-Path $Destination $relativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $restorePath) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $restorePath -Force
        }
        throw
    }

    @{
        version = $ExpectedVersion
        installedAtUtc = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $StateDirectory "last-update.json") -Encoding UTF8

    Remove-Item -LiteralPath $workDirectory -Recurse -Force
    Remove-Item -LiteralPath $Archive -Force
} catch {
    Write-Host ($_ | Out-String)
    exit 1
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
