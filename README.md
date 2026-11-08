<div align="center">

# G-Sync-Patch

**Unofficial VRR unlock for laptop eDP panels on NVIDIA GPUs**

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-experimental-orange)

</div>

An independent, unofficial tool that unlocks **G-SYNC-style variable refresh rate (VRR)** on a laptop's internal screen when the panel can do VRR but the NVIDIA driver never offers it, because the laptop's firmware does not provide the platform object the driver looks for.

The patch is a set of PowerShell scripts. It generates that platform object for **your** GPU and panel and hands it to the NVIDIA driver through a registry value the driver already reads (`RMemNBSItable`). It does not modify driver files, the BIOS, the panel's EDID or anything else, and it can be undone at any time.

> [!NOTE]
> **Confirmed on:** Dell G15 5530 · GeForce RTX 3050 6 GB Laptop GPU · CMN1522 panel (eDP) · NVIDIA driver 621.14.
> On other laptops it is **experimental**: it cannot create VRR on hardware that does not support it.

> [!IMPORTANT]
> **Not affiliated with, endorsed by or supported by NVIDIA or Dell.** NVIDIA and G-SYNC are trademarks of NVIDIA Corporation, used here only to describe compatibility. See [Legal notes](#legal-notes).

---

## Contents

- [Why this exists](#why-this-exists)
- [What it changes, and what it does not](#what-it-changes-and-what-it-does-not)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Presets](#presets)
- [How it works](#how-it-works)
- [Backups and safe restore](#backups-and-safe-restore)
- [Command reference](#command-reference)
- [Checking that it worked](#checking-that-it-worked)
- [Troubleshooting](#troubleshooting)
- [Compatibility and limits](#compatibility-and-limits)
- [FAQ](#faq)
- [Files](#files)
- [Legal notes](#legal-notes)
- [Sources and license](#sources-and-license)

---

## Why this exists

On many gaming laptops the internal panel is physically capable of variable refresh, yet the **G-SYNC** page never appears in the NVIDIA Control Panel. The reason is not the panel. It is a check the driver makes against the **platform**:

1. During start-up the NVIDIA driver asks the system firmware (ACPI, through the NBCI/NBSI interfaces) for a small **platform object of type "VK"**. That object describes, for one specific GPU and panel combination, a platform designed for variable refresh.
2. On the laptop where this tool was developed, the firmware answered that request with an empty (all-zero) object. With no valid object, the driver treats the panel as plain eDP and never offers VRR.
3. The driver also reads a copy of that platform table from the registry, in the value `RMemNBSItable` under the GPU's driver key. The table layout follows the NBSI structures published in NVIDIA's open-source kernel modules (see [Sources](#sources-and-license)).

With a valid table for that GPU and panel in place, the **Set up G-SYNC** page appeared, the driver reported the panel as VRR-capable, and variable refresh worked in games.

This package turns that into a safe, repeatable tool:

- it reads your GPU's PCI IDs and your panel's EDID IDs;
- it builds the matching table in memory;
- it saves a backup of whatever was there before;
- it writes only that one registry value;
- it can restore the original state exactly.

## What it changes, and what it does not

**Changes:** one `REG_BINARY` value, `RMemNBSItable`, in the class key of the selected NVIDIA GPU (`HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-…}\NNNN`).

**Does not change:**

- NVIDIA driver files (`.sys` / `.dll`), the BIOS/UEFI or firmware;
- the panel's EDID or DPCD;
- the MUX / Advanced Optimus mode;
- NVIDIA Control Panel settings, PowerShell's execution policy, Secure Boot, the antivirus or memory integrity;
- anything else in the registry (in particular, it does **not** set `RmAllowUnknown4PartIds`).

It never restarts Windows or the GPU on its own.

The strings inside the generated object (such as "Genuine NVIDIA Certified GSync Ready Platform") are part of the format the driver recognizes. **They are not an NVIDIA certification**, and this project is not affiliated with or endorsed by NVIDIA.

## Requirements

- Windows 10 or 11, 64-bit, with **Windows PowerShell 5.1** (built into Windows). Nothing else to install: no Python, SDK or extra driver. The small C# part is compiled in memory by PowerShell itself.
- An NVIDIA GPU driving the **internal eDP panel directly**. On laptops with a MUX switch or Advanced Optimus, select the dedicated GPU (dGPU) mode first. The scripts do not change the MUX.
- A panel that is physically capable of variable refresh.
- Administrator rights to enable or disable. Windows shows a UAC prompt.

External HDMI/DisplayPort monitors and LVDS panels are **not** targets of this package. External G-SYNC monitors already work through the normal NVIDIA Control Panel.

Keep the whole folder together. The scripts load the module from the `src` subfolder.

## Quick start

### 1. Check, without changing anything

Open PowerShell in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Enable.ps1 -CheckOnly
```

It prints the GPU, the panel, the preset it would use, the driver key it would write to and the SHA-256 of the table. It does not touch the registry or any backup. Example from the confirmed laptop:

```text
Gpu                 : NVIDIA GeForce RTX 3050 6GB Laptop GPU
DriverVersion       : 32.0.16.2114
MonitorId           : DISPLAY\CMN1522\<instance>
ManufacturerRaw     : 0xAE0D
Product             : 0x1522
Connection          : eDP directly on the NVIDIA GPU
Preset              : DellValidated
PhysicallyValidated : True
Sha256              : 509176cbfb658ff4b4cf6c3def7f08a5ac5917aaa2ac3e189385a9f7178a73db
Bytes               : 226
TableExists         : True
AlreadyMatches      : True
```

### 2. Enable

Double-click **`Enable.cmd`** and accept the UAC prompt. Then:

1. Restart Windows.
2. Open **NVIDIA Control Panel → Display → Set up G-SYNC**.
3. Tick **Enable G-SYNC** and choose fullscreen, or fullscreen and windowed.
4. Test a game in fullscreen. The G-SYNC indicator, in the **Display** menu at the top of the NVIDIA Control Panel, helps you confirm it is active.

### 3. Disable

Double-click **`Disable.cmd`**, accept UAC and restart Windows. The original value comes back exactly as it was, or the value is removed if it did not exist before.

> [!TIP]
> Both actions can be repeated as often as you like. Always restart Windows afterwards: the driver only reads the table at start-up.

## Presets

| Preset | When it is used | Format | Status |
|---|---|---|---|
| `Auto` (default) | Picks `DellValidated` when the known GPU, panel and platform IDs match; otherwise `Generic2023` | — | — |
| `DellValidated` | Dell G15 5530 with RTX 3050 (10DE:25EC, subsystem 1028:0BF8), CMN1522 panel and the matching Intel host bridge | 2014 G-SYNC template, including platform IDs | Byte-identical to the table confirmed in practice (226 bytes) |
| `Generic2023` | Any other eDP panel on an NVIDIA GPU | 2023 G-SYNC template with only GPU and panel IDs (no motherboard IDs) | Validated offline only; **no physical test** on other hardware yet |

To preview the generic table without applying anything:

```powershell
.\Enable.ps1 -CheckOnly -Preset Generic2023
```

## How it works

### 1. Detection

- `EnumDisplayDevicesW` lists active display adapters with vendor `VEN_10DE` (NVIDIA) and their active monitors.
- `WmiMonitorConnectionParams` confirms that the same monitor instance is connected as **eDP** (video output technology 11).
- The GPU's PnP device is matched to that adapter. Its `Driver` property resolves the **current** class key. The script never assumes a fixed `0001` subkey. Ambiguous setups are refused or need explicit `-GpuInstanceId` / `-MonitorId`.
- The panel's EDID is read from that monitor instance and validated: header, length, digital input and the checksum of every block. The manufacturer and product words are read in the little-endian order the NVIDIA parser uses. On the CMN1522, bytes `0D AE` become `AE0D` and the product is `1522`. That order was decisive in the confirmed case.

### 2. Generation

The table is built in memory by `src/Native.cs`:

1. **Template.** One of two NVIDIA G-SYNC platform templates (2014 or 2023). Each has a 20-character region (offsets 62–81) filled with ASCII zeros and an ID region starting at offset 85.
2. **IDs.** The GPU's PCI IDs (vendor, device, subsystem vendor, subsystem device), the panel's manufacturer and product words and, for `DellValidated`, the platform IDs.
3. **Encoding.** The IDs are encoded into the ID region with the same rolling-key scheme the driver decodes:

   <details>
   <summary>Encoding pseudo-code</summary>

   ```text
   checksum = sum(bytes 62..81) mod 256
   key  = checksum mod 63
   step = floor(checksum / 20)
   for each byte at absolute offset position:
       encoded = ((original - 32) XOR key) + 32
       key  = (key + step) mod 63
       step = (step + position) mod 256
   ```

   </details>

4. **VK object.** The payload gets a NUL terminator and a 16-byte NBSI header: an 8-byte FNV-1a 64-bit hash, type `VK` (`0x564B`), the total size and version `0x0100`.
5. **Directory.** A 12-byte NBSI directory with a single entry wraps the object (signature `0x4E425349`, size, count 1, version 1, type `VK`).

The result is 226 bytes for `DellValidated` and 210 bytes for `Generic2023`.

### 3. Writing

`Enable` saves the backup **before** writing, writes only `RMemNBSItable`, then reads the value back and compares its hash. If the value already equals the generated table, nothing is written.

## Backups and safe restore

Backups are stored outside this folder, readable only by Administrators and SYSTEM:

```text
%ProgramData%\NvidiaVrrPatch\<machine fingerprint>\<GPU hash>.json
```

Each backup records:

- whether the value existed, its type and its exact bytes (Base64, with a hash);
- a hash of the machine's identity and the GPU instance;
- the hash of the table that was applied.

Writes use a temporary file and an atomic replace. Restored backups move to `history`.

The restore logic refuses to guess:

| Situation | What happens |
|---|---|
| Current value is the table this patch applied | Original restored (or value removed if it did not exist) |
| Current value already equals the original | Nothing to do; reported as already original |
| Current value was changed by something else after activation | **Stops**, nothing overwritten |
| Backup from another computer, or corrupted | **Refused** |
| A table already exists and no backup of its original is known | `Enable` refuses to replace it |

Re-running `Enable` never replaces the original backup. `Disable` resolves the GPU from the backup, so it works even if the panel is not active at that moment.

> [!CAUTION]
> There is no `-Force` option. The scripts never apply over an invalid EDID, a display not driven by the NVIDIA GPU, or a conflicting backup.

## Command reference

| Command | What it does |
|---|---|
| `Enable.cmd` | Double-click: runs `Enable.ps1` with a UAC prompt and waits for Enter at the end |
| `Disable.cmd` | Double-click: runs `Disable.ps1` with a UAC prompt |
| `.\Enable.ps1 -CheckOnly` | Shows the target and the table; changes nothing |
| `.\Enable.ps1 -WhatIf` | Same as above, through PowerShell's standard preview |
| `.\Enable.ps1 -Preset DellValidated\|Generic2023` | Forces a preset (`Auto` by default) |
| `.\Enable.ps1 -ImportBackup <file>` | Imports a backup of the original value made by an earlier manual procedure |
| `.\Disable.ps1 -WhatIf` | Shows what would be restored; may need an elevated window to read the protected backups |
| `.\Diagnostics.ps1` | Read-only report of the selected target |
| `.\Diagnostics.ps1 -List` | Lists every display on an NVIDIA GPU, with eDP eligibility |
| `-GpuInstanceId '<PCI\VEN_10DE&…>'` | Selects the GPU explicitly (Enable, Disable, Diagnostics) |
| `-MonitorId 'DISPLAY\<MODEL>\<INSTANCE>'` | Selects the panel explicitly (Enable, Diagnostics) |

The scripts do not bypass PowerShell's execution policy on their own. The `.cmd` launchers call PowerShell with `-File`; if a policy set by your administrator blocks scripts, nothing is applied.

## Checking that it worked

- After the restart, **Set up G-SYNC** must be listed under **Display** in the NVIDIA Control Panel.
- With G-SYNC on and the indicator enabled, a fullscreen game shows the G-SYNC indicator.
- Watch for tearing, flicker or blackouts. Seeing the option in the panel alone does not prove the display's physical refresh range.

In the confirmed case the driver reported the panel as VRR-capable and the user confirmed it worked perfectly. The panel's full refresh range was not measured independently. Below about 48 Hz the driver uses Low Framerate Compensation (it repeats frames).

## Troubleshooting

<details>
<summary><b>"No active display is connected directly to the NVIDIA GPU"</b></summary>

The internal screen is driven by the Intel/AMD GPU (hybrid mode). Switch the laptop to dedicated GPU mode in the manufacturer's software or BIOS. Choosing "high-performance GPU" for one app is not enough.

</details>

<details>
<summary><b>"Did not find exactly one active eDP display"</b></summary>

The target may be external, inactive or not reported as eDP by Windows. Run `.\Diagnostics.ps1 -List`. With several eligible displays, pass `-MonitorId` with the exact instance.

</details>

<details>
<summary><b>"RMemNBSItable already exists and there is no backup of its original value"</b></summary>

An OEM configuration or an earlier patch is present. Without a known backup of the original, the script will not replace it. If you made such a backup with an earlier manual procedure (a JSON with `Key`, `Name`, `Existed`, `OriginalBase64` and `AppliedSha256`), put it in an `original-backup` folder next to the scripts, where `Enable` and `Disable` pick it up automatically, or pass it with `-ImportBackup`. Never delete a value or a backup to force an install: a backup made after patching does not represent the original state.

</details>

<details>
<summary><b>"This computer has no managed activation" when disabling</b></summary>

No backup of this patch was found, and no matching backup exists in an `original-backup` folder next to the scripts. The script does not remove tables it did not create.

</details>

<details>
<summary><b>"The current value changed after activation"</b></summary>

Other software or a driver reinstall changed the value. The script stops so that state is preserved. Check the driver version and the current configuration before deciding on any manual restore.

</details>

<details>
<summary><b>The G-SYNC option did not appear</b></summary>

Restart Windows after enabling and run the diagnostics again. Make sure the panel is still on the NVIDIA GPU. On other hardware or drivers, the table may be rejected or something else may block VRR. Writing the value successfully does not prove that the driver accepted it.

</details>

<details>
<summary><b>It appeared, but the screen is unstable</b></summary>

Turn G-SYNC off in the NVIDIA Control Panel to test. Then run `Disable.cmd` and restart. Disabling does not undo settings you changed by hand in the Control Panel.

</details>

<details>
<summary><b>After a driver update the option disappeared</b></summary>

An update or clean reinstall can remove or ignore the table. Run `.\Enable.ps1 -CheckOnly`, then `Enable.cmd` again, and restart.

</details>

## Compatibility and limits

| Item | Status |
|---|---|
| Dell G15 5530, BIOS 1.36.0, RTX 3050 6 GB Laptop (10DE:25EC / 1028:0BF8), CMN1522 panel, driver 621.14 (32.0.16.2114), Windows 11 | **Confirmed in practice** (`DellValidated`) |
| `Generic2023` on the same hardware | Validated offline only; not physically tested as a separate preset |
| Other laptops, panels or driver versions | Untested: the table is generated for your IDs, but whether the driver accepts it is not guaranteed |

The scripts are refused when:

- PowerShell is 32-bit, or the system is not Windows;
- no active display is on the NVIDIA GPU, or the connection is not eDP;
- the EDID is missing, analog, truncated or has a bad checksum;
- the target is ambiguous;
- the GPU's driver key cannot be identified;
- a table exists without a known original backup.

A driver update can remove the value or stop accepting it. The package does not use private driver offsets or run code in the kernel, but acceptance of the object still depends on the driver's implementation.

## FAQ

<details>
<summary><b>Is this an official NVIDIA certification or a driver mod?</b></summary>

No. It writes one registry value that the unmodified driver reads. It is an independent experiment, not affiliated with or endorsed by NVIDIA.

</details>

<details>
<summary><b>Can it damage the panel?</b></summary>

It does not change voltages, timings, EDID or firmware. It only lets the driver use VRR on a panel that already supports it. If something looks wrong, disable it and restart.

</details>

<details>
<summary><b>Does it need Secure Boot, the antivirus or memory integrity turned off?</b></summary>

No.

</details>

<details>
<summary><b>Can I copy my backup to another PC to disable the patch there?</b></summary>

No. Backups are tied to the machine and the GPU, and the scripts refuse a backup from another computer.

</details>

<details>
<summary><b>Will it survive Windows updates?</b></summary>

Usually yes, because it lives in the driver's registry key. A GPU driver reinstall can remove it; just enable it again.

</details>

## Files

| File | Purpose |
|---|---|
| `Enable.cmd` / `Enable.ps1` | Check and enable |
| `Disable.cmd` / `Disable.ps1` | Restore the original state |
| `Diagnostics.ps1` | Read-only report |
| `src/NvidiaVrrPatch.psm1` | Detection, backups, writing and restore |
| `src/Native.cs` | Display enumeration and table generation (compiled in memory by PowerShell) |
| `LICENSE` | MIT license |

## Legal notes

- **Independent project.** Not affiliated with, endorsed, sponsored or supported by NVIDIA Corporation, Dell Inc. or any hardware vendor. NVIDIA, GeForce and G-SYNC are trademarks of NVIDIA Corporation; Dell is a trademark of Dell Inc. The names are used only to describe compatibility.
- **No NVIDIA files.** This package contains no NVIDIA driver, firmware, binary or source code, and it does not modify any of them. It writes one registry value that the unmodified driver reads.
- **Interoperability.** The template text inside the generated table is reproduced only because the driver's parser requires that exact layout. It is not a certification. Enabling VRR this way is not an official NVIDIA feature for your hardware.
- **Your hardware, your responsibility.** Use it only on hardware you own. You are responsible for complying with the license terms of your GPU driver and with the laws of your country. The tool is free, non-commercial and provided as is, without warranty of any kind (see `LICENSE`).
- **Rights holders.** If you represent a rights holder and have a concern about this project, please open an issue. It will be addressed promptly.

## Sources and license

- [NVIDIA open-gpu-kernel-modules](https://github.com/NVIDIA/open-gpu-kernel-modules): `nbsi_table.h`, `nbsi_init.c`, `fnv_hash.c`, `edid.h`, `nvt_edid.c`, used as a reference for structures and flows.
- [Microsoft: EnumDisplayDevicesW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaydevicesw)
- [Microsoft: WmiMonitorConnectionParams](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorconnectionparams)
- [Microsoft: DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_video_output_technology)

The tooling and documentation are released under the **MIT License** (see `LICENSE`). NVIDIA names, marks and template strings belong to NVIDIA. Provided as is, with no warranty. Use it at your own risk.
