# macOS on VMware Workstation (Windows host) — the whole chain

Getting a working macOS guest on VMware Workstation is four separate jobs, and most write-ups cover
one of them. This repo covers the chain end to end: **patch Workstation → obtain a macOS image →
create the VM and install → make the guest actually usable.**

Every part carries an explicit **status**. Parts marked *not yet validated* are checklists built
from documented sources, not procedure that has been watched working here. That distinction is the
entire point of this repo — see below.

| Part | What it covers | Status |
|---|---|---|
| **[1 · Unlocker](part1-unlocker.md)** | Exposing macOS as a guest type. Why the popular unlocker **silently does nothing** on Workstation 26.x, and what to use instead | ✅ **Validated** on 26.0.0.25388281 (26H1) / Windows 11, 2026-07-22 |
| **[2 · Obtaining macOS](part2-obtaining-macos.md)** | Pulling a recovery image from Apple's own servers and converting it to a format Workstation will boot (**VMDK, not ISO**) | ✅ **Validated** 2026-08-11 — 3 versions built; Ventura VMDK **confirmed bootable** to macOS Recovery |
| **[3 · VM creation & install](part3-vm-creation-and-install.md)** | Wizard settings, the version-dropdown trap, the single-socket rule, Disk Utility, the install itself | ✅ **Validated on TWO versions** 2026-08-11 — Ventura 13 (~56 min) and Sequoia 15 (~54 min), with the Setup Assistant differences between them |
| **[4 · Post-install](part4-post-install.md)** | VMware Tools, clipboard, shared folders, and headless **SSH** access | ✅ **Validated** 2026-08-11 — SSH-reachable guest; bash 3.2 / BSD `sed` / no `tac` confirmed |

**No binaries are redistributed here** — no `darwin.iso`, no patched VMware files, no unlocker
release, no macOS image. Everything is fetched from its own maintainer or from Apple.

📋 **[FINDINGS.md](FINDINGS.md)** — every defect and trap hit along the way, with the environment it
was seen in and steps to reproduce it. Twelve so far (one retracted), including two authored here's own verification
script. Reported upstream where the project accepts reports
([BDisp/unlocker#79](https://github.com/BDisp/unlocker/issues/79#issuecomment-5256063426),
[DrDonk/OC4VM#100](https://github.com/DrDonk/OC4VM/issues/100)).

> **All four parts are now validated on hardware.** Every checklist here was replaced with real
> captured output as it was actually run, and the status column above moved in the same commit — so
> what you are reading is what was tested, on the versions named. Where something was *not*
> exercised it says **[unverified]** rather than quietly generalising.
>
> Validated end to end with **Ventura 13.7.8**. Sequoia and Tahoe images were built identically and
> have not been booted.

---

## Does this match what you're seeing?

If any of these is your situation, you're in the right place — they are all the **same single
cause**, explained below:

- **macOS / Apple Mac OS X is missing from the guest operating system list** in VMware Workstation.
- The unlocker **said `Finished!` but nothing happened** — no macOS option, no change at all.
- The unlocker printed **`0 File(s) copied`** over and over while backing up.
- It failed with **`FileNotFoundError`** on
  `SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation`.
- It reported a **blank install path and blank product version** for a VMware that is clearly
  installed.
- **`darwin.iso` never downloaded** — `HTTP Error 404` from `softwareupdate.vmware.com`.
- macOS support **worked, then disappeared after a VMware Workstation update**.
- You are on **Workstation Pro 26.x / 26H1** and every unlocker guide you can find was written for
  version 15.

Running as Administrator, disabling antivirus, re-downloading the unlocker and reinstalling
Workstation will not fix any of them.

## Start here if you already have a problem

**Your unlocker printed `Finished!` and macOS still isn't in the New Virtual Machine wizard.**

Nothing was patched. The widely-circulated **Unlocker 3.0.2** (Dave Parsons, 2018) targets
Workstation 11–15; on 26.x it fails at *every* stage and then **exits reporting success**. That
silent success is the whole problem — there is no error to search for, so the usual next moves
(re-download, run as admin, disable antivirus, reinstall Workstation) are all aimed at the wrong
thing.

| # | What 3.0.2 assumes | What Workstation 26.x does | Symptom |
|---|---|---|---|
| 1 | Registry under `HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\...` | 64-bit now — keys are in the native hive `HKLM\SOFTWARE\VMware, Inc.\...` | Blank install path and version, then `FileNotFoundError` from `OpenKey` |
| 2 | `vmware-vmx.exe` in the install **root** | Moved to the **`x64\` subfolder** (`InstallPath64`) | `0 File(s) copied` — **including the backup**, so there is no rollback either |
| 3 | Tools from `softwareupdate.vmware.com` | Dead post-Broadcom | `HTTP Error 404`, no `darwin.iso` |

**The fix:** the maintained fork, [BDisp/unlocker](https://github.com/BDisp/unlocker) release
**3.1.4**, which reads the native hive, backs up from `x64\`, and falls back to the Broadcom
package feed. Its changelog for 3.1.4 reads *"Fixed Windows registry in the VMware 26H1"* —
[issue #79](https://github.com/BDisp/unlocker/issues/79).

Full console output of both runs on the same machine, minutes apart:
**[part1-evidence.md](part1-evidence.md)**.

## Two scripts, because "Finished!" is not evidence

```powershell
# Before you start — read-only, no admin needed.
# Tells you whether a legacy unlocker would silently no-op on THIS machine.
.\tools\Test-UnlockerPreflight.ps1

# After patching — read-only. Proves the patch actually landed.
.\tools\Test-UnlockerPatch.ps1
```

[`Test-UnlockerPatch.ps1`](tools/Test-UnlockerPatch.ps1) does not trust timestamps alone. Where the
unlocker's `backup-windows\` folder is available it hashes each backed-up original against its
installed counterpart, which is definitive and requires no knowledge of what the patch writes. When
the two signals disagree it says so rather than resolving in favour of the good news — that exact
disagreement (**stock binaries, recent timestamps**) is the signature of a Workstation update having
silently reverted the patch.

Both scripts were written for this repo, after the fact. The 2026-07-22 run used BDisp's own
`win-install.cmd` and manual verification; the scripts exist because the missing preflight check is
what made the first attempt cost an afternoon.

## Credits

The patching work is not mine. This repo is documentation, tooling and evidence around it.

- **[BDisp/unlocker](https://github.com/BDisp/unlocker)** — the maintained fork supporting
  Workstation 11–26H1 / Player 7–25H2. **This is what you should download.**
- **[DrDonk/unlocker](https://github.com/drdonk/unlocker)** — the archived upstream (Dave Parsons).
  Unlocker 3.0.2, the version that fails on 26.x, comes from here. Linked because it is still the
  first result most people find.
- **[DrDonk/recoveryOS](https://github.com/DrDonk/recoveryOS)** — creates virtualisation-ready
  macOS recovery images. Used in [Part 2](part2-obtaining-macos.md).
- **[acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)** — `macrecovery.py`, the
  canonical way to pull recovery images from Apple's servers.

## Scope and caveats

- **Windows hosts only.** Not VMware Fusion, ESXi, or Linux hosts.
- **Apple's macOS EULA permits macOS only on Apple-branded hardware.** Documented here for local
  testing, troubleshooting and UAT. Assess your own position before relying on it.
- A Workstation product update overwrites the patched binaries and silently removes macOS support.
  Re-run `win-install.cmd`, then `Test-UnlockerPatch.ps1`.

## Licence

[MIT](LICENSE), covering the documentation and scripts in this repo only. The linked projects carry
their own licences.
