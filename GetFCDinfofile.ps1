#!/usr/bin/env pwsh
# Requires VMware PowerCLI

# Parameters
param(
    [string]$vCenterServer = $(Read-Host "Enter vCenter Server"),
    [string]$vCenterUser = $(Read-Host "Enter vCenter Username"),
    [string]$vCenterPassword = $(Read-Host "Enter vCenter Password - will be prompted")
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
$filename1 = $x.Substring(0, $x.IndexOf('.') + 1 + $x.Substring($x.IndexOf('.') + 1).IndexOf('.'))  -replace "\.", "-"
$filename1 += "-INFO.txt"

Remove-Item -Path $filename1

try {
    # Get all First Class Disks
    $fcds = Get-VDisk

    # Filter for orphaned FCDs (those not attached to any VM)
    $orphanedFcds = $fcds | Where-Object { $_.VM -eq $null }

    # Display the orphaned FCDs
    if ($orphanedFcds.Count -gt 0) {
        "Orphaned First Class Disks:" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
        foreach ($fcd in $orphanedFcds) {
            "  Name: $($fcd.Name)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  Datastore: $($fcd.Datastore.Name)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  CapacityGB: $($fcd.CapacityGB)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  UID: $($fcd.Uid)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  ID: $($fcd.Id)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  Filename: $($fcd.Filename )" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
            "  ------------------------" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
        }
    } else {
        "No orphaned First Class Disks found." | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
    }
}
catch {
    Write-Error $_
}
finally {
    # Disconnect from vCenter Server
    Disconnect-VIServer -Confirm:$false
    "Completed" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8 #added to output to file.
    Write-Host "Completed" #keep console output
}
