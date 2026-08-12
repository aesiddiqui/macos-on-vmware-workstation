# Part 4 — Making the guest actually usable

> **STATUS: VALIDATED ON THREE VERSIONS, 2026-08-11.**
> VMware Tools, clipboard, shared folders and key-based SSH working on **Ventura 13.7.8**
> (22H730), **Sequoia 15.7.9** (24G830) and **Tahoe 26.6.1** (25G76), under VMware Workstation Pro
> **26.0.0.25388281**. **Every step below was validated on all three**, unless it says otherwise;
> anything not exercised is marked **[unverified]**.
>
> **The userland does not change across those four years** — `bash` 3.2.57, BSD `sed`, no `tac` on
> all three. See the verified-environment table below.

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

> **Sequoia adds one screen** Ventura does not: **"Select a Destination"**, offering *Install for all
> users of this computer* with the other two options greyed out. Take the default and continue.
> Otherwise the flow — authenticate, extension approval, preboot update, restart — is identical.

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

- [ ] **Shut the guest down first.** Shared Folders could not be configured on a running macOS
      guest — the setting has to be added with the VM powered off, then the guest started again.
      Trying it live is what makes people conclude shared folders are unsupported on macOS
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

**Verified on all three:** with Tools running, the guest resolution follows the VMware window. On
Sequoia the guest reported `Resolution: 1677 x 920` — a non-standard size matching the window, which
is auto-resize working rather than a preset being picked.

**[unverified]** HiDPI/Retina scaling was not exercised. Treat it as best-effort.

## Step 4b — If the desktop is unusable (macOS 26 / Tahoe especially)

At VMware's defaults, **macOS 26 Tahoe is not a usable interactive desktop.** Opening Safari and
playing a video froze the entire guest — clicks queued and were processed minutes later. macOS 13
and 15 do not do this.

**It is not memory.** Measured while the GUI was completely wedged: **87% memory free, 0.00M swap
in use**, at both 4 GB and 8 GB. Adding RAM does nothing because nothing is short of RAM.

**It is `WindowServer`** — the macOS compositor — software-rendering the entire framebuffer:

```console
$ ps -Ao pcpu,comm -r | head -3      # taken over SSH while the GUI was frozen
 191.4  .../SkyLight.framework/Resources/WindowServer
   3.5  .../Safari
```

Safari at 3.5%; the compositor at 191%. The apps were not working — the compositor was.

### What fixed it — one line

```
mks.enable3d = "TRUE"
```

Added to the `.vmx` with the guest **powered off**. It is **absent by default** from macOS guests
created through the wizard.

**Measured `WindowServer` CPU, same load throughout (Chrome playing video):**

| Configuration | WindowServer | Desktop |
|---|---|---|
| Defaults | **191%** | frozen, clicks queued for minutes |
| `reduceTransparency` alone | 104–206% | still froze |
| `mks.enable3d` **+** five animation tweaks | 95–127% | usable |
| **`mks.enable3d` alone** | **94–112%** | **usable** |

The last two rows are indistinguishable. **The 3D flag carries the entire improvement.**

Confirm it engaged — `vmware.log` should show the renderer binding to a host adapter:

```console
MKS: Renderer adapter luid = 0x15138
```

> #### The visual tweaks everyone recommends did nothing here
>
> These are the standard advice for a slow macOS guest. All five were applied, measured, then
> reverted and measured again. **No detectable difference either way**, with 3D enabled:
>
> ```bash
> defaults write com.apple.universalaccess reduceTransparency -bool true
> defaults write com.apple.universalaccess reduceMotion -bool true
> defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
> defaults write com.apple.dock launchanim -bool false
> defaults write com.apple.finder DisableAllAnimations -bool true
> ```
>
> `reduceTransparency` was also tested **alone, without 3D**: 104–206% CPU and the desktop still
> froze. It does not address the bottleneck.
>
> Recorded rather than omitted, because "turn off transparency and animations" is the first thing
> every thread suggests, and on this workload it is not the answer. Harmless to apply if you prefer
> the look; do not expect it to fix anything.

### Video playback: use Chrome, not Safari

Even with 3D enabled, **Safari will not play video.** `VTDecoderXPCService` spawns and sits at
**0.0% CPU** while `WebKit.GPU` idles at ~500 MB — Safari asks VideoToolbox for hardware decode,
VMware's virtual GPU provides none, and the pipeline stalls rather than falling back.

**Chrome works**, because it ships its own software decoders: its processes take ~11% / 5% / 2% CPU
doing the decode and hand frames to `WindowServer` to composite.

So: **VMware's virtual GPU gives macOS a render path but no hardware video decode.** Compositing can
be accelerated; decoding cannot.

### Things that do NOT help — ruled out by measurement

- **More RAM.** Zero swap at 4 GB and 8 GB, idle and under load.
- **`svga.enableHDPI = "FALSE"`.** Only relevant under Retina scaling; the guest framebuffer was
  1:1 (`Resolution: 1677x920` = `UI Looks like: 1677x920`).
- **`MemTrimRate`, `mainMem.useNamedFile`, `sched.mem.pshare.enable`.** These address *host paging*
  of guest memory. There was no paging problem.
- **More vCPUs.** Would likely help, but **changing core count after installation is a known
  breakage** — [OC4VM#88](https://github.com/DrDonk/OC4VM/issues/88). Set cores before installing.

### A separate, larger factor — and a security decision, not a tweak

`vmware.log` also reports:

```console
IOPL_Init: Hyper-V detected by CPUID
Monitor Mode: ULM
You are running this virtual machine with side channel mitigations enabled.
Side channel mitigations provide enhanced security but also lower performance.
```

With Windows' virtualization-based security active, VMware runs guests in **User Level Monitor**
mode — user mode rather than kernel mode — which degrades **every** VM on the host, not just macOS.

Two settings exist here, and neither is a performance knob:

- **Disable side-channel mitigations** (*VM → Settings → Options → Advanced*) removes Spectre/
  Meltdown-class protections against a guest reading host memory.
- **Disabling Hyper-V/VBS** to escape ULM means turning off **Memory Integrity / Credential Guard**
  on the host, and breaks WSL2, Docker Desktop and Windows Sandbox.

**We fixed this guest without touching either.** Try `mks.enable3d` first; treat the rest as security
decisions you make deliberately, and check corporate policy on a managed machine.

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

### Driving the guest headlessly (verified)

Start with no window at all, then connect:

```powershell
& "...\vmrun.exe" -T ws start "<path>\<vm>.vmx" nogui
```

**Measured:** `sshd` accepted connections **~20 seconds** after `vmrun start`, with `uptime`
reporting `0 users` — nothing logged in at the GUI.

**Remote shutdown — use `vmrun stop … soft` from the host.** All three candidates were tested; only
one works headlessly:

| Method | Works with no GUI session? | Notes |
|---|---|---|
| **`vmrun stop <vmx> soft`** (host) | ✅ **yes** | Tools-mediated. Verified on Ventura 13 and Sequoia 15; exit 0, 0 panic reports afterwards. Allow up to a few minutes — macOS shutdown is not instant |
| `osascript … shut down` (SSH) | ❌ **no** | Needs an Aqua session. **Fails silently — see below** |
| `sudo shutdown -h now` (SSH) | ❌ no | Stock macOS `sudo` requires a password; SSH gives it no TTY |

```powershell
& "...\vmrun.exe" -T ws stop "<path>\<vm>.vmx" soft
```

> ### ⚠ The `osascript` shutdown fails silently on a headless guest
>
> With a user logged in at the desktop it works. With **nobody logged in** — which is the whole
> point of a headless VM — it fails:
>
> ```console
> $ ssh <host> "osascript -e 'tell application \"System Events\" to shut down'"
> 36:45: execution error: An error of type -10810 has occurred. (-10810)
> $ echo $?
> 0                      # <-- SSH reports SUCCESS. The VM is still running.
> ```
>
> `-10810` is "could not launch the application": System Events needs a GUI session to launch into.
> The error goes to stderr and **the exit status is 0**, so a script sees success and moves on
> while the machine stays up.
>
> If you do want an in-guest shutdown, ensure a user is logged in and **check the output, not the
> exit code**. For anything unattended, use `vmrun stop … soft`.

For a scripted **restart**, `vmrun reset <vmx> soft` is the equivalent.

**Networking note:** NAT is enough to reach the guest **from its own host**. To reach it from
elsewhere on your LAN, switch the adapter to **Bridged**.

### Security posture — what enabling SSH actually costs you

**First, what has to be true before any of this is reachable.** None of it is a drive-by:

| Precondition | Is it a real barrier? |
|---|---|
| **Remote Login must be deliberately enabled.** macOS ships with it **off**. | ✅ **Yes — this is the real gate.** Nothing below matters until an operator turns it on. |
| The attacker must know the **account name**. | ⚠️ Weak. macOS account names are usually derived from the owner's real name, and the home directory name gives it away to anyone who ever sees the filesystem. |
| The attacker must reach the **IP**. | ⚠️ Depends entirely on the adapter. On **NAT**, only the host can reach it — a genuine barrier. On **Bridged**, one `nmap` sweep of the subnet finds it in seconds. |
| The attacker must present a **credential** — key or password. | ✅ Yes, and it is the one doing the actual work. |

So the honest summary: **the opt-in and the credential are real security; the username and IP are
obscurity**, and obscurity is worth little once the guest is on a routable network. Design as though
both are known.

**Second, what the exposure actually is** once Remote Login is on. Measured on this guest:

- **Shutdown is a user-level action on macOS, by design.** Any logged-in user can shut down from the
  Apple menu without a password, so an SSH user doing it via `osascript` is not privilege
  escalation. `sudo` was correctly refused throughout (`sudo: a password is required`).
- **`PasswordAuthentication` is ON by default.** Key auth working does not disable it — the account
  password remains a remote attack surface. Once keys work:
  `PasswordAuthentication no` in `/etc/ssh/sshd_config`, then restart Remote Login.
- **Restrict who may log in.** *Sharing → Remote Login → Only these users*, not *All users*.
- **A passphrase-less key means host filesystem access ⇒ guest access.** Anyone who can read your
  host `~/.ssh` gets in with no further authentication. On a shared or untrusted host, use a
  passphrase and accept the agent friction.
- **Keep it on NAT unless you need otherwise.** NAT reaches the guest from its own host only;
  Bridged exposes it to the whole LAN.
- **The largest exposure is not shutdown.** An authenticated SSH user has full user-level control —
  read every file in the home directory, install login items, exfiltrate. Shutdown is simply the
  most visible thing they could do, and the least damaging.
- **Host access already implies total VM control.** `vmrun stop`/`start`/`deleteVM` need no guest
  credentials at all. Anyone at the hypervisor owns the VM regardless of what you configure inside
  it — that is inherent to virtualisation, not a macOS weakness.

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

## Verified environment — and it does not change between macOS versions

Both guests reached over SSH from the Windows host:

| | **Ventura 13.7.8** (22H730) | **Sequoia 15.7.9** (24G830) |
|---|---|---|
| Guest RAM / cores | 4 GB / 1×4 | 8 GB / 1×4 |
| `hw.model` | `VMware20,1` | `VMware20,1` |
| `bash --version` | **3.2.57(1)** `darwin22` | **3.2.57(1)** `darwin24` |
| `zsh --version` | 5.9 | 5.9 |
| `sed 's/\s/_/'` on `a b` | `a b` — **unchanged** | `a b` — **unchanged** |
| `declare -A` | `invalid option` | `invalid option` |
| `tac` | **absent** | **absent** |

Present on both: `git`, `python3`, `curl`. Absent on both: `brew`, `tac`, `gsed`.

> ### The important part: two major releases apart, nothing moved
>
> Apple froze `bash` at **3.2.57 (2007)** over the GPLv3 licence change and has not shipped a newer
> one since; the BSD userland is equally static. `zsh` is the modern default shell, but **`/bin/bash`
> is still 3.2** and any script with a `#!/bin/bash` shebang gets it.
>
> **So it does not matter which macOS version you build a test guest on.** The failure modes below
> are identical on 13, 15 and 26. Pick whichever installs fastest rather than chasing version parity
> with some particular Mac.

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
