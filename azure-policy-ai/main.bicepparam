using './main.bicep'

// ─────────────────────────────────────────────
// Step 1 before deploying: find the built-in policy IDs
//
// No local auth:
//   az policy definition list \
//     --query "[?contains(displayName,'key access disabled') && contains(displayName,'AI Services')].{id:id,display:displayName}" \
//     -o table
//
// Restrict network access:
//   az policy definition list \
//     --query "[?contains(displayName,'restrict network access') && contains(displayName,'AI Services')].{id:id,display:displayName}" \
//     -o table
//
// Paste the full /providers/Microsoft.Authorization/policyDefinitions/... IDs below.
// ─────────────────────────────────────────────

param targetResourceGroupName = 'rg-openai-bicep-lab'

param noLocalAuthPolicyId      = '/providers/Microsoft.Authorization/policyDefinitions/71ef260a-8f18-47b7-abcb-62d0673d94dc'
param restrictNetworkPolicyId  = '/providers/Microsoft.Authorization/policyDefinitions/037eea7a-bd0a-46c5-9a66-03aea78705d3'

param allowedLocations = [
  'westeurope'
  'northeurope'
  'swedencentral'
]

param approvedModels = [
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-5.4-mini'
  'text-embedding-3-small'
  'text-embedding-ada-002'
]

// Switch to 'DoNotEnforce' first if you have existing resources to audit before blocking
param enforcementMode = 'Default'
