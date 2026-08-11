# Part 4 — Making the guest actually usable

> **STATUS: NOT YET VALIDATED.**
> Checklist assembled from documented sources. Steps marked **[verify]** are the ones most likely
> to need correcting. Sections are replaced with captured output once actually run.

A freshly installed macOS guest is technically working and practically unpleasant — fixed low
resolution, no clipboard, no host integration. This part closes that gap, and ends with the
headless/SSH configuration that makes the VM useful as a build or test target rather than something
you have to sit in front of.

**Prerequisite:** [Part 3](part3-vm-creation-and-install.md) complete, snapshot taken.

---

## Step 1 — VMware Tools (`darwin.iso`)

The unlocker already placed the macOS guest tools next to the product in
`C:\Program Files\VMware\VMware Workstation\`. This is what they are for.

- [ ] With the guest running: **VM → Removable Devices → CD/DVD → Settings → Use ISO image**
- [ ] Select `darwin.iso` from the install directory. Use `darwinPre15.iso` only for pre-10.15
      guests
- [ ] In the guest, open the mounted volume and run **Install VMware Tools**
- [ ] Approve the kernel extension when macOS prompts: **System Settings → Privacy & Security →
      Allow** — the installer will *appear* to finish without this and the tools will not work
      **[verify]** the exact pane wording on your macOS version
- [ ] Reboot the guest

**Verification:** the display resizes with the window, and copy/paste works between host and guest.
Both failing means the kext was not approved.

> If the Install VMware Tools menu item is greyed out, mount `darwin.iso` manually as above — some
> product variants do not surface it automatically.

## Step 2 — Display

- [ ] **VM → Settings → Display** — enable **Accelerate 3D graphics**, raise graphics memory
      **[verify]** which combination Workstation 26.x actually honours for macOS guests
- [ ] Set a sensible resolution in the guest's Display settings
- [ ] HiDPI/Retina scaling in a VM is unreliable; treat it as best-effort **[verify]**

## Step 3 — Network

- [ ] NAT is the sane default and needs nothing
- [ ] Use **Bridged** if the guest must be reachable from other machines on your LAN — required if
      you want to SSH in from anywhere but the host
- [ ] Verify in the guest: `ifconfig en0` and a `ping` to something external

## Step 4 — Shared folders / file transfer

- [ ] Enable **VM → Settings → Options → Shared Folders**
- [ ] **[verify]** whether shared folders function on macOS guests on Workstation 26.x — support has
      historically been weaker than on Windows/Linux guests. If they do not work, the reliable
      alternatives are SSH/`scp` (Step 5) or a plain SMB share from the host

## Step 5 — Headless + SSH access (the useful part)

This is what turns the VM from a desktop you visit into a machine you can drive from the host — a
real macOS test target without borrowing physical hardware.

- [ ] In the guest: **System Settings → General → Sharing → Remote Login: ON**
- [ ] Restrict to your user rather than "All users"
- [ ] Note the guest IP (`ipconfig getifaddr en0`)
- [ ] From the host: `ssh <user>@<guest-ip>`
- [ ] Install a public key: `ssh-copy-id` **[verify]** — not present on stock macOS in all versions;
      the fallback is appending to `~/.ssh/authorized_keys` manually
- [ ] Confirm `sudo` works over SSH for the operations you need
- [ ] Optional: run the VM headless so it needs no window —
      `vmrun -T ws start "<path>\macOS.vmx" nogui` **[verify]** exact syntax and whether it holds
      for macOS guests

**Verification:** you can SSH in from the host, run a command, and log out — with the Workstation
window closed.

> **Why this step earns its place.** On stock macOS, `bash` is **3.2** and the userland is BSD, not
> GNU — `declare -A` fails at runtime while execution *continues*, and BSD `sed` ignores `\s` and
> returns the string subtly wrong rather than erroring. Cross-platform shell code that passes every
> test on a Linux or Git-Bash host can fail silently there. A reachable macOS guest is how you find
> that out on purpose instead of in the field.

## Step 6 — Snapshots and maintenance

- [ ] Snapshot after tools + SSH are working: `configured-baseline`
- [ ] **After any VMware Workstation product update, re-run
      [`tools/Test-UnlockerPatch.ps1`](tools/Test-UnlockerPatch.ps1)** — an update silently restores
      stock binaries and removes macOS support. The script detects this specific case, including the
      version where the timestamps *look* patched but the binaries are stock
- [ ] Guest macOS updates: minor updates are generally fine; treat major upgrades as risky and
      snapshot first **[verify]**

---

## Verification for this part

- [ ] Display resizes with the window; clipboard works both directions
- [ ] Guest reachable by SSH from the host, key-based, with the Workstation window closed
- [ ] `sw_vers` and `bash --version` return over SSH
- [ ] Snapshot `configured-baseline` exists
