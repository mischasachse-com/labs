using 'main.bicep'

param location = 'swedencentral'

// Account becomes 'oai-<uniqueString(resourceGroup().id)>' — deterministic per RG.
param accountNamePrefix = 'oai'

param deploymentName = 'chat'
param modelName = 'gpt-5.4-mini'
param modelVersion = '2026-03-17'
param modelSkuName = 'DataZoneStandard'
param modelCapacity = 1

// Set AZURE_PRINCIPAL_ID to your object id before deploying:
//   az ad signed-in-user show --query id -o tsv
// The all-zero fallback fails fast instead of silently binding a wrong principal.
param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '00000000-0000-0000-0000-000000000000')
