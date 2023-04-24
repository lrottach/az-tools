package main

import (
	"context"
	"fmt"
	"log"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/desktopvirtualization/armdesktopvirtualization/v2"
)

func main() {

	subId := "e7933ac0-8efa-46fa-9d1e-929ae1dd5e24"
	rgName := ""
	hpName := ""

	ctx := context.Background()

	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatalf("failed to obtain credentials: %v", err)
	}

	hpClient, err := createAzHostPoolClient(subId, cred)
	if err != nil {
		log.Fatalf("failed to acquire new host pool client %v: ", err)
	}

	hpList, err := listAzHostPools(hpClient, ctx)
	if err != nil {
		log.Fatalf("error: %v", err)
	}

	shClient, err := createAzSessionHostsClient(subId, cred)
	if err != nil {
		log.Fatalf("failed to acquire new session host client %v: ", err)
	}

	for _, pool := range hpList {
		// Print the id of each host pool
		if pool != nil && pool.ID != nil {
			fmt.Println("HostPool Id: ", *pool.ID)
		}
	}

	shList, err := listAzSessionHosts(shClient, ctx, rgName, hpName)
	if err != nil {
		log.Fatalf("failed query list of session hosts: %v", err)
	}

	for _, host := range shList {
		// Print the name of eacht host pools
		if host != nil && host.ID != nil {
			fmt.Println("Session Host Id: ", *host.ID)
		}
	}
}

// createAzHostPoolClient takes Azure credentials and generates a new HostPoolsClient
func createAzHostPoolClient(subId string, cred *azidentity.DefaultAzureCredential) (*armdesktopvirtualization.HostPoolsClient, error) {

	client, err := armdesktopvirtualization.NewHostPoolsClient(subId, cred, nil)
	if err != nil {
		log.Fatalf("failed to create HostPoolsClient: %v", err)
	}

	return client, nil
}

// createAzSessionHostsClient takes Azure credentials and generates a new SessionHostsClient
func createAzSessionHostsClient(subId string, cred *azidentity.DefaultAzureCredential) (*armdesktopvirtualization.SessionHostsClient, error) {
	client, err := armdesktopvirtualization.NewSessionHostsClient(subId, cred, nil)
	if err != nil {
		log.Fatalf("failed to create SessionHostsClient: %v", err)
	}

	return client, nil
}

// listAzHostPools func creates a list of
func listAzHostPools(client *armdesktopvirtualization.HostPoolsClient, ctx context.Context) ([]*armdesktopvirtualization.HostPool, error) {

	pager := client.NewListPager(nil)
	for pager.More() {
		nextResult, err := pager.NextPage(ctx)
		if err != nil {
			log.Fatalf("failed to advance page: %v", err)
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
			log.Fatalf("failed to advance page: %v", err)
		}

		for _, v := range nextResult.Value {
			log.Println("session host %s:", v.Name)
		}

		return nextResult.Value, nil
	}

	return nil, fmt.Errorf("failed to acquire list of session hosts")
}
