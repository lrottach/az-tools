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
