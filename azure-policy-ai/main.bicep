targetScope = 'subscription'

// ─────────────────────────────────────────────
// Parameters
// ─────────────────────────────────────────────

@description('Resource group that will receive the policy assignment.')
param targetResourceGroupName string

@description('Built-in policy ID: Azure AI Services key access disabled (disable local authentication). Find with: az policy definition list --query "[?contains(displayName,\'key access disabled\') && contains(displayName,\'AI Services\')].id" -o tsv')
param noLocalAuthPolicyId string

@description('Built-in policy ID: Azure AI Services restrict network access. Find with: az policy definition list --query "[?contains(displayName,\'restrict network access\') && contains(displayName,\'AI Services\')].id" -o tsv')
param restrictNetworkPolicyId string

@description('Allowed Azure regions for AI resources.')
param allowedLocations array = [
  'westeurope'
  'northeurope'
  'swedencentral'
]

@description('Approved Azure OpenAI model names. Any deployment with a model not in this list will be denied.')
param approvedModels array = [
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-5.4-mini'
  'text-embedding-3-small'
  'text-embedding-ada-002'
]

@description('Use DoNotEnforce to audit existing resources before switching to Deny.')
@allowed([ 'Default', 'DoNotEnforce' ])
param enforcementMode string = 'Default'

// ─────────────────────────────────────────────
// Variables
// ─────────────────────────────────────────────

// "Allowed locations" built-in — ID is stable across all tenants
var allowedLocationsPolicyId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'

// ─────────────────────────────────────────────
// Custom policy: approved models only
// No built-in exists for this rule yet.
// Resource type: Microsoft.CognitiveServices/accounts/deployments
// Alias: Microsoft.CognitiveServices/accounts/deployments/model.name
// Verify alias: az provider show --namespace Microsoft.CognitiveServices \
//   --expand "resourceTypes/aliases" \
//   --query "resourceTypes[?resourceType=='accounts/deployments'].aliases[*].name" -o tsv
// ─────────────────────────────────────────────

resource approvedModelsPolicy 'Microsoft.Authorization/policyDefinitions@2023-04-01' = {
  name: 'ai-approved-deployments-only'
  properties: {
    displayName: 'Azure OpenAI deployments must use approved models'
    description: 'Denies Azure OpenAI model deployments whose model name is not on the approved list.'
    policyType: 'Custom'
    mode: 'All'
    parameters: {
      approvedModels: {
        type: 'Array'
        metadata: {
          displayName: 'Approved model names'
          description: 'List of allowed model names, e.g. ["gpt-4o","text-embedding-3-small"]'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.CognitiveServices/accounts/deployments'
          }
          {
            field: 'Microsoft.CognitiveServices/accounts/deployments/model.name'
            notIn: '[parameters(\'approvedModels\')]'
          }
        ]
      }
      then: {
        effect: 'Deny'
      }
    }
  }
}

// ─────────────────────────────────────────────
// Policy initiative (policySetDefinition)
// ─────────────────────────────────────────────

resource aiGovernanceInitiative 'Microsoft.Authorization/policySetDefinitions@2023-04-01' = {
  name: 'ai-governance-initiative'
  properties: {
    displayName: 'AI Governance Initiative'
    description: 'Enforces keyless auth, approved models, allowed regions and network restrictions for Azure AI Services.'
    policyType: 'Custom'
    parameters: {
      allowedLocations: {
        type: 'Array'
        metadata: { displayName: 'Allowed Azure locations' }
      }
      approvedModels: {
        type: 'Array'
        metadata: { displayName: 'Approved model names' }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: noLocalAuthPolicyId
        policyDefinitionReferenceId: 'deny-local-auth'
        // built-in 'effect' defaults to Audit — pass Deny explicitly
        parameters: {
          effect: { value: 'Deny' }
        }
      }
      {
        policyDefinitionId: allowedLocationsPolicyId
        policyDefinitionReferenceId: 'allowed-locations'
        parameters: {
          listOfAllowedLocations: { value: '[parameters(\'allowedLocations\')]' }
        }
      }
      {
        policyDefinitionId: restrictNetworkPolicyId
        policyDefinitionReferenceId: 'audit-network-access'
        parameters: {
          effect: { value: 'Audit' }
        }
      }
      {
        policyDefinitionId: approvedModelsPolicy.id
        policyDefinitionReferenceId: 'approved-models-only'
        parameters: {
          approvedModels: { value: '[parameters(\'approvedModels\')]' }
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────
// Policy assignment (resource group scope)
// ─────────────────────────────────────────────

// A resource can't be created at resource-group scope from a subscription-scope
// file (BCP139) — the assignment lives in a small module deployed to the RG.
module policyAssignment 'assignment.bicep' = {
  name: 'ai-governance-assignment'
  scope: resourceGroup(targetResourceGroupName)
  params: {
    initiativeId: aiGovernanceInitiative.id
    displayName: 'AI Governance – ${targetResourceGroupName}'
    enforcementMode: enforcementMode
    allowedLocations: allowedLocations
    approvedModels: approvedModels
  }
}

// ─────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────

output initiativeId string = aiGovernanceInitiative.id
output assignmentId string = policyAssignment.outputs.assignmentId
output customPolicyId string = approvedModelsPolicy.id
