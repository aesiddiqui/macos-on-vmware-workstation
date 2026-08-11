# Part 3 — Creating the VM and installing macOS

> **STATUS: VALIDATED ON TWO VERSIONS, 2026-08-11.**
> macOS **Ventura 13.7.8** (~56 min) and **Sequoia 15** (~54 min) installed end to end on VMware
> Workstation Pro **26.0.0.25388281** (26H1), Windows 11 host, from recoveryOS VMDKs built in
> [Part 2](part2-obtaining-macos.md). Everything below is what happened, including three things our
> own earlier draft got wrong.
>
> The **Tahoe** VM is configured identically but has **not been booted**. Setup Assistant already
> drifts measurably between 13 and 15 — see the per-version note in Step 6 — so expect further
> drift on newer releases and treat the screen list as a shape, not a script.

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

**Result:** the desktop, Finder and Dock.

> ### Setup Assistant differs by macOS version — the list above is Ventura 13
>
> Validated on **Sequoia 15** as well. Same shape, but five differences, and two of them change
> where the opt-out lives:
>
> | Ventura 13 | Sequoia 15 |
> |---|---|
> | **Migration Assistant** — *Not Now* link, bottom-left | **Transfer Your Data to This Mac** — the escape is now a **radio button**, *Set up as new*, not a link |
> | **Create a Computer Account** | **Create a Mac Account** — with a new checkbox, **ticked by default**: *Allow computer account password to be reset with your Apple Account* |
> | **Sign In with Your Apple ID** | **Sign In to Your Apple Account** (rebranded; *Set Up Later* still bottom-left) |
> | Separate **Enable Location Services** screen | **Folded into Time Zone** as a checkbox: *Set time zone automatically using current location* |
> | — | **NEW: Update Mac Automatically** — escape is *Only Download Automatically*, bottom-left |
>
> Sequoia also **reorders**: data-transfer moves to position 2 (straight after Country/Region), and
> the account is created **before** Apple Account sign-in — the reverse of Ventura.
>
> **Two to watch:**
> - The *Allow … password to be reset with your Apple Account* box is **on by default**. It is moot
>   if you skip Apple Account sign-in, but untick it deliberately rather than by accident.
> - The Time Zone screen can show a **timezone that disagrees with the Closest City** you picked.
>   Check the resulting clock rather than trusting the screen.
>
> Expect further drift on newer releases. Treat the list as a shape, not a script.

## Step 7 — Detach and snapshot

Do this before installing anything into the guest.

- [ ] **Shut down.** Either **Apple menu → Shut Down** or **VM → Power → Shut Down Guest** works and
      both are clean — but **let it finish.** macOS shutdown in a VM takes 30–60 seconds and looks
      stalled when it is merely slow. Issuing a second shutdown on top of one already running is what
      produces an unclean state (see [FINDINGS F-10](FINDINGS.md), retracted and corrected)
- [ ] **VM → Settings → select the ~2–3 GB recovery hard disk → Remove.** Removes it from the VM
      only — do not delete the `.vmdk` from disk
- [ ] Power on and confirm it boots from its own disk unaided
- [ ] **Take a snapshot: `clean-install`**

---

## Measured results — two versions, same host, 2026-08-11

| | Ventura 13.7.8 | Sequoia 15 |
|---|---|---|
| Guest RAM | 4096 MB | 8192 MB |
| Installer's opening estimate | 2 h 17 m | 2 h 52 m |
| …then revised to | 48 m | 58 m |
| **Install → Setup Assistant** | **~39 min** | **~44 min** |
| Setup Assistant → desktop | ~17 min | ~10 min |
| **Total** | **~56 min** | **~54 min** |
| Restarts during install | flicker + bar restart, no firmware splash | identical |
| Returned to Recovery? | no | no |
| `smc.version = "0"` needed? | no | no |
| "CPU has been disabled"? | no | no |

**Two conclusions worth having:**

1. **The opening estimate is roughly 3× reality on both runs**, then collapses. Expect an absurd
   first number; it means nothing.
2. **Doubling RAM did not speed up installation** — 8 GB was marginally *slower*, because Sequoia is
   a larger download. The phase is bound by the download from Apple, not by memory. **4 GB is
   sufficient**, and that is now tested rather than assumed. Extra RAM buys post-install
   responsiveness, not install time.

The two runs differ in *both* OS version and RAM, so this is not a controlled comparison — but the
direction is unambiguous: more memory did not help.

---

## Detail — Ventura 13, 2026-08-11

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

### The restarts are internal to the installer — you do nothing

Some guides tell you to detach the recovery disk between reboots to stop the VM booting back into
Recovery. **That is not necessary.**

**Both versions behaved identically.** During the install the screen flickers and the progress bar
restarts, several times. What you do **not** see is the VMware/EFI splash — so these are the macOS
installer cycling through its own stages, not the VM power-cycling through firmware.

That distinction is the useful one, because it tells you which thing you are looking at:

| What you see | What it is |
|---|---|
| Screen flickers, progress bar restarts, **no firmware splash** | Normal. Installer staging. Leave it alone |
| **VMware/EFI splash**, then macOS Recovery | The guest actually rebooted and booted the recovery disk. Only then is boot order worth looking at |

Neither version ever returned to the Recovery menu, neither needed intervention, and both ran
through to Setup Assistant **with the recovery disk attached the whole time.**

**Do not detach the recovery disk mid-install** and do not intervene when the screen flickers.
Detach at Step 7, once macOS is up.

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
