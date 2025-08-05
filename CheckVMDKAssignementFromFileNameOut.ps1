#!/usr/bin/env pwsh
# Requires VMware PowerCLI
#
# 🚀 FULLY AUTOMATED orphaned FCD detection and removal script with snapshot handling
# 
# FEATURES:
# - Detects orphaned First Class Disks (FCDs) not assigned to any VM
# - AUTOMATICALLY removes FCD snapshots using vSphere VSLM API
# - AUTOMATICALLY removes orphaned FCDs after snapshot cleanup
# - Falls back to manual instructions if automation fails
# - Comprehensive logging to console and file
# - Real-time progress indicators
#
# AUTOMATED SNAPSHOT HANDLING:
# ✅ Detects FCD snapshots automatically
# ✅ Extracts snapshot IDs from error messages  
# ✅ Calls vSphere VslmDeleteSnapshot_Task API directly
# ✅ Waits for snapshot removal completion
# ✅ Removes the FCD automatically after snapshot cleanup
# ✅ Provides manual fallback options if automation fails
#
# REQUIREMENTS:
# - VMware PowerCLI
# - vCenter Server connectivity  
# - vSphere 6.7+ (for VSLM API support)
# - Datastore.FileManagement privilege on target datastores
#
# USAGE:
# .\CheckVMDKAssignementFromFileNameOut.ps1 -RemoveOrphaned
# 
# The script will:
# 1. Scan for orphaned FCDs (those not assigned to any VM)
# 2. For each orphaned FCD:
#    a. Try to remove it directly
#    b. If snapshots exist, automatically remove them using vSphere API
#    c. Remove the FCD after snapshot cleanup
#    d. Provide manual instructions if automation fails
# 3. Log all operations to console and file

# Parameters
param(
    [string]$vCenterServer,
    [string]$vCenterUser,
    [string]$vCenterPassword,
    [switch]$RemoveOrphaned # Add a switch to control removal
)

# Automated FCD snapshot removal using vSphere VSLM API
function Remove-FCDSnapshot {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FCDUuid,
        [Parameter(Mandatory=$true)]
        [string]$SnapshotId,
        [Parameter(Mandatory=$true)]
        [VMware.VimAutomation.ViCore.Types.V1.DatastoreManagement.Datastore]$Datastore
    )
    
    try {
        Write-Host "Attempting to remove FCD snapshot automatically..." -ForegroundColor Cyan
        
        # Get the vSphere Storage Object Manager
        $si = Get-View ServiceInstance
        $vsom = Get-View $si.Content.VStorageObjectManager
        
        # Create the storage object ID
        $storageObjectId = New-Object VMware.Vim.ID
        $storageObjectId.Id = $FCDUuid
        
        # Create snapshot ID object  
        $snapshotIdObj = New-Object VMware.Vim.ID
        $snapshotIdObj.Id = $SnapshotId
        
        # Delete the snapshot using the VslmDeleteSnapshot_Task API
        $task = $vsom.VslmDeleteSnapshot_Task($storageObjectId, $Datastore.ExtensionData.MoRef, $snapshotIdObj)
        
        # Wait for task completion
        $taskView = Get-View $task
        $timeout = 300 # 5 minute timeout
        $elapsed = 0
        
        while ($taskView.Info.State -eq "running" -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 5
            $elapsed += 5
            $taskView.UpdateViewData()
            Write-Host "." -NoNewline -ForegroundColor Yellow
        }
        Write-Host ""
        
        if ($taskView.Info.State -eq "success") {
            Write-Host "✅ Successfully removed FCD snapshot: $SnapshotId" -ForegroundColor Green
            return $true
        } elseif ($elapsed -ge $timeout) {
            Write-Warning "⏱️  Snapshot removal task timed out after $timeout seconds. Task may still be running in background."
            return $false
        } else {
            $errorMsg = if ($taskView.Info.Error) { $taskView.Info.Error.LocalizedMessage } else { "Unknown error" }
            Write-Error "❌ Snapshot removal task failed: $errorMsg"
            return $false
        }
    }
    catch {
        Write-Error "❌ Failed to remove FCD snapshot using vSphere API: $_"
        return $false
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
                        # Try to remove the VDisk directly
                        $vdisk = Get-VDisk -Id $($item.ID)
                        Remove-VDisk -VDisk $vdisk -Confirm:$false -ErrorAction Stop
                        Write-Host "Successfully removed orphaned VMDK: $($item.Filename)"
                        $outputString += " *Removed orphaned VMDK: $($item.Filename)"
                    }
                    catch {
                        # Check if the error is related to snapshots
                        if ($_.Exception.Message -like "*snapshot*" -or $_.Exception.Message -like "*Cannot be performed on FCD with snapshots*" -or $_ -like "*relies on this FCD*") {
                            # Extract snapshot ID from error message if possible
                            $snapshotId = ""
                            if ($_.Exception.Message -match "Snapshot ([0-9a-f\s\-]+) relies on this FCD") {
                                $snapshotId = $matches[1].Trim()
                            }
                            
                            # Extract UUID from FCD ID (remove datastore prefix)
                            $fcdUuid = $item.ID
                            if ($fcdUuid -match ":(.+)$") {
                                $fcdUuid = $matches[1]
                            }
                            
                            # Clean up snapshot ID for MOB usage (remove extra spaces)
                            $cleanSnapshotId = $snapshotId -replace '\s+', ' '
                            
                            Write-Host "⚠️  FCD SNAPSHOT DETECTED: $($item.Filename)" -ForegroundColor Yellow
                            Write-Host "Full FCD ID: $($item.ID)" -ForegroundColor White
                            Write-Host "FCD UUID: $fcdUuid" -ForegroundColor White
                            if ($snapshotId) {
                                Write-Host "Detected Snapshot ID: $snapshotId" -ForegroundColor Red
                            }
                            Write-Host ""
                            
                            # Try automated snapshot removal first
                            $automationSuccessful = $false
                            if ($snapshotId -and $cleanSnapshotId) {
                                $snapshotRemoved = Remove-FCDSnapshot -FCDUuid $fcdUuid -SnapshotId $cleanSnapshotId -Datastore $vdisk.Datastore
                                
                                if ($snapshotRemoved) {
                                    # Try to remove the FCD again after snapshot removal
                                    try {
                                        Write-Host "Now attempting to remove the FCD..." -ForegroundColor Cyan
                                        Remove-VDisk -VDisk $vdisk -Confirm:$false -ErrorAction Stop
                                        Write-Host "✅ Successfully removed orphaned VMDK: $($item.Filename)" -ForegroundColor Green
                                        $outputString += " *Removed FCD and its snapshot automatically*"
                                        $automationSuccessful = $true
                                    }
                                    catch {
                                        Write-Warning "Snapshot removed but FCD removal failed: $_"
                                        $outputString += " *Snapshot removed automatically, but FCD removal failed*"
                                        $automationSuccessful = $false
                                    }
                                } else {
                                    Write-Warning "Automated snapshot removal failed"
                                    $automationSuccessful = $false
                                }
                            } else {
                                Write-Warning "Cannot extract snapshot ID for automated removal"
                                $automationSuccessful = $false
                            }
                            
                            # If automated removal failed, provide manual instructions
                            if (-not $automationSuccessful) {
                                Write-Host "🔧 FALLBACK: MANUAL REMOVAL OPTIONS" -ForegroundColor Cyan
                                Write-Host "Automated removal failed. Please use one of these manual methods:" -ForegroundColor Yellow
                                Write-Host ""
                                Write-Host "Option 1 - vSphere Client UI (Recommended):" -ForegroundColor Green
                                Write-Host "  1. Open vSphere Client" 
                                Write-Host "  2. Navigate to Storage > First Class Disks"
                                Write-Host "  3. Find FCD: $($item.Name)"
                                Write-Host "  4. Right-click > Manage Snapshots > Delete snapshots"
                                Write-Host ""
                                Write-Host "Option 2 - GOVC Command Line:" -ForegroundColor Green
                                Write-Host "  # List snapshots:"
                                Write-Host "  govc disk.snapshot.ls $fcdUuid" -ForegroundColor White
                                if ($snapshotId) {
                                    Write-Host "  # Remove the detected snapshot:"
                                    Write-Host "  govc disk.snapshot.rm $fcdUuid `"$snapshotId`"" -ForegroundColor White
                                } else {
                                    Write-Host "  # Remove each snapshot (use snapshot ID from list):"
                                    Write-Host "  govc disk.snapshot.rm $fcdUuid <snapshot-id>" -ForegroundColor White
                                }
                                Write-Host ""
                                Write-Host "After removing snapshots, re-run this script to delete the FCD." -ForegroundColor Cyan
                                $outputString += " *ERROR: Automatic snapshot removal failed - manual removal required*"
                            }
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
