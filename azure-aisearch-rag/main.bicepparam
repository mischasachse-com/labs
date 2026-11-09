using 'main.bicep'

param location = 'swedencentral'

// swedencentral returned InsufficientResourcesAvailable and westeurope no
// longer accepts new AI Search services on this subscription; northeurope works.
param searchLocation = 'northeurope'

// Search, storage and OpenAI names are derived from the resource group id
// in main.bicep (.bicepparam files cannot call resourceGroup()).

param embeddingDeploymentName = 'embedding'
param embeddingCapacity = 50

// Set AZURE_PRINCIPAL_ID to your object id before deploying:
//   export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
// The all-zero fallback fails fast instead of silently binding a wrong principal.
param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '00000000-0000-0000-0000-000000000000')
