#Requires -Version 5.1
# Shared installer helpers; these do not run OpenCode or read its data.
function Get-OcrPathKey {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($Value.Trim().Trim([char]34))
    return $expanded.Replace('/', '\').TrimEnd('\').ToUpperInvariant()
}

function Get-OcrUserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    try {
        $exists = $false
        $value = ''
        $kind = 'ExpandString'
        if ($null -ne $key -and @($key.GetValueNames()) -contains 'Path') {
            $exists = $true
            $value = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $kind = $key.GetValueKind('Path').ToString()
            if ($kind -notin @('String', 'ExpandString')) {
                throw 'The current user PATH has an unexpected registry type. PATH was not changed.'
            }
        }
        return [pscustomobject]@{ Exists = $exists; Value = $value; Kind = $kind }
    }
    finally {
        if ($null -ne $key) { $key.Close() }
    }
}

function Set-OcrUserPath {
    param([string]$Value, [string]$Kind = 'ExpandString', [switch]$Delete)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($Delete) { $key.DeleteValue('Path', $false) }
        else {
            $valueKind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], $Kind)
            $key.SetValue('Path', $Value, $valueKind)
        }
    }
    finally { if ($null -ne $key) { $key.Close() } }
}

function Send-OcrEnvironmentChange {
    # Notify Explorer. Existing terminal processes still need to be reopened.
    try {
        if (-not ('OcrLauncher.EnvironmentNotification' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OcrLauncher {
    public static class EnvironmentNotification {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hwnd, uint msg, UIntPtr wParam, string lParam,
            uint flags, uint timeout, out UIntPtr result);
    }
}
'@
        }
        $result = [UIntPtr]::Zero
        $null = [OcrLauncher.EnvironmentNotification]::SendMessageTimeout(
            [IntPtr]0xffff, 0x001a, [UIntPtr]::Zero, 'Environment', 2, 1000, [ref]$result)
    }
    catch {
        Write-Warning 'PATH was saved. Windows could not be notified; sign out and in if a new terminal does not see it.'
    }
}

function Save-OcrManifest {
    param([object]$Manifest, [string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($true)
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, ($Manifest | ConvertTo-Json -Depth 6), $encoding)
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporary, $Path, $Path + '.bak') }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
