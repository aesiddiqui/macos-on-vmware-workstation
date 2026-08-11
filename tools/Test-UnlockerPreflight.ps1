<#
.SYNOPSIS
    Read-only preflight for applying a macOS unlocker to VMware Workstation on Windows.

.DESCRIPTION
    Reports the installed Workstation version and install layout, and answers the one question
    that the unlocker itself will not tell you: whether a legacy (pre-26.x) unlocker would
    silently do nothing on this machine.

    Legacy Unlocker 3.0.2 reads HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\... and patches binaries
    in the install ROOT. Workstation 26.x keeps its keys in the native hive and its binaries in
    an x64\ subfolder. When those assumptions miss, 3.0.2 prints its failures but still exits
    "Finished!" -- so the operator is told the job succeeded on an untouched install.

    This script only READS. It does not modify the registry, the filesystem, or any service.
    Administrator rights are not required.

.EXAMPLE
    .\Test-UnlockerPreflight.ps1

.OUTPUTS
    Exit 0 - ready to patch (or already patched)
    Exit 1 - VMware Workstation not found
    Exit 2 - found, but blocked (VMware running, or expected files missing)

.LINK
    https://github.com/BDisp/unlocker
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$NativeKey = 'HKLM:\SOFTWARE\VMware, Inc.\VMware Workstation'
$LegacyKey = 'HKLM:\SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation'

function Write-Head { param([string]$Text) Write-Host ''; Write-Host $Text -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host "  [ OK ] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string]$Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Note { param([string]$Text) Write-Host "         $Text" -ForegroundColor DarkGray }

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name }
    catch { return $null }
}

Write-Host 'VMware Workstation - macOS unlocker preflight (read-only)' -ForegroundColor White
Write-Host '=========================================================' -ForegroundColor White

# --- 1. Registry -------------------------------------------------------------------------------
Write-Head '1. Registry'

$nativeFound = Test-Path -LiteralPath $NativeKey
$legacyFound = Test-Path -LiteralPath $LegacyKey

if (-not $nativeFound -and -not $legacyFound) {
    Write-Bad 'VMware Workstation not found in either registry hive.'
    Write-Note 'Checked: HKLM\SOFTWARE\VMware, Inc.\VMware Workstation'
    Write-Note '         HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation'
    Write-Note 'Is Workstation installed? Player and Workstation register separately.'
    exit 1
}

$productVersion = $null
$installPath    = $null
$installPath64  = $null

if ($nativeFound) {
    Write-Ok "Native hive present: $NativeKey"
    $productVersion = Get-RegValue -Path $NativeKey -Name 'ProductVersion'
    $installPath    = Get-RegValue -Path $NativeKey -Name 'InstallPath'
    $installPath64  = Get-RegValue -Path $NativeKey -Name 'InstallPath64'
} else {
    Write-Warn "Native hive NOT present; only the legacy WoW6432Node hive was found."
    $productVersion = Get-RegValue -Path $LegacyKey -Name 'ProductVersion'
    $installPath    = Get-RegValue -Path $LegacyKey -Name 'InstallPath'
}

if ($legacyFound) {
    Write-Note "Legacy hive also present: $LegacyKey"
} else {
    Write-Note 'Legacy hive absent - this is normal on modern (64-bit) Workstation.'
}

if ($productVersion) { Write-Ok "ProductVersion : $productVersion" }
else                 { Write-Warn 'ProductVersion could not be read.' }

if ($installPath)   { Write-Ok "InstallPath    : $installPath" }
if ($installPath64) { Write-Ok "InstallPath64  : $installPath64" }
else                { Write-Note 'InstallPath64 not set - older layout, binaries live in the install root.' }

if (-not $installPath) {
    Write-Bad 'InstallPath is empty; cannot continue.'
    exit 2
}

$root = $installPath.TrimEnd('\')

# --- 2. Binary layout --------------------------------------------------------------------------
Write-Head '2. Patch-target layout'

$vmxNames = @('vmware-vmx.exe', 'vmware-vmx-debug.exe', 'vmware-vmx-stats.exe')
$x64Dir   = Join-Path $root 'x64'
$vmxInX64 = 0
$vmxInRoot = 0

foreach ($n in $vmxNames) {
    if (Test-Path -LiteralPath (Join-Path $x64Dir $n)) { $vmxInX64++ }
    if (Test-Path -LiteralPath (Join-Path $root   $n)) { $vmxInRoot++ }
}

$baseDll = Join-Path $root 'vmwarebase.dll'
$baseDllFound = Test-Path -LiteralPath $baseDll

if ($vmxInX64 -gt 0) { Write-Ok "vmware-vmx binaries in x64\ : $vmxInX64 of $($vmxNames.Count)" }
if ($vmxInRoot -gt 0) { Write-Ok "vmware-vmx binaries in root : $vmxInRoot of $($vmxNames.Count)" }
if ($vmxInX64 -eq 0 -and $vmxInRoot -eq 0) {
    Write-Bad 'No vmware-vmx binaries found in either location.'
    exit 2
}
if ($baseDllFound) { Write-Ok 'vmwarebase.dll present in install root' }
else               { Write-Warn 'vmwarebase.dll NOT found - the GOS patch target is missing.' }

# --- 3. The silent-no-op verdict ---------------------------------------------------------------
Write-Head '3. Would a legacy unlocker (3.0.2) work here?'

$legacyWouldFail = @()
if (-not $legacyFound) { $legacyWouldFail += 'it reads the WoW6432Node hive, which does not exist on this machine' }
if ($vmxInRoot -eq 0)  { $legacyWouldFail += 'it backs up and patches from the install root, but the binaries are in x64\' }

if ($legacyWouldFail.Count -gt 0) {
    Write-Bad 'NO - a legacy unlocker would fail here, and would still print "Finished!".'
    foreach ($r in $legacyWouldFail) { Write-Note "- $r" }
    Write-Note '- its guest-tools feed (softwareupdate.vmware.com) is dead post-Broadcom (HTTP 404)'
    Write-Host ''
    Write-Host '  Use the maintained fork: https://github.com/BDisp/unlocker/releases' -ForegroundColor Yellow
} else {
    Write-Ok 'A legacy unlocker MIGHT work here (old-style layout detected).'
    Write-Note 'The maintained fork is still the safer choice: https://github.com/BDisp/unlocker'
}

# --- 4. Quiesce state --------------------------------------------------------------------------
Write-Head '4. Is VMware quiesced?'

$blockers = @()
foreach ($p in @('vmware', 'vmware-vmx')) {
    $proc = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($proc) { $blockers += "$p (PID $($proc.Id -join ', '))" }
}

if ($blockers.Count -gt 0) {
    Write-Bad 'VMware is running - the patch targets are locked.'
    foreach ($b in $blockers) { Write-Note "- $b" }
    Write-Note 'Shut down every guest cleanly and exit the VMware UI before patching.'
} else {
    Write-Ok 'vmware.exe and vmware-vmx.exe are not running.'
    Write-Note 'Background services (vmware-authd, vmnetdhcp, usbarbitrator) are fine - the installer stops those itself.'
}

# --- 5. Already patched? -----------------------------------------------------------------------
Write-Head '5. Current patch state'

$darwinIso = Join-Path $root 'darwin.iso'
if (Test-Path -LiteralPath $darwinIso) {
    Write-Ok "darwin.iso present ($((Get-Item -LiteralPath $darwinIso).LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
    Write-Note 'Guest tools are in place. Run Test-UnlockerPatch.ps1 for a full verification.'
} else {
    Write-Note 'darwin.iso absent - guest tools not yet retrieved (expected before patching).'
}

# --- Summary -----------------------------------------------------------------------------------
Write-Head 'Summary'
if ($blockers.Count -gt 0) {
    Write-Host '  BLOCKED - quiesce VMware, then re-run.' -ForegroundColor Yellow
    exit 2
}
Write-Host '  READY - see RUNBOOK.md step 2 onwards.' -ForegroundColor Green
exit 0
