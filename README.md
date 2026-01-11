# NahimicOSD Slicer Exclusion Tool

A PowerShell script to automatically add 3D slicer applications to the Nahimic Audio "BlackApps" exclusion list. This prevents the Nahimic OSD (On-Screen Display) from injecting into these applications, which often causes crashes or stability issues in slicers like Orca Slicer, Bambu Studio, and PrusaSlicer.

## Features

- **Automatic Discovery**: Recursively searches `C:\ProgramData\A-Volute` for `BlackApps.dat` configuration files.
- **Idempotent**: Checks if entries already exist before adding them to prevent duplicates.
- **Service Management**: Automatically restarts the `AWCCService` (Alienware Command Center Service) if changes are applied.
- **Safe Editing**: writes files with ANSI encoding and ensures proper trailing newlines, mimicking the original file format.
- **WhatIf Support**: Supports `-WhatIf` to preview changes without applying them.

## Supported Slicers

- Bambu Studio (`bambu-studio.exe`)
- Orca Slicer (`orca-slicer.exe`)
- PrusaSlicer (`prusa-slicer.exe`)
- SuperSlicer (`superslicer.exe`)
- Slic3r (`slic3r.exe`)

## Usage

Run the script as Administrator.

```powershell
.\Add-SlicersToNahimic.ps1
```

### Preview Changes (Dry Run)

```powershell
.\Add-SlicersToNahimic.ps1 -WhatIf
```

### Manual Path

If you know the specific path to your config file, you can pipe it or pass it as an argument (though auto-discovery is recommended).

```powershell
Add-NahimicConfigEntries -ConfigPath "C:\Path\To\BlackApps.dat" -ExecutablesToAdd "another-app.exe"
```

## Requirements

- Windows PowerShell 5.1 or later.
- Administrator privileges (script will request elevation if not present).

## Known Issues / Driver Check

Even with the blacklist entry patched, you may still see the Nahimic overlay notification or experience crashes if you are running an outdated Realtek driver.

**Specific Driver Bug:**
The blacklist functionality is known to fail specifically with `RTKVHD64.sys` version `6.0.9394.1`. 

If you encounter this, updating to a later driver version (e.g., `6.0.9484.1` or higher) fixes the problem immediately. For Alienware users (e.g., Aurora R16), check the [Dell Support Drivers Page](https://www.dell.com/support/product-details/en-us/product/alienware-aurora-r16-desktop/drivers) (YMMV).

The script attempts to detect this version and warns you if found.
