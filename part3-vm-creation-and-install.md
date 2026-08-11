# Part 3 — Creating the VM and installing macOS

> **STATUS: NOT YET VALIDATED.**
> Checklist assembled from documented sources. Steps marked **[verify]** are the ones most likely
> to need correcting. Sections are replaced with captured output once actually run.

**Prerequisites:** [Part 1](part1-unlocker.md) complete and verified
(`tools/Test-UnlockerPatch.ps1` reports PATCHED), and a `.vmdk` recovery disk from
[Part 2](part2-obtaining-macos.md).

---

## Step 1 — Create the VM, but do not boot it

- [ ] **New Virtual Machine → Custom (advanced)**
- [ ] Guest OS: **Apple Mac OS X**
- [ ] **Version:** select the entry matching the macOS you downloaded. This is a real trap — the
      wizard defaults to an older release (e.g. macOS 10.15), and a modern installer booted against
      a too-low version fails in ways that look like a broken image. If your target is not listed,
      take the highest available.
- [ ] Installer media: **"I will install the operating system later"** — do **not** point it at the
      recovery image here. It is attached as a disk, not as installation media.
- [ ] Firmware: **EFI** (should be automatic for a macOS guest)
- [ ] CPUs / RAM / disk: 2+ vCPU, 8 GB+, 80 GB+ recommended for a usable guest **[verify]** against
      your target version's stated minimums
- [ ] **Finish, and do not power on.**

## Step 2 — Attach the recovery disk

- [ ] **VM → Settings → Add… → Hard Disk**
- [ ] Bus type: **SATA** **[verify]** — NVMe/SCSI are reported not to work for the recovery disk
- [ ] **Use an existing virtual disk** → select your `recovery.vmdk`
- [ ] If prompted to convert the disk format, **decline and re-check Part 2** — a conversion prompt
      means the VMDK was not written in the compatible variant

**Verification:** VM settings now list two hard disks — your empty target disk and the recovery
disk.

## Step 3 — Power on

- [ ] Start the VM. It should boot into **macOS Recovery**.

**If VMware crashes or core-dumps at this point:** shut everything down and add to the `.vmx` file:

```text
smc.version = "0"
```

This is the single most commonly needed edit and is documented in the unlocker's own readme.
**[verify]** whether it is required on Workstation 26.x specifically — it may no longer be.

**If it boots to a black screen or a prohibited sign (🚫):** the Version selected in Step 1 is
usually too low for the image, or the recovery disk is not on SATA.

## Step 4 — Partition the target disk

- [ ] In Recovery, open **Disk Utility**
- [ ] **View → Show All Devices** — without this the VMware virtual disk may not be selectable
- [ ] Select the *empty* virtual disk (match it by size — do not erase the recovery disk)
- [ ] **Erase**: Name of your choosing, Format **APFS**, Scheme **GUID Partition Map**
- [ ] Quit Disk Utility

## Step 5 — Install

- [ ] **Reinstall macOS** → select the disk you just erased
- [ ] The installer downloads the full OS from Apple over the guest's network connection. Expect a
      long download and **several automatic reboots** — leaving it alone is the correct action; a
      long silent stretch is normal, not a hang
- [ ] **[verify]** whether the recovery disk must be detached between reboots to avoid booting back
      into Recovery — behaviour differs across guides

## Step 6 — First boot and setup

- [ ] Complete Setup Assistant. **An Apple ID is not required** — look for the skip option
- [ ] Create the local account you will use
- [ ] Shut down cleanly, then **detach the recovery disk** from VM settings
- [ ] **Take a snapshot** named e.g. `clean-install` before installing anything. This is the
      cheapest insurance in the whole process

---

## Verification for this part

- [ ] macOS boots from its own disk with the recovery disk detached
- [ ] `About This Mac` reports the version you intended to install
- [ ] The `.vmx` contains `guestOS = "darwin<NN>-64"` and `smc.present = "TRUE"`
- [ ] A snapshot exists

## Known failure modes

| Symptom | Likely cause |
|---|---|
| VMware core-dumps on power-on | Missing `smc.version = "0"`; or hardware compatibility level too high |
| Prohibited sign (🚫) at boot | Version dropdown set below the image's macOS version |
| Recovery disk not offered as bootable | Attached on the wrong bus (use SATA), or attached as CD/DVD rather than a disk |
| Target disk absent in Disk Utility | **View → Show All Devices** not enabled |
| Installer stalls near the end | Usually still downloading; check the guest's network before intervening |
