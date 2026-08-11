<#
.SYNOPSIS
    Read-only verification that a macOS unlocker patch actually landed on VMware Workstation.

.DESCRIPTION
    The unlocker's own "Finished!" is not evidence -- Unlocker 3.0.2 prints it on a run that
    patched nothing. This script checks the install itself.

    Three independent signals, strongest first:

      1. Backup comparison (definitive). If the unlocker's backup-windows\ folder is available,
         hash each backed-up original against its installed counterpart. Different hash means the
         installed binary was genuinely modified. This needs no knowledge of what the patch writes.

      2. Timestamp divergence. Patched binaries carry a write time that stands apart from the rest
         of the product's files, which all share the original install date.

      3. Guest tools. darwin.iso / darwinPre15.iso present in the install directory.

    This script only READS. It does not modify anything, and does not require Administrator
    rights (though hashing files under Program Files may need read access that a standard user
    already has).

.PARAMETER BackupPath
    Path to the unlocker's backup-windows folder. If omitted, common locations are searched.

.EXAMPLE
    .\Test-UnlockerPatch.ps1

.EXAMPLE
    .\Test-UnlockerPatch.ps1 -BackupPath "$env:USERPROFILE\Downloads\unlocker-3.1.4\backup-windows"

.OUTPUTS
    Exit 0 - patch verified present
    Exit 1 - VMware Workstation not found
    Exit 2 - patch NOT detected, or evidence inconclusive

.LINK
    https://github.com/BDisp/unlocker
#>
[CmdletBinding()]
param(
    [string]$BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$NativeKey = 'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation'
$LegacyKey = 'HKLM:\SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation'

function Write-Head { param([string]$Text) Write-Host ''; Write-Host $Text -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  [ OK ] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Note { param([string]$Text) Write-Host "         $Text" -ForegroundColor DarkGray }

function Get-InstallRoot {
    foreach ($k in @($NativeKey, $LegacyKey)) {
        if (Test-Path -LiteralPath $k) {
            try {
                $p = (Get-ItemProperty -Path $k -Name 'InstallPath' -ErrorAction Stop).InstallPath
                if ($p) { return $p.TrimEnd('\') }
            } catch { }
        }
    }
    return $null
}

Write-Host 'VMware Workstation - macOS unlocker patch verification (read-only)' -ForegroundColor White
Write-Host '==================================================================' -ForegroundColor White

$root = Get-InstallRoot
if (-not $root) {
    Write-Bad 'VMware Workstation not found in the registry.'
    exit 1
}
Write-Note "Install root: $root"

# Resolve the patch targets wherever they live.
$x64Dir = Join-Path $root 'x64'
$targets = @()
foreach ($n in @('vmware-vmx.exe', 'vmware-vmx-debug.exe', 'vmware-vmx-stats.exe')) {
    $inX64  = Join-Path $x64Dir $n
    $inRoot = Join-Path $root   $n
    if (Test-Path -LiteralPath $inX64)       { $targets += [pscustomobject]@{ Name = "x64\$n"; Path = $inX64 } }
    elseif (Test-Path -LiteralPath $inRoot)  { $targets += [pscustomobject]@{ Name = $n;       Path = $inRoot } }
}
$baseDll = Join-Path $root 'vmwarebase.dll'
if (Test-Path -LiteralPath $baseDll) { $targets += [pscustomobject]@{ Name = 'vmwarebase.dll'; Path = $baseDll } }

if ($targets.Count -eq 0) {
    Write-Bad 'No patch-target binaries found.'
    exit 2
}

# Each signal records its own verdict. They are NOT pooled: the backup comparison is
# authoritative and a positive from a weaker signal must never override its negative.
$backupVerdict = 'inconclusive'
$timeVerdict   = 'inconclusive'

# --- 1. Backup comparison (definitive) ---------------------------------------------------------
Write-Head '1. Backup comparison (definitive)'

if (-not $BackupPath) {
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Documents')
    )
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        $hit = Get-ChildItem -LiteralPath $c -Directory -Filter 'backup-windows' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $BackupPath = $hit.FullName; break }
    }
}

if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
    Write-Note "Backup folder: $BackupPath"
    $compared = 0; $differs = 0
    foreach ($t in $targets) {
        $rel = $t.Name
        $bak = Join-Path $BackupPath $rel
        if (-not (Test-Path -LiteralPath $bak)) { continue }
        $compared++
        $hInst = (Get-FileHash -LiteralPath $t.Path -Algorithm SHA256).Hash
        $hBak  = (Get-FileHash -LiteralPath $bak    -Algorithm SHA256).Hash
        if ($hInst -ne $hBak) {
            $differs++
            Write-Ok "$rel differs from its backed-up original (modified)"
        } else {
            Write-Bad "$rel is byte-identical to its backup (NOT patched)"
        }
    }
    if ($compared -eq 0) {
        Write-Warn 'Backup folder found but contained no matching originals.'
        $backupVerdict = 'inconclusive'
    } elseif ($differs -eq $compared) {
        $backupVerdict = 'patched'
    } elseif ($differs -eq 0) {
        $backupVerdict = 'unpatched'
    } else {
        Write-Warn "Mixed: $differs of $compared modified - a partial or reverted patch."
        $backupVerdict = 'partial'
    }
} else {
    Write-Note 'No backup-windows folder located; skipping the definitive check.'
    Write-Note 'Pass -BackupPath to enable it. Keeping that folder IS your rollback path.'
    $backupVerdict = 'inconclusive'
}

# --- 2. Timestamp divergence -------------------------------------------------------------------
Write-Head '2. Timestamp divergence'

# Baseline: the modal write-date of the product's other binaries.
$others = Get-ChildItem -LiteralPath $root -File -Include '*.dll', '*.exe' -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -ne 'vmwarebase.dll' }
if (-not $others -or $others.Count -eq 0) {
    $others = Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue
}

if ($others -and $others.Count -gt 0) {
    $baseline = ($others | Group-Object { $_.LastWriteTime.Date } |
                 Sort-Object Count -Descending | Select-Object -First 1).Name
    Write-Note "Product baseline write-date: $baseline (from $($others.Count) files)"

    $diverged = 0
    foreach ($t in $targets) {
        $d = (Get-Item -LiteralPath $t.Path).LastWriteTime
        if ($d.Date.ToString() -ne $baseline) {
            $diverged++
            Write-Ok "$($t.Name) -> $($d.ToString('yyyy-MM-dd HH:mm')) (diverges from baseline)"
        } else {
            Write-Note "$($t.Name) -> $($d.ToString('yyyy-MM-dd HH:mm')) (matches baseline)"
        }
    }
    if ($diverged -eq $targets.Count) { $timeVerdict = 'patched' }
    elseif ($diverged -eq 0)          { $timeVerdict = 'unpatched' }
    else                              { $timeVerdict = 'partial' }
} else {
    Write-Warn 'Could not establish a baseline from the install directory.'
    $timeVerdict = 'inconclusive'
}

# --- 3. Guest tools ----------------------------------------------------------------------------
Write-Head '3. macOS guest tools'

$isoFound = 0
foreach ($iso in @('darwin.iso', 'darwinPre15.iso')) {
    $p = Join-Path $root $iso
    if (Test-Path -LiteralPath $p) {
        $isoFound++
        Write-Ok "$iso present ($((Get-Item -LiteralPath $p).LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
    } else {
        Write-Warn "$iso absent"
    }
}
if ($isoFound -eq 0) {
    Write-Note 'Guest tools were not retrieved. On a legacy unlocker this is the HTTP 404 symptom.'
}

# --- Verdict -----------------------------------------------------------------------------------
Write-Head 'Verdict'

# Signal 1 is authoritative. Signal 2 only decides when signal 1 could not.
# Disagreement is REPORTED, never silently resolved in favour of the positive -- a stock
# binary with a recent timestamp is exactly what a Workstation update leaves behind.
if ($backupVerdict -ne 'inconclusive' -and $timeVerdict -ne 'inconclusive' -and
    $backupVerdict -ne $timeVerdict) {
    Write-Warn "Signals DISAGREE - backup says '$backupVerdict', timestamps say '$timeVerdict'."
    if ($backupVerdict -eq 'unpatched' -and $timeVerdict -eq 'patched') {
        Write-Note 'Most likely cause: a VMware Workstation product update replaced the patched'
        Write-Note 'binaries with stock ones, giving them a fresh write time. The patch is GONE.'
        Write-Note 'Re-run win-install.cmd.'
    } else {
        Write-Note 'The backup comparison is the reliable one; treat it as the answer.'
    }
}

$final = $backupVerdict
if ($final -eq 'inconclusive') { $final = $timeVerdict }

switch ($final) {
    'partial' {
        Write-Host '  PARTIAL - some targets modified, some not. Re-run win-install.cmd.' -ForegroundColor Yellow
        exit 2
    }
    'patched' {
        Write-Host '  PATCHED - the unlocker modified this install.' -ForegroundColor Green
        if ($isoFound -lt 2) {
            Write-Note 'Guest tools are incomplete; win-update-tools.cmd retrieves them.'
        }
        Write-Note 'Confirm end to end: New Virtual Machine wizard should offer Apple macOS.'
        exit 0
    }
    'unpatched' {
        Write-Host '  NOT PATCHED - this install is stock, whatever the unlocker reported.' -ForegroundColor Red
        Write-Note 'See RUNBOOK.md. Use https://github.com/BDisp/unlocker for Workstation 26.x.'
        exit 2
    }
    default {
        Write-Host '  INCONCLUSIVE - no backup to compare against and no timestamp signal.' -ForegroundColor Yellow
        Write-Note 'Definitive test: open the New Virtual Machine wizard and look for Apple macOS.'
        exit 2
    }
}
