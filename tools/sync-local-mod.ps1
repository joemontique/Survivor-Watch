[CmdletBinding()]
param(
    [string]$ModPath,
    [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$configPath = Join-Path $PSScriptRoot '.sync-local-mod.json'
$swapStarted = $false
$payloadInstalled = $false
$backupPath = $null
$displaced = $null
$livePayload = $null

function Invoke-Git {
    param([string[]]$Arguments)
    $result = & git -C $script:repo @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $result" }
    return ($result -join "`n").Trim()
}

function Get-RealDirectory {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { throw "Not a directory: $Path" }
    # Reject links in the path and its ancestors; lexical containment alone is insufficient.
    $ancestor = $item
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked directory is not allowed: $($ancestor.FullName)"
        }
        $ancestor = $ancestor.Parent
    }
    return $item.FullName.TrimEnd('\')
}

function Assert-NoLinks {
    param([string]$Path)
    foreach ($entry in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked file/directory is not allowed: $($entry.FullName)"
        }
    }
}

function Assert-ModIdentity {
    param([string]$Payload)
    $info = Join-Path $Payload 'mod.info'
    if (-not (Test-Path -LiteralPath $info -PathType Leaf)) { throw "Missing mod.info: $info" }
    $text = Get-Content -LiteralPath $info -Raw
    if ($text -notmatch '(?m)^name=Survivor Watch\r?$' -or $text -notmatch '(?m)^id=SurvivorPhone\r?$') {
        throw "Wrong mod identity: $info"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Payload 'media/lua/client/SurvivorPhone') -PathType Container)) {
        throw "Missing SurvivorPhone Lua directory: $Payload"
    }
}

function Get-Manifest {
    param([string]$Root)
    $manifest = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
        $relative = $file.FullName.Substring($Root.TrimEnd('\').Length + 1).Replace('\', '/')
        $manifest[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $manifest
}

function Assert-ManifestsMatch {
    param($Expected, $Actual, [string]$Label)
    if ($Expected.Count -ne $Actual.Count) { throw "$Label file count differs." }
    foreach ($name in $Expected.Keys) {
        if (-not $Actual.ContainsKey($name) -or $Expected[$name] -ne $Actual[$name]) {
            throw "$Label mismatch: $name"
        }
    }
}

try {
    $repo = Get-RealDirectory (Join-Path $PSScriptRoot '..')
    $gitRoot = Invoke-Git -Arguments @('rev-parse', '--show-toplevel')
    if ((Get-RealDirectory $gitRoot) -ne $repo) { throw 'Script must be inside the repository tools directory.' }
    $remote = Invoke-Git -Arguments @('remote', 'get-url', 'origin')
    if ($remote -notmatch '^(https://github\.com/|git@github\.com:)joemontique/Survivor-Watch(\.git)?/?$') {
        throw "Unexpected GitHub repository: $remote"
    }
    $branch = Invoke-Git -Arguments @('symbolic-ref', '--short', 'HEAD')
    $commit = Invoke-Git -Arguments @('rev-parse', 'HEAD')
    $dirty = Invoke-Git -Arguments @('status', '--porcelain', '--untracked-files=all', '--', '42')
    if ($dirty) { throw "Uncommitted mod payload changes; commit or preserve them before deployment:`n$dirty" }
    $source = Get-RealDirectory (Join-Path $repo '42')
    Assert-NoLinks $source
    Assert-ModIdentity $source
    $required = @(
        'mod.info', 'media/lua/client/SurvivorPhone/SleepCoach.lua',
        'media/lua/client/SurvivorPhone/WatchUI.lua',
        'media/lua/client/SurvivorPhone/WatchPanelUI.lua',
        'media/lua/client/SurvivorPhone/ClockHotspot.lua',
        'media/lua/client/SurvivorPhone/PhoneMain.lua',
        'media/lua/client/SurvivorPhone/Planner.lua'
    )
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
            throw "Required branch payload file missing: $name"
        }
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if (-not $ModPath) { $ModPath = $config.modPath }
        if (-not $BackupRoot) { $BackupRoot = $config.backupRoot }
    }
    if (-not $ModPath) {
        $mods = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid/mods'
        $candidates = @()
        if (Test-Path -LiteralPath $mods -PathType Container) {
            foreach ($folder in Get-ChildItem -LiteralPath $mods -Directory) {
                try {
                    Assert-ModIdentity (Join-Path $folder.FullName '42')
                    $candidates += $folder.FullName
                } catch { continue }
            }
        }
        if ($candidates.Count -ne 1) { throw 'Cannot uniquely identify the installed mod. Supply -ModPath explicitly.' }
        $ModPath = $candidates[0]
    }
    $destination = Get-RealDirectory $ModPath
    $modsDirectory = Get-Item -LiteralPath (Split-Path -Parent $destination)
    $zomboidDirectory = $modsDirectory.Parent
    if ($modsDirectory.Name -ne 'mods' -or $zomboidDirectory.Name -ne 'Zomboid') {
        throw 'Destination must be a verified mod directly within a Zomboid/mods directory.'
    }
    if ($destination -eq $repo) { throw 'Development repository cannot be the live destination.' }
    Assert-NoLinks $destination
    $livePayload = Get-RealDirectory (Join-Path $destination '42')
    Assert-ModIdentity $livePayload

    if (-not $BackupRoot) { $BackupRoot = Join-Path $zomboidDirectory.FullName 'ModBackups/SurvivorPhone' }
    $backupFull = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
    # Backups are limited to the dedicated ModBackups directory, never Saves or game installation paths.
    $allowedBackup = Join-Path $zomboidDirectory.FullName 'ModBackups'
    if (-not $backupFull.StartsWith($allowedBackup + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "BackupRoot must be inside $allowedBackup"
    }
    $existingAncestor = $backupFull
    while (-not (Test-Path -LiteralPath $existingAncestor)) {
        $existingAncestor = Split-Path -Parent $existingAncestor
    }
    Get-RealDirectory $existingAncestor | Out-Null
    New-Item -ItemType Directory -Path $backupFull -Force | Out-Null
    $backupFull = Get-RealDirectory $backupFull
    $running = @(Get-Process -Name 'ProjectZomboid*' -ErrorAction SilentlyContinue).Count -gt 0
    Write-Host "Source: $repo"
    Write-Host "Branch: $branch / Commit: $commit"
    Write-Host "Destination: $destination"
    Write-Host "Project Zomboid running: $running"

    $sourceManifest = Get-Manifest $source
    $installedManifest = Get-Manifest $destination
    $backupPath = Join-Path $backupFull ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $backupPath | Out-Null
    $backupPath = Get-RealDirectory $backupPath
    $backupMod = Join-Path $backupPath 'SurvivorPhone'
    Copy-Item -LiteralPath $destination -Destination $backupMod -Recurse -Force
    Assert-ManifestsMatch $installedManifest (Get-Manifest $backupMod) 'Backup'
    Write-Host "Verified full backup: $backupMod"

    $staged = Join-Path $backupPath 'staged-42'
    Copy-Item -LiteralPath $source -Destination $staged -Recurse -Force
    Assert-ManifestsMatch $sourceManifest (Get-Manifest $staged) 'Staged payload'
    Assert-ManifestsMatch $sourceManifest (Get-Manifest $source) 'Source changed during staging'
    Assert-ManifestsMatch $installedManifest (Get-Manifest $destination) 'Destination changed during backup'
    # Swap only the positively identified 42 directory; no recursive deletion or save/game access.
    $displaced = Join-Path $backupPath 'previous-42'
    Move-Item -LiteralPath $livePayload -Destination $displaced
    $swapStarted = $true
    Move-Item -LiteralPath $staged -Destination $livePayload
    $payloadInstalled = $true
    Assert-ModIdentity $livePayload
    Assert-ManifestsMatch $sourceManifest (Get-Manifest $livePayload) 'Live payload'

    $receipt = [ordered]@{
        repository = $repo; remote = $remote; branch = $branch; commit = $commit
        destination = $destination; backup = $backupMod; filesVerified = $sourceManifest.Count
        projectZomboidRunning = $running; restartRequired = $running
        verifiedAt = (Get-Date).ToString('o'); manifest = $sourceManifest
    }
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupPath 'deployment.json') -Encoding UTF8
    @{modPath=$destination; backupRoot=$backupFull} | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    Write-Host "Verified: all $($sourceManifest.Count) payload files match $branch at $commit."
    if ($running) { Write-Host 'Restart the game before testing. The running process was left open.' }
    else { Write-Host 'Start Project Zomboid normally to test the deployed mod.' }
    exit 0
} catch {
    $failure = $_
    if ($swapStarted) {
        try {
            # Preserve a failed replacement and restore the displaced original payload.
            if ($payloadInstalled) {
                Move-Item -LiteralPath $livePayload -Destination (Join-Path $backupPath 'failed-42')
            }
            Move-Item -LiteralPath $displaced -Destination $livePayload
            Write-Warning 'Original installed payload restored after deployment failure.'
        } catch {
            Write-Warning "Automatic restore failed. Original payload remains at $displaced. Error: $_"
        }
    }
    Write-Error -Message "Sync failed: $failure" -ErrorAction Continue
    exit 1
}
