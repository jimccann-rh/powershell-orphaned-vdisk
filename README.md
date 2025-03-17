# powershell-orphaned-vdisk
These scripts are to help find orpahaned FCD/VMDK and remove them. It will not remove if FCD/VMDK is attached to a VM.

The 1st script GetFCDinfofile.ps1 gets information on FCD/VMDK and puts into a file to be viewed and it will be processed by the 2nd script.

CheckVMDKAssignementFromFileNameOut.ps1 will used the data from the GetFCDinfofile.ps1 script to do the process of removing FCD/VMDK if the flag is set. Otherwise it will just make a report.


Example RUN below:

./GetFCDinfofile.ps1  -vCenterServer "vcenter.local.com" -vCenterUser "administrator@vsphere.local" -vCenterPassword ""
./CheckVMDKAssignementFromFileNameOut.ps1  -vCenterServer "vcenter.local.com" -vCenterUser "administrator@vsphere.local" -vCenterPassword "" -RemoveOrphaned 
