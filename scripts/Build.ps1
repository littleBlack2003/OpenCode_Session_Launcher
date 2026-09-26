#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RefreshLogo)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'app'
if ($RefreshLogo) {
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $app 'Build-Logo.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Logo generation failed.' }
}
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $app 'LICENSE') -Force
& (Join-Path $app 'Build.ps1')
& (Join-Path $app 'Update-Checksums.ps1')
