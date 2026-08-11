# Evidence — the same machine, two unlockers

Console output from a single Windows 11 host running **VMware Workstation Pro 26.0.0.25388281**
(26H1), captured 2026-07-22.

Both transcripts are unedited except for two redactions, marked inline:

- the local username is replaced with `<user>`;
- the 32 bytes of Apple SMC key material in the `Key After` lines are elided as `<32 bytes written>`.
  The *before* lines are shown in full, because all-zeros → non-zeros is the entire point and no key
  material is needed to make it.

---

## Run 1 — Unlocker 3.0.2 (DrDonk / Dave Parsons, 2018)

Every stage fails. The script exits `Finished!` anyway, and VMware is left completely unmodified.

```text
C:\Windows\System32>cd "C:\Users\<user>\Downloads\VMW Unblocker"

C:\Users\<user>\Downloads\VMW Unblocker>win-install.cmd

Unlocker 3.0.2 for VMware Workstation
=====================================
(c) Dave Parsons 2011-18

Set encoding parameters...
Active code page: 850

ERROR: The system was unable to find the specified registry key or value.
VMware is installed at:
ERROR: The system was unable to find the specified registry key or value.
VMware product version:

Stopping VMware services...

Backing up files...
File not found - vmware-vmx.exe
0 File(s) copied
File not found - vmware-vmx-debug.exe
0 File(s) copied
File not found - vmware-vmx-stats.exe
0 File(s) copied
File not found - vmwarebase.dll
0 File(s) copied

Patching...
Traceback (most recent call last):
  File "C:\Users\<user>\Downloads\VMW Unblocker\unlocker.py", line 401, in <module>
    main()
  File "C:\Users\<user>\Downloads\VMW Unblocker\unlocker.py", line 378, in main
    key = OpenKey(reg, r'SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation')
FileNotFoundError: [WinError 2] The system cannot find the file specified

Getting VMware Tools...
Trying to get tools from the packages folder...
Traceback (most recent call last):
  File "C:\Users\<user>\Downloads\VMW Unblocker\gettools.py", line 166, in <module>
    main()
  File "C:\Users\<user>\Downloads\VMW Unblocker\gettools.py", line 115, in main
    response = urlopen(url)
  ...
urllib.error.HTTPError: HTTP Error 404: Not Found
File not found - darwin*.*
0 File(s) copied

Starting VMware services...

Finished!
```

Read that last line against everything above it. Nothing was backed up, nothing was patched, no
tools were fetched — and the operator is told the job is done.

### Why each stage failed

The registry is the root cause, and it is directly observable:

```text
> reg query "HKLM\SOFTWARE\Wow6432Node\VMware, Inc.\VMware Workstation"
ERROR: The system was unable to find the specified registry key or value.

> reg query "HKLM\SOFTWARE\VMware, Inc.\VMware Workstation"

HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware Workstation
    ProductCode       REG_SZ    {86B6E794-CF20-4939-A2B4-1CD53C370315}
    ProductVersion    REG_SZ    26.0.0.25388281
    InstallPath       REG_SZ    C:\Program Files\VMware\VMware Workstation\
    InstallPath64     REG_SZ    C:\Program Files\VMware\VMware Workstation\x64\
```

`unlocker.py:378` queries the first path. `InstallPath64` — the `x64\` subfolder holding the actual
patch targets — is a key the 2018 script has no concept of. And `gettools.py:110` still points at
`http://softwareupdate.vmware.com/cds/vmw-desktop/fusion/`, which is gone post-Broadcom.

The shipped `readme.txt` says so plainly, and is easy to skip past:

```text
Unlocker 3 is designed for VMware Workstation 11-15 and Player 7-15.
```

---

## Run 2 — Unlocker 3.1.4 (BDisp fork), same machine, minutes later

```text
C:\>cd /d "C:\Users\<user>\Downloads\unlocker-3.1.4"

C:\Users\<user>\Downloads\unlocker-3.1.4>win-install.cmd

Unlocker 3.1.4 for VMware Workstation
=====================================
(c) Dave Parsons 2011-18

Set encoding parameters...
Active code page: 850

VMware is installed at: "C:\Program Files\VMware\VMware Workstation\"
VMware product version: 26.0.0.25388281
Checking for backup folder: C:\Users\<user>\Downloads\unlocker-3.1.4\backup-windows
No backup-windows folder found in script directory.
Proceeding with installation...

Stopping VMware services...

Backing up files...
C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe -> C:\Users\<user>\Downloads\unlocker-3.1.4\backup-windows\x64\vmware-vmx.exe
1 File(s) copied
C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx-debug.exe -> ...\backup-windows\x64\vmware-vmx-debug.exe
1 File(s) copied
...
C:\Program Files\VMware\VMware Workstation\vmwarebase.dll -> ...\backup-windows\vmwarebase.dll
1 File(s) copied

Patching...
File: C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx.exe

appleSMCTableV0 (smc.version = "0")
appleSMCTableV0 Address      : 0xe5fb30
appleSMCTableV0 Private Key #: 0xF2/242
appleSMCTableV0 Public Key  #: 0xF0/240
appleSMCTableV0 Table        : 0xe5fb50
+LKS Key:
002 0xe5fb98 +LKS 01 flag 0x90 0x1404a6930 07
OSK0 Key Before:
241 0xe63ed0 OSK0 32 ch8* 0x80 0x1404a69b0 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
OSK0 Key After:
241 0xe63ed0 OSK0 32 ch8* 0x80 0x1404a6930 <32 bytes written>
OSK1 Key Before:
242 0xe63f18 OSK1 32 ch8* 0x80 0x1404a69b0 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
OSK1 Key After:
242 0xe63f18 OSK1 32 ch8* 0x80 0x1404a6930 <32 bytes written>

appleSMCTableV1 (smc.version = "1")
...
OSK0 Key Before:
435 0xe6b990 OSK0 32 ch8* 0x90 0x1404a69b0 00 00 00 ... 00
OSK0 Key After:
435 0xe6b990 OSK0 32 ch8* 0x90 0x1404a6930 <32 bytes written>

File: C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx-debug.exe
...
File: C:\Program Files\VMware\VMware Workstation\x64\vmware-vmx-stats.exe
...

GOS Patched: C:\Program Files\VMware\VMware Workstation\vmwarebase.dll

Getting VMware Tools...
...

Starting VMware services...

Finished!
```

Both SMC tables (`V0` and `V1`) are patched in **each of the three** `vmware-vmx` binaries — six
`OSK0`/`OSK1` pairs in total — followed by the GOS patch on `vmwarebase.dll` (42 flags) and a
successful tools download that fell back from the dead `softwareupdate.vmware.com` to
`packages-prod.broadcom.com`.

---

## Independent confirmation on disk

The product was installed in April; the patch ran on 22 July at 14:21. The divergence is the
simplest available proof, and needs no tooling:

| File | Modified |
|---|---|
| `...\darwin.iso` | Jul 22 14:21 |
| `...\darwinPre15.iso` | Jul 22 14:21 |
| `...\x64\vmware-vmx.exe` | Jul 22 14:21 |
| `...\x64\vmware-vmx-debug.exe` | Jul 22 14:21 |
| `...\x64\vmware-vmx-stats.exe` | Jul 22 14:21 |
| everything else (`.ROM`, other DLLs and EXEs) | Apr 24 |

And `backup-windows\` holds the four genuine pre-patch originals, all stamped Apr 24 — the rollback
path is intact.

After the patch, **Apple macOS** was selectable in the New Virtual Machine wizard with a live
Version dropdown, and a created guest's `.vmx` carried:

```text
guestOS = "darwin25-64"
smc.present = "TRUE"
firmware = "efi"
board-id.reflectHost = "TRUE"
```

`guestOS = "darwin25-64"` is a value the wizard cannot produce on an unpatched `vmwarebase.dll`.

---

## The failed attempt is still on disk, and it also proves the point

The 3.0.2 folder from run 1 remains as it was left:

- `backup\x64\` — **empty**
- `tools\` — **empty**

A tool that reported `Finished!` produced no backup and no tools. Had that run been trusted, there
would have been nothing to restore from either.
