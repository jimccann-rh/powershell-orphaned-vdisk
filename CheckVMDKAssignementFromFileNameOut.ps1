#!/usr/bin/env pwsh
# Requires VMware PowerCLI

# Parameters
param(
    [string]$vCenterServer = $(Read-Host "Enter vCenter Server"),
    [string]$vCenterUser = $(Read-Host "Enter vCenter Username"),
    [string]$vCenterPassword = $(Read-Host "Enter vCenter Password - will be prompted"),
    [switch]$RemoveOrphaned # Add a switch to control removal
)

if (-not $vCenterPassword) {
    $vCenterPassword = Read-Host -AsSecureString "Enter vCenter Password" | ConvertFrom-SecureString
}

# Connect to vCenter
try {
    Connect-VIServer -Server $vCenterServer -User $vCenterUser -Password $vCenterPassword -force
}
catch {
    Write-Error "Failed to connect to vCenter: $_"
    exit 1
}

$x = $vCenterServer
$filename0 = $x.Substring(0, $x.IndexOf('.') + 1 + $x.Substring($x.IndexOf('.') + 1).IndexOf('.'))  -replace "\.", "-"
$filename1 = $filename0 + "-INFO.txt"
$filename2 = $filename0 + "-PROCESSED.txt"

Remove-Item -Path $filename2

try {
    # Get all VMs
    $vms = Get-VM

    # Read INFO.txt file
    $infoFile = Get-Content -Path ./$filename1

    # Loop through each line in the file and extract Name and Filename
    $vmdkInfo = @()
    $currentName = ""
    foreach ($line in $infoFile) {
        if ($line -like "  Name: *") {
            $currentName = $line.Substring($line.IndexOf(":") + 2).Trim()
        }
        if ($line -like "  ID: *") {
            $currentId = $line.Substring($line.IndexOf(":") + 2).Trim()
        }
        if ($line -like "  Filename: *") {
            # Extract VMDK path
            $vmdkPath = $line.Substring($line.IndexOf("[")).Trim()
            $vmdkInfo += [PSCustomObject]@{
                Name     = $currentName
                Filename = $vmdkPath
                ID       = $currentId
            }
        }
    }

    # Process each VMDK path
    foreach ($item in $vmdkInfo) {
        $assignedVm = $null
        foreach ($vm in $vms) {
            $vmDisks = $vm | Get-HardDisk -ErrorAction SilentlyContinue
            foreach ($disk in $vmDisks) {
                if ($disk.Filename -eq $item.Filename) {
                    $assignedVm = $vm
                    break
                }
            }
            if ($assignedVm) {
                break
            }
        }

        # Output result to file and console
        $outputString = ""
        if ($assignedVm) {
            $outputString = "VMDK '$($item.Filename)' (Name: $($item.Name), ID: $($item.ID)) is assigned to VM: $($assignedVm.Name) *****"
        } else {
            $outputString = "VMDK '$($item.Filename)' (Name: $($item.Name), ID: $($item.ID)) is not assigned to any VM."
                if ($RemoveOrphaned) {
                    try {
                        # Get the VDisk object
                        $vdisk = Get-VDisk -Id $($item.ID)
                        
                        # Check for and remove snapshots first
                        $snapshots = Get-VDiskSnapshot -VDisk $vdisk -ErrorAction SilentlyContinue
                        if ($snapshots) {
                            Write-Host "Found $($snapshots.Count) snapshot(s) for VMDK: $($item.Filename)"
                            $outputString += " Found $($snapshots.Count) snapshot(s)."
                            foreach ($snapshot in $snapshots) {
                                try {
                                    Remove-VDiskSnapshot -VDiskSnapshot $snapshot -Confirm:$false
                                    Write-Host "Removed snapshot: $($snapshot.Name)"
                                    $outputString += " Removed snapshot: $($snapshot.Name)."
                                }
                                catch {
                                    Write-Error "Failed to remove snapshot '$($snapshot.Name)': $_"
                                    $outputString += " Failed to remove snapshot '$($snapshot.Name)': $_"
                                    throw # Re-throw to prevent FCD removal if snapshot removal fails
                                }
                            }
                        }
                        
                        # Now remove the VDisk
                        Remove-VDisk -VDisk $vdisk -Confirm:$false
                        Write-Host "Removed orphaned VMDK: $($item.Filename)"
                        $outputString += " *Removed orphaned VMDK: $($item.Filename)"
                    }
                    catch {
                        Write-Error "Failed to remove VMDK '$($item.Filename)': $_"
                        $outputString += " Failed to remove VMDK '$($item.Filename)': $_"
                    }
                }
        }
        Write-Host $outputString #output to console
        $outputString | Out-File -FilePath ./$filename2 -Append -Encoding UTF8 #output to file
    }
}
catch {
    Write-Error $_
}
finally {
    # Disconnect from vCenter
    Disconnect-VIServer -Confirm:$false
}
