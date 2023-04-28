package main

import (
	"context"
	"fmt"
	"os"
	"regexp"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v4"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/desktopvirtualization/armdesktopvirtualization/v2"
	"github.com/charmbracelet/log"
)

func main() {

	subId := "sub-id"
	rgName := "rg-name"
	hpName := "hp-name"

	ctx := context.Background()

	log.Info("creating new Azure default credential")
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatal("failed to obtain credentials", "error", err)
		os.Exit(1)
	}

	shClient, err := createAzSessionHostsClient(subId, cred)
	if err != nil {
		log.Fatal("failed to acquire new session host client", "error", err)
		os.Exit(1)
	}

	vmClient, err := createAzVirtualMachinesClient(subId, cred)
	if err != nil {
		log.Fatal("failed to create new VirtualMachinesClient", "error", err)
	}

	shList, err := listAzSessionHosts(shClient, ctx, rgName, hpName)
	if err != nil {
		log.Fatal("failed to query list of session hosts", "error", err)
		os.Exit(1)
	}

	log.Info("found session hosts", "count", len(shList))

	for _, host := range shList {
		log.Info("processing", "host", *host.Name)
		err := startAzvirtualMachine(vmClient, ctx, *host.Properties.ResourceID)
		if err != nil {
			log.Error("failed to start", "virtual machine", *host.Name)
		}
	}
}

// createAzHostPoolClient takes Azure credentials and generates a new HostPoolsClient
func createAzHostPoolClient(subId string, cred *azidentity.DefaultAzureCredential) (*armdesktopvirtualization.HostPoolsClient, error) {

	client, err := armdesktopvirtualization.NewHostPoolsClient(subId, cred, nil)
	if err != nil {
		log.Fatal("failed to create HostPoolsClient: %v", err)
		os.Exit(1)
	}

	return client, nil
}

// createAzSessionHostsClient takes Azure credentials and generates a new SessionHostsClient
func createAzSessionHostsClient(subId string, cred *azidentity.DefaultAzureCredential) (*armdesktopvirtualization.SessionHostsClient, error) {
	client, err := armdesktopvirtualization.NewSessionHostsClient(subId, cred, nil)
	if err != nil {
		log.Fatal("failed to create SessionHostsClient: %v", err)
	}

	return client, nil
}

// createAzVirtualMachinesClient takes Azure credentials and generates a new VirtualMachinesClient
func createAzVirtualMachinesClient(subId string, cred *azidentity.DefaultAzureCredential) (*armcompute.VirtualMachinesClient, error) {

	log.Info("creating new client factory")
	factory, err := armcompute.NewClientFactory(subId, cred, nil)
	if err != nil {
		log.Fatal("failed to create new factory", "error", err)
		os.Exit(1)
	}

	log.Info("creating new VirtualMachinesClient")
	client := factory.NewVirtualMachinesClient()

	return client, nil
}

// listAzHostPools func creates a list of
func listAzHostPools(client *armdesktopvirtualization.HostPoolsClient, ctx context.Context) ([]*armdesktopvirtualization.HostPool, error) {

	pager := client.NewListPager(nil)
	for pager.More() {
		nextResult, err := pager.NextPage(ctx)
		if err != nil {
			log.Fatal("failed to advance page: %v", err)
		}
		return nextResult.Value, nil
	}

	return nil, fmt.Errorf("failed to acquire list of host pools")
}

// listAzSessionHosts lists all session hosts of a host pool
func listAzSessionHosts(client *armdesktopvirtualization.SessionHostsClient, ctx context.Context, rgName string, hpName string) ([]*armdesktopvirtualization.SessionHost, error) {

	pager := client.NewListPager(rgName, hpName, nil)

	for pager.More() {
		nextResult, err := pager.NextPage(ctx)
		if err != nil {
			log.Fatal("failed to advance page: %v", err)
		}

		return nextResult.Value, nil
	}

	return nil, fmt.Errorf("failed to acquire list of session hosts")
}

// extractResourceGroup takes a resource id as an input and extracts the resource group name
func extractResourceGroup(resourceId string) string {
	re := regexp.MustCompile(`resourceGroups/([a-zA-Z0-9_-]+)/providers`)
	match := re.FindStringSubmatch(resourceId)

	if len(match) == 2 {
		return match[1]
	}

	return ""
}

// extractVmName takes a resource id as an input and extracts the virtual machine name
func extractVmName(resourceId string) string {
	re := regexp.MustCompile(`/virtualMachines/([a-zA-Z0-9_-]+)$`)
	match := re.FindStringSubmatch(resourceId)

	if len(match) == 2 {
		return match[1]
	}

	return ""
}

// startAzVirtualMachine takes a resource id of a virtual machine and starts it
func startAzvirtualMachine(client *armcompute.VirtualMachinesClient, ctx context.Context, vmId string) error {

	vmName := extractVmName(vmId)
	rgName := extractResourceGroup(vmId)

	_, err := client.BeginStart(ctx, rgName, vmName, nil)
	if err != nil {
		log.Fatal("failed to request virtual machine start", "error", err)
	}

	return nil
}

// deallocateAzVirtualMachine takes a resource id of a virtual machine and begins deallocating it
func deallocateAzVirtualMachine(client *armcompute.VirtualMachinesClient, ctx context.Context, vmId string) error {
	vmName := extractVmName(vmId)
	rgName := extractResourceGroup(vmId)

	_, err := client.BeginDeallocate(ctx, rgName, vmName, nil)
	if err != nil {
		log.Fatal("failed to request vm deallocate", "error", err)
	}

	return nil
}
