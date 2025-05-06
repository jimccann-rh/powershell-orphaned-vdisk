#!/usr/bin/env pwsh
# Requires VMware PowerCLI

# Parameters
param(
    [string]$vCenterServer = $(Read-Host "Enter vCenter Server"),
    [string]$vCenterUser = $(Read-Host "Enter vCenter Username"),
    [string]$vCenterPassword = $(Read-Host -AsSecureString "Enter vCenter Password - will be prompted")
)

# Prompt for password if not provided via parameter
if (-not $vCenterPassword) {
    $vCenterPassword = Read-Host -AsSecureString "Enter vCenter Password" | ConvertFrom-SecureString
}

# Connect to vCenter
try {
    Write-Host "Connecting to vCenter Server: $($vCenterServer)..."
    Connect-VIServer -Server $vCenterServer -User $vCenterUser -Password $vCenterPassword -force
    Write-Host "Successfully connected to vCenter Server."
}
catch {
    Write-Error "Failed to connect to vCenter: $_"
    exit 1
}

# --- Directory and File Naming Handling ---

# Define the directory name for output files
$outputDirectory = "TPMFILES"

# Create the output directory if it doesn't exist
Write-Host "Ensuring output directory './$outputDirectory' exists..."
try {
    New-Item -Path "./$outputDirectory" -ItemType Directory -Force | Out-Null
    Write-Host "Output directory './$outputDirectory' is ready."
}
catch {
    Write-Error "Failed to create or ensure output directory './$outputDirectory': $_"
    Disconnect-VIServer -Confirm:$false # Attempt to disconnect before exiting
    exit 1
}

# Get the current date and format it as MMDDYY
$currentDate = Get-Date -Format "MMddyy"

# Extract the first part of the vCenter server name (up to the second dot, replacing dots with hyphens)
# Append the formatted date and "-TPM.txt" to the filename
$vCenterBaseName = $vCenterServer.Substring(0, $vCenterServer.IndexOf('.') + 1 + $vCenterServer.Substring($vCenterServer.IndexOf('.') + 1).IndexOf('.')) -replace "\.", "-"
$outputFileName = "$vCenterBaseName-$currentDate-TPM.txt"

# Construct the full path for the output file
$fullOutputPath = Join-Path -Path "./$outputDirectory" -ChildPath $outputFileName

Write-Host "Output will be saved to: $fullOutputPath"

# Remove the output file if it already exists (to start fresh)
if (Test-Path -Path $fullOutputPath) {
    Write-Host "Removing existing output file: $fullOutputPath"
    Remove-Item -Path $fullOutputPath
}

# --- Function to Get Encryption Recovery Keys ---

function Get-EncryptionRecoveryKeys {
    Write-Host "Gathering ESXi host information..."
    # Get powered on and connected ESXi hosts
    $esxiHosts = get-vmhost | Where { $_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected" }
    $encryptionKeys = @()

    Write-Host "Retrieving encryption recovery keys from hosts..."
    foreach ($esxiHost in $esxiHosts) {
        try {
            Write-Host "  Processing host: $($esxiHost.Name)"
            $esxCli = Get-EsxCli -VMHost $esxiHost -V2
            $recoveryKeyList = $esxCli.system.settings.encryption.recovery.list.Invoke()

            if ($recoveryKeyList) {
                foreach ($key in $recoveryKeyList) {
                    $encryptionKeys += [PSCustomObject]@{
                        HostName = $esxiHost.Name
                        RecoveryKey = $key.Key
                        #Description = $key.Description # Uncomment if needed
                        #CreatedTime = $key.Created # Uncomment if needed
                        RecoveryID = $key.RecoveryID
                    }
                }
                 Write-Host "    Found $($recoveryKeyList.Count) recovery keys."
            } else {
                 Write-Host "    No recovery keys found."
            }

        } catch {
            Write-Error "Failed to retrieve encryption keys for host $($esxiHost.Name): $_"
        }
    }

    return $encryptionKeys
}

# --- Main Execution ---

# Get the encryption keys and output them to the file
Write-Host "Executing Get-EncryptionRecoveryKeys function..."
Get-EncryptionRecoveryKeys | Out-File -FilePath $fullOutputPath -Append -Encoding UTF8

# Disconnect from vCenter Server
Write-Host "Disconnecting from vCenter Server..."
Disconnect-VIServer -Confirm:$false
Write-Host "Disconnected from vCenter Server."

# Add a completion message to the file and console
"Completed script execution." | Out-File -FilePath $fullOutputPath -Append -Encoding UTF8 #added to output to file.
Write-Host "Completed script execution." #keep console output

