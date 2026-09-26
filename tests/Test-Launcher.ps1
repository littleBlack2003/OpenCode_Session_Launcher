#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$base = Join-Path (Split-Path $PSScriptRoot -Parent) 'app'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('OpenCodeLauncherTests-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($true)
$script:checks = 0
function Assert-OcrTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
    Write-Host ('PASS: ' + $Message)
}
function Write-TestFile([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $utf8) }
function Run-TestInstaller([string]$Path, [switch]$NoPath) {
    if ($NoPath) { $log = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path -NoPath 2>&1 }
    else { $log = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path 2>&1 }
    if ($LASTEXITCODE -ne 0) { throw ($log -join [Environment]::NewLine) }
}
try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $fixture = Join-Path $testRoot 'package'
    $null = New-Item -ItemType Directory -Path $fixture
    Get-ChildItem -LiteralPath $base -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $fixture }
    $local = Join-Path $testRoot 'LocalAppData'
    $desktop = Join-Path $testRoot 'Desktop'
    $programs = Join-Path $testRoot 'Programs'
    foreach ($dir in @($local, $desktop, $programs)) { $null = New-Item -ItemType Directory -Path $dir }
    $pathState = Join-Path $testRoot 'path-state.json'
    Write-TestFile $pathState '{"Exists":true,"Value":"C:\\ExistingTools","Kind":"ExpandString"}'

    # Redirect installation destinations; this test never writes the actual desktop or registry.
    $installSource = [IO.File]::ReadAllText((Join-Path $fixture 'Install.ps1'))
    $installSource = $installSource.Replace("[Environment]::GetFolderPath('LocalApplicationData')", ("'" + $local.Replace("'", "''") + "'"))
    $installSource = $installSource.Replace("[Environment]::GetFolderPath('DesktopDirectory')", ("'" + $desktop.Replace("'", "''") + "'"))
    $installSource = $installSource.Replace("[Environment]::GetFolderPath('Programs')", ("'" + $programs.Replace("'", "''") + "'"))
    Write-TestFile (Join-Path $fixture 'Install.ps1') $installSource
    $mocks = @'
function Get-OcrUserPath { Get-Content -LiteralPath $env:OCR_TEST_PATH_STATE -Raw | ConvertFrom-Json }
function Set-OcrUserPath {
    param([string]$Value, [string]$Kind='ExpandString', [switch]$Delete)
    [pscustomobject]@{Exists=(-not $Delete); Value=$Value; Kind=$Kind} | ConvertTo-Json | Set-Content -LiteralPath $env:OCR_TEST_PATH_STATE -Encoding UTF8
}
function Send-OcrEnvironmentChange { }
'@
    $env:OCR_TEST_PATH_STATE = $pathState
    $helperPath = Join-Path $fixture 'InstallerHelpers.ps1'
    Write-TestFile $helperPath ([IO.File]::ReadAllText($helperPath) + [Environment]::NewLine + $mocks)
    $uninstallPath = Join-Path $fixture 'Uninstall.ps1'
    $uninstallSource = [IO.File]::ReadAllText($uninstallPath).Replace("`$answer = Read-Host 'Continue? [y/N]'", "`$answer = 'y'")
    Write-TestFile $uninstallPath $uninstallSource
    & (Join-Path $fixture 'Update-Checksums.ps1')

    $shell = New-Object -ComObject WScript.Shell
    $unrelatedPath = Join-Path $desktop 'OpenCode Sessions (ocr).lnk'
    $unrelated = $shell.CreateShortcut($unrelatedPath)
    $unrelated.TargetPath = Join-Path $env:WINDIR 'notepad.exe'
    $unrelated.Save()
    $installer = Join-Path $fixture 'Install.ps1'
    Run-TestInstaller $installer -NoPath
    $installed = Join-Path $local 'OpenCodeSessionLauncher'
    $manifest = Join-Path $installed 'launcher-manifest.json'
    $state = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    Assert-OcrTest (Test-Path -LiteralPath (Join-Path $installed 'OpenCodeSessions.exe')) 'GUI payload installed in isolated directory'
    Assert-OcrTest ((Get-FileHash -LiteralPath (Join-Path $installed 'LICENSE')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $base 'LICENSE')).Hash) 'Installed distribution retains MIT license'
    Assert-OcrTest (-not $state.PathAddedByInstaller) 'NoPath installation leaves simulated PATH unchanged'
    Assert-OcrTest ($state.ShortcutPaths.Count -eq 2) 'Desktop and Start Menu shortcuts created'
    Assert-OcrTest ($shell.CreateShortcut($unrelatedPath).TargetPath -like '*notepad.exe') 'Unrelated shortcut preserved'
    foreach ($linkPath in $state.ShortcutPaths) {
        Assert-OcrTest ($shell.CreateShortcut($linkPath).TargetPath -eq (Join-Path $installed 'OpenCodeSessions.exe')) 'Shortcut targets GUI executable'
    }
    Run-TestInstaller $installer
    Run-TestInstaller $installer
    $savedPath = Get-Content -LiteralPath $pathState -Raw | ConvertFrom-Json
    Assert-OcrTest (@($savedPath.Value -split ';' | Where-Object { $_ -eq $installed }).Count -eq 1) 'Repeated install adds PATH once'

    # Simulate an old v5 shortcut and core; upgrade must reuse the links and back up the core.
    foreach ($linkPath in $state.ShortcutPaths) { $link=$shell.CreateShortcut($linkPath); $link.TargetPath=Join-Path $installed 'ocr.cmd'; $link.Save() }
    Add-Content -LiteralPath (Join-Path $installed 'ocr-core.ps1') -Value '# old version'
    Run-TestInstaller $installer
    Assert-OcrTest (@(Get-ChildItem -LiteralPath $installed -Filter 'ocr-before-install-*.ps1.bak').Count -eq 1) 'Upgrade backs up changed legacy core'
    foreach ($linkPath in $state.ShortcutPaths) { Assert-OcrTest ($shell.CreateShortcut($linkPath).TargetPath -eq (Join-Path $installed 'OpenCodeSessions.exe')) 'Upgrade reuses legacy shortcut' }
    $savedPath.Value += ';C:\AddedLater'
    Write-TestFile $pathState ($savedPath | ConvertTo-Json)
    Run-TestInstaller (Join-Path $installed 'Uninstall.ps1')
    $after = Get-Content -LiteralPath $pathState -Raw | ConvertFrom-Json
    Assert-OcrTest ($after.Value -eq 'C:\ExistingTools;C:\AddedLater') 'Uninstall preserves later PATH additions'
    Assert-OcrTest (@($state.ShortcutPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) 'Uninstall removes owned GUI shortcuts'
    Assert-OcrTest (Test-Path -LiteralPath $unrelatedPath) 'Uninstall keeps unrelated shortcut'

    # Execute the actual CLI control flow with a fixture instead of real interactive programs.
    $project = Join-Path $testRoot "中文  project's & test"
    $null = New-Item -ItemType Directory -Path $project
    $sessionJson = ConvertTo-Json -Compress -InputObject @([pscustomobject]@{id='ses_test'; title='中文'; updated=1; directory=$project})
    $mock = 'function Out-GridView { param([Parameter(ValueFromPipeline=$true)]$InputObject, $Title, [switch]$PassThru) process { $InputObject } }; function opencode { [IO.File]::WriteAllText($env:OCR_TEST_CWD, (Get-Location).Path); & $env:ComSpec /d /c "exit 42" }'
    $core = [IO.File]::ReadAllText((Join-Path $base 'ocr_v5.ps1'))
    $core = $core.Replace('$jsonText = Read-OpenCodeSessionsJson -Count $MaxCount', ($mock + [Environment]::NewLine + '$jsonText = ' + "'" + $sessionJson.Replace("'", "''") + "'"))
    $core = $core.Replace('$fzfPath = Get-FzfPath', '$fzfPath = $null')
    $corePath = Join-Path $testRoot 'test-core.ps1'
    $env:OCR_TEST_CWD = Join-Path $testRoot 'cwd.txt'
    Write-TestFile $corePath $core
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath
    Assert-OcrTest ($LASTEXITCODE -eq 42) 'CLI propagates failing OpenCode exit code'
    Assert-OcrTest ([IO.File]::ReadAllText($env:OCR_TEST_CWD) -eq $project) 'CLI resumes in exact Chinese and double-space directory'
    Write-Host ('ALL PASSED: ' + $script:checks)
}
finally {
    Remove-Item Env:OCR_TEST_PATH_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:OCR_TEST_CWD -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('OpenCodeLauncherTests-')) {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
