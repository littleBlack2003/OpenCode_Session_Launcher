#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Live, [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'Build.ps1') }
$arguments = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'tests\Test.ps1'))
if ($Live) { $arguments += '-Live' }
& powershell.exe @arguments
if ($LASTEXITCODE -ne 0) { throw 'Manager tests failed.' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Test-Launcher.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Launcher tests failed.' }
