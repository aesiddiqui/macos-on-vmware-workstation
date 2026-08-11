# Part 2 — Obtaining a macOS installation image

> **STATUS: NOT YET VALIDATED.**
> This part is a checklist assembled from documented sources, not from a run observed on this
> machine. Steps marked **[verify]** are the ones most likely to need correcting. Each will be
> replaced with captured output once it has actually been run. Do not treat this as tested
> procedure — that is the mistake [Part 1](part1-unlocker.md) exists to warn about.

---

## What you are getting, and from where

Every method below pulls **from Apple's own servers**. Nothing here involves a third-party copy of
macOS.

Two different artifacts are commonly confused:

| Artifact | Size | What it is |
|---|---|---|
| **recoveryOS / BaseSystem** | ~700 MB – 3 GB | The recovery environment. Boots, then **downloads** the full OS over the network during install. |
| **Full installer** (`Install macOS <name>.app`) | ~12–15 GB | The complete OS. Installs offline. Practically obtainable only from a Mac. |

For a Workstation guest, **recoveryOS is the normal path** — smaller, obtainable from Windows, and
the install pulls the rest itself.

## Format: VMDK, not ISO

This is the step most guides get wrong and it costs hours.

`BaseSystem.dmg` **cannot be used directly** by VMware, and converting it to `.iso` commonly yields
something Workstation will not boot — the resulting GPT image is not recognised as bootable.
**Convert to VMDK and attach it as a disk**, not as a CD/DVD.

---

## Option A — `recoveryOS` (recommended)

[DrDonk/recoveryOS](https://github.com/DrDonk/recoveryOS) — same author lineage as the archived
unlocker, and built for exactly this purpose: it downloads the BaseSystem for a chosen macOS
version and converts it to a virtual disk. Output formats include **VMware VMDK**, QCOW2, VHDX and
raw.

- [ ] Download the release from <https://github.com/DrDonk/recoveryOS/releases>
- [ ] Run it, select the target macOS version, select **VMDK** output **[verify]** — confirm the
      exact flag/menu wording
- [ ] Note the output path; you will attach this file in [Part 3](part3-vm-creation-and-install.md)

**Why this is first:** one tool, no separate conversion step, no QEMU install, and the output is
already the format Workstation wants.

## Option B — OpenCore `macrecovery.py` + `qemu-img`

The manual route. More moving parts, but it is the canonical, well-documented method and worth
knowing when Option A misbehaves.

- [ ] Get `macrecovery.py` from
      [`acidanthera/OpenCorePkg`](https://github.com/acidanthera/OpenCorePkg/blob/master/Utilities/macrecovery/macrecovery.py)
      (`Utilities/macrecovery/`)
- [ ] Download the recovery image for your target version:

      ```powershell
      cd <OpenCorePkg>\Utilities\macrecovery
      py -3 macrecovery.py -b <board-id> -m 00000000000000000 download
      ```

      The board-id selects the macOS version. Example for **Sequoia (15)**:
      `-b Mac-937A206F2EE63C01` **[verify]** — confirm against `recovery_urls.txt` in the same
      folder, which is the authoritative version↔board-id table. Do not trust a board-id copied
      from a blog post, including this one.

- [ ] Output lands in a new `com.apple.recovery.boot\` folder containing `BaseSystem.dmg` and
      `BaseSystem.chunklist`
- [ ] Install QEMU for Windows (`qemu-w64-setup-*.exe`, installs to `C:\Program Files\qemu`)
- [ ] Convert to VMDK:

      ```powershell
      & "C:\Program Files\qemu\qemu-img.exe" convert -O vmdk -o compat6 `
          .\com.apple.recovery.boot\BaseSystem.dmg .\recovery.vmdk
      ```

      `-o compat6` matters — it produces the VMware-compatible variant. **[verify]** the resulting
      file opens in Workstation's "use an existing disk" dialog without a conversion prompt.

## Option C — from a real Mac

Only relevant if you have access to a Mac and want a **full offline installer**.

- [ ] `softwareupdate --list-full-installers` to see what is available **[verify]**
- [ ] `softwareupdate --fetch-full-installer --full-installer-version <x.y.z>`
- [ ] Build a bootable image from `/Applications/Install macOS <name>.app` via `hdiutil` +
      `createinstallmedia`, then convert to VMDK as in Option B **[verify]** — the
      `hdiutil`/`createinstallmedia` sequence has several published variants and they are not
      equivalent

---

## Verification for this part

- [ ] The output file is a `.vmdk`, non-zero size, and Workstation accepts it via
      **Add Disk → Use an existing virtual disk** without offering to convert it
- [ ] The macOS version you downloaded is one the patched Workstation's **Version** dropdown can
      actually name (see [Part 3](part3-vm-creation-and-install.md)); a mismatch here is a common
      cause of a non-booting installer

## Licensing note

Apple's macOS EULA permits macOS only on Apple-branded hardware. Downloading from Apple's recovery
servers is what these tools do; whether your intended use is permitted is your call to make. This
document covers local testing, troubleshooting and UAT.

## Sources

- <https://github.com/DrDonk/recoveryOS>
- <https://github.com/acidanthera/OpenCorePkg> — `Utilities/macrecovery/`
- <https://dortania.github.io/OpenCore-Install-Guide/installer-guide/windows-install.html>
