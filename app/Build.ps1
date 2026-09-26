#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (-not (Test-Path (Join-Path $framework 'csc.exe'))) {
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
}
$compiler = Join-Path $framework 'csc.exe'
if (-not (Test-Path $compiler)) { throw 'Windows .NET Framework 4.x compiler was not found.' }
$output = Join-Path $PSScriptRoot 'OpenCodeSessions.exe'
$staging = Join-Path $PSScriptRoot 'OpenCodeSessions.build.exe'
$references = @('System.dll', 'System.Core.dll', 'System.Web.Extensions.dll', 'System.Xaml.dll', 'System.Windows.Forms.dll', 'WPF\WindowsBase.dll', 'WPF\PresentationCore.dll', 'WPF\PresentationFramework.dll')
$arguments = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/utf8output', ('/out:' + $staging))
foreach ($reference in $references) { $arguments += '/reference:' + (Join-Path $framework $reference) }
$arguments += '/resource:' + (Join-Path $PSScriptRoot 'App.xaml') + ',App.xaml'
$arguments += '/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')
$arguments += '/win32icon:' + (Join-Path $PSScriptRoot 'logo.ico')
$arguments += Join-Path $PSScriptRoot 'Manager.cs'
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'GUI compilation failed.' }
Move-Item -LiteralPath $staging -Destination $output -Force
Write-Host "Built: $output"
