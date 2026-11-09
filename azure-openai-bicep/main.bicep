targetScope = 'resourceGroup'

@description('Azure region for the OpenAI account. Verified candidates: swedencentral, westeurope, eastus2.')
param location string = resourceGroup().location

@description('Name prefix; the account gets a uniqueString suffix so it is globally unique (also used as custom subdomain for Entra ID auth).')
param accountNamePrefix string = 'oai'

@description('Name of the model deployment (used as deployment id in the client).')
param deploymentName string = 'chat'

@description('Model to deploy.')
param modelName string = 'gpt-5.4-mini'

@description('Model version.')
param modelVersion string = '2026-03-17'

@description('Deployment SKU. gpt-5.4-mini has PAYG quota only on DataZoneStandard in this subscription (verified via az cognitiveservices usage list).')
param modelSkuName string = 'DataZoneStandard'

@description('Deployment capacity in thousands of tokens per minute. 1 = minimal footprint for a smoke test.')
@minValue(1)
param modelCapacity int = 1

@description('Object ID of the Entra ID principal that gets the Cognitive Services OpenAI User role.')
param principalId string

// Cognitive Services OpenAI User
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// uniqueString lives here: .bicepparam files cannot call resourceGroup() (BCP057).
var accountName = '${accountNamePrefix}-${uniqueString(resourceGroup().id)}'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    // NoAutoUpgrade pins the exact model version above — reproducible for the lab.
    // Alternatives: 'OnceCurrentVersionExpired' (ARM default: auto-upgrade at retirement)
    // or 'OnceNewDefaultVersionAvailable' (upgrade as soon as a new default ships).
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, principalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

output endpoint string = account.properties.endpoint
output accountName string = account.name
output deploymentName string = deployment.name
