// Module: policy assignment at resource group scope.
// Deployed from main.bicep (subscription scope) via:
//   scope: resourceGroup(targetResourceGroupName)

param initiativeId string
param displayName string
param enforcementMode string
param allowedLocations array
param approvedModels array

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'ai-governance-assignment'
  properties: {
    displayName: displayName
    description: 'Assigned by Bicep. Enforces the AI Governance Initiative on this resource group.'
    policyDefinitionId: initiativeId
    enforcementMode: enforcementMode
    parameters: {
      allowedLocations: { value: allowedLocations }
      approvedModels: { value: approvedModels }
    }
  }
}

output assignmentId string = policyAssignment.id
