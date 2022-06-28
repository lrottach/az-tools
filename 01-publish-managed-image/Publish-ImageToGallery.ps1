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

function New-AzManagedImage {
  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ImageName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ImageVm,
 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingRgName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ImageNamePrefix 
  )

  Write-Log -Message "Starting image creation process" -Severity Information
  Write-Log -Message "Checking status for working virtual machine '$($ImageVm)'" -Severity Information

  $sysprepStatus = (Get-AzVM -Name $ImageVm -ResourceGroupName $WorkingRgName -Status).Statuses[1].DisplayStatus

  if (!($sysprepStatus.Contains("deallocated"))) {
    Write-Log -Message "VM was not properly deallocated. Start deallocating it" -Severity Information
    try {
      Stop-AzVM -Name $ImageVm -ResourceGroupName $WorkingRgName -Force
      Write-Log -Message "Deallocated virtual machine" -Severity Success
    }
    catch {
      Write-Log -Message "Failed to deallocate virtual machine" -Severity Error
      exit
    }
  }

  # Set vm status to generalized
  Write-Log -Message "Trying to set vm status to 'generalized'" -Severity Information
  try {
    $vmStatus = Set-AzVM -ResourceGroupName $WorkingRgName -Name $ImageVm -Generalized
    Write-Log -Message "Successfully set vm status to 'generalized'" -Severity Success
  }
  catch {
    Write-Log -Message "Failed to set vm status to 'generalized'" -Severity Error
    exit
  }

  Write-Log -Message "Loading vm information"
  $vmInformation = Get-AzVM -ResourceGroupName $WorkingRgName -Name $ImageVm
  $vmInformationGen = Get-AzVM -ResourceGroupName $WorkingRgName -Name $ImageVm -Status

  Write-Log -Message "Starting image creation process for managed image '$($imageName)' to resource group '$($WorkingRgName)'" -Severity Information
  try {
    # Create image and configuration
    $imageConfig = New-AzImageConfig -Location $vmInformation.Location -SourceVirtualMachineId $vmInformation.Id -HyperVGeneration $vmInformationGen.HyperVGeneration
    New-AzImage -Image $imageConfig -ImageName $ImageName -ResourceGroupName $WorkingRgName
    Write-Log -Message "Created managed image. Continue execution" -Severity Success
  }
  catch {
    Write-Log -Message "Failed to create managed image '$($imageName)'" -Severity Error
    exit
  }

  Start-Sleep -Seconds 10
}

  [CmdletBinding()]
  param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ManagedImageName,
 
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingRgName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ImageDefinition,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ImageVersion,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ComputeGallery,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ComputeGalleryRg
  )

  Write-Log -Message "Acquiring Azure managed image details for image '$($ManagedImageName)'"
  $managedImage = Get-AzImage -ImageName $ManagedImageName -ResourceGroupName $WorkingRgName
  Write-Log -Message "Checking target Azure Compute Gallery '$($ComputeGallery)'" -Severity Information
  $targetGallery = Get-AzGallery -Name $ComputeGallery -ResourceGroupName $ComputeGalleryRg

  try {
    Write-Log -Message "Starting deployment for new image version '$($ImageVersion)' on target definition '$($ImageDefinition)'" -Severity Information
    $imageVersion = New-AzGalleryImageVersion -ResourceGroupName $targetGallery.ResourceGroupName `
      -GalleryName $targetGallery.Name `
      -GalleryImageDefinitionName $ImageDefinition `
      -Name $ImageVersion `
      -Location $targetGallery.Location `
      -SourceImageId $managedImage.Id
    
    Write-Log -Message "Finished deployment of new image version" -Severity Success
  }
  catch {
    Write-Log -Message "Failed to create new image version on Azure Compute Gallery '$($ComputeGallery)'"
    exit
  }
  
  Start-Sleep -Seconds 5
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
Write-Host "------------------------------------------------------------------------------------" -ForegroundColor DarkBlue
Write-Host "Title:        Azure Managed Image Publisher" -ForegroundColor DarkBlue
Write-Host "Author:       Lukas Rottach" -ForegroundColor DarkBlue
Write-Host "Description:  Create and publish Azure Managed Images to an Azure Compute Gallery" -ForegroundColor DarkBlue
Write-Host "------------------------------------------------------------------------------------" -ForegroundColor DarkBlue

# Connection
Write-Log -Message "Checking if account is already authenticated for the configured tenant and subscription" -Severity Information
$isAuthenticated = Compare-AzContext -TenantId $tenantId -SubscriptionId $subscriptionId

if ($isAuthenticated) {
  Write-Log -Message "Already authenticated to Azure Tenant $($tenantId)" -Severity Success
}
else {
  Write-Log -Message "Follow the instructions to connect to your Azure tenant" -Severity Information
  try {
    $connectionDetails = Connect-AzAccount -UseDeviceAuthentication -Tenant $tenantId -Subscription $subscriptionId
    Write-Log -Message "Authentication successful. Welcome user $($connectionDetails.Context.Account.Id)" -Severity Success
  }
  catch {
    Write-Log -Message "Authentication failed" -Severity Error
    exit
  }
}

# Preparing
Write-Log -Message "Checking for temporary resource group $($temporaryRgName)" -Severity Information
$temporaryRg = Get-AzResourceGroup -Name $temporaryRgName -Location $deploymentLocation -ErrorAction SilentlyContinue
if ($temporaryRg) {
  Write-Log -Message "Temporary resource group already exists. Continue execution" -Severity Information
}
else {
  Write-Log -Message "Temporary resource group does not exist. Continue creation" -Severity Information
  try {
    $temporaryRg = New-AzResourceGroup -Name $temporaryRgName -Location $deploymentLocation -ErrorAction SilentlyContinue
    Write-Log "Successfully created temporary resource group $($temporaryRg.ResourceGroupName)" -Severity Success
  }
  catch {
    Write-Log "Failed to create temporary resource group $($temporaryRgName)" -Severity Error
    exit
  }
}

# Temp Vm Deployment
$tempVmName = New-AzTemporaryVm -SourceVm $SourceVm -TargetRgName $temporaryRgName

# Get ip configuration
$tempVm = Get-AzVM -Name $tempVmName
$tempVmNic = $tempVm.NetworkProfile.NetworkInterfaces[0].Id.Split("/") | Select-Object -Last 1
$ipConfig = (Get-AzNetworkInterface -Name $tempVmNic).IpConfigurations.PrivateIpAddress

# Waiting until sysprep was performed by user and vm is turned off
Write-Log -Message "Waiting until sysprep is completed" -Severity Information
Write-Log -Message "Connect to VM $($tempVm.Name) on address $($ipConfig) and shutdown after completed" -Severity Information
Write-Log -Message "Waiting until VM was turned off" -Severity Information
$sysprepCompleted = $false

do {
  $vmStatus = (Get-AzVM -Name $tempVmName -ResourceGroupName $temporaryRgName -Status).Statuses[1].DisplayStatus
  if ($vmStatus.Contains("deallocated") -or $vmStatus.Contains("stopped")) {
    $sysprepCompleted = $true
    Write-Log -Message "Detected that VM is stopped. Continue execution" -Severity Information
  }
  Start-Sleep -Seconds 10
} while (!($sysprepCompleted))

# Image creation
New-AzManagedImage -ImageName $imageName -ImageVm $tempVmName -WorkingRgName $temporaryRgName -ImageNamePrefix "win10-21H2-x64-en-gen2"

# Publish to compute gallery
Add-ImageToAzGallery -ManagedImageName $imageName `
  -WorkingRgName $temporaryRgName `
  -ImageDefinition $ImageDefinition `
  -ImageVersion $ImageVersion `
  -ComputeGallery $targetComputeGallery `
  -ComputeGalleryRg $targetComputeGalleryRg

Write-Log -Message "Starting cleanup tasks for temporary resources" -Severity Information
try {
  Remove-AzResourceGroup -Name $temporaryRgName -Force
  Write-Log -Message "Finished removal of all temporary resources" -Severity Success
}
catch {
  Write-Log -Message "Failed to remove temporary resources" -Severity Error
  exit
}

Write-Log -Message "End of script" -Severity Information