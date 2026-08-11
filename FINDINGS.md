# Findings

Defects and traps found while getting a macOS guest working on VMware Workstation Pro 26.x, each
with the environment it was seen in and steps to reproduce it.

Everything here was **observed on a real machine**, not inferred. Where something was not tested,
it says so. Where a finding belongs to someone else's project, that is stated plainly and credited —
several of these are not bugs in any tool, just undocumented behaviour that costs people hours.

**Test environment unless noted otherwise**

| | |
|---|---|
| Host OS | Windows 11 (build 10.0.26200.8875) |
| VMware Workstation Pro | 26.0.0.25388281 (26H1) |
| Unlocker (failing) | 3.0.2 — Dave Parsons / DrDonk, 2018 |
| Unlocker (working) | 3.1.4 — BDisp fork, 2026-05-16 |
| recoveryOS | 1.0.1-0012c39 (OC4VM Image Maker) |
| QEMU | 11.0.50 (`v11.0.0-12631-g54e84cdc7a`) |
| Dates observed | 2026-07-22 (F-1, F-5), 2026-08-11 (F-2…F-4, F-6) |

---

## F-1 · Unlocker 3.0.2 reports success while patching nothing

**Status:** Fixed upstream in BDisp 3.1.4 · [issue #79](https://github.com/BDisp/unlocker/issues/79)
· not a new defect — documented here because the *failure mode* is not.

**Severity:** high — the operator is told the job succeeded.

**Reproduce:** run Unlocker 3.0.2's `win-install.cmd` elevated on Workstation 26.x.

**Expected:** a non-zero exit, or at minimum a final message distinguishing failure from success.

**Actual:** three independent failures — registry key not found (`Wow6432Node` hive no longer
exists), `0 File(s) copied` for all four backups (binaries moved to `x64\`), and `HTTP Error 404`
for guest tools (`softwareupdate.vmware.com` is dead post-Broadcom) — followed by `Finished!` and
exit. VMware is left completely unmodified, **and the backup is empty, so there is nothing to
restore either.**

Full console output of the failing and succeeding runs on the same machine minutes apart:
[part1-evidence.md](part1-evidence.md).

**Credit:** [BDisp](https://github.com/BDisp/unlocker) diagnosed and fixed the underlying cause. The
contribution here is documenting the silent-success shape, which is why the failure is hard to
search for.

---

## F-2 · The QEMU Windows installer adds itself to no PATH

**Status:** open · not reported upstream · affects any tool that requires `qemu-img` by name.

**Severity:** medium — causes a downstream tool to fail for a reason that is not its own.

**Reproduce:**

```powershell
winget install --id SoftwareFreedomConservancy.QEMU
# new shell
qemu-img --version
```

**Expected:** `qemu-img` resolves, since `recoveryOS` and comparable tools require it *on PATH*.

**Actual:** `qemu-img` is not found. Measured immediately after a successful install — **neither**
the machine PATH **nor** the user PATH contained the install directory:

```powershell
[Environment]::GetEnvironmentVariable('Path','Machine') -like '*qemu*'   # False
[Environment]::GetEnvironmentVariable('Path','User')    -like '*qemu*'   # False
Test-Path 'C:\Program Files\qemu\qemu-img.exe'                           # True
```

The binary is present and unreachable by name. Fix in
[part2-obtaining-macos.md](part2-obtaining-macos.md).

---

## F-3 · recoveryOS loops forever on stdin EOF

**Status:** **reported upstream** — [DrDonk/OC4VM#100](https://github.com/DrDonk/OC4VM/issues/100),
filed 2026-08-11, PR offered.

**Severity:** medium — unbounded CPU consumption, and no way to terminate; makes the tool
unusable in any non-interactive context (CI, scripts, remote shells).

**Reproduce** — two lines, no macOS knowledge required:

```powershell
cd recoveryOS-1.0.1\windows\amd64
printf '7\n0\n' | .\recoveryOS.exe        # or any menu input via a pipe
```

**Expected:** on EOF, exit — or at minimum stop reading and terminate non-zero.

**Actual:** the menu reader treats EOF as invalid input and re-prompts, unbounded:

```text
Input menu number: Invalid selection. Please try again.
Input menu number: Invalid selection. Please try again.
... indefinitely, until taskkill
```

Observed twice on 2026-08-11. Both times the **download completed correctly** and the conversion
step never ran — so the symptom presents as a slow download rather than a hang, which is what makes
it expensive. The first occurrence consumed ten minutes before it was recognised.

**Workaround:** run `recoveryOS.exe` in a real console. For automation use the bundled
`macrecovery.exe`, which is flag-driven — see [part2-obtaining-macos.md](part2-obtaining-macos.md).

**Where to report recoveryOS bugs:** issues are **disabled** on `DrDonk/recoveryOS` itself. They
belong on **[DrDonk/OC4VM](https://github.com/DrDonk/OC4VM/issues)** — the tool identifies itself as
the *OC4VM recoveryOS Image Maker*, and
[OC4VM#84](https://github.com/DrDonk/OC4VM/issues/84) is a recoveryOS bug tracked there and fixed in
1.0.1. Per that project's §5 Support policy: hypervisor/CPU/OS *combination* questions go to
Discussions; obvious bugs go to Issues.

---

## F-4 · recoveryOS's default `-board-db` path and the shipped `boards.json` disagree — *unverified*

**Status:** open · **[unverified]** — inferred from file layout, not observed failing.

`macrecovery.exe -board-db` defaults to `boards.json` **in the current working directory**. The
archive ships `boards.json` at its **root**, while the binaries live in `windows/<arch>\` — and the
README instructs you to run from the arch folder. Those two are not the same place.

We passed `-board-db ..\..\boards.json` explicitly and therefore **did not test whether the default
resolves on its own** — it may well locate it relative to the executable. Recorded so it is checked
rather than assumed. **Do not cite this as a defect until someone confirms it.**

---

## F-5 · A Workstation update silently reverts the patch

**Status:** known and documented by the unlocker itself · listed because the *detection* is the
gap.

Applying a VMware Workstation product update overwrites the patched binaries with stock ones. macOS
support disappears with no notification.

What makes it awkward is the forensic signature: the binaries are **stock**, but their timestamps
are **recent** — so the most obvious check ("were these files modified after the product install?")
gives the wrong answer with confidence.

[`tools/Test-UnlockerPatch.ps1`](tools/Test-UnlockerPatch.ps1) handles this by hashing installed
binaries against the unlocker's `backup-windows\` originals, and reporting signal disagreement
rather than resolving it in favour of the positive.

---

## F-6 · A defect in this repo's own verification script, found by testing it

**Status:** fixed, 2026-08-11 · recorded because it is the same class the repo is about.

`Test-UnlockerPatch.ps1` passed on a genuinely patched machine. It was then run against a synthetic
backup byte-identical to the installed files — i.e. an **unpatched** machine.

**Actual (before fix):** signal 1 correctly reported `NOT patched`, and the final verdict was
still **PATCHED, exit 0** — because a positive from the weaker timestamp signal was pooled with,
and outranked, a negative from the definitive one.

That is exactly the F-5 signature, so the tool would have reported "patched" to the one person most
needing to hear otherwise.

**Fix:** signals are no longer pooled. The backup comparison is authoritative; the timestamp signal
decides only when the first is unavailable; disagreement is reported explicitly. Both polarities are
now exercised.

The general lesson, and the reason this repo exists: **a check that has only ever passed has not
been tested.**

---

## How to reproduce any of this

Nothing here needs macOS or a licence. F-1 needs a Workstation 26.x install and the 3.0.2 release.
F-2 and F-3 need only Windows and the two downloads. F-6 needs this repo.

Corrections are welcome — including to findings marked unverified. If something here is wrong, it
is better to say so than to leave it standing.
