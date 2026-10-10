param(
    [Parameter(Mandatory=$true)]
    [string]$PreviewPath,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source42 = Join-Path $repoRoot '42'
$templateWorkshop = Join-Path $repoRoot 'workshop\workshop.txt'

if (-not $OutputPath) {
    $OutputPath = Join-Path $repoRoot 'dist\SurvivorWatchWorkshop'
}

$sourceModInfo = Join-Path $source42 'mod.info'
if (-not (Test-Path -LiteralPath $sourceModInfo -PathType Leaf)) {
    throw "Missing source mod.info: $sourceModInfo"
}

$modInfo = Get-Content -LiteralPath $sourceModInfo -Raw
$requiredMetadata = @(
    'name=Survivor Watch',
    'id=SurvivorPhone',
    'versionMin=42.20'
)
foreach ($marker in $requiredMetadata) {
    if ($modInfo -notmatch [regex]::Escape($marker)) {
        throw "Source mod.info is missing required metadata: $marker"
    }
}
if ($modInfo -notmatch 'description=Version 1\.6\.6') {
    throw 'Source mod.info does not describe Version 1.6.6.'
}

if (-not (Test-Path -LiteralPath $templateWorkshop -PathType Leaf)) {
    throw "Missing Workshop template: $templateWorkshop"
}

$preview = (Resolve-Path -LiteralPath $PreviewPath).Path
$previewInfo = Get-Item -LiteralPath $preview
if ($previewInfo.Extension.ToLowerInvariant() -ne '.png') {
    throw 'Workshop preview must be a PNG file.'
}
if ($previewInfo.Length -gt (1000 * 1024)) {
    throw "Workshop preview is too large: $($previewInfo.Length) bytes. Maximum is 1000 KB."
}

Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($preview)
try {
    if ($image.Width -ne 256 -or $image.Height -ne 256) {
        throw "Workshop preview must be exactly 256x256 pixels. Found $($image.Width)x$($image.Height)."
    }
}
finally {
    $image.Dispose()
}

$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
$markerName = '.survivor-watch-workshop-package'
$existingWorkshopId = $null

if (Test-Path -LiteralPath $outputFull) {
    $markerPath = Join-Path $outputFull $markerName
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw "Refusing to replace an existing directory not created by this script: $outputFull"
    }

    $existingWorkshopFile = Join-Path $outputFull 'workshop.txt'
    if (Test-Path -LiteralPath $existingWorkshopFile -PathType Leaf) {
        $existingText = Get-Content -LiteralPath $existingWorkshopFile -Raw
        $match = [regex]::Match($existingText, '(?m)^id=(\d+)\s*$')
        if ($match.Success) {
            $existingWorkshopId = $match.Groups[1].Value
        }
    }
}

$parent = Split-Path -Parent $outputFull
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$staging = "$outputFull.staging-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    Copy-Item -LiteralPath $preview -Destination (Join-Path $staging 'preview.png')

    $workshopText = Get-Content -LiteralPath $templateWorkshop -Raw
    if ($existingWorkshopId) {
        if ($workshopText -match '(?m)^id=') {
            $workshopText = [regex]::Replace($workshopText, '(?m)^id=.*$', "id=$existingWorkshopId")
        }
        else {
            $workshopText = $workshopText.TrimEnd() + [Environment]::NewLine + "id=$existingWorkshopId" + [Environment]::NewLine
        }
    }
    Set-Content -LiteralPath (Join-Path $staging 'workshop.txt') -Value $workshopText -Encoding UTF8

    $modRoot = Join-Path $staging 'Contents\mods\SurvivorPhone'
    New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
    $commonRoot = Join-Path $modRoot 'common'
    New-Item -ItemType Directory -Path $commonRoot -Force | Out-Null

    # Build 42 Workshop validation checks mod.info inside common/ or a valid
    # version directory. Keep the root copy for compatibility, but ensure
    # common/mod.info is always present for the uploader.
    Copy-Item -LiteralPath $sourceModInfo -Destination (Join-Path $modRoot 'mod.info')
    Copy-Item -LiteralPath $sourceModInfo -Destination (Join-Path $commonRoot 'mod.info')
    Copy-Item -LiteralPath $source42 -Destination (Join-Path $modRoot '42') -Recurse

    Set-Content -LiteralPath (Join-Path $staging $markerName) -Value 'Survivor Watch Workshop package managed by tools/build-workshop-package.ps1' -Encoding ASCII

    $sourceFiles = Get-ChildItem -LiteralPath $source42 -File -Recurse | ForEach-Object {
        [pscustomobject]@{
            Relative = $_.FullName.Substring($source42.Length).TrimStart('\')
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }

    $commonModInfo = Join-Path $commonRoot 'mod.info'
    if (-not (Test-Path -LiteralPath $commonModInfo -PathType Leaf)) {
        throw "Workshop validator metadata missing: $commonModInfo"
    }
    if ((Get-FileHash -LiteralPath $commonModInfo -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $sourceModInfo -Algorithm SHA256).Hash) {
        throw 'Workshop common/mod.info does not match source mod.info.'
    }

    $package42 = Join-Path $modRoot '42'
    $packageFiles = Get-ChildItem -LiteralPath $package42 -File -Recurse | ForEach-Object {
        [pscustomobject]@{
            Relative = $_.FullName.Substring($package42.Length).TrimStart('\')
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }

    if ($sourceFiles.Count -ne $packageFiles.Count) {
        throw "Packaged file count mismatch. Source=$($sourceFiles.Count), Package=$($packageFiles.Count)"
    }

    $packageByPath = @{}
    foreach ($file in $packageFiles) {
        $packageByPath[$file.Relative] = $file.Hash
    }

    foreach ($file in $sourceFiles) {
        if (-not $packageByPath.ContainsKey($file.Relative)) {
            throw "Packaged file missing: $($file.Relative)"
        }
        if ($packageByPath[$file.Relative] -ne $file.Hash) {
            throw "SHA-256 mismatch: $($file.Relative)"
        }
    }

    if (Test-Path -LiteralPath $outputFull) {
        Remove-Item -LiteralPath $outputFull -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $outputFull

    Write-Host ''
    Write-Host 'Survivor Watch Steam Workshop package ready.' -ForegroundColor Green
    Write-Host "Output: $outputFull"
    Write-Host "Build 42 payload files verified: $($sourceFiles.Count)"
    Write-Host 'SHA-256 verification: PASS'
    Write-Host 'Mod ID: SurvivorPhone'
    Write-Host 'Release: 1.6.6'
    Write-Host 'Workshop validator metadata: common/mod.info PASS'
    if ($existingWorkshopId) {
        Write-Host "Preserved Workshop ID: $existingWorkshopId"
    }
    else {
        Write-Host 'Workshop ID: not assigned yet (first upload)'
    }
    Write-Host 'Visibility template: unlisted'
}
catch {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    throw
}
