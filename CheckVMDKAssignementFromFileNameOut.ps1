#!/usr/bin/env pwsh
# Requires VMware PowerCLI
#
# IMPORTANT: This script cannot automatically remove FCDs that have snapshots.
# If a FCD has snapshots, you'll need to remove them manually first using:
# 1. vSphere Client UI (recommended)
# 2. govc command line tool: 
#    - List snapshots: govc disk.snapshot.ls <FCD-ID>
#    - Remove snapshot: govc disk.snapshot.rm <FCD-ID> <snapshot-ID>
# 3. vSphere MOB (Managed Object Browser)
#
# PowerCLI does not have native cmdlets for managing FCD snapshots.

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
                        # Try to remove the VDisk directly
                        $vdisk = Get-VDisk -Id $($item.ID)
                        Remove-VDisk -VDisk $vdisk -Confirm:$false
                        Write-Host "Removed orphaned VMDK: $($item.Filename)"
                        $outputString += " *Removed orphaned VMDK: $($item.Filename)"
                    }
                    catch {
                        # Check if the error is related to snapshots
                        if ($_.Exception.Message -like "*snapshot*" -or $_.Exception.Message -like "*Cannot be performed on FCD with snapshots*") {
                            Write-Warning "VMDK '$($item.Filename)' has snapshots and cannot be removed automatically."
                            Write-Warning "You need to manually remove FCD snapshots first using one of these methods:"
                            Write-Warning "1. Use VMware vSphere Client UI to delete snapshots"
                            Write-Warning "2. Use govc command: govc disk.snapshot.ls $($item.ID) (to list) and govc disk.snapshot.rm $($item.ID) <snapshot-id> (to remove)"
                            Write-Warning "3. Use vSphere MOB (Managed Object Browser) to delete snapshots manually"
                            $outputString += " *ERROR: Has snapshots - manual removal required. See console for instructions.*"
                        } else {
                            Write-Error "Failed to remove VMDK '$($item.Filename)': $_"
                            $outputString += " Failed to remove VMDK '$($item.Filename)': $_"
                        }
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
