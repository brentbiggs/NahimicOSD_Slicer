[CmdletBinding(SupportsShouldProcess = $true)]
param()

<#
.SYNOPSIS
    Asserts that the script is running with Administrator privileges.
.DESCRIPTION
    Checks if the current process has Administrator role. If not, it attempts to restart the script
    with elevated privileges using 'RunAs'.
#>
function Assert-AdminPrivileges {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "This script requires Administrator privileges. Restarting as Administrator..." -ForegroundColor Yellow
        # Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"") -Verb RunAs
        
    }
}

<#
.SYNOPSIS
    Adds executable names to the Nahimic BlackApps.dat configuration file.
.DESCRIPTION
    Reads the existing BlackApps.dat file, checks for duplicates, and adds new executables
    if they are not already present. It rewrites the file ensuring ANSI encoding and a trailing newline.
    If no ConfigPath is provided, it recursively searches for BlackApps.dat in C:\ProgramData\A-Volute.
.PARAMETER ConfigPath
    Path to the BlackApps.dat file. Accepts pipeline input.
.PARAMETER ExecutablesToAdd
    Array of executable names (e.g., "app.exe") to add to the exclusion list.
.EXAMPLE
    Add-NahimicConfigEntries -ExecutablesToAdd "slicer.exe"
.EXAMPLE
    Get-ChildItem -Recurse -Filter "BlackApps.dat" | Add-NahimicConfigEntries -ExecutablesToAdd "myapp.exe"
#>
function Add-NahimicConfigEntries {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$ConfigPath,

        [string[]]$ExecutablesToAdd
    )

    begin {
        $pathsToProcess = @()
        
        # Check if ConfigPath was passed as a parameter (non-pipeline)
        if ($PSBoundParameters.ContainsKey('ConfigPath')) {
            $pathsToProcess = $ConfigPath
        }
        # If not passed and not expecting pipeline input, search for defaults
        elseif (-not $PSCmdlet.MyInvocation.ExpectingInput) {
            $searchRoot = "C:\ProgramData\A-Volute"
            Write-Verbose "Searching for BlackApps.dat files in $searchRoot..."
            $foundFiles = Get-ChildItem -Path $searchRoot -Filter "BlackApps.dat" -Recurse -ErrorAction SilentlyContinue
            
            if ($foundFiles) {
                $pathsToProcess = $foundFiles.FullName
            }
            else {
                Write-Warning "No BlackApps.dat files found in $searchRoot."
            }
        }
    }

    process {
        # If we have pipeline input, processing the current object ($ConfigPath denotes current item here)
        $currentBatch = @()
        if ($PSCmdlet.MyInvocation.ExpectingInput) {
            # If value comes from pipeline, it's bound to $ConfigPath
            if ($ConfigPath) { $currentBatch = @($ConfigPath) }
        }
        else {
            $currentBatch = $pathsToProcess
        }
        
        $processModified = $false
        
        foreach ($p in $currentBatch) {
            Write-Verbose "Processing: $p"
            
            if (-not (Test-Path $p)) {
                Write-Error "Config file not found: $p"
                continue
            }

            try {
                # Read existing content
                # Force array in case of single line
                $existingLines = @(Get-Content -Path $p)
                
                # Use a HashSet for efficient case-insensitive uniqueness check
                $existingSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$existingLines, [System.StringComparer]::OrdinalIgnoreCase)
                
                # Prepare list for final content
                $finalLines = [System.Collections.Generic.List[string]]::new()
                $finalLines.AddRange([string[]]$existingLines)

                $fileModified = $false
                foreach ($exe in $ExecutablesToAdd) {
                    # Attempt to add to the set; Add returns true if element was added (i.e., not present)
                    if ($existingSet.Add($exe)) {
                        Write-Host "Adding $exe to Configurator..." -ForegroundColor Green
                        $finalLines.Add($exe)
                        $fileModified = $true
                    }
                    else {
                        Write-Verbose "$exe is already present."
                    }
                }

                if ($fileModified) {
                    if ($PSCmdlet.ShouldProcess($p, "Update configuration with new slicer executables")) {
                        # Write back using ANSI encoding (Default in WinPS 5.1 is ANSI)
                        # Set-Content adds a newline after each item, ensuring a trailing newline
                        Set-Content -Path $p -Value $finalLines -Encoding Default
                        $processModified = $true
                    }
                }
            }
            catch {
                Write-Error "An error occurred reading or writing the config file '$p': $_"
            }
        }
        
        # Return status for this block execution
        return $processModified
    }

    end {
        # Cleanup if needed
    }
}

<#
.SYNOPSIS
    Wrapper function to add specific 3D slicer applications to Nahimic exclusions.
.DESCRIPTION
    Defines a list of known 3D slicer executables and adds them to found Nahimic configuration files.
    Restarts the AWCCService if changes are made.
.EXAMPLE
    Add-SlicerExclusions
.EXAMPLE
    Add-SlicerExclusions -WhatIf
#>
function Add-SlicerExclusions {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $slicerExecutables = @(
        "bambu-studio.exe",
        "orca-slicer.exe",
        "prusa-slicer.exe",
        "superslicer.exe",
        "slic3r.exe",
        "AnycubicSlicerNext.exe"
    )

    Write-Verbose "Checking Slicer Exclusions..."
    
    # Call the advanced function. It will handle searching if no ConfigPath is provided.
    # Returns an array of booleans if multiple processing steps occur, so we check if any are true.
    $results = Add-NahimicConfigEntries -ExecutablesToAdd $slicerExecutables
    
    $anyModified = $false
    if ($results -contains $true) {
        $anyModified = $true
    }

    if ($anyModified) {
        Write-Host "Configuration updated." -ForegroundColor Cyan
        
        $servicesToRestart = @("AWCCService", "NahimicService")
        $restartedCount = 0

        foreach ($serviceName in $servicesToRestart) {
            if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
                Write-Host "Restarting $serviceName..." -ForegroundColor Yellow
                try {
                    Restart-Service -Name $serviceName -Force -ErrorAction Stop
                    Write-Host "$serviceName restarted successfully." -ForegroundColor Green
                    $restartedCount++
                }
                catch {
                    Write-Error "Failed to restart service $serviceName : $_"
                }
            }
            else {
                Write-Verbose "Service '$serviceName' not found."
            }
        }

        if ($restartedCount -eq 0) {
            Write-Warning "No relevant services were found to restart automatically."
            Write-Warning "Please restart your computer manually to apply changes."
        }
    }
    else {
        Write-Verbose "No changes were needed for any found configuration files."
    }
}

<#
.SYNOPSIS
    Checks the installed Realtek Audio driver version.
.DESCRIPTION
    Warns the user if the Realtek Audio driver version is 6.0.9394.1 or lower,
    as newer versions (6.0.9484.1+) are required for the blacklist to function correctly.
#>
function Test-RealtekDriverVersion {
    $drivers = Get-CimInstance Win32_PnPSignedDriver -Filter "DriverName like 'RTKVHD64.sys'" -ErrorAction SilentlyContinue
    
    if (-not $drivers) {
        # If no Realtek audio driver found, nothing to warn about regarding this specific version issue.
        return
    }

    $minVersion = [System.Version]"6.0.9484.1"
    $warnThreshold = [System.Version]"6.0.9394.1"

    foreach ($driver in $drivers) {
        if ($driver.DriverVersion) {
            try {
                $currentVersion = [System.Version]$driver.DriverVersion
                
                if ($currentVersion -le $warnThreshold) {
                    Write-Warning "Detected Realtek Audio Driver version $currentVersion."
                    Write-Warning "The Nahimic blacklist may not work properly with driver versions 6.0.9394.1 or older."
                    Write-Warning "It is recommended to upgrade to driver version $minVersion or higher."
                }
            }
            catch {
                # Ignore version parsing errors
            }
        }
    }
}

# --- Main Script Execution ---

Test-RealtekDriverVersion

Assert-AdminPrivileges

# You can add other function calls here for different app groups if needed
Add-SlicerExclusions

Write-Host "Done."
Read-Host "Press Enter to exit"
