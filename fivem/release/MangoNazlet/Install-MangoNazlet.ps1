<#
.SYNOPSIS
    Installs MangoNazlet into a FiveM server.

.DESCRIPTION
    Copies the resource in, edits server.cfg, and first checks the server has
    what MangoNazlet needs.

    Every path here is handled literally. FiveM resource folders are named
    [cfx-default], [qb], [jobs] and so on, and PowerShell reads square brackets
    in a -Path as a wildcard character class, so Test-Path, Get-ChildItem and
    Copy-Item all misbehave on a normal FiveM layout. This script therefore
    uses .NET's IO methods and robocopy, which have no wildcard semantics at
    all, rather than the usual cmdlets.

.PARAMETER ServerPath
    Root of the FiveM server. Defaults to C:\FiveMServer.

.PARAMETER ResourcesFolder
    Sub-folder of resources\ to install into. Defaults to [jobs].

.PARAMETER WhatIf
    Show everything that would happen without changing a single file.

.EXAMPLE
    .\Install-MangoNazlet.ps1
    .\Install-MangoNazlet.ps1 -ServerPath "D:\servers\rp" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ServerPath      = 'C:\FiveMServer',
    [string] $ResourcesFolder = '[jobs]'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── output ─────────────────────────────────────────────────────
function Write-Head($text) {
    Write-Host ''
    Write-Host "  $text" -ForegroundColor Yellow
    Write-Host "  $('-' * $text.Length)" -ForegroundColor DarkYellow
}
function Write-Ok($text)   { Write-Host "  [ ok ] $text" -ForegroundColor Green }
function Write-Info($text) { Write-Host "  [ .. ] $text" -ForegroundColor Gray }
function Write-Warn($text) { Write-Host "  [warn] $text" -ForegroundColor Yellow }
function Write-Bad($text)  { Write-Host "  [fail] $text" -ForegroundColor Red }

# ── literal path helpers ───────────────────────────────────────
# These never interpret [ ] as a wildcard, which the cmdlet equivalents do.
function Test-Dir([string] $path)  { return [System.IO.Directory]::Exists($path) }
function Test-File([string] $path) { return [System.IO.File]::Exists($path) }

function Get-DirNames([string] $path) {
    try   { return [System.IO.Directory]::GetDirectories($path) }
    catch { return @() }
}

# Breadth-first walk to a fixed depth. Iterative so a deep or looping tree
# cannot blow the stack.
function Get-DirsToDepth([string] $root, [int] $maxDepth) {
    $found   = New-Object System.Collections.Generic.List[string]
    $current = @($root)

    for ($level = 0; $level -le $maxDepth; $level++) {
        $next = New-Object System.Collections.Generic.List[string]
        foreach ($dir in $current) {
            foreach ($child in Get-DirNames $dir) {
                $found.Add($child)
                $next.Add($child)
            }
        }
        if ($next.Count -eq 0) { break }
        $current = $next.ToArray()
    }
    return $found
}

# robocopy: native to Windows, entirely literal, and it handles long paths.
# Exit codes below 8 are success; 8 and above are real failures.
function Invoke-RoboCopy([string] $from, [string] $to, [switch] $Mirror) {
    # Not $args: that is an automatic variable in PowerShell.
    $roboArgs = @($from, $to, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP', '/R:2', '/W:1')
    if ($Mirror) { $roboArgs += '/PURGE' }

    $null = & robocopy.exe @roboArgs
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed copying '$from' to '$to' (exit code $LASTEXITCODE)"
    }
}

Write-Host ''
Write-Host '  MangoNazlet installer' -ForegroundColor Magenta
Write-Host '  =====================' -ForegroundColor Magenta

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Bad "This installer needs PowerShell 3.0 or newer (you have $($PSVersionTable.PSVersion))."
    exit 1
}

# ── find the resource beside this script ───────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source    = Join-Path $scriptDir 'mangonazlet'

if (-not (Test-File (Join-Path $source 'fxmanifest.lua'))) {
    Write-Bad 'Could not find the resource next to this script.'
    Write-Host ''
    Write-Host "  Expected: $source\fxmanifest.lua"
    Write-Host '  Keep this script in the same folder as the "mangonazlet" folder.'
    exit 1
}
Write-Ok 'Found the resource to install'

# ── locate the server ──────────────────────────────────────────
Write-Head 'Checking the server folder'

if (-not (Test-Dir $ServerPath)) {
    Write-Bad "$ServerPath does not exist."
    Write-Host ''
    Write-Host '  Point the installer at your server folder:'
    Write-Host "    .\Install-MangoNazlet.ps1 -ServerPath 'D:\my-server'"
    exit 1
}
Write-Ok "Server folder: $ServerPath"

# resources\ sits at the root, under server-data, or inside a txAdmin recipe
$resourcesRoot = $null
foreach ($candidate in @(
    (Join-Path $ServerPath 'resources'),
    (Join-Path $ServerPath 'server-data\resources'),
    (Join-Path $ServerPath 'txData\resources')
)) {
    if (Test-Dir $candidate) { $resourcesRoot = $candidate; break }
}

if (-not $resourcesRoot) {
    # txAdmin keeps each deployment in txData\<name>\resources
    $txData = Join-Path $ServerPath 'txData'
    if (Test-Dir $txData) {
        foreach ($deployment in Get-DirNames $txData) {
            $candidate = Join-Path $deployment 'resources'
            if (Test-Dir $candidate) { $resourcesRoot = $candidate; break }
        }
    }
}

if (-not $resourcesRoot) {
    Write-Bad "No 'resources' folder found under $ServerPath"
    Write-Host ''
    Write-Host '  Find the folder holding "resources" and "server.cfg", then:'
    Write-Host "    .\Install-MangoNazlet.ps1 -ServerPath '<that folder>'"
    exit 1
}
Write-Ok "Resources: $resourcesRoot"

$serverCfg = $null
foreach ($candidate in @(
    (Join-Path (Split-Path -Parent $resourcesRoot) 'server.cfg'),
    (Join-Path $ServerPath 'server.cfg')
)) {
    if (Test-File $candidate) { $serverCfg = $candidate; break }
}

if ($serverCfg) { Write-Ok "server.cfg: $serverCfg" }
else            { Write-Warn 'No server.cfg found - you will have to add the ensure lines yourself' }

# ── audit ──────────────────────────────────────────────────────
Write-Head 'Auditing your server'

# A resource is any folder holding a manifest. They nest inside [bracket]
# folders, sometimes more than one deep. Case-insensitive, because Windows
# folder names are and 'OX_lib' must not read as ox_lib missing.
$installed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

foreach ($dir in Get-DirsToDepth $resourcesRoot 2) {
    if ((Test-File (Join-Path $dir 'fxmanifest.lua')) -or
        (Test-File (Join-Path $dir '__resource.lua'))) {
        [void]$installed.Add([System.IO.Path]::GetFileName($dir))
    }
}
Write-Info "$($installed.Count) resources detected"

function Test-Resource([string] $name) { return $installed.Contains($name) }

$framework = if     (Test-Resource 'qbx_core')    { 'Qbox (qbx_core)' }
             elseif (Test-Resource 'qb-core')     { 'QBCore (qb-core)' }
             elseif (Test-Resource 'es_extended') { 'ESX (es_extended)' }
             else                                 { 'none - standalone mode' }

$inventory = if     (Test-Resource 'ox_inventory') { 'ox_inventory' }
             elseif (Test-Resource 'qb-inventory') { 'qb-inventory' }
             elseif (Test-Resource 'qs-inventory') { 'qs-inventory' }
             elseif (Test-Resource 'es_extended')  { 'ESX default' }
             else                                  { 'none' }

$target = if     (Test-Resource 'ox_target') { 'ox_target' }
          elseif (Test-Resource 'qb-target') { 'qb-target' }
          else                               { 'none' }

$hasOxLib = Test-Resource 'ox_lib'
$hasMysql = Test-Resource 'oxmysql'

Write-Host ''
Write-Host "    Framework : $framework"
Write-Host "    Inventory : $inventory"
Write-Host "    Target    : $target"
Write-Host "    Database  : $(if ($hasMysql) { 'oxmysql' } else { 'none' })"
Write-Host "    ox_lib    : $(if ($hasOxLib) { 'present' } else { 'MISSING' })"
Write-Host ''

if (-not $hasOxLib) {
    Write-Bad 'ox_lib is required and is not installed.'
    Write-Host '         Download: https://github.com/overextended/ox_lib/releases'
    Write-Host "         Extract to $resourcesRoot\ox_lib, then run this again."
    Write-Host ''
    Write-Bad 'Stopping. Nothing was changed.'
    exit 1
}

if ($inventory -eq 'none') {
    Write-Warn 'No inventory detected. Crafting will produce nothing until one is installed.'
}
if (-not $hasMysql) {
    Write-Warn 'oxmysql not detected. The shop works but nothing persists across restarts.'
}
if ($target -eq 'none') {
    Write-Warn 'No target resource. Install ox_target: https://github.com/overextended/ox_target'
}
if ($inventory -ne 'ox_inventory' -and $inventory -ne 'none') {
    Write-Info 'Without ox_inventory the freezer, pantry and melting are unavailable. Everything else works.'
}

# ── install ────────────────────────────────────────────────────
Write-Head 'Installing the resource'

$targetParent = Join-Path $resourcesRoot $ResourcesFolder
$targetPath   = Join-Path $targetParent 'mangonazlet'
$updating     = Test-Dir $targetPath

# Never overwrite a folder that is not ours.
if ($updating) {
    $existingManifest = Join-Path $targetPath 'fxmanifest.lua'
    if (-not (Test-File $existingManifest)) {
        Write-Bad "$targetPath exists but has no fxmanifest.lua."
        Write-Host '         Refusing to overwrite it. Move or delete it, then run this again.'
        exit 1
    }
    if (-not ((Get-Content -LiteralPath $existingManifest -Raw) -match 'mangonazlet')) {
        Write-Bad "$targetPath contains a different resource."
        Write-Host '         Refusing to overwrite it. Move or delete it, then run this again.'
        exit 1
    }
}

if ($PSCmdlet.ShouldProcess($targetPath, $(if ($updating) { 'Update' } else { 'Install' }))) {
    try {
        [void][System.IO.Directory]::CreateDirectory($targetParent)

        $savedConfig = $null
        if ($updating) {
            $existingConfig = Join-Path $targetPath 'config'
            if (Test-Dir $existingConfig) {
                $savedConfig = Join-Path $env:TEMP ('mn-config-' + [Guid]::NewGuid().ToString('N'))
                Invoke-RoboCopy $existingConfig $savedConfig
                Write-Info 'Preserved your existing config\ folder'
            }
        }

        # /PURGE on an update clears files an older version left behind.
        if ($updating) { Invoke-RoboCopy $source $targetPath -Mirror }
        else           { Invoke-RoboCopy $source $targetPath }

        if ($savedConfig) {
            Invoke-RoboCopy $savedConfig (Join-Path $targetPath 'config')
            [System.IO.Directory]::Delete($savedConfig, $true)
            Write-Ok 'Updated, your config was kept'
        }
        elseif ($updating) { Write-Ok 'Updated' }
        else               { Write-Ok "Installed to $targetPath" }
    }
    catch {
        Write-Bad "Copy failed: $($_.Exception.Message)"
        Write-Host ''
        Write-Host '  Common causes:'
        Write-Host '    - the server is running and holds the files open (stop it first)'
        Write-Host '    - this window lacks permission to write there (run as Administrator)'
        Write-Host '    - antivirus is locking the folder'
        exit 1
    }

    try {
        $luaCount = [System.IO.Directory]::GetFiles($targetPath, '*.lua', [System.IO.SearchOption]::AllDirectories).Count
        Write-Info "$luaCount Lua files in place"
    } catch { }
}
else {
    Write-Info "Would install to $targetPath"
}

# ── server.cfg ─────────────────────────────────────────────────
if ($serverCfg) {
    Write-Head 'Updating server.cfg'

    $lines = @(Get-Content -LiteralPath $serverCfg)

    function Test-Ensured([string] $resource) {
        # @() so an empty result still has .Count under Set-StrictMode
        return @($lines | Where-Object {
            $_ -match "^\s*(ensure|start)\s+$([regex]::Escape($resource))\s*$"
        }).Count -gt 0
    }

    $alreadyEnsured = Test-Ensured 'mangonazlet'

    $idxLib = -1; $idxMn = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(ensure|start)\s+ox_lib\s*$')      { $idxLib = $i }
        if ($lines[$i] -match '^\s*(ensure|start)\s+mangonazlet\s*$') { $idxMn  = $i }
    }

    if ($alreadyEnsured) {
        Write-Ok 'mangonazlet is already in server.cfg'

        if ($idxLib -lt 0) {
            Write-Warn "ox_lib has no ensure line. Add 'ensure ox_lib' above 'ensure mangonazlet'."
        } elseif ($idxLib -gt $idxMn) {
            Write-Warn 'ox_lib starts AFTER mangonazlet - the resource will not start.'
            Write-Warn "Move 'ensure ox_lib' above 'ensure mangonazlet' in server.cfg."
        } else {
            Write-Ok 'Start order is correct'
        }
    }
    elseif ($PSCmdlet.ShouldProcess($serverCfg, 'Add ensure lines')) {
        $backup = "$serverCfg.mangonazlet-backup"
        if (-not (Test-File $backup)) {
            [System.IO.File]::Copy($serverCfg, $backup, $false)
            Write-Ok "Backed up to $([System.IO.Path]::GetFileName($backup))"
        }

        $block = @('', '# ---- MangoNazlet ----------------------------------------',
                       '# ox_lib must start before mangonazlet.')
        if (-not (Test-Ensured 'ox_lib')) { $block += 'ensure ox_lib' }
        $block += 'ensure mangonazlet'
        $block += '# ---------------------------------------------------------'

        Add-Content -LiteralPath $serverCfg -Value ($block -join "`r`n")
        Write-Ok 'Added the ensure lines to the end of server.cfg'

        if ($idxLib -ge 0) {
            Write-Info 'ox_lib was already ensured earlier in the file - left as it is'
        }
    }
    else {
        Write-Info "Would add 'ensure mangonazlet' to server.cfg"
    }
}

# ── done ───────────────────────────────────────────────────────
Write-Head 'Done'
Write-Host '  Restart your server, then look for:'
Write-Host ''
Write-Host '    [mangonazlet] framework=... inventory=... database=...' -ForegroundColor DarkGray
Write-Host '    [mangonazlet] ready - 30 products, 18 recipes' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  MangoNazlet registers its own job and items on that first start.'
Write-Host ''
Write-Host '  Then in game, as an admin:' -ForegroundColor Cyan
Write-Host '    /mn:setjob <your server id> 5'
Write-Host ''
Write-Host '  The shop is the mango blip on Vespucci beach.'
Write-Host ''
