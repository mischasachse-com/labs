targetScope = 'resourceGroup'

// Deploy this template into the SAME resource group as the blog 1 lab
// (labs/azure-openai-bicep, default rg-openai-bicep-lab). The OpenAI account
// name is then derived exactly like in blog 1, so no IDs or names to copy.

@description('Azure region for the new resources. Same region as the OpenAI account.')
param location string = resourceGroup().location

@description('Region for the Search service. Defaults to location; override when a region has no AI Search capacity.')
param searchLocation string = location

@description('Name of the existing Azure OpenAI account from blog 1 (same resource group).')
param openAiAccountName string = 'oai-${uniqueString(resourceGroup().id)}'

@description('Name for the Azure AI Search service. Globally unique.')
@minLength(2)
@maxLength(60)
param searchServiceName string = 'srch-${uniqueString(resourceGroup().id)}'

@description('Name for the storage account. Globally unique, 3-24 lowercase letters and digits.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'strag${uniqueString(resourceGroup().id)}'

@description('Name of the embedding deployment on the OpenAI account.')
param embeddingDeploymentName string = 'embedding'

@description('Embedding capacity in thousands of tokens per minute.')
@minValue(1)
param embeddingCapacity int = 50

@description('Object ID of the user who runs the Python scripts.')
param principalId string

// Built-in role definition IDs
var cognitiveServicesOpenAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

// ── Existing Azure OpenAI account (blog 1) ───────────────────────────────────
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openAiAccountName
}

// ── Embedding deployment on the existing account ─────────────────────────────
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: embeddingDeploymentName
  sku: {
    name: 'DataZoneStandard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

// ── Storage account for the source documents ─────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false   // Entra ID only, no storage keys or SAS
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource docsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'documents'
  properties: { publicAccess: 'None' }
}

// ── Azure AI Search ──────────────────────────────────────────────────────────
resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: searchLocation
  sku: { name: 'basic' }
  identity: { type: 'SystemAssigned' }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    semanticSearch: 'free'     // 1,000 semantic ranker requests per month
    disableLocalAuth: true     // no admin or query keys: Entra ID (RBAC) only
  }
}

// ── Role assignments ─────────────────────────────────────────────────────────
// Your user already has Cognitive Services OpenAI User on the account (blog 1).

// 1. Search managed identity → OpenAI: lets the index vectorizer embed queries.
resource searchToOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, searchService.id, cognitiveServicesOpenAiUserRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// 2. User → Storage: upload and read documents.
resource userToStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// 3. User → Search: create and manage the index definition.
resource userToSearchServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principalId, searchServiceContributorRoleId)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// 4. User → Search: upload documents and run queries.
resource userToSearchDataRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, principalId, searchIndexDataContributorRoleId)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output searchEndpoint string = 'https://${searchService.name}.search.windows.net'
output storageAccountName string = storageAccount.name
output openAiEndpoint string = openAiAccount.properties.endpoint
output embeddingDeploymentName string = embeddingDeployment.name
