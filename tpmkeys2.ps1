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
$filename1 += "-TPM.txt"

Remove-Item -Path $filename1


function Get-EncryptionRecoveryKeys {
    $esxiHosts = get-vmhost | Where { $_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected" }
    $encryptionKeys = @()
 
    foreach ($esxiHost in $esxiHosts) {
        $esxCli = Get-EsxCli -VMHost $esxiHost -V2
        try {
            $recoveryKeyList = $esxCli.system.settings.encryption.recovery.list.Invoke()
            foreach ($key in $recoveryKeyList) {
                $encryptionKeys += [PSCustomObject]@{
                    HostName = $esxiHost.Name
                    RecoveryKey = $key.Key
                    #Description = $key.Description
                    #CreatedTime = $key.Created
                    RecoveryID = $key.RecoveryID
                }
            }
        } catch {
            Write-Error "Failed to retrieve encryption keys for host $($esxiHost.Name)"
        }
    }
 
    return $encryptionKeys
    Write-host $encryptionKeys
}

Get_EncryptionRecoveryKeys | Out-File -FilePath ./$filename1 -Append -Encoding UTF8

# Disconnect from vCenter Server
Disconnect-VIServer -Confirm:$false
"Completed" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8 #added to output to file.
Write-Host "Completed" #keep console output

