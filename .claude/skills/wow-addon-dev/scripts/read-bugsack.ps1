<#
.SYNOPSIS
    Read recent Lua errors captured by !BugGrabber.

.DESCRIPTION
    Parses the !BugGrabber SavedVariables file (a Lua-syntax assignment of a
    table of error records) and prints the most recent errors with their
    stacks. Output is text the user can read or paste back into chat.

.PARAMETER Account
    BattleNet account folder name. If omitted, the script picks the first
    folder it finds.

.PARAMETER Edition
    retail (default), classic, classic_era, anniversary, or forever (WoW Forever).

.PARAMETER WowPath
    Optional override for WoW install root.

.PARAMETER Limit
    Max number of errors to print (default 20).

.PARAMETER MatchAddon
    If set, only show errors whose stack mentions the named addon folder.

.EXAMPLE
    .\read-bugsack.ps1
    .\read-bugsack.ps1 -Limit 5
    .\read-bugsack.ps1 -MatchAddon CrownCosmosCallout
#>

[CmdletBinding()]
param(
    [string]$Account,
    [ValidateSet('retail', 'classic', 'classic_era', 'anniversary', 'forever')]
    [string]$Edition = 'retail',
    [string]$WowPath = 'C:\Program Files (x86)\World of Warcraft',
    [int]$Limit = 20,
    [string]$MatchAddon
)

$editionMap = @{
    retail       = '_retail_'
    classic      = '_classic_'
    classic_era  = '_classic_era_'
    anniversary  = '_anniversary_'
    forever      = '_forever_'
}

$accountRoot = Join-Path $WowPath "$($editionMap[$Edition])\WTF\Account"
if (-not (Test-Path -LiteralPath $accountRoot)) {
    Write-Error "WTF Account folder not found: $accountRoot"
    exit 1
}

if (-not $Account) {
    $candidate = Get-ChildItem -LiteralPath $accountRoot -Directory |
                 Where-Object { $_.Name -ne 'SavedVariables' } |
                 Select-Object -First 1
    if (-not $candidate) {
        Write-Error "No account folder found under $accountRoot"
        exit 1
    }
    $Account = $candidate.Name
    Write-Host "Using account: $Account" -ForegroundColor Cyan
}

$bugFile = Join-Path $accountRoot "$Account\SavedVariables\!BugGrabber.lua"
if (-not (Test-Path -LiteralPath $bugFile)) {
    Write-Error "BugGrabber SavedVariables not found: $bugFile (is BugGrabber installed and has it run at least once?)"
    exit 1
}

Write-Host "Reading $bugFile" -ForegroundColor Cyan
$content = Get-Content -LiteralPath $bugFile -Raw -Encoding UTF8

# !BugGrabber stores errors as a Lua array of tables. We don't have a real Lua
# parser here, so we approximate: every ["message"] = "..." starts a record that
# runs until the next one, and the other fields are looked up inside that span
# in any order. ["time"] may be a quoted string or a Unix timestamp number
# (current BugGrabber, e.g. on WoW Forever, writes the number).

function ConvertFrom-LuaString([string]$s) {
    return ($s -replace '\\n', "`n" -replace '\\"', '"' -replace '\\\\', '\')
}

$errors = @()
$luaStr = '"((?:[^"\\]|\\.)*)"'
$starts = [regex]::Matches($content, '\["message"\]\s*=\s*' + $luaStr, 'Singleline')
for ($i = 0; $i -lt $starts.Count; $i++) {
    $m = $starts[$i]
    $end = if ($i + 1 -lt $starts.Count) { $starts[$i + 1].Index } else { $content.Length }
    $span = $content.Substring($m.Index, $end - $m.Index)

    $msg = ConvertFrom-LuaString $m.Groups[1].Value
    $stack = ''
    $sm = [regex]::Match($span, '\["stack"\]\s*=\s*' + $luaStr, 'Singleline')
    if ($sm.Success) { $stack = ConvertFrom-LuaString $sm.Groups[1].Value }
    $time = ''
    $tm = [regex]::Match($span, '\["time"\]\s*=\s*(?:' + $luaStr + '|(\d+))', 'Singleline')
    if ($tm.Success) {
        if ($tm.Groups[2].Success) {
            $time = [DateTimeOffset]::FromUnixTimeSeconds([long]$tm.Groups[2].Value).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
        } else {
            $time = $tm.Groups[1].Value
        }
    }
    if ($MatchAddon -and ($msg + $stack) -notlike "*$MatchAddon*") { continue }
    $errors += [pscustomobject]@{
        Time    = $time
        Message = $msg
        Stack   = $stack
    }
}

if ($errors.Count -eq 0) {
    if ($MatchAddon) {
        Write-Host "No errors matching '$MatchAddon' found." -ForegroundColor Yellow
    } else {
        Write-Host "No parseable errors found in $bugFile" -ForegroundColor Yellow
    }
    exit 0
}

# Most recent last in BugGrabber files (typically). Reverse to print newest first.
[array]::Reverse($errors)
$shown = 0
foreach ($e in $errors) {
    if ($shown -ge $Limit) { break }
    $shown++
    Write-Host ""
    Write-Host "[$($e.Time)]" -ForegroundColor Cyan
    Write-Host $e.Message -ForegroundColor White
    Write-Host "Stack:" -ForegroundColor DarkGray
    foreach ($line in ($e.Stack -split "`n")) {
        if ($line.Trim() -ne '') { Write-Host "  $line" -ForegroundColor Gray }
    }
}

Write-Host ""
Write-Host "Showed $shown of $($errors.Count) error(s)." -ForegroundColor Cyan
