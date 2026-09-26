#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'app'
& (Join-Path $PSScriptRoot 'Build.ps1')
& (Join-Path $PSScriptRoot 'Test.ps1') -SkipBuild

$version = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $app 'OpenCodeSessions.exe')).Version
$releaseVersion = '{0}.{1}.{2}' -f $version.Major, $version.Minor, $version.Build
$dist = Join-Path $root 'dist'
$null = New-Item -ItemType Directory -Path $dist -Force
$staging = Join-Path $dist ('.package-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $staging 'OpenCodeSessions'
$archive = Join-Path $dist ('OpenCodeSessions-v' + $releaseVersion + '-windows.zip')
$temporaryArchive = Join-Path $dist ('.archive-' + [Guid]::NewGuid().ToString('N') + '.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    $null = New-Item -ItemType Directory -Path $payload -Force
    $names = @('OpenCodeSessions.exe', 'ocr.cmd', 'ocr-cli.cmd', 'ocr_v5.ps1', 'Install.cmd', 'Install.ps1', 'InstallerHelpers.ps1', 'Uninstall.cmd', 'Uninstall.ps1', 'README.md', 'LICENSE')
    foreach ($name in $names) { Copy-Item -LiteralPath (Join-Path $app $name) -Destination (Join-Path $payload $name) }
    Copy-Item -LiteralPath (Join-Path $root 'CHANGELOG.md') -Destination (Join-Path $payload 'CHANGELOG.md')
    $lines = foreach ($file in (Get-ChildItem -LiteralPath $payload -File | Sort-Object Name)) {
        (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $file.Name
    }
    [IO.File]::WriteAllLines((Join-Path $payload 'SHA256SUMS.txt'), [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $temporaryArchive)
    $zip = [IO.Compression.ZipFile]::OpenRead($temporaryArchive)
    try {
        foreach ($line in $lines) {
            $expected, $name = $line -split '  ', 2
            $entry = $zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq ('OpenCodeSessions/' + $name) }
            if ($null -eq $entry) { throw "Missing ZIP entry: $name" }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($actual -ne $expected) { throw "Packaged checksum mismatch: $name" }
        }
    }
    finally { $zip.Dispose() }
    Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
    $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($archive + '.sha256'), ($digest + '  ' + [IO.Path]::GetFileName($archive) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Host "Release ready: $archive"
}
finally {
    $resolved = [IO.Path]::GetFullPath($staging)
    $allowed = [IO.Path]::GetFullPath($dist).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Staging cleanup is outside dist.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    if (Test-Path -LiteralPath $temporaryArchive) { Remove-Item -LiteralPath $temporaryArchive -Force }
}
