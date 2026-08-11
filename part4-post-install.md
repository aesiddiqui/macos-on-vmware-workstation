# Part 4 — Making the guest actually usable

> **STATUS: VALIDATED, 2026-08-11.**
> VMware Tools, clipboard, shared folders and key-based SSH all working on macOS **Ventura 13.7.8
> (22H730)** under VMware Workstation Pro **26.0.0.25388281**. Everything below was observed.
> Display/HiDPI notes are marked where they were not exercised.

A freshly installed macOS guest is technically working and practically unpleasant. This part closes
that gap and ends with headless SSH, which is what turns the VM from something you sit in front of
into a machine you drive from the host.

**Prerequisite:** [Part 3](part3-vm-creation-and-install.md) complete, snapshot taken.

---

## Step 1 — VMware Tools

The unlocker already placed the guest tools next to the product as `darwin.iso`. You do not need to
find them.

- [ ] With the guest running, VMware shows a **yellow prompt bar** at the bottom of the window
      offering to install Tools. Clicking it mounts `darwin.iso` automatically — the `.vmx` gains
      `sata0:1.deviceType = "cdrom-image"` pointing at the ISO in the install directory
- [ ] In the guest, open the mounted **VMware Tools** volume and run **Install VMware Tools**
- [ ] Authenticate, and approve *"Installer would like to administer your computer"*

> ### The step everyone misses: System Extension Blocked
>
> Partway through you will get:
>
> > *"System Extension Blocked — A program tried to load new system extension(s) signed by
> > 'VMware, Inc.'"*
>
> Go to **System Settings → Privacy & Security**, scroll to the bottom, and click **Allow** next to
> *"System software from VMware, Inc. was blocked"*. Authenticate again.
>
> **The installer will report success whether or not you do this.** If you skip it, Tools installs
> and does nothing useful.

- [ ] Let it finish (*"Updating preboot volume…"* is the long tail) → **Restart**

**Verification — ask the host, not your eyes.** This is the single most useful command in this
document:

```powershell
& "C:\Program Files\VMware\VMware Workstation\vmrun.exe" -T ws checkToolsState "<path>\<vm>.vmx"
```

`running` means Tools is installed, loaded and talking to the hypervisor. Any symptom you still have
is **not** a Tools problem, and reinstalling cannot fix it. See F-9 below for why that matters.

> **On the installer's time estimate:** it says *"About a minute"*. Budget considerably more — the
> preboot-volume stage plus the extension approval and restart took substantially longer here. As in
> Part 3, the estimate is decorative.

## Step 2 — Clipboard, and the trap

Copy/paste is enabled by default: **VM → Settings → Options → Guest Isolation** shows *Enable copy
and paste* and *Enable drag and drop* both ticked. They appear **greyed out while the VM is powered
on** — greyed means *locked*, not *disabled*.

> ### If copy/paste "doesn't work", check the modifier key before anything else
>
> In a macOS guest paste is **Cmd+V**, and VMware maps **Cmd to the Windows key**. `Ctrl+V` inside
> macOS does nothing, silently.
>
> | Action | Keys |
> |---|---|
> | Copy on the Windows host | `Ctrl+C` |
> | Paste into the macOS guest | **`Win+V`** |
> | Copy in the macOS guest | **`Win+C`** |
> | Paste on the Windows host | `Ctrl+V` |
>
> This cost real time here. The standard internet answer to the symptom is "reinstall VMware Tools",
> which is slow and cannot help — `checkToolsState` said `running` throughout. See
> [FINDINGS F-9](FINDINGS.md).

## Step 3 — Shared folders (they do work, they are just hidden)

Shared folders **are** supported on macOS guests — `darwin.iso` ships the HGFS driver.

- [ ] **VM → Settings → Options → Shared Folders → Always enabled**, add a host folder
- [ ] In the guest, Finder shows nothing new. **This is expected.** It is mounted at a path Finder
      does not surface:

```
/Volumes/VMware Shared Folders/<name>
```

- [ ] Finder → **Go → Go to Folder** (**Win+Shift+G**) → paste that path. Drag it to the Finder
      sidebar so you never have to do it again

**Verification:** write a file on the host, read it in the guest. Write-back is confirmed when
AppleDouble sidecar files (`._name`) start appearing on the host side — macOS wrote those.

*(Finder is macOS's Explorer: leftmost Dock icon, the blue face. It is always running. `Win+N` opens
a new window.)*

## Step 4 — Display

- [ ] **VM → Settings → Display** — Accelerate 3D graphics, raise graphics memory
- [ ] With Tools running, the guest resolution follows the VMware window when you resize it

**[unverified]** HiDPI/Retina scaling was not exercised. Treat it as best-effort.

## Step 5 — Headless SSH access (the point of all this)

- [ ] Guest: **System Settings → General → Sharing → Remote Login: ON**
- [ ] Restrict to **Only these users → your account**, not All users
- [ ] Get the guest IP **from the host** — no need to read it off the screen:

```powershell
& "...\vmrun.exe" -T ws getGuestIPAddress "<path>\<vm>.vmx"      # e.g. 192.168.144.130
```

Cross-check against `C:\ProgramData\VMware\vmnetdhcp.leases` if you want a second source.

- [ ] Confirm `sshd` is really listening, not just the port being open:

```powershell
Test-NetConnection -ComputerName <guest-ip> -Port 22
ssh -o BatchMode=yes nobody@<guest-ip> exit
# expect: Permission denied (publickey,password,keyboard-interactive)
```

That "Permission denied" is a **success** — it proves `sshd` answered.

### Key-based auth without `ssh-copy-id`

`ssh-copy-id` is not present on stock macOS. Use the shared folder from Step 3 instead:

**On the host** — generate a key **dedicated to the VM**. Do not reuse a key that reaches your code
hosting accounts:

```powershell
ssh-keygen -t ed25519 -C "macos-lab-vm" -f $env:USERPROFILE\.ssh\id_ed25519_macos_lab
copy $env:USERPROFILE\.ssh\id_ed25519_macos_lab.pub <shared-folder>\macos-lab.pub
```

**In the guest** (Terminal — `Win+Space`, type `terminal`):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat "/Volumes/VMware Shared Folders/<name>/macos-lab.pub" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**From the host:**

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519_macos_lab <account>@<guest-ip>
```

> **On passphrases.** A passphrase-less key means anyone with read access to your host `~/.ssh` can
> reach the VM. For a NAT-only lab guest that is usually a fair trade, and it avoids depending on an
> ssh-agent. Decide deliberately rather than by default.

**Networking note:** NAT is enough to reach the guest **from its own host**. To reach it from
elsewhere on your LAN, switch the adapter to **Bridged**.

## Step 6 — Snapshots and maintenance

- [ ] Verify clipboard, shared folders and SSH **before** snapshotting — otherwise you consolidate a
      half-working state into your baseline
- [ ] Snapshot `tools-installed`, then delete the earlier `clean-install` if you want the space.
      Deleting a snapshot **consolidates** the delta into the base disk: it takes minutes and needs
      temporary free space
- [ ] **After any VMware Workstation product update, re-run
      [`tools/Test-UnlockerPatch.ps1`](tools/Test-UnlockerPatch.ps1)** — an update silently restores
      stock binaries and removes macOS support
- [ ] **Software Update will offer macOS versions your physical Mac cannot run** (see
      [FINDINGS F-8](FINDINGS.md)). If this VM exists to *match* a physical machine, taking that
      upgrade destroys the reason it exists. A fresh install defaults to *Security updates only* —
      leave it there
- [ ] **VMware Tools → Time sync** is **off** by default. The guest clock drifted hours from the host
      during setup. Turn it on if you do anything time-sensitive in the guest

---

## Verified environment

Reached over SSH from the Windows host, guest at 4 GB / 1×4 cores:

```console
$ sw_vers
ProductName:    macOS
ProductVersion: 13.7.8
BuildVersion:   22H730

$ sysctl -n hw.model
VMware20,1
$ sysctl -n machdep.cpu.brand_string
Intel(R) Core(TM) Ultra 7 165H

$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin22)
```

Present: `git`, `python3`, `curl`. **Absent:** `brew`, `tac`, `gsed`.

### Why this VM is worth building, if you ship shell code

Stock macOS is **not** the Linux-ish environment most cross-platform scripts are tested against, and
the differences fail *silently* rather than loudly:

```console
$ printf 'a b\n' | sed 's/\s/_/'
a b                          # UNCHANGED. BSD sed ignores \s -- the value comes back
                             # subtly WRONG rather than erroring. GNU sed gives "a_b".

$ /bin/bash -c 'declare -A t'
declare: -A: invalid option  # associative arrays do not exist in bash 3.2

$ command -v tac
                             # ABSENT. GNU-only. A pipeline using it silently produces nothing.
```

Each of those has caused a real defect that passed every test on a Linux or Git-Bash host: a
security guard that returned a *wrong* value instead of failing, a lookup table that degenerated to
one element, and a rollback routine that iterated zero times and reported success.

A macOS guest you can SSH into makes those reproducible in one command instead of requiring physical
hardware — which is the difference between finding them on purpose and finding them in the field.
