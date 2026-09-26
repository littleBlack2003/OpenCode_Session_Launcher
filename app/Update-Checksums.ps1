#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
# Generated output is ignored by Git; releases compute checksums after staging.
$names = @('Install.cmd', 'Install.ps1', 'InstallerHelpers.ps1', 'ocr.cmd', 'ocr-cli.cmd', 'ocr_v5.ps1', 'OpenCodeSessions.exe', 'README.md', 'Uninstall.cmd', 'Uninstall.ps1', 'LICENSE')
$lines = foreach ($name in ($names | Sort-Object)) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    $hash + '  ' + $name
}
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'SHA256SUMS.txt'), [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
Write-Host 'Runtime checksums updated.'
