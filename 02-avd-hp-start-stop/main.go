package main

import (
	"context"
	"fmt"
	"log"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/desktopvirtualization/armdesktopvirtualization/v2"
)

func main() {

	subId := ""

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

	for _, pool := range hpList {
		// Print the id of each host pool
		if pool != nil && pool.ID != nil {
			fmt.Println("HostPool Id: ", *pool.ID)
		}
	}

}

// createAzHostPoolClient takes Azure credentials and generates a new HostPoolsClient
func createAzHostPoolClient(subId string, cred *azidentity.DefaultAzureCredential) (*armdesktopvirtualization.HostPoolsClient, error) {

	client, err := armdesktopvirtualization.NewHostPoolsClient(subId, cred, nil)
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}

	return client, nil
}

// listAzHostPoolsfunc craetes a list of
func listAzHostPools(client *armdesktopvirtualization.HostPoolsClient, ctx context.Context) ([]*armdesktopvirtualization.HostPool, error) {

	pager := client.NewListPager(nil)
	for pager.More() {
		nextResult, err := pager.NextPage(ctx)
		if err != nil {
			log.Fatalf("failed to advance page: %v", err)
		}
		for _, v := range nextResult.Value {
			fmt.Println(v.Name)
			_ = v
		}
		return nextResult.Value, nil
	}
	return nil, fmt.Errorf("failed to acquire list of host pools")

}
