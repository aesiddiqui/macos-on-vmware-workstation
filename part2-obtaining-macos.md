# Part 2 — Obtaining a macOS installation image

> **STATUS: VALIDATED, 2026-08-11.**
> Three recovery images were downloaded from Apple and converted to VMware VMDK on Windows 11 with
> Workstation Pro 26.0.0.25388281. Everything below is what actually happened, including the parts
> that went wrong.
>
> **Boot confirmed:** the Ventura VMDK, attached as a second SATA disk, booted to the Apple logo and
> on to macOS Recovery, where Disk Utility erased the target disk to APFS. Sequoia and Tahoe were
> produced identically but have **not** been booted yet.
>
> Sections marked **[unverified]** were not exercised.

---

## What you are getting, and from where

Every method here pulls **from Apple's own servers** — the download URLs are `oscdn.apple.com`.
Nothing involves a third-party copy of macOS.

| Artifact | Size | What it is |
|---|---|---|
| **recoveryOS / BaseSystem** | ~700–950 MB | The recovery environment. Boots, then **downloads** the full OS over the network during install. |
| **Full installer** (`Install macOS <name>.app`) | ~12–15 GB | The complete OS. Installs offline. Practically obtainable only from a Mac. |

For a Workstation guest, **recoveryOS is the right path** — small, obtainable from Windows, and the
install pulls the rest itself.

## Format: VMDK, not ISO

`BaseSystem.dmg` cannot be attached to a VMware VM directly, and converting it to `.iso` commonly
produces something Workstation will not boot. **Convert to VMDK and attach it as a disk**, not as a
CD/DVD. Confirmed here: `qemu-img` produced `monolithicSparse` VMDKs, which is the type Workstation
consumes without a conversion prompt.

---

## Prerequisite — `qemu-img`, and the PATH trap

**`qemu-img` is a hard requirement.** [`recoveryOS`](https://github.com/DrDonk/recoveryOS) shells out
to it for every conversion; without it on **PATH** the tool cannot produce a virtual disk. Its README
states this, and it is easy to skim past.

The tool's README suggests Chocolatey or Scoop. Neither was present on this machine. **winget
works and is on stock Windows 11:**

```powershell
winget install --id SoftwareFreedomConservancy.QEMU
```

Installed **QEMU 11.0.50**, GPL-2.0, from `qemu.weilnetz.de` (the official Windows build), to
`C:\Program Files\qemu`. ~150 MB download.

> ### ⚠ The QEMU installer does not add itself to PATH
>
> Measured immediately after a successful install: **neither the machine PATH nor the user PATH
> contained QEMU.** `qemu-img` was present on disk and unreachable by name. recoveryOS requires it
> *on PATH*, so it fails here for a reason that has nothing to do with recoveryOS.
>
> Fix — user PATH, no admin needed, reversible:
>
> ```powershell
> $q = 'C:\Program Files\qemu'
> $u = [Environment]::GetEnvironmentVariable('Path','User')
> if ($u -split ';' -notcontains $q) {
>     [Environment]::SetEnvironmentVariable('Path', $u.TrimEnd(';') + ';' + $q, 'User')
> }
> ```
>
> **Open a new shell afterwards** — an already-running one keeps the old PATH.
>
> Verify:
> ```powershell
> qemu-img --version        # qemu-img version 11.0.50 (v11.0.0-12631-g54e84cdc7a)
> ```

An alternative winget package, `cloudbase.qemu-img`, is a standalone `qemu-img` — but it is pinned
at **version 2.3.0** (QEMU from 2015). Not used here; assume it is too old for a modern DMG until
someone proves otherwise.

---

## Option A — `macrecovery.exe` (recommended: scriptable, and it verifies)

recoveryOS ships a Go port of OpenCore's `macrecovery`, at `windows/amd64/macrecovery.exe`. It is
**fully flag-driven**, which makes it the better path — repeatable, loggable, and it checks its own
download.

```powershell
cd <extracted>\recoveryOS-1.0.1\windows\amd64

.\macrecovery.exe -action download `
                  -board-id Mac-B4831CEBD52A0C4C `
                  -mlb 00000000000000000 `
                  -basename ventura `
                  -outdir . `
                  -board-db ..\..\boards.json
```

It downloads `<basename>.dmg` + `<basename>.chunklist`, then validates the image chunk by chunk and
prints:

```text
Chunk 68 (4022672 bytes)
Image verification complete!
```

That verification step is real value — the interactive menu never surfaced it.

> **Note on `-board-db`:** it defaults to `boards.json` **in the current directory**, but
> `boards.json` ships at the **archive root** while the binaries live in `windows/<arch>\`. Since the
> README tells you to run from the arch folder, the default and the file are in different places. We
> passed the path explicitly and did not test the default — **[unverified]** whether it resolves on
> its own.

### Choosing a board ID

The `-board-id` selects the macOS version. `boards.json` in the archive root is the authoritative
map. A few, as shipped in 1.0.1:

| Board ID | Version |
|---|---|
| `Mac-B4831CEBD52A0C4C` | 13.7.8 (Ventura) |
| `Mac-937A206F2EE63C01` | 15.7.4 (Sequoia) |
| `Mac-E1008331FDC96864` | `latest` |

**Read `boards.json` rather than copying an ID from a blog post — including this one.** It ships
with the tool and is versioned with it.

> **If you are choosing for real hardware:** a Mac's board ID determines the newest macOS it can
> run. A 2017 MacBook Pro (`MacBookPro14,x`) tops out at **Ventura 13.7.x** — Sonoma dropped
> pre-2018 models. But note that **recoveryOS output is a virtual disk, not bootable USB installer
> media**: to reinstall a physical Mac, use Internet Recovery (⌘⌥R) or `softwareupdate
> --fetch-full-installer` + `createinstallmedia` on the Mac itself.

## Option B — the `recoveryOS` interactive menu

The tool's headline interface. It works, and it is **interactive-only**.

```powershell
cd <extracted>\recoveryOS-1.0.1\windows\amd64
.\recoveryOS.exe
```

```text
OC4VM recoveryOS Image Maker
============================
Version 1.0.1-0012c39
(c) David Parsons 2022-2026

Create a recoveryOS virtual image
1. Catalina   2. Big Sur   3. Monterey   4. Ventura
5. Sonoma     6. Sequoia   7. Tahoe      0. Exit
```

Pick a version, then pick a format (`1. VMware VMDK`).

> ### ⚠ Do not pipe input to it — it will spin forever
>
> Run it in a **real console**. When stdin reaches EOF, the menu reader does not exit: it prints
> `Invalid selection. Please try again.` in an unbounded loop and the process must be killed.
>
> Observed here twice. A piped `printf '6\n1\n' | recoveryOS.exe` downloaded the image correctly and
> then hung; a piped `printf '7\n0\n'` likewise downloaded and then spun, consuming CPU until
> `taskkill`. In both cases the **download succeeded and the conversion never ran**, which reads
> exactly like a slow download and cost ten minutes before it was recognised.
>
> This is a defect worth reporting upstream, not a usage error: a menu that loops forever on EOF has
> no way to terminate in any non-interactive context.

If you want automation, use **Option A** and convert with `qemu-img` yourself (below).

## Converting a `.dmg` yourself

What recoveryOS does internally, and what you need after Option A:

```powershell
& "C:\Program Files\qemu\qemu-img.exe" convert -p -O vmdk -o compat6 ventura.dmg ventura.vmdk
```

`-o compat6` produces the VMware-compatible variant; `-p` shows progress (the conversion is not
instant — ~2–3 minutes per image here).

Verify the result:

```powershell
& "C:\Program Files\qemu\qemu-img.exe" info ventura.vmdk
```

```text
file format: vmdk
virtual size: 3 GiB (3221204992 bytes)
create type: monolithicSparse
```

`create type: monolithicSparse` is what you want. If Workstation later offers to *convert* the disk
when you attach it, something is wrong with the format.

## Option C — from a real Mac **[unverified]**

Not exercised here. Only relevant if you want a **full offline installer** and have a Mac.

- `softwareupdate --list-full-installers`
- `softwareupdate --fetch-full-installer --full-installer-version <x.y.z>`
- Build media from `/Applications/Install macOS <name>.app` via `createinstallmedia`, then convert
  as above

---

## Measured results

Three versions, same machine, 2026-08-11. Wall-clock includes download over a domestic connection.

| Version | Board ID | `.dmg` | `.vmdk` on disk | VMDK virtual size |
|---|---|---|---|---|
| **Ventura** 13.7.8 | `Mac-B4831CEBD52A0C4C` | 706,568,592 B (674 MB) | 1,965,948,928 B (1.83 GB) | 3 GiB |
| **Sequoia** 15.x | (menu option 6) | 888,615,275 B (847 MB) | 2,451,439,616 B (2.28 GB) | 3 GiB |
| **Tahoe** 26.x | (menu option 7) | 960,529,096 B (916 MB) | 2,418,147,328 B (2.25 GB) | 2.49 GiB |

**Budget ~10.5 GB** of disk for all three (DMG + VMDK retained). The `.dmg` and `.chunklist` can be
deleted once the VMDK is verified, halving that — keep them if you may want to re-convert without
re-downloading.

## Verification for this part

- [x] Output is a `.vmdk`, non-zero, reported by `qemu-img info` as `vmdk` /
      `monolithicSparse`
- [x] `macrecovery` reports `Image verification complete!` against the chunklist
- [x] Workstation accepts it via **Add Disk → Use an existing virtual disk** with no conversion
      prompt — confirmed on all three
- [x] It boots to macOS Recovery — confirmed on Ventura (`darwin22-64`); Sequoia and Tahoe untested

## Licensing note

Apple's macOS EULA permits macOS only on Apple-branded hardware. These tools download from Apple's
own recovery servers; whether your intended use is permitted is your call. This document covers
local testing, troubleshooting and UAT.

## Sources

- <https://github.com/DrDonk/recoveryOS> — recoveryOS / OC4VM Image Maker, v1.0.1
- <https://github.com/acidanthera/OpenCorePkg> — `Utilities/macrecovery/`, the original
- <https://www.qemu.org/> — `qemu-img`
