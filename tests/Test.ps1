#Requires -Version 5.1
param([switch]$Live)
$ErrorActionPreference = 'Stop'
$base = Join-Path (Split-Path $PSScriptRoot -Parent) 'app'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (-not (Test-Path (Join-Path $framework 'csc.exe'))) { $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319' }
$output = Join-Path $PSScriptRoot 'Manager.Tests.exe'
$refs = @('System.dll', 'System.Core.dll', 'System.Web.Extensions.dll', 'System.Xaml.dll', 'System.Windows.Forms.dll', 'WPF\WindowsBase.dll', 'WPF\PresentationCore.dll', 'WPF\PresentationFramework.dll')
$arguments = @('/nologo', '/target:exe', '/main:OpenCodeSessions.Tests', '/utf8output', ('/out:' + $output))
foreach ($ref in $refs) { $arguments += '/reference:' + (Join-Path $framework $ref) }
$arguments += '/resource:' + (Join-Path $base 'App.xaml') + ',App.xaml'
$arguments += Join-Path $base 'Manager.cs'
$arguments += Join-Path $PSScriptRoot 'Manager.Tests.cs'
& (Join-Path $framework 'csc.exe') @arguments
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
Push-Location $PSScriptRoot
try {
    if ($Live) { & $output --live } else { & $output }
    if ($LASTEXITCODE -ne 0) { throw 'Manager tests failed.' }
}
finally { Pop-Location }
