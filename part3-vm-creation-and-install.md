# Part 3 — Creating the VM and installing macOS

> **STATUS: VALIDATED, 2026-08-11.**
> macOS **Ventura 13** installed end to end on VMware Workstation Pro **26.0.0.25388281** (26H1),
> Windows 11 host, from a recoveryOS VMDK built in [Part 2](part2-obtaining-macos.md). Reached the
> desktop in **~56 minutes**. Everything below is what happened, including three things our own
> earlier draft got wrong.
>
> Validated on **Ventura only**. Sequoia and Tahoe VMs were configured identically and **have not
> been booted**; details may differ on newer releases.

**Prerequisites:** [Part 1](part1-unlocker.md) complete (`tools/Test-UnlockerPatch.ps1` reports
PATCHED) and a `.vmdk` recovery disk from [Part 2](part2-obtaining-macos.md).

---

## The configuration that worked

| Setting | Value | Notes |
|---|---|---|
| Guest OS | Apple macOS | |
| Version | **match the image** — see table below | The most common cause of a non-booting installer |
| Firmware | **EFI** | Automatic for macOS guests |
| **Processors** | **1 socket × 4 cores** | See the single-socket trap below |
| Memory | **4096 MB** | Genuinely sufficient — see Measured results |
| Hard disk (target) | **SATA, 80 GB**, single file, not pre-allocated | Thin; the VM folder reached **31 GB** on the host after install + Tools + one snapshot |
| Recovery disk | **SATA**, *Use an existing virtual disk* | A second **hard disk**, never a CD/DVD |
| Network | **NAT** | Required — the installer downloads the OS |
| Installer media | **"I will install the operating system later"** | |

### Version and guestOS mapping

VMware's `guestOS` string is the **Darwin** version, not the macOS marketing number. That
off-by-one is what makes the Version dropdown so easy to get wrong.

| Image | macOS | Wizard | `.vmx` should read |
|---|---|---|---|
| `ventura.vmdk` | 13 Ventura | macOS 13 | `darwin22-64` |
| `sequoia.vmdk` | 15 Sequoia | macOS 15 | `darwin24-64` |
| `tahoe.vmdk` | 26 Tahoe | macOS 26 | `darwin25-64` |

**Verify after creating the VM, before powering on** — read the `.vmx` and confirm `guestOS`,
`numvcpus`, `cpuid.coresPerSocket`, `memsize` and `firmware` are what you intended.

To list what your patched install actually supports, search `vmwarebase.dll` for the pattern
`darwin<NN>-64`. On the validated host that returned `darwin10-64` through `darwin26-64`.

> ### macOS guests are single-socket — allocate cores, not sockets
>
> Setting **2 processors x 2 cores** produces:
>
> > *"The virtual machine might not run properly because it is configured to use more virtual
> > processor sockets than the guest supports."*
>
> Real Macs are single-socket and VMware enforces it for `darwin*` guests. Use **1 processor with 4
> cores per processor**. Same four cores, correct topology.
>
> **Get this right before installing.** Changing the core count *after* macOS is installed is a
> known cause of breakage — see [OC4VM#88](https://github.com/DrDonk/OC4VM/issues/88).

> ### Memory: measure FREE RAM, not installed RAM
>
> An earlier version of this guide recommended 8 GB "because the host has 32". The host had
> **17.8 GB already in use** — so an 8 GB guest would have left ~5.6 GB of headroom, not ~23.
>
> **4096 MB completed the install without trouble** and is what we now recommend. Memory is safely
> adjustable after installation; **core count is not**. Start low.
>
> Judge "insufficient" from the guest's **Activity Monitor → Memory → Memory Pressure** graph, not
> the "memory used" figure — macOS deliberately fills RAM with cache and the raw number always
> looks alarming.

---

## Step 1 — Create the VM, do not boot it

- [ ] **New Virtual Machine → Custom (advanced)**
- [ ] Guest OS **Apple macOS**, Version per the table above
- [ ] **"I will install the operating system later"** — the recovery image is a *disk*, not media
- [ ] Processors **1 x 4**; Memory **4096 MB**; disk **80 GB SATA**, single file
- [ ] **Finish. Do not power on.**

## Step 2 — Attach the recovery disk

- [ ] **VM → Settings → Add… → Hard Disk → SATA → Use an existing virtual disk**
- [ ] Select the `.vmdk` from Part 2 — **matching the version chosen in Step 1**
- [ ] **If Workstation offers to convert the disk format, stop.** The VMDK is wrong; revisit Part 2.
      On a correctly built `monolithicSparse` disk there is no prompt.

**Verification:** the VM lists **two** hard disks — an empty 80 GB and a ~2–3 GB recovery disk.
Confirmed in the `.vmx` as `sata0:0` (target) and `sata0:2` (recovery).

> The VMs reference the VMDKs **in place**. If they live in a downloads folder, do not delete it
> until installs are finished — or copy each `.vmdk` into its own VM folder first.

## Step 3 — Power on

- [ ] Start the VM

> **A dialog that looks like a failure and is not:**
>
> > *"Cannot connect the virtual device sata0:1 because no corresponding device is available on the
> > host. Do you want to try to connect this virtual device every time you power on the virtual
> > machine?"*
>
> That is the **empty CD/DVD drive** set to "auto detect", on a host with no optical drive. It has
> nothing to do with the recovery disk. Answer **No**. To silence it permanently, uncheck
> *Connect at power on* for the CD/DVD device.

**Expected:** brief EFI splash, then the **Apple logo with a progress bar** (1–3 minutes is normal),
then language selection, then **macOS Recovery**.

Reaching the Apple logo is also the first end-to-end proof that Part 1's **SMC patch works** — that
is the boot-time Apple hardware check being satisfied on non-Apple hardware.

## Step 4 — Erase the target disk

- [ ] **Disk Utility**
- [ ] **View → Show All Devices**
- [ ] **Identify by size, not by name.** The ~80 GB device is the target; the ~2–3 GB one is the
      recovery image you are booted from. **Erasing the wrong one destroys your installer mid-run.**
- [ ] Erase the 80 GB device: Name `macOS`, Format **APFS**, Scheme **GUID Partition Map**
- [ ] Quit Disk Utility

**Verification (observed):** `macOS`, APFS Volume, **85.69 GB** capacity, mount point
`/Volumes/macOS`. An 80 GiB virtual disk reports ~85.69 GB decimal — that is the same disk, not an
error.

## Step 5 — Install

- [ ] **Reinstall macOS <version>** → Continue → **Agree** (twice — a confirmation sheet follows)
- [ ] Select the volume you erased. The picker shows both **`macOS` (85.69 GB)** and **`macOS Base
      System` (2.88 GB)** — choose the large one
- [ ] Install, then **leave it alone**

> **Ignore the time estimate.** It opened at *"About 2 hours and 17 minutes remaining"*, fell to
> ~48 minutes, and finished in **~39 minutes**. The progress bar and the estimate routinely
> disagree; neither is reliable. Expect long stretches with no visible movement — normal, not a hang.

## Step 6 — Setup Assistant

Nothing here needs an Apple ID or any Apple service.

- [ ] Country/Region · Written and Spoken Languages · Accessibility → **Not Now** · Data & Privacy
- [ ] **Migration Assistant → Not Now** (bottom-left)
- [ ] **Sign In with Your Apple ID → "Set Up Later"** (bottom-left, easy to miss) → **Skip**
- [ ] Terms and Conditions → **Agree** (plus the confirmation sheet)
- [ ] **Create a Computer Account** — remember this password; `sudo` and SSH need it in
      [Part 4](part4-post-install.md)
- [ ] Location Services → clear the checkbox → **Don't Use** · Time Zone · Analytics → leave
      unchecked · Screen Time → **Set Up Later** · Choose Your Look

**Result:** the Ventura desktop, Finder and Dock.

## Step 7 — Detach and snapshot

Do this before installing anything into the guest.

- [ ] **Apple menu → Shut Down** — shut down from *inside* macOS. Do **not** use VM → Power → Shut Down Guest: it stops the VM but macOS records the shutdown as unclean (see [FINDINGS F-10](FINDINGS.md))
- [ ] **VM → Settings → select the ~2–3 GB recovery hard disk → Remove.** Removes it from the VM
      only — do not delete the `.vmdk` from disk
- [ ] Power on and confirm it boots from its own disk unaided
- [ ] **Take a snapshot: `clean-install`**

---

## Measured results — Ventura 13, 2026-08-11

| | |
|---|---|
| Host | Windows 11 10.0.26200.8875 · Intel Core Ultra 7 165H (16C/22LP, **hybrid P/E**) · 31.4 GB RAM |
| Workstation | Pro 26.0.0.25388281 (26H1), unlocker 3.1.4 |
| Guest config | `darwin22-64` · 1x4 cores · 4096 MB · 80 GB SATA · NAT |
| Install start to Setup Assistant | **~39 min** |
| Setup Assistant to desktop | **~17 min** |
| **Total** | **~56 min** |
| Installer's own first estimate | 2 h 17 min |
| Disk consumed | **31 GB** on the host after install + VMware Tools + one snapshot |

### Three things that did NOT happen

Recorded because guides commonly present them as expected — and an earlier draft of this file did
too:

1. **No core dump on VM creation or power-on.** `smc.version = "0"` was **not required**. Keep it as
   a remedy if you hit a crash; do not apply it pre-emptively.
2. **No "The CPU has been disabled by the guest Operating System."** This ran on a **hybrid P/E-core
   Intel Core Ultra 7 165H** with 1x4 cores. That combination is a documented trouble class
   ([OC4VM#80](https://github.com/DrDonk/OC4VM/issues/80),
   [#88](https://github.com/DrDonk/OC4VM/issues/88)) and it did not reproduce here.
3. **4 GB was not a bottleneck.** The install completed normally.

### It never went back to Recovery, and needed no intervention

Some guides tell you to detach the recovery disk between reboots to stop the VM booting back into
Recovery. **That was not necessary here.**

Observed by an operator watching and screenshotting throughout: after the install began, the VM
**never returned to the macOS Recovery menu**, and no reboot back to Recovery was seen. It ran
straight through to Setup Assistant with the recovery disk still attached the whole time.

**Do not detach the recovery disk mid-install.** Detach it at Step 7, once macOS is up.

**Still unknown:** whether any automatic reboot occurred at all, and if so how many. None was
observed, but the guest was not watched continuously enough to state the count as zero.
**[unverified]** — the practically important part, that no intervention is required, is confirmed.

## Known failure modes

| Symptom | Likely cause |
|---|---|
| *"more virtual processor sockets than the guest supports"* | Multiple sockets configured. Use 1 socket with N cores |
| *"Cannot connect the virtual device sata0:1"* | **Benign** — empty CD/DVD, no host optical drive. Answer No |
| VMware core-dumps on power-on | Add `smc.version = "0"` to the `.vmx`, or lower hardware compatibility |
| Prohibited sign at boot | Version dropdown does not match the image's macOS version |
| Recovery disk not bootable | Wrong bus (use SATA), or attached as CD/DVD rather than a hard disk |
| Target disk absent in Disk Utility | **View → Show All Devices** not enabled |
| *"The CPU has been disabled by the guest Operating System"* | CPU topology — see OC4VM #80/#88. Not caused by the unlocker |
| Installer appears stalled | Usually still downloading. Check the guest's network before intervening |
