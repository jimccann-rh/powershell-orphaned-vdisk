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


$VMHosts = get-vmhost | Sort-Object

foreach ($VMHost in $VMHosts) {
    $esxcli = Get-EsxCli -VMHost $VMHost
    try {
        $key = $esxcli.system.settings.encryption.recovery.list()
        "TPM Keys:" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
        Write-Host "$VMHost;$($key.RecoveryID);$($key.Key)"
        "$VMHost;$($key.RecoveryID);$($key.Key)" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8
    }

    catch {
        Write-Error $_
    }
}

# Disconnect from vCenter Server
Disconnect-VIServer -Confirm:$false
"Completed" | Out-File -FilePath ./$filename1 -Append -Encoding UTF8 #added to output to file.
Write-Host "Completed" #keep console output

