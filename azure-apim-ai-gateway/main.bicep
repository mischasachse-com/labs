targetScope = 'resourceGroup'

@description('Globally unique name for the API Management instance.')
param apiManagementServiceName string = 'apim-${uniqueString(resourceGroup().id)}'

@description('Publisher email address for the API Management instance.')
@minLength(1)
param publisherEmail string

@description('Publisher name for the API Management instance.')
@minLength(1)
param publisherName string

@description('Azure region for the API Management instance.')
param location string = resourceGroup().location

// This template creates the APIM instance only (Developer tier, system-assigned
// managed identity). The API import, backend access, APIM subscriptions and the
// token-limit policy are configured afterwards — see README.md.
resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

output apimName string = apiManagementService.name
output gatewayUrl string = apiManagementService.properties.gatewayUrl
output principalId string = apiManagementService.identity.principalId
