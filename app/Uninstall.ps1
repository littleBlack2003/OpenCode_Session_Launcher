#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This uninstaller is for Windows.' }
. (Join-Path $PSScriptRoot 'InstallerHelpers.ps1')
$manifestPath = Join-Path $PSScriptRoot 'launcher-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Run Uninstall.cmd from the installed OpenCodeSessionLauncher folder, not the extracted package.'
}
$state = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.AppId -ne 'OpenCodeSessionLauncher-v5' -or
    (Get-OcrPathKey $state.InstallDir) -ne (Get-OcrPathKey $PSScriptRoot)) {
    throw 'Installation manifest mismatch. Nothing was removed.'
}
Write-Host 'This removes the launcher shortcuts and its own user PATH entry.'
Write-Host 'OpenCode, your project folders, sessions, and model configuration will not be touched.'
$answer = Read-Host 'Continue? [y/N]'
if ($answer -notin @('y', 'yes')) { exit 0 }

if ($state.PathAddedByInstaller) {
    $snapshot = Get-OcrUserPath
    $wanted = Get-OcrPathKey $PSScriptRoot
    $parts = @($snapshot.Value -split ';')
    $remaining = @($parts | Where-Object { (Get-OcrPathKey $_) -ne $wanted })
    if ($remaining.Count -ne $parts.Count) {
        $newPath = $remaining -join ';'
        if ([string]::IsNullOrEmpty($newPath) -and $null -ne $state.PathBeforeInstall -and -not $state.PathBeforeInstall.Exists) {
            Set-OcrUserPath -Delete
        }
        else { Set-OcrUserPath -Value $newPath -Kind $snapshot.Kind }
        Send-OcrEnvironmentChange
    }
    $state.PathAddedByInstaller = $false
    Save-OcrManifest $state $manifestPath
}

$remainingLinks = @()
$launcherKeys = @((Get-OcrPathKey (Join-Path $PSScriptRoot 'ocr.cmd')), (Get-OcrPathKey (Join-Path $PSScriptRoot 'OpenCodeSessions.exe')))
try {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($path in @($state.ShortcutPaths)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $link = $shell.CreateShortcut($path)
            if ((Get-OcrPathKey $link.TargetPath) -in $launcherKeys) {
                Remove-Item -LiteralPath $path -Force
            }
            else { Write-Warning "Shortcut was changed after installation; it was not removed: $path" }
        }
        catch { $remainingLinks += $path; Write-Warning $_.Exception.Message }
    }
}
catch {
    $remainingLinks = @($state.ShortcutPaths)
    Write-Warning $_.Exception.Message
}
$state.ShortcutPaths = $remainingLinks
$state.Installed = $false
Save-OcrManifest $state $manifestPath
Write-Host 'Finished. Close and reopen your terminal for PATH changes to take effect.' -ForegroundColor Green
Write-Host "Launcher files were retained. After closing this window, you may delete this folder manually: $PSScriptRoot"
