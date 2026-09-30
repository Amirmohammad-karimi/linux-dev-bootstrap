param(
    [Parameter(Mandatory = $true)]
    [string]$UsbIdsFile
)

$ErrorActionPreference = "Stop"

function Find-Usbipd {
    $command = Get-Command usbipd -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $fallback = "C:\Program Files\usbipd-win\usbipd.exe"

    if (Test-Path $fallback) {
        return $fallback
    }

    return $null
}

function Install-Usbipd {
    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if (-not $winget) {
        throw "usbipd-win is missing and winget is unavailable."
    }

    Write-Host "[INFO] Installing usbipd-win..."

    winget install `
        --exact `
        --id dorssel.usbipd-win `
        --interactive `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        throw "usbipd-win installation failed."
    }
}

if (-not (Test-Path $UsbIdsFile)) {
    throw "USB ID configuration not found: $UsbIdsFile"
}

$usbIds = @(
    Get-Content $UsbIdsFile |
    ForEach-Object { $_.Trim().ToLower() } |
    Where-Object {
        $_ -and
        -not $_.StartsWith("#") -and
        $_ -match '^[0-9a-f]{4}:[0-9a-f]{4}$'
    }
)

if ($usbIds.Count -eq 0) {
    throw "No valid VID:PID entries found in $UsbIdsFile"
}

Write-Host "[INFO] Supported ST-LINK IDs:"
foreach ($id in $usbIds) {
    Write-Host "       $id"
}

$usbipd = Find-Usbipd

if (-not $usbipd) {
    Install-Usbipd
    $usbipd = Find-Usbipd
}

if (-not $usbipd) {
    throw "usbipd executable not found."
}

Write-Host "[OK] usbipd found: $usbipd"

$list = & $usbipd list

$escapedIds = $usbIds | ForEach-Object {
    [regex]::Escape($_)
}

$hardwareRegex = ($escapedIds -join "|")

$deviceLines = @(
    $list | Where-Object {
        $_ -match $hardwareRegex
    }
)

if ($deviceLines.Count -eq 0) {
    Write-Host "[WARN] No configured ST-LINK programmer is currently connected."
    exit 0
}

foreach ($line in $deviceLines) {

    if ($line -notmatch '^\s*(\d+-\d+)') {
        Write-Warning "Could not determine BUSID from: $line"
        continue
    }

    $busId = $Matches[1]

    Write-Host "[INFO] ST-LINK detected at BUSID $busId"

    if ($line -match '\bAttached\b') {
        Write-Host "[OK] ST-LINK $busId already attached to WSL."
        continue
    }

    if ($line -match 'Not shared') {

        Write-Host "[INFO] ST-LINK $busId requires one-time binding."

        $process = Start-Process `
            -FilePath $usbipd `
            -Verb RunAs `
            -Wait `
            -PassThru `
            -ArgumentList @(
                "bind",
                "--busid=$busId"
            )

        if ($process.ExitCode -ne 0) {
            throw "Failed to bind ST-LINK $busId."
        }

        Write-Host "[OK] ST-LINK $busId bound."

        $list = & $usbipd list

        $line = $list |
            Where-Object {
                $_ -match "^\s*$([regex]::Escape($busId))\s"
            } |
            Select-Object -First 1
    }

    if ($line -match '\bShared\b') {

        Write-Host "[INFO] Attaching ST-LINK $busId to WSL..."

        & $usbipd attach --wsl "--busid=$busId"

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to attach ST-LINK $busId."
        }

        Write-Host "[OK] ST-LINK $busId attached to WSL."
    }
}
