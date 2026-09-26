#Requires -Version 5.1
[CmdletBinding()]
param([switch]$NoPath)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This installer is for Windows.' }
. (Join-Path $PSScriptRoot 'InstallerHelpers.ps1')

$appId = 'OpenCodeSessionLauncher-v5'
$localData = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Cannot locate the current user LocalAppData folder.' }
$installDir = Join-Path $localData 'OpenCodeSessionLauncher'
$manifestPath = Join-Path $installDir 'launcher-manifest.json'
$coreSource = Join-Path $PSScriptRoot 'ocr_v5.ps1'
$coreTarget = Join-Path $installDir 'ocr-core.ps1'
$guiTarget = Join-Path $installDir 'OpenCodeSessions.exe'
if (Test-Path -LiteralPath $guiTarget -PathType Leaf) {
    try {
        $probe = [IO.File]::Open($guiTarget, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $probe.Dispose()
    }
    catch { throw 'Close OpenCode Sessions before updating; the GUI executable is in use or not writable.' }
}

$packageFiles = @('ocr_v5.ps1', 'ocr.cmd', 'ocr-cli.cmd', 'OpenCodeSessions.exe', 'InstallerHelpers.ps1', 'Uninstall.ps1', 'Uninstall.cmd', 'README.md', 'LICENSE')
foreach ($name in $packageFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name) -PathType Leaf)) {
        throw "Missing package file: $name. Extract the whole ZIP, then run Install.cmd."
    }
}

# Check all packaged payload files before changing an existing installation.
$sumsPath = Join-Path $PSScriptRoot 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sumsPath -PathType Leaf)) { throw 'Missing SHA256SUMS.txt.' }
$checksums = @{}
foreach ($line in (Get-Content -LiteralPath $sumsPath)) {
    if ($line -match '^([a-fA-F0-9]{64})\s+([^\\/]+)$') { $checksums[$Matches[2]] = $Matches[1] }
}
foreach ($name in $packageFiles) {
    if (-not $checksums.ContainsKey($name) -or (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash -ne $checksums[$name]) {
        throw "Package verification failed: $name. Extract the complete release again."
    }
}

if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $state = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.AppId -ne $appId) { throw 'The install folder belongs to another application. Nothing was overwritten.' }
    if ((Get-OcrPathKey $state.InstallDir) -ne (Get-OcrPathKey $installDir)) {
        throw 'The existing installation manifest has a different location. Nothing was overwritten.'
    }
}
else {
    if ((Test-Path -LiteralPath $installDir) -and @(Get-ChildItem -LiteralPath $installDir -Force).Count -gt 0) {
        throw "The folder is not empty and has no launcher manifest: $installDir"
    }
    $null = New-Item -ItemType Directory -Path $installDir -Force
    $state = [pscustomobject]@{
        AppId = $appId
        InstallDir = $installDir
        Installed = $false
        Created = [DateTime]::UtcNow.ToString('o')
        PathAddedByInstaller = $false
        PathBeforeInstall = $null
        ShortcutPaths = @()
        CoreSha256 = ''
    }
    Save-OcrManifest $state $manifestPath
}

# Keep a previous CLI core as a backup when upgrading from v5.
$sourceHash = (Get-FileHash -LiteralPath $coreSource -Algorithm SHA256).Hash
if (Test-Path -LiteralPath $coreTarget -PathType Leaf) {
    $oldHash = (Get-FileHash -LiteralPath $coreTarget -Algorithm SHA256).Hash
    if ($oldHash -ne $sourceHash) {
        $backupName = 'ocr-before-install-' + [Guid]::NewGuid().ToString('N') + '.ps1.bak'
        Copy-Item -LiteralPath $coreTarget -Destination (Join-Path $installDir $backupName)
    }
}
Copy-Item -LiteralPath $coreSource -Destination $coreTarget -Force
foreach ($name in @('ocr.cmd', 'ocr-cli.cmd', 'OpenCodeSessions.exe', 'InstallerHelpers.ps1', 'Uninstall.ps1', 'Uninstall.cmd', 'README.md', 'LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $installDir $name) -Force
}
if ((Get-FileHash -LiteralPath $coreTarget -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Core file verification failed.'
}
$state.CoreSha256 = $sourceHash
Save-OcrManifest $state $manifestPath

# Add desktop and current-user Start Menu shortcuts, without replacing unrelated shortcuts.
$launcher = Join-Path $installDir 'OpenCodeSessions.exe'
$legacyLauncher = Join-Path $installDir 'ocr.cmd'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcuts = @($state.ShortcutPaths)
try {
    $shell = New-Object -ComObject WScript.Shell
    $folders = @([Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('Programs'))
    foreach ($folder in $folders) {
        if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
            Write-Warning 'A desktop or Start Menu folder was unavailable; that shortcut was skipped.'
            continue
        }
        $n = 1
        while ($true) {
            $name = if ($n -eq 1) { 'OpenCode Sessions (ocr).lnk' } else { "OpenCode Sessions (ocr) ($n).lnk" }
            $linkPath = Join-Path $folder $name
            if (-not (Test-Path -LiteralPath $linkPath)) { break }
            $existing = $shell.CreateShortcut($linkPath)
            if ((Get-OcrPathKey $existing.TargetPath) -in @((Get-OcrPathKey $launcher), (Get-OcrPathKey $legacyLauncher))) { break }
            $n++
        }
        $link = $shell.CreateShortcut($linkPath)
        $link.TargetPath = $launcher
        $link.WorkingDirectory = [Environment]::GetFolderPath('UserProfile')
        $link.Description = 'OpenCode Sessions - desktop conversation manager v6'
        $link.IconLocation = $launcher + ',0'
        $link.WindowStyle = 1
        $link.Save()
        if ($shortcuts -notcontains $linkPath) { $shortcuts += $linkPath }
        $state.ShortcutPaths = $shortcuts
        Save-OcrManifest $state $manifestPath
        Write-Host "Shortcut: $linkPath"
    }
}
catch {
    Write-Warning "Shortcut creation failed: $($_.Exception.Message)"
    Write-Host "You can still double-click: $launcher"
}

# Append only one entry to the current user's PATH; never replace the machine PATH.
if (-not $NoPath) {
    $snapshot = Get-OcrUserPath
    $wanted = Get-OcrPathKey $installDir
    $present = @($snapshot.Value -split ';' | Where-Object { (Get-OcrPathKey $_) -eq $wanted }).Count -gt 0
    if (-not $present) {
        $state.PathAddedByInstaller = $true
        $state.PathBeforeInstall = $snapshot
        Save-OcrManifest $state $manifestPath
        if ([string]::IsNullOrEmpty($snapshot.Value)) { $newPath = $installDir }
        elseif ($snapshot.Value.EndsWith(';')) { $newPath = $snapshot.Value + $installDir }
        else { $newPath = $snapshot.Value + ';' + $installDir }
        Set-OcrUserPath -Value $newPath -Kind $snapshot.Kind
        Send-OcrEnvironmentChange
    }
}
$state.Installed = $true
Save-OcrManifest $state $manifestPath

Write-Host ''
Write-Host 'Installed OpenCode Sessions v6.0 GUI. Use ocr-cli.cmd for the terminal selector.' -ForegroundColor Green
Write-Host "Location: $installDir"
Write-Host 'Double-click OpenCode Sessions (ocr) on your desktop to start.'
if (-not $NoPath) {
    Write-Host 'For the ocr command: fully close Windows Terminal / PowerShell, then reopen it.'
    Write-Host 'If you previously defined an ocr function or alias, use ocr.cmd to avoid that old definition.'
}
Write-Host 'No administrator access, PowerShell profile edits, or permanent execution-policy changes were requested.'
Write-Host 'To remove shortcuts and the added PATH entry, run Uninstall.cmd in the install folder.'
