param(
    [ValidateRange(1, 100000)][int]$MaxCount = 1000
)

$ErrorActionPreference = "Stop"

# Refresh this child process only; a launcher may inherit an older desktop PATH.
$env:Path = $env:Path + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

# OpenCode emits UTF-8 JSON. Windows PowerShell 5.1 can decode native-command
# stdout using the legacy system code page, which corrupts Chinese text and can
# even make otherwise-valid JSON fail ConvertFrom-Json.
#
# We therefore redirect OpenCode's stdout to a file at the cmd.exe level (raw
# bytes), then read that file explicitly as UTF-8.

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = $Utf8NoBom
try {
    [Console]::InputEncoding  = $Utf8NoBom
    [Console]::OutputEncoding = $Utf8NoBom
    # Windows PowerShell 5.1 may still keep the console code page on GBK/936.
    # Force UTF-8 so native TUI programs such as fzf render CJK correctly.
    & "$env:ComSpec" /d /c "chcp 65001 > nul"
}
catch {
    # Some hosts do not allow changing console encoding; the JSON path below
    # still works because it reads bytes explicitly as UTF-8.
}

function Get-LocalDateFromEpochMs {
    param([object]$Value)
    if ($null -eq $Value -or "$Value" -eq "") { return $null }

    try {
        $epoch = [DateTime]::SpecifyKind([DateTime]"1970-01-01 00:00:00", [DateTimeKind]::Utc)
        return $epoch.AddMilliseconds([double]$Value).ToLocalTime()
    }
    catch {
        return $null
    }
}

function Get-ProjectName {
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        return "(unknown)"
    }

    $clean = $Directory.TrimEnd('\', '/')
    try {
        $leaf = Split-Path -Leaf $clean
        if ([string]::IsNullOrWhiteSpace($leaf)) { return $clean }
        return $leaf
    }
    catch {
        return $clean
    }
}

function Clean-OneLine {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    return (("$Value" -replace "[`r`n`t]+", " ") -replace "\s{2,}", " ").Trim()
}

function Get-FzfPath {
    $cmd = Get-Command fzf -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # winget commonly exposes command aliases here. This lets the script work
    # immediately after installation, even before PowerShell is restarted.
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\fzf.exe"),
        (Join-Path $env:USERPROFILE "scoop\shims\fzf.exe")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    return $null
}

function Read-OpenCodeSessionsJson {
    param([int]$Count)

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("opencode_sessions_" + [Guid]::NewGuid().ToString("N") + ".json")

    try {
        # Redirection is performed by cmd.exe, so the UTF-8 bytes from OpenCode
        # are written directly to disk instead of being decoded by Windows
        # PowerShell 5.1 first.
        $cmdLine = 'opencode session list --format json --max-count {0} > "{1}"' -f $Count, $tmp
        & "$env:ComSpec" /d /c $cmdLine

        if ($LASTEXITCODE -ne 0) {
            throw "OpenCode session list failed with exit code $LASTEXITCODE."
        }

        if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) {
            throw "OpenCode did not create the temporary JSON file."
        }

        $bytes = [IO.File]::ReadAllBytes($tmp)

        # Strip UTF-8 BOM if one is present; OpenCode normally does not emit one.
        if ($bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF) {
            $jsonText = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        }
        else {
            $jsonText = [Text.Encoding]::UTF8.GetString($bytes)
        }

        if ([string]::IsNullOrWhiteSpace($jsonText)) {
            throw "OpenCode returned empty JSON."
        }

        return $jsonText
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Reading OpenCode sessions..." -ForegroundColor Cyan

$jsonText = Read-OpenCodeSessionsJson -Count $MaxCount

try {
    # Windows PowerShell 5.1 can keep a top-level JSON array as one nested
    # System.Object[] object. Force pipeline enumeration so each session
    # becomes an individual object before sorting.
    $parsed = $jsonText | ConvertFrom-Json
    $sessions = @($parsed | ForEach-Object { $_ })
}
catch {
    # Save the exact UTF-8 text for diagnosis instead of dumping a huge,
    # potentially garbled payload into the terminal.
    $debugPath = Join-Path $env:TEMP "opencode_sessions_debug.json"
    [IO.File]::WriteAllText($debugPath, $jsonText, $Utf8NoBom)

    throw @"
Could not parse OpenCode JSON even after reading it as UTF-8.
The exact output was saved to:
  $debugPath

Try:
  Get-Content -Raw -Encoding UTF8 "$debugPath" | ConvertFrom-Json
"@
}

if ($sessions.Count -eq 0) {
    Write-Host "No OpenCode sessions found." -ForegroundColor Yellow
    exit 0
}

$rows = @()
$i = 0

$sortedSessions = @(
    $sessions | Sort-Object -Property @{
        Expression = {
            if ($null -eq $_.updated -or "$($_.updated)" -eq "") {
                [Int64]0
            }
            else {
                [Int64]$_.updated
            }
        }
    } -Descending
)

foreach ($s in $sortedSessions) {
    $i++

    $updated = Get-LocalDateFromEpochMs $s.updated
    if ($updated) {
        $updatedText = $updated.ToString("yyyy-MM-dd HH:mm")
    }
    else {
        $updatedText = "unknown"
    }

    # The filesystem path must remain byte-for-byte intact; clean only display fields.
    $directory = [string]$s.directory
    $title = Clean-OneLine $s.title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = "(untitled)" }

    $rows += [PSCustomObject]@{
        Index     = $i
        Project   = Get-ProjectName $directory
        Title     = $title
        Updated   = $updatedText
        Directory = $directory
        Id        = [string]$s.id
    }
}

$selected = $null
$fzfPath = Get-FzfPath

if ($fzfPath) {
    $lines = foreach ($r in $rows) {
        "{0}`t{1}`t{2}`t{3}`t{4}" -f `
            $r.Index, `
            (Clean-OneLine $r.Project), `
            (Clean-OneLine $r.Title), `
            $r.Updated, `
            (Clean-OneLine $r.Directory)
    }

    # Avoid Windows PowerShell 5.1's native-pipeline encoding path entirely.
    # Write fzf input as UTF-8 bytes and capture the selected row as UTF-8 bytes.
    $fzfInput  = Join-Path ([IO.Path]::GetTempPath()) ("ocr_fzf_in_"  + [Guid]::NewGuid().ToString("N") + ".txt")
    $fzfOutput = Join-Path ([IO.Path]::GetTempPath()) ("ocr_fzf_out_" + [Guid]::NewGuid().ToString("N") + ".txt")

    try {
        [IO.File]::WriteAllLines($fzfInput, [string[]]$lines, $Utf8NoBom)

        $escapedFzf = '"' + $fzfPath.Replace('"', '""') + '"'
        $escapedIn  = '"' + $fzfInput.Replace('"', '""') + '"'
        $escapedOut = '"' + $fzfOutput.Replace('"', '""') + '"'

        # Use full-screen fzf here. Some Windows/cmd/fzf combinations
        # mis-parse percentage values passed to --height (for example 85%).
        # Full-screen mode avoids that compatibility issue entirely.
        $fzfArgs = '--layout reverse --border ' +
                   '--prompt "OpenCode > " ' +
                   '--header "Project | Title | Updated | Directory" ' +
                   '--delimiter "\t" --with-nth "2.."'

        # fzf draws its interactive UI on the terminal while its selected line
        # is redirected to a file. chcp 65001 makes the terminal side UTF-8 too.
        $cmdLine = 'chcp 65001 > nul & {0} {1} < {2} > {3}' -f `
            $escapedFzf, $fzfArgs, $escapedIn, $escapedOut

        & "$env:ComSpec" /d /c $cmdLine
        $fzfExitCode = $LASTEXITCODE

        if (Test-Path -LiteralPath $fzfOutput -PathType Leaf) {
            $pickedBytes = [IO.File]::ReadAllBytes($fzfOutput)
            $picked = [Text.Encoding]::UTF8.GetString($pickedBytes).TrimEnd("`r", "`n")
        }
        else {
            $picked = $null
        }

        if ($fzfExitCode -ne 0 -and $fzfExitCode -ne 1 -and $fzfExitCode -ne 130) {
            Write-Warning "fzf exited with code $fzfExitCode."
        }
    }
    finally {
        Remove-Item -LiteralPath $fzfInput  -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fzfOutput -Force -ErrorAction SilentlyContinue
    }

    if (-not [string]::IsNullOrWhiteSpace($picked)) {
        $pickedIndex = [int](($picked -split "`t", 2)[0])
        $selected = $rows | Where-Object { $_.Index -eq $pickedIndex } | Select-Object -First 1
    }
}
elseif (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    Write-Host "fzf was not found; falling back to Out-GridView." -ForegroundColor Yellow
    $selected = $rows |
        Select-Object Project, Title, Updated, Directory, Id, Index |
        Out-GridView -Title "OpenCode Session Manager" -PassThru |
        Select-Object -First 1
}
else {
    Write-Host "fzf was not found. Using simple console search." -ForegroundColor Yellow
    Write-Host "Install with: winget install --id junegunn.fzf -e" -ForegroundColor DarkGray

    $query = Read-Host "Search project/title/path (blank = latest sessions)"
    if ([string]::IsNullOrWhiteSpace($query)) {
        $matches = @($rows | Select-Object -First 30)
    }
    else {
        $matches = @(
            $rows | Where-Object {
                $_.Project   -like "*$query*" -or
                $_.Title     -like "*$query*" -or
                $_.Directory -like "*$query*"
            } | Select-Object -First 30
        )
    }

    if ($matches.Count -eq 0) {
        Write-Host "No matching sessions." -ForegroundColor Yellow
        exit 0
    }

    $matches | Format-Table Index, Project, Title, Updated -AutoSize
    $choice = Read-Host "Enter session number"

    $parsed = 0
    if ([int]::TryParse($choice, [ref]$parsed)) {
        $selected = $rows | Where-Object { $_.Index -eq $parsed } | Select-Object -First 1
    }
}

if ($null -eq $selected) {
    Write-Host "Cancelled." -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "Project : $($selected.Project)" -ForegroundColor Cyan
Write-Host "Title   : $($selected.Title)"
Write-Host "Updated : $($selected.Updated)"
Write-Host "Session : $($selected.Id)"
Write-Host "Dir     : $($selected.Directory)"
Write-Host ""

# Resume from the session's original working directory.
if (-not [string]::IsNullOrWhiteSpace($selected.Directory) -and
    (Test-Path -LiteralPath $selected.Directory -PathType Container)) {

    Push-Location -LiteralPath $selected.Directory
    try {
        & opencode --session $selected.Id
        $resumeExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    exit $resumeExitCode
}
else {
    Write-Warning "The saved session directory does not exist on this machine:"
    Write-Warning "  $($selected.Directory)"
    Write-Host "For safety, OpenCode was not launched from the wrong directory." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Resume manually with:" -ForegroundColor Cyan
    Write-Host "  cd <correct-project-directory>"
    Write-Host "  opencode --session $($selected.Id)"
    exit 1
}
