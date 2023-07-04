# Azure Image Publisher Script

There are several different ways to create and publish images in Azure. 
You can implement solutions like the Azure Image Builder or HashiCorp Packer. Creating your images manually, with a script or automatically using pipelines.

### Purpose
This script is a simple way to create a managed image from a VM and publish it to a Azure Compute Gallery.

### Usage
The first part of the script is split into dynamic and static variables. The dynamic parameters are the ones which are changing from execution to execution.
The static parameters are the ones which are not changing normally.

### Process
The script is doing the following steps:
1. Checks the current authentication context and prompts for a new one if needed
2. Creates a temporary working resource group if it does not exist
3. Deployes a new snapshot using the provided VM as source
4. Creates a new temporary VM using the snapshot
5. Waiting until you sysprep the VM and shut it down
6. Deallocate the VM and set its status to generalized
7. Create a new managed image from the VM
8. Publish the image to the Azure Compute Gallery
9. Cleanup the temporary resources