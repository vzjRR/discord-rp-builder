<#
.SYNOPSIS
    Installs MangoNazlet into a FiveM server.

.DESCRIPTION
    Does the whole install on your machine:
      1. Verifies the target really is a FiveM server.
      2. Audits what the server already runs (framework, inventory, target, database).
      3. Copies the resource into resources\[jobs]\mangonazlet.
      4. Backs up server.cfg and adds the ensure lines in the correct order.
      5. Reports what it found and what it changed.

    Safe to run more than once: it updates an existing install rather than
    duplicating it, and never adds a server.cfg line twice.

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

# -Depth on Get-ChildItem needs PowerShell 5.0. Windows 10 and 11 ship 5.1,
# so this only bites on something quite old.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host ''
    Write-Host "  This installer needs PowerShell 5.0 or newer." -ForegroundColor Red
    Write-Host "  You are on $($PSVersionTable.PSVersion)."
    Write-Host "  Install the resource manually instead - see INSTALLATION.md."
    exit 1
}

# ── output helpers ─────────────────────────────────────────────
function Write-Head($text) {
    Write-Host ''
    Write-Host "  $text" -ForegroundColor Yellow
    Write-Host "  $('-' * $text.Length)" -ForegroundColor DarkYellow
}
function Write-Ok($text)   { Write-Host "  [ ok ] $text"   -ForegroundColor Green }
function Write-Info($text) { Write-Host "  [ .. ] $text"   -ForegroundColor Gray }
function Write-Warn($text) { Write-Host "  [warn] $text"   -ForegroundColor Yellow }
function Write-Bad($text)  { Write-Host "  [fail] $text"   -ForegroundColor Red }

Write-Host ''
Write-Host '  MangoNazlet installer' -ForegroundColor Magenta
Write-Host '  =====================' -ForegroundColor Magenta

# ── locate the resource next to this script ────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source    = Join-Path $scriptDir 'mangonazlet'

if (-not (Test-Path (Join-Path $source 'fxmanifest.lua'))) {
    Write-Bad "Could not find the resource next to this script."
    Write-Host ''
    Write-Host "  Expected: $source\fxmanifest.lua"
    Write-Host "  Keep Install-MangoNazlet.ps1 in the same folder as the"
    Write-Host "  'mangonazlet' folder and run it again."
    exit 1
}
Write-Ok "Found the resource to install"

# ── verify the target is a FiveM server ────────────────────────
Write-Head 'Checking the server folder'

if (-not (Test-Path $ServerPath)) {
    Write-Bad "$ServerPath does not exist."
    Write-Host ''
    Write-Host "  Point the installer at your server folder, for example:"
    Write-Host "    .\Install-MangoNazlet.ps1 -ServerPath 'D:\my-server'"
    exit 1
}
Write-Ok "Server folder: $ServerPath"

# resources\ can sit at the root or one level down (txAdmin layouts vary)
$resourcesRoot = $null
foreach ($candidate in @(
    (Join-Path $ServerPath 'resources'),
    (Join-Path $ServerPath 'server-data\resources'),
    (Join-Path $ServerPath 'txData\resources')
)) {
    if (Test-Path $candidate) { $resourcesRoot = $candidate; break }
}

if (-not $resourcesRoot) {
    # txAdmin keeps each deployment under txData\<name>\resources
    $txData = Join-Path $ServerPath 'txData'
    if (Test-Path $txData) {
        $found = Get-ChildItem $txData -Directory -ErrorAction SilentlyContinue |
                 ForEach-Object { Join-Path $_.FullName 'resources' } |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($found) { $resourcesRoot = $found }
    }
}

if (-not $resourcesRoot) {
    Write-Bad "No 'resources' folder found under $ServerPath"
    Write-Host ''
    Write-Host "  This does not look like a FiveM server folder. Look for the"
    Write-Host "  folder that contains 'resources' and 'server.cfg', and pass it:"
    Write-Host "    .\Install-MangoNazlet.ps1 -ServerPath '<that folder>'"
    exit 1
}
Write-Ok "Resources: $resourcesRoot"

# server.cfg lives beside resources, or at the server root
$serverCfg = $null
foreach ($candidate in @(
    (Join-Path (Split-Path -Parent $resourcesRoot) 'server.cfg'),
    (Join-Path $ServerPath 'server.cfg')
)) {
    if (Test-Path $candidate) { $serverCfg = $candidate; break }
}

if ($serverCfg) { Write-Ok "server.cfg: $serverCfg" }
else            { Write-Warn "No server.cfg found - you will have to add the ensure lines yourself" }

# ── audit what the server already runs ─────────────────────────
Write-Head 'Auditing your server'

# A resource is any folder holding a manifest. They nest inside [bracket]
# folders, sometimes more than one deep, so walk three levels of directories.
# Case-insensitive: Windows folder names are, and a server with 'OX_lib' must
# not be told ox_lib is missing.
$installed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

$candidates = @(Get-ChildItem $resourcesRoot -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue)
foreach ($dir in $candidates) {
    if ((Test-Path (Join-Path $dir.FullName 'fxmanifest.lua')) -or
        (Test-Path (Join-Path $dir.FullName '__resource.lua'))) {
        [void]$installed.Add($dir.Name)
    }
}
Write-Info "$($installed.Count) resources detected"

function Test-Resource($name) { return $installed.Contains($name) }

$framework = if     (Test-Resource 'qbx_core')     { 'Qbox (qbx_core)' }
             elseif (Test-Resource 'qb-core')      { 'QBCore (qb-core)' }
             elseif (Test-Resource 'es_extended')  { 'ESX (es_extended)' }
             else                                  { 'none - standalone mode' }

$inventory = if     (Test-Resource 'ox_inventory') { 'ox_inventory' }
             elseif (Test-Resource 'qb-inventory') { 'qb-inventory' }
             elseif (Test-Resource 'qs-inventory') { 'qs-inventory' }
             elseif (Test-Resource 'es_extended')  { 'ESX default' }
             else                                  { 'none' }

$target    = if     (Test-Resource 'ox_target')    { 'ox_target' }
             elseif (Test-Resource 'qb-target')    { 'qb-target' }
             else                                  { 'none' }

$hasOxLib  = Test-Resource 'ox_lib'
$hasMysql  = (Test-Resource 'oxmysql')

Write-Host ''
Write-Host "    Framework : $framework"
Write-Host "    Inventory : $inventory"
Write-Host "    Target    : $target"
Write-Host "    Database  : $(if ($hasMysql) { 'oxmysql' } else { 'none' })"
Write-Host "    ox_lib    : $(if ($hasOxLib) { 'present' } else { 'MISSING' })"
Write-Host ''

$blocked = $false

if (-not $hasOxLib) {
    Write-Bad "ox_lib is required and is not installed."
    Write-Host "         Get it from https://github.com/overextended/ox_lib/releases"
    Write-Host "         Extract to $resourcesRoot\ox_lib, then run this installer again."
    $blocked = $true
}
if ($inventory -eq 'none') {
    Write-Warn "No inventory detected. Crafting will produce nothing until one is installed."
}
if (-not $hasMysql) {
    Write-Warn "oxmysql not detected. The shop will work but nothing will persist across restarts."
}
if ($target -eq 'none') {
    Write-Warn "No target resource. ox_target is recommended: https://github.com/overextended/ox_target"
}
if ($inventory -ne 'ox_inventory' -and $inventory -ne 'none') {
    Write-Info "Without ox_inventory the freezer, pantry and melting are unavailable. Everything else works."
}

if ($blocked) {
    Write-Host ''
    Write-Bad "Stopping - install ox_lib first. Nothing was changed."
    exit 1
}

# ── copy the resource ──────────────────────────────────────────
Write-Head 'Installing the resource'

$targetParent = Join-Path $resourcesRoot $ResourcesFolder
$targetPath   = Join-Path $targetParent 'mangonazlet'
$updating     = Test-Path $targetPath

if ($PSCmdlet.ShouldProcess($targetPath, $(if ($updating) { 'Update' } else { 'Install' }))) {
    if (-not (Test-Path $targetParent)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Write-Info "Created $targetParent"
    }

    try {
        if ($updating) {
            # Keep the operator's edited config files; replace only the code.
            $keep = Join-Path $env:TEMP ("mangonazlet-config-" + [Guid]::NewGuid().ToString('N'))
            $existingConfig = Join-Path $targetPath 'config'
            if (Test-Path $existingConfig) {
                Copy-Item $existingConfig $keep -Recurse -Force
                Write-Info "Preserved your existing config\ folder"
            }

            # Stage the new copy beside the old one, then swap. A failure part
            # way through leaves the working install untouched rather than
            # half-deleted.
            $staging = "$targetPath.new"
            if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
            Copy-Item $source $staging -Recurse -Force

            if (Test-Path $keep) {
                Copy-Item (Join-Path $keep '*') (Join-Path $staging 'config') -Recurse -Force
                Remove-Item $keep -Recurse -Force
            }

            $retired = "$targetPath.old"
            if (Test-Path $retired) { Remove-Item $retired -Recurse -Force }
            Move-Item $targetPath $retired -Force
            Move-Item $staging $targetPath -Force
            Remove-Item $retired -Recurse -Force

            Write-Ok $(if (Test-Path (Join-Path $targetPath 'config')) {
                'Updated, your config was kept' } else { 'Updated' })
        } else {
            Copy-Item $source $targetPath -Recurse -Force
            Write-Ok "Installed to $targetPath"
        }
    }
    catch {
        Write-Bad "Copy failed: $($_.Exception.Message)"
        Write-Host ''
        Write-Host "  Common causes:"
        Write-Host "    - the server is running and has the files open (stop it first)"
        Write-Host "    - this window is not running as a user that can write there"
        Write-Host "    - antivirus is holding the folder"
        Write-Host ''
        Write-Host "  Your previous install, if any, was left in place."
        exit 1
    }

    $luaCount = @(Get-ChildItem $targetPath -Recurse -Filter '*.lua' -ErrorAction SilentlyContinue).Count
    Write-Info "$luaCount Lua files in place"
} else {
    Write-Info "Would install to $targetPath"
}

# ── patch server.cfg ───────────────────────────────────────────
if ($serverCfg) {
    Write-Head 'Updating server.cfg'

    $lines = @(Get-Content $serverCfg)

    # Which ensure lines are already there?
    function Test-Ensured($resource) {
        # @() so an empty result is still an array - .Count on $null throws
        # under Set-StrictMode.
        return @($lines | Where-Object {
            $_ -match "^\s*(ensure|start)\s+$([regex]::Escape($resource))\s*$"
        }).Count -gt 0
    }

    $alreadyEnsured = Test-Ensured 'mangonazlet'

    # Work these out once, up front: both branches below read them.
    $idxLib = -1; $idxMn = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*(ensure|start)\s+ox_lib\s*$')      { $idxLib = $i }
        if ($lines[$i] -match '^\s*(ensure|start)\s+mangonazlet\s*$') { $idxMn  = $i }
    }

    if ($alreadyEnsured) {
        Write-Ok "mangonazlet is already in server.cfg"

        # Ordering still has to be right: ox_lib must come first.
        if ($idxLib -ge 0 -and $idxMn -ge 0 -and $idxLib -gt $idxMn) {
            Write-Warn "ox_lib is started AFTER mangonazlet - the resource will not start."
            Write-Warn "Move 'ensure ox_lib' above 'ensure mangonazlet' in server.cfg."
        } elseif ($idxLib -lt 0) {
            Write-Warn "ox_lib has no ensure line in server.cfg. Add 'ensure ox_lib' above mangonazlet."
        } else {
            Write-Ok "Start order is correct"
        }
    }
    elseif ($PSCmdlet.ShouldProcess($serverCfg, 'Add ensure lines')) {
        $backup = "$serverCfg.mangonazlet-backup"
        if (-not (Test-Path $backup)) {
            Copy-Item $serverCfg $backup -Force
            Write-Ok "Backed up to $(Split-Path -Leaf $backup)"
        }

        $block = @()
        $block += ''
        $block += '# ---- MangoNazlet ----------------------------------------'
        $block += '# ox_lib must start before mangonazlet.'
        if (-not (Test-Ensured 'ox_lib')) { $block += 'ensure ox_lib' }
        $block += 'ensure mangonazlet'
        $block += '# ---------------------------------------------------------'

        Add-Content -Path $serverCfg -Value ($block -join "`r`n")
        Write-Ok "Added the ensure lines to the end of server.cfg"

        if ($idxLib -ge 0) {
            Write-Info "ox_lib was already ensured earlier in the file - left as it is"
        }
    }
    else {
        Write-Info "Would add 'ensure mangonazlet' to server.cfg"
    }
}

# ── done ───────────────────────────────────────────────────────
Write-Head 'Done'

Write-Host "  Restart your server, then watch the console for:"
Write-Host ''
Write-Host "    [mangonazlet] MangoNazlet v1.0.0 starting" -ForegroundColor DarkGray
Write-Host "    [mangonazlet] framework=... inventory=... database=..." -ForegroundColor DarkGray
Write-Host "    [mangonazlet] ready - 30 products, 18 recipes" -ForegroundColor DarkGray
Write-Host ''
Write-Host "  MangoNazlet registers its own job and items on that first start."
Write-Host "  There is nothing else for you to edit."
Write-Host ''
Write-Host "  Then, in game as an admin:" -ForegroundColor Cyan
Write-Host "    /mn:setjob <your server id> 5     put yourself on as Owner"
Write-Host ''
Write-Host "  The shop is the mango blip on Vespucci beach."
Write-Host "  If anything sits in the wrong place, /mn:place moves it - see"
Write-Host "  mangonazlet\docs\admin.md"
Write-Host ''
