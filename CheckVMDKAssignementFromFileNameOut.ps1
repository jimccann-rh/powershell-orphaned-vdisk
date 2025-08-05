#!/usr/bin/env pwsh
# Requires VMware PowerCLI
#
# Enhanced orphaned FCD detection and removal script with snapshot handling
# 
# FEATURES:
# - Detects orphaned First Class Disks (FCDs) not assigned to any VM
# - Attempts automatic removal of orphaned FCDs  
# - Detects FCDs with snapshots and provides detailed removal instructions
# - Supports both interactive and automated execution
# - Comprehensive logging to console and file
#
# FCD SNAPSHOT HANDLING:
# When the script encounters an FCD with snapshots, it provides three removal options:
# 1. vSphere Client UI (recommended for most users)
# 2. govc command line tool (for automation/scripting)  
# 3. vSphere MOB (for advanced API users)
#
# REQUIREMENTS:
# - VMware PowerCLI
# - vCenter Server connectivity
# - Appropriate permissions for FCD management

# Parameters
param(
    [string]$vCenterServer,
    [string]$vCenterUser,
    [string]$vCenterPassword,
    [switch]$RemoveOrphaned # Add a switch to control removal
)

# Simplified approach: Detect snapshots via error messages and provide clear instructions
# The vSphere VSLM API methods are complex and vary between versions
# We'll detect snapshot issues and provide multiple removal options

# Prompt for required parameters if not provided
if (-not $vCenterServer) {
    $vCenterServer = Read-Host "Enter vCenter Server"
}

if (-not $vCenterUser) {
    $vCenterUser = Read-Host "Enter vCenter Username"
}

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
                        Write-Host "Successfully removed orphaned VMDK: $($item.Filename)"
                        $outputString += " *Removed orphaned VMDK: $($item.Filename)"
                    }
                    catch {
                        # Check if the error is related to snapshots
                        if ($_.Exception.Message -like "*snapshot*" -or $_.Exception.Message -like "*Cannot be performed on FCD with snapshots*") {
                            Write-Host "⚠️  FCD SNAPSHOT DETECTED: $($item.Filename)" -ForegroundColor Yellow
                            Write-Host "This FCD has snapshots and cannot be removed until snapshots are deleted." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "🔧 MANUAL REMOVAL OPTIONS:" -ForegroundColor Cyan
                            Write-Host "Option 1 - vSphere Client UI (Recommended):" -ForegroundColor Green
                            Write-Host "  1. Open vSphere Client" 
                            Write-Host "  2. Navigate to Storage > First Class Disks"
                            Write-Host "  3. Find FCD: $($item.Name)"
                            Write-Host "  4. Right-click > Manage Snapshots > Delete snapshots"
                            Write-Host ""
                            Write-Host "Option 2 - GOVC Command Line:" -ForegroundColor Green
                            Write-Host "  # List snapshots:"
                            Write-Host "  govc disk.snapshot.ls $($item.ID)" -ForegroundColor White
                            Write-Host "  # Remove each snapshot (use snapshot ID from list):"
                            Write-Host "  govc disk.snapshot.rm $($item.ID) <snapshot-id>" -ForegroundColor White
                            Write-Host ""
                            Write-Host "Option 3 - vSphere MOB (Advanced):" -ForegroundColor Green
                            Write-Host "  URL: https://$vCenterServer/vslm/mob/?moid=VStorageObjectManager&method=VslmDeleteSnapshot_Task"
                            Write-Host "  Parameters: id=$($item.ID), datastore=<datastore-moref>, snapshotId=<snapshot-id>"
                            Write-Host ""
                            Write-Host "After removing snapshots, re-run this script to delete the FCD." -ForegroundColor Cyan
                            $outputString += " *ERROR: Has snapshots - manual removal required (see console for instructions)*"
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
