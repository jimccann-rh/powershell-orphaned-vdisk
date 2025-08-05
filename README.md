# powershell-orphaned-vdisk

## 🚀 **Automated VMware FCD/VMDK Orphan Detection & Removal Suite**

These scripts are to help find orphaned FCD/VMDK and remove them. It will not remove if FCD/VMDK is attached to a VM.

### **📋 Script Overview**

This repository contains **two PowerShell scripts** that work together to identify and safely remove orphaned First Class Disks (FCDs) and VMDKs from VMware vSphere environments:

#### **🔍 Script 1: `GetFCDinfofile.ps1` (Data Collection)**
- **Purpose**: Scans vCenter for all First Class Disks and identifies orphaned ones
- **Output**: Creates an INFO file containing detailed FCD information
- **Key Features**:
  - ✅ Connects to vCenter Server
  - ✅ Discovers all FCDs across all datastores
  - ✅ Identifies orphaned FCDs (not attached to any VM)
  - ✅ Exports FCD details: Name, ID, Datastore, Capacity, Filename
  - ✅ Safe read-only operation

#### **🎯 Script 2: `CheckVMDKAssignementFromFileNameOut.ps1` (Processing & Removal)**
- **Purpose**: Processes the FCD data and optionally removes orphaned disks
- **Input**: Uses data from `GetFCDinfofile.ps1` output
- **Key Features**:
  - ✅ **FULLY AUTOMATED** orphaned FCD detection and removal
  - ✅ **AUTOMATIC SNAPSHOT HANDLING**: Detects and removes FCD snapshots using vSphere API
  - ✅ Cross-references FCDs against all VM disk assignments
  - ✅ **Safe Operation**: Only removes truly orphaned FCDs (not assigned to any VM)
  - ✅ **Real-time Progress**: Color-coded console output with progress indicators
  - ✅ **Comprehensive Logging**: Detailed logs to both console and file
  - ✅ **Error Recovery**: Robust error handling with fallback options
  - ✅ **Manual Fallback**: Provides detailed manual instructions if automation fails

### **🔥 Advanced Snapshot Handling**

**NEW in latest version**: Fully automated FCD snapshot removal!

- **🤖 Automatic Detection**: Extracts snapshot IDs from vCenter error messages
- **🔧 API Integration**: Calls vSphere `DeleteSnapshot_Task` API directly  
- **⏱️ Task Monitoring**: Waits for snapshot deletion completion with timeout
- **🔄 Sequential Processing**: Removes snapshots first, then the FCD automatically
- **📋 Manual Fallback**: Provides vSphere Client, GOVC, and MOB instructions if needed

### **💡 How It Works**

The 1st script GetFCDinfofile.ps1 gets information on FCD/VMDK and puts into a file to be viewed and it will be processed by the 2nd script.

CheckVMDKAssignementFromFileNameOut.ps1 will used the data from the GetFCDinfofile.ps1 script to do the process of removing FCD/VMDK if the flag is set. Otherwise it will just make a report.


### **⚙️ Requirements**

- **VMware PowerCLI** (latest version recommended)
- **vCenter Server** connectivity
- **vSphere 6.7+** (for VSLM API snapshot handling)
- **Datastore.FileManagement** privilege on target datastores
- **PowerShell 5.1+** or **PowerShell Core 6+**

### **🔄 Complete Workflow**

1. **Data Collection Phase**:
   ```powershell
   ./GetFCDinfofile.ps1 -vCenterServer "vcenter.local.com" -vCenterUser "admin@vsphere.local"
   ```
   - Scans all FCDs and creates `[vcenter-name]-INFO.txt`

2. **Analysis & Removal Phase**:
   ```powershell
   # Report only (safe mode)
   ./CheckVMDKAssignementFromFileNameOut.ps1 -vCenterServer "vcenter.local.com" -vCenterUser "admin@vsphere.local"
   
   # Automated removal (with snapshot handling)
   ./CheckVMDKAssignementFromFileNameOut.ps1 -vCenterServer "vcenter.local.com" -vCenterUser "admin@vsphere.local" -RemoveOrphaned
   ```
   - Creates `[vcenter-name]-PROCESSED.txt` with results

### **🛡️ Safety Features**

- ✅ **VM Assignment Verification**: Triple-checks FCD assignments against all VMs
- ✅ **Read-Only Mode**: Default operation generates reports without changes
- ✅ **Explicit Removal Flag**: Requires `-RemoveOrphaned` parameter for deletions
- ✅ **Snapshot Detection**: Handles FCDs with snapshots automatically or provides manual guidance
- ✅ **Error Recovery**: Comprehensive error handling with fallback instructions
- ✅ **Detailed Logging**: Complete audit trail of all operations

### **📊 Output Files**

| File | Description | Content |
|------|-------------|---------|
| `[vcenter]-INFO.txt` | FCD Discovery Results | All orphaned FCDs with details |
| `[vcenter]-PROCESSED.txt` | Processing Results | Assignment status and removal actions |

### **🎯 Use Cases**

- **🧹 Storage Cleanup**: Remove orphaned FCDs consuming datastore space
- **📋 Compliance Auditing**: Generate reports of unattached storage objects  
- **🔍 Storage Analysis**: Understand FCD usage patterns across your environment
- **⚡ Automation**: Integrate into scheduled maintenance workflows

Example RUN below:

./GetFCDinfofile.ps1  -vCenterServer "vcenter.local.com" -vCenterUser "administrator@vsphere.local" -vCenterPassword ""
./CheckVMDKAssignementFromFileNameOut.ps1  -vCenterServer "vcenter.local.com" -vCenterUser "administrator@vsphere.local" -vCenterPassword "" -RemoveOrphaned 
