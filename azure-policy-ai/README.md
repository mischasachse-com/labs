# Lab: Azure Policy for AI

Blog post: **Azure Policy for AI: approved models, no API keys, allowed regions**  
Published: 2026-11-09  
Series: Azure AI with Bicep (part 3 of ongoing series)  
Repo path: `labs/azure-policy-ai/`

## Overview

This lab deploys a **policy initiative** that enforces four governance rules across Azure AI Services resources in a resource group:

| Rule | Source | Effect |
|---|---|---|
| No API key access (disableLocalAuth) | Built-in | Deny |
| Allowed Azure locations | Built-in | Deny |
| Restrict network access | Built-in | Audit |
| Approved model names only | Custom (this lab) | Deny |

**Lab cost: €0** — policy definitions and assignments are free. Failed Deny-effect deployments do not incur charges.

## Prerequisites

- Azure CLI ≥ 2.20 (`az --version`)
- Bicep CLI (bundled with Azure CLI ≥ 2.20)
- Subscription with **Owner** or **Resource Policy Contributor** role
- Resource group `rg-openai-bicep-lab` (create if it doesn't exist: `az group create -n rg-openai-bicep-lab -l westeurope`)

## Files

| File | Purpose |
|---|---|
| `main.bicep` | Custom policy definition + initiative + module call |
| `assignment.bicep` | Module: the RG-scoped policy assignment |
| `main.bicepparam` | Parameters (fill in built-in policy IDs here) |

## Deploy

### Step 1: find the built-in policy IDs

```bash
# No local auth (key access disabled)
az policy definition list \
  --query "[?contains(displayName,'key access disabled') && contains(displayName,'AI Services')].{id:id,display:displayName}" \
  -o table

# Restrict network access
az policy definition list \
  --query "[?contains(displayName,'restrict network access') && contains(displayName,'AI Services')].{id:id,display:displayName}" \
  -o table
```

Paste the full `/providers/Microsoft.Authorization/policyDefinitions/...` IDs into `main.bicepparam`.

### Step 2: verify the model.name alias

```bash
az provider show \
  --namespace Microsoft.CognitiveServices \
  --expand "resourceTypes/aliases" \
  --query "resourceTypes[?resourceType=='accounts/deployments'].aliases[*].name" \
  -o tsv
```

Confirm `Microsoft.CognitiveServices/accounts/deployments/model.name` appears in the output.

### Step 3: deploy

```bash
az deployment sub create \
  --name ai-policy-deployment \
  --location westeurope \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Step 4: test the Deny effect

```bash
# This should FAIL (API keys enabled — blocked by no-local-auth policy)
# az cognitiveservices account create has no --properties flag; use az resource
# create --is-full-object. westeurope rejects new OpenAI accounts on this
# subscription — use swedencentral (it's on the allowed list anyway).
az resource create \
  --resource-group rg-openai-bicep-lab \
  --name oai-keys-test \
  --resource-type Microsoft.CognitiveServices/accounts \
  --location swedencentral \
  --is-full-object \
  --properties '{
    "kind": "OpenAI",
    "sku": { "name": "S0" },
    "location": "swedencentral",
    "properties": {
      "disableLocalAuth": false,
      "publicNetworkAccess": "Enabled",
      "customSubDomainName": "oai-keys-test"
    }
  }'
```

Expected: `RequestDisallowedByPolicy` error. No resource is created.
The same command with `"disableLocalAuth": true` succeeds — and must be
followed by `az resource delete` + `az cognitiveservices account purge`.

### Step 5: compliance scan

```bash
az policy state trigger-scan --resource-group rg-openai-bicep-lab

az policy state summarize \
  --resource-group rg-openai-bicep-lab \
  --query "results.policyDetails[]" \
  -o table
```

## Cleanup

```bash
# 1. Remove the assignment
az policy assignment delete \
  --name ai-governance-assignment \
  --scope /subscriptions/YOUR-SUB-ID/resourceGroups/rg-openai-bicep-lab

# 2. Remove the initiative
az policy set-definition delete --name ai-governance-initiative

# 3. Remove the custom policy
az policy definition delete --name ai-approved-deployments-only
```

## Notes

- Policy definitions are created at **subscription scope** (`targetScope = 'subscription'`).
- The assignment is scoped to the **resource group** via `scope: targetRg`.
- The `noLocalAuthPolicyId` and `restrictNetworkPolicyId` values are tenant-independent (built-in), but should be verified before each deployment (`az policy definition list`).
- The `approvedModels` list in `main.bicepparam` should match the models approved in your tenant. Update it before assigning in production.
- Never publish real subscription IDs, tenant IDs or principal IDs in screenshots or code.
