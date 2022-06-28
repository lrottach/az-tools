<#
.SYNOPSIS
  <Publish a new image version to an existing Azure Compute Gallery>
.DESCRIPTION
  <Guide a user through the image creation process from a Golden VM and publish it to an Azure Compute Gallery>
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - Example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  Version:        <1.0>
  Author:         <Lukas Rottach>
  Creation Date:  <23/06/2022>
  License:        <MIT>
  Site:           <https://github.com/lrottach/az-tools>
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

[CmdletBinding()]
param (
  [Parameter()]
  [string]$SourceVm,

  [Parameter()]
  [string]$ImageDefinition,

  [Parameter()]
  [string]$ImageVersion
)

$VerbosePreference = "Continue"
$InformationPreference = "Continue"

#----------------------------------------------------------[Declarations]----------------------------------------------------------

# Deployment variables
$tenantId = ""
$subscriptionId = ""
$deploymentLocation = ""

# Target resources
$targetComputeGallery = ""
$temporaryRg = ""


#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Function to write customized outputs to console
function Write-Log {
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Message,
 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Information', 'Warning', 'Error', 'Success')]
    [string]$Severity = 'Information'
  )
  
  switch ($Severity) {
    'Information' { 
      Write-Host "[INFORMATION] $Message" -ForegroundColor Blue
    }
    'Warning' {
      Write-Host "[WARNING] $Message" -ForegroundColor Yellow
    }
    'Error' {
      Write-Host "[ERROR] $Message" -ForegroundColor Red
    }
    'Success' {
      Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    }
  }
}

function Compare-AzContext {
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
  )

  $contextDetails = Get-AzContext

  if ($null -eq $contextDetails) {
    return $false
  }

  if ($contextDetails.Subscription.TenantId -eq $TenantId -and $contextDetails.Subscription.Id -eq $SubscriptionId) {
    return $true
  }

  return $false
  
}

function New-AzTemporaryVm {
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SourceVm,
 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TargetRgName
  )

  # Dependency Check
  Write-Log -Message "Checking required depencencies for temporary VM deployment" -Severity Information

  $vm = Get-AzVM -Name $SourceVm

  if ($null -eq $vm) {
    Write-Log -Message "The requested source VM does not exist. Restart the script and provide a valid virtual machine" -Severity Error
    exit
  }

  Write-Log -Message "Building new resource names" -Severity Information

  $vmName = $SourceVm + "temp"
  $snapshotName = $vmName + "-snapshot"
  $diskName = $vmName + "-disk"
  $nicName = $vmName + "-nic"
  
  if ($null -ne (Get-AzVM -Name $vmName)) {
    Write-Log -Message "Virtual machine with the name $($vmName) already exists in resource group $($TargetRgName)" -Severity Error
    Write-Log -Message "Cleanup old temporary resources and run the script again" -Severity Error
    exit
  }

  # Create snapshot from existing Golden VM
  Write-Log -Message "Preparing snapshot configuration" -Severity Information
  $snapshotConfig = New-AzSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id `
    -Location $vm.Location `
    -CreateOption Copy
    
  Write-Log -Message "Creating snapshot $($snapshotName)" -Severity Information
  $snapshot = New-AzSnapshot -Name $snapshotName -ResourceGroupName $TargetRgName -Snapshot $snapshotConfig

  $snapshot = Get-AzSnapshot -ResourceGroupName $TargetRgName -Name $snapshotName

  # Create managed disk from snapshot
  Write-Log -Message "Creating new managed disk $($diskName)" -Severity Information
  $diskconfig = New-AzDiskConfig -Location $deploymentLocation `
    -SourceResourceId $snapshot.Id `
    -CreateOption Copy
    
  $disk = New-AzDisk -Disk $diskconfig -ResourceGroupName $TargetRgName -DiskName $diskName

  Write-Log -Message "Starting VM configuration with size 'Standard_D2as_v4'" -Severity Information
  $vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_D2as_v4"
  $vmConfig = Set-AzVMOSDisk -VM $vmConfig `
    -ManagedDiskId $disk.Id `
    -CreateOption Attach `
    -Windows
  
  Write-Log -Message "Gathering resource information for target subnet $($targetSubnet) in virtual network $($targetVnetName)" -Severity Information
  $vnet = Get-AzVirtualNetwork -Name $targetVnetName -ResourceGroupName $targetVnetRgName
  $subnet = Get-AzVirtualNetworkSubnetConfig -Name $targetSubnet -VirtualNetwork $vnet

  Write-Log -Message "Started creation of network interface $($nicName)" -Severity Information

  $vmNic = New-AzNetworkInterface -Name $nicName `
    -ResourceGroupName $TargetRgName `
    -Location $deploymentLocation `
    -SubnetId $subnet.Id `
    -ErrorAction Continue

  $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $vmnic.Id
  $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Disable

  Write-Log -Message "Starting deployment of virtual machine $($vmName)" -Severity Information
  try {
    $vmInformation = New-AzVm -VM $vmConfig -ResourceGroupName $TargetRgName -Location $deploymentLocation -DisableBginfoExtension
    Write-Log -Message "Successfully created virtual machine" -Severity Success
  }
  catch {
    Write-Log -Message "Failed to deploy virtual machine $($vmName)" -Severity Error
    exit
  }

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Host "
 __      _______ _____ _______ _    _         _        _____  ______  _____ _  _________ ____  _____  
 \ \    / /_   _|  __ \__   __| |  | |  /\   | |      |  __ \|  ____|/ ____| |/ /__   __/ __ \|  __ \ 
  \ \  / /  | | | |__) | | |  | |  | | /  \  | |      | |  | | |__  | (___ | ' /   | | | |  | | |__) |
   \ \/ /   | | |  _  /  | |  | |  | |/ /\ \ | |      | |  | |  __|  \___ \|  <    | | | |  | |  ___/ 
    \  /   _| |_| | \ \  | |  | |__| / ____ \| |____  | |__| | |____ ____) | . \   | | | |__| | |     
     \/   |_____|_|  \_\ |_|   \____/_/    \_\______| |_____/|______|_____/|_|\_\  |_|  \____/|_|     
                                                                                                      
" -ForegroundColor DarkBlue
Write-Host "--------------------------------------------------------------"
Write-Host "Title:        Azure Managed Image Publisher"
Write-Host "Author:       Lukas Rottach"
Write-Host "Description:  Create and publish Azure Managed Images to an Azure Compute Gallery"
Write-Host "--------------------------------------------------------------"
