#!/usr/bin/env pwsh
# Requires VMware PowerCLI and vSphere 6.7+ for FCD snapshot management
#
# This script can now automatically remove FCD snapshots using the vSphere DeleteSnapshot_Task API!
# 
# FEATURES:
# - Automatically detects and removes FCD snapshots before deleting orphaned FCDs
# - Uses vSphere VSLM (Virtual Storage Lifecycle Management) APIs
# - Provides detailed logging of snapshot removal process
# - Falls back to manual instructions if automatic removal fails
#
# REQUIREMENTS:
# - vSphere 6.7 or later (for FCD snapshot management APIs)
# - PowerCLI with appropriate permissions
# - Datastore.FileManagement privilege on the target datastore
#
# FALLBACK OPTIONS (if automatic removal fails):
# 1. vSphere Client UI (recommended)
# 2. govc command line tool: 
#    - List snapshots: govc disk.snapshot.ls <FCD-ID>
#    - Remove snapshot: govc disk.snapshot.rm <FCD-ID> <snapshot-ID>
# 3. vSphere MOB: https://<vcenter>/vslm/mob/?moid=VStorageObjectManager&method=VslmDeleteSnapshot_Task

# Parameters
param(
    [string]$vCenterServer,
    [string]$vCenterUser,
    [string]$vCenterPassword,
    [switch]$RemoveOrphaned # Add a switch to control removal
)

# Helper functions for FCD snapshot management using vSphere API
function Get-VDiskSnapshots {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VDiskId,
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore
    )
    
    try {
        # Get the vSphere Storage Object Manager
        $si = Get-View ServiceInstance
        $vsom = Get-View $si.Content.VStorageObjectManager
        
        # Create the storage object ID
        $storageObjectId = New-Object VMware.Vim.ID
        $storageObjectId.Id = $VDiskId
        
        # List snapshots for the FCD
        $snapshotInfo = $vsom.VslmListSnapshots($storageObjectId, $Datastore.ExtensionData.MoRef)
        
        # Extract snapshot IDs from the snapshot info
        $snapshots = @()
        if ($snapshotInfo -and $snapshotInfo.Snapshots) {
            foreach ($snap in $snapshotInfo.Snapshots) {
                $snapshots += [PSCustomObject]@{
                    Id = $snap.Id.Id
                    Description = $snap.Description
                    CreateTime = $snap.CreateTime
                }
            }
        }
        
        return $snapshots
    }
    catch {
        Write-Warning "Could not retrieve snapshots for FCD $VDiskId using vSphere API: $_"
        return @()
    }
}

function Remove-VDiskSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VDiskId,
        [Parameter(Mandatory=$true)]
        [string]$SnapshotId,
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore
    )
    
    try {
        # Get the vSphere Storage Object Manager
        $si = Get-View ServiceInstance
        $vsom = Get-View $si.Content.VStorageObjectManager
        
        # Create the storage object ID
        $storageObjectId = New-Object VMware.Vim.ID
        $storageObjectId.Id = $VDiskId
        
        # Create snapshot ID object
        $snapshotIdObj = New-Object VMware.Vim.ID
        $snapshotIdObj.Id = $SnapshotId
        
        # Delete the snapshot using the DeleteSnapshot_Task API
        $task = $vsom.VslmDeleteSnapshot_Task($storageObjectId, $Datastore.ExtensionData.MoRef, $snapshotIdObj)
        
        # Wait for task completion
        $taskView = Get-View $task
        while ($taskView.Info.State -eq "running") {
            Start-Sleep -Seconds 2
            $taskView.UpdateViewData()
        }
        
        if ($taskView.Info.State -eq "success") {
            Write-Verbose "Successfully removed snapshot $SnapshotId from FCD $VDiskId"
            return $true
        } else {
            throw "Task failed: $($taskView.Info.Error.LocalizedMessage)"
        }
    }
    catch {
        Write-Error "Failed to remove snapshot $SnapshotId from FCD $VDiskId using vSphere API: $_"
        throw
    }
}

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
                        # Get the VDisk object first to check for snapshots
                        $vdisk = Get-VDisk -Id $($item.ID)
                        
                        # Try to get FCD snapshots using vSphere API
                        $fcdSnapshots = Get-VDiskSnapshots -VDiskId $($item.ID) -Datastore $vdisk.Datastore
                        
                        if ($fcdSnapshots.Count -gt 0) {
                            Write-Host "Found $($fcdSnapshots.Count) snapshot(s) for VMDK: $($item.Filename)"
                            $outputString += " Found $($fcdSnapshots.Count) snapshot(s)."
                            
                            # Remove each snapshot
                            foreach ($snapshot in $fcdSnapshots) {
                                try {
                                    Write-Host "Removing snapshot: $($snapshot.Id) (Description: $($snapshot.Description), Created: $($snapshot.CreateTime))"
                                    Remove-VDiskSnapshot -VDiskId $($item.ID) -SnapshotId $snapshot.Id -Datastore $vdisk.Datastore
                                    Write-Host "Successfully removed snapshot: $($snapshot.Id)"
                                    $outputString += " Removed snapshot: $($snapshot.Id)."
                                }
                                catch {
                                    Write-Error "Failed to remove snapshot '$($snapshot.Id)': $_"
                                    $outputString += " Failed to remove snapshot '$($snapshot.Id)': $_"
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
                        # Check if the error is related to snapshots
                        if ($_.Exception.Message -like "*snapshot*" -or $_.Exception.Message -like "*Cannot be performed on FCD with snapshots*") {
                            Write-Warning "VMDK '$($item.Filename)' has snapshots that couldn't be removed automatically."
                            Write-Warning "You can try manual removal using one of these methods:"
                            Write-Warning "1. Use VMware vSphere Client UI to delete snapshots"
                            Write-Warning "2. Use govc command: govc disk.snapshot.ls $($item.ID) (to list) and govc disk.snapshot.rm $($item.ID) <snapshot-id> (to remove)"
                            Write-Warning "3. Use vSphere MOB: https://<vcenter-ip>/vslm/mob/?moid=VStorageObjectManager&method=VslmDeleteSnapshot_Task"
                            $outputString += " *ERROR: Has snapshots - automatic removal failed, manual removal required.*"
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
