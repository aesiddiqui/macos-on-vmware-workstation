# Runbook — Enabling macOS Guests on VMware Workstation Pro 26.x

**Status:** Validated end-to-end on Workstation Pro **26.0.0.25388281** (26H1), Windows 11,
using [BDisp/unlocker](https://github.com/BDisp/unlocker) release **3.1.4**.

---

## 1. Purpose & scope

VMware Workstation Pro for Windows does not expose **Apple macOS** as a guest operating-system
type, and its virtual SMC controller is not configured to let macOS boot. The community
"unlocker" patches the Workstation binaries to add that capability. This runbook covers applying
it to **Workstation Pro 26.x** (the Broadcom-era, date-based release line), where older unlocker
builds fail because the installation layout changed.

**In scope:**

- Patching Workstation Pro 26.x on Windows to expose macOS as a guest type.
- Installing the macOS `darwin.iso` guest tools alongside the product.
- Verifying the patch and preserving a clean rollback path.

**Out of scope:**

- Obtaining or installing macOS itself. The unlocker enables the capability only; a macOS
  installer image is supplied separately and is not linked here.
- Guest-side macOS configuration, GPU acceleration, Apple ID / iCloud sign-in.
- VMware Fusion (macOS host), ESXi, or Linux hosts.
- Any use beyond local testing, troubleshooting, and UAT — see §4.

## 2. Audience & prerequisites

**Audience:** a Windows operator comfortable with an elevated Command Prompt, Windows services,
and basic registry concepts. No Python knowledge required — the Windows release ships a bundled
interpreter.

**Prerequisites:**

- VMware Workstation Pro 17.x–26.x on a 64-bit Windows host (validated on 26.0.0.25388281,
  Windows 11).
- Local Administrator rights — the patch stops services and writes to
  `C:\Program Files\VMware\...`.
- The unlocker Windows release, from the maintained source (§3.3).
- All virtual machines shut down and VMware fully exited before starting.
- A macOS installer image on hand for the post-patch VM build.

## 3. Background

### 3.1 Problem statement

The original Dave Parsons **Unlocker 3.0.2** (2018) targets Workstation 11–15. On Workstation Pro
26.x it fails at every stage because three aspects of the install changed:

1. **Registry location.** Old Workstation was a 32-bit application, so its keys lived under
   `HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\...`. Modern Workstation is 64-bit; its keys are in the
   native hive `HKLM\SOFTWARE\VMware, Inc.\...`. The old script queries the WoW6432Node path, finds
   nothing, and reports a blank install path.
2. **Binary location.** The patch targets (`vmware-vmx.exe` and derivatives) moved from the install
   root into an `x64\` subfolder (`InstallPath64`). The old script backs up from the root and
   copies zero files — **so there is no rollback either**.
3. **Tools download URL.** The macOS guest-tools feed at `softwareupdate.vmware.com` is dead
   post-Broadcom, returning HTTP 404.

The net effect is an old unlocker that appears to run — it prints `Finished!` — while patching
nothing. A version-drift trap with no error to search for.

The maintained **BDisp** fork (release 3.1.4, 2026-05-16) fixes all three: it reads the native
registry hive, backs up from `x64\`, and falls back to the Broadcom tools feed.

### 3.2 What the patch actually modifies

```
C:\Program Files\VMware\VMware Workstation\
├── vmwarebase.dll            <- GOS patch: exposes "Apple macOS" guest type
└── x64\
    ├── vmware-vmx.exe        <- SMC patch: lets macOS boot
    ├── vmware-vmx-debug.exe  <- SMC patch
    └── vmware-vmx-stats.exe  <- SMC patch
```

- The **SMC patch** writes Apple's `OSK0`/`OSK1` key material into the virtual SMC tables of each
  `vmware-vmx` binary, satisfying the boot-time Apple hardware check.
- The **GOS ("guest OS") patch** flips flags in `vmwarebase.dll` so the New VM wizard lists Apple
  macOS and its versions.
- The unlocker also downloads `darwin.iso` / `darwinPre15.iso` (the macOS VMware Tools) into the
  install directory.

### 3.3 References & sources

- BDisp unlocker (maintained fork): <https://github.com/BDisp/unlocker>
- Registry fix for 26H1: <https://github.com/BDisp/unlocker/issues/79>
- DrDonk unlocker (archived upstream): <https://github.com/drdonk/unlocker>

## 4. Foundational requirements

Cross-cutting rules every step must respect:

- **Licensing boundary.** Apple's EULA permits macOS only on Apple hardware. This procedure is
  documented for local testing, troubleshooting and UAT; it is not a production or distribution
  configuration.
- **Quiesce before patching.** No VM may be running and VMware must be fully exited. Windows locks
  a running `vmware-vmx.exe`, so patching a live install fails with a sharing violation or risks a
  corrupt binary.
- **Preserve rollback.** The unlocker's `backup-windows\` folder is the only clean restore path. Do
  not delete it while the patch is in effect, and do not extract the release to a temp folder.
- **Trust the source.** Download only from the maintained GitHub releases page. Third-party mirrors
  repackage this free tool and some charge for it.
- **Match the version to the layout.** Use a fork that explicitly supports 26.x; an older
  unlocker's byte signatures do not map onto current binaries.

---

## Step 1 — Confirm the Workstation version and install layout

Establish what is actually installed before touching anything. Confirm the native registry hive
holds the key and that the `x64\` binaries and `vmwarebase.dll` exist.

```cmd
reg query "HKLM\SOFTWARE\VMware, Inc.\VMware Workstation" /v ProductVersion
reg query "HKLM\SOFTWARE\VMware, Inc.\VMware Workstation" /v InstallPath
dir "C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe"
dir "C:\Program Files\VMware\VMware Workstation\vmwarebase.dll"
```

Or run [`tools/Test-UnlockerPreflight.ps1`](tools/Test-UnlockerPreflight.ps1), which performs all of
the above plus the legacy-hive check and reports in one pass.

**Verification:** `ProductVersion` returns a 26.x value (e.g. `26.0.0.25388281`), `InstallPath`
resolves, and both binary paths exist. If the query fails under `VMware, Inc.` but the product is
installed, do not proceed with an old unlocker — obtain the maintained fork instead.

## Step 2 — Download the maintained unlocker

Fetch the Windows release from the maintained fork. The Windows bundle ships a packaged Python
interpreter, so no Python install is required.

```text
Download "Unlocker-Windows-3.1.4.zip" from:
  https://github.com/BDisp/unlocker/releases

Extract to a clean, PERSISTENT folder — not a temp path, because the backup lives here:
  %USERPROFILE%\Downloads\unlocker-3.1.4\
```

**Verification:** the extracted folder contains `win-install.cmd`, `win-uninstall.cmd`,
`win-helper-functions.cmd`, `unlocker.exe`, `gettools.exe`, and a `VERSION` file reading `3.1.4`.
Do not reuse a previously extracted older unlocker folder — extract fresh, so old and new patch
logic never mix.

> **Optional but recommended:** open `win-helper-functions.cmd` and confirm it reads
> `HKLM\SOFTWARE\VMware, Inc.\VMware Workstation` (**no** `Wow6432Node`) and backs up from
> `%INSTALLPATH%x64\`. Two minutes here is what distinguishes a version that will work from one
> that will silently no-op.

## Step 3 — Quiesce VMware

Shut down every guest cleanly and exit the VMware UI. Confirm no VMware processes hold the
patch-target binaries open.

```cmd
tasklist | findstr /I "vmware vmx"
```

**Verification:** `vmware.exe` (the UI) and `vmware-vmx.exe` (a running guest) must be absent.
Background services (`vmware-authd.exe`, `vmware-usbarbitrator64.exe`, `vmnetdhcp.exe`) may still
be listed — the installer stops those itself and they do not lock the patch targets.

## Step 4 — Apply the patch (elevated)

Run the installer from an **Administrator** Command Prompt. It detects the install, stops services,
backs up the four binaries, patches them, and pulls the macOS tools.

```cmd
cd /d "%USERPROFILE%\Downloads\unlocker-3.1.4"
win-install.cmd
```

**Verification** — the output must show, in contrast to the failed 3.0.2 run:

- a populated install path and version, **not blank**;
- real files copied during backup, **not** `0 File(s) copied`;
- an SMC table dump for each `vmware-vmx` binary with `OSK0`/`OSK1` **"After"** values written;
- `GOS Patched: ...vmwarebase.dll`;
- a successful tools download;
- `Finished!` with **no Python traceback**.

If it prints `Administrator privileges required!`, the prompt was not elevated.

## Step 5 — Verify the patch landed

Confirm the artifacts were modified and the tools ISOs are in place.

```cmd
dir "C:\Program Files\VMware\VMware Workstation\darwin.iso"
dir "C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe"
dir "%USERPROFILE%\Downloads\unlocker-3.1.4\backup-windows"
```

Or run [`tools/Test-UnlockerPatch.ps1`](tools/Test-UnlockerPatch.ps1).

**Verification:** `darwin.iso` and `darwinPre15.iso` exist in the install directory with today's
timestamp; `vmware-vmx.exe` and `vmwarebase.dll` show a current modified time (they will stand out
against the product's original install date); `backup-windows\` contains the four original binaries
(`vmwarebase.dll` plus `x64\vmware-vmx*.exe`).

## Step 6 — Test end to end

**Pre-flight:**

- VMware services restarted (the installer's final step) or host rebooted.
- `backup-windows\` present and untouched.

**Trigger:** open VMware Workstation and start the **New Virtual Machine** wizard (Custom). Advance
to the **Guest Operating System** selection screen.

**Validation checklist:**

- [ ] **Apple macOS** appears as a selectable guest-OS family.
- [ ] The **Version** dropdown lists macOS releases and can be changed.
- [ ] A macOS VM can be created, selecting the version matching the installer to be used.
- [ ] No VMware crash or core dump occurred on VM creation — see Known issues.

A created macOS VM's `.vmx` should carry `guestOS = "darwin<NN>-64"`; that value is direct proof the
GOS patch took.

---

## Known issues

### VM creation triggers a core dump on Windows

On some Windows builds, creating or first-powering a macOS VM causes VMware to stop with a core
dump.

**Mitigation:** set the VM hardware compatibility to an earlier level, or edit the `.vmx` file and
add `smc.version = "0"`.

### Version dropdown defaults too low for a modern installer

The wizard defaults the macOS version to an older release (e.g. macOS 10.15). Booting a newer macOS
installer against a too-low version can fail.

**Mitigation:** select the dropdown entry matching the macOS you are installing. If it is not
listed, choose the highest available; if boot still fails, add `smc.version = "0"` to the `.vmx`.

### VMware Tools ISO not auto-offered

Some product variants do not surface `darwin.iso` via the Install VMware Tools menu.

**Mitigation:** manually attach `darwin.iso` (in the install directory) to the running macOS
guest's virtual CD/DVD drive.

### A Workstation update reverts the patch

Applying a Workstation product update overwrites the patched binaries with stock versions, removing
macOS support — silently.

**Mitigation:** re-run `win-install.cmd` after the update. To fully revert before updating, run
`win-uninstall.cmd` from the same folder.

---

## Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-07-22 | Use BDisp fork 3.1.4, not the bundled 3.0.2 | 3.0.2 fails on 26.x — WoW6432Node registry, root-folder binaries, dead tools URL — and 3.1.4 fixes all three |
| 2026-07-22 | Do **not** hand-patch 3.0.2's paths | Fixing the three visible failures would still leave 2018-era byte signatures being matched against 2026 binaries. Use the fork that is maintained against current builds |
| 2026-07-22 | Read `win-helper-functions.cmd` against the live machine before running | The failure mode is silent; a pre-run path match is the only cheap way to know the tool can see your install |
| 2026-07-22 | Patch with all VMs down and VMware exited | Windows locks a running `vmware-vmx.exe`; patching live risks a sharing violation or corrupt binary |
| 2026-07-22 | Preserve `backup-windows\`; do not delete | Sole clean rollback path for `win-uninstall.cmd` and post-update recovery |

---

## Appendix A — Old vs. maintained unlocker on Workstation 26.x

| Stage | Unlocker 3.0.2 (2018) | Unlocker 3.1.4 (BDisp) |
|---|---|---|
| Registry lookup | `HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\...` → not found | `HKLM\SOFTWARE\VMware, Inc.\...` → resolves |
| Install path / version reported | blank | `C:\Program Files\VMware\VMware Workstation\` / `26.0.0.25388281` |
| Binary backup | install root → `0 File(s) copied` | `x64\` subfolder → files copied |
| SMC / GOS patch | Python traceback (`OpenKey` fails) | `OSK0`/`OSK1` written to all three vmx binaries; `vmwarebase.dll` GOS flags patched |
| Tools download | `softwareupdate.vmware.com` → HTTP 404 | falls back to `packages-prod.broadcom.com` → both ISOs retrieved |
| Exit message | `Finished!` | `Finished!` |

The last row is the point of this document.
