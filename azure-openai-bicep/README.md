# Lab: Azure OpenAI with Bicep — your first AI request without API keys

Companion code for the blog post on mischasachse.com. Deploys an Azure OpenAI
account + model deployment entirely via Bicep, grants your signed-in user the
`Cognitive Services OpenAI User` role, and calls the model from Python using
`DefaultAzureCredential` — no keys involved.

## Prerequisites

- Azure subscription (pay-as-you-go is fine — this lab costs a fraction of a cent)
- Owner, or User Access Administrator + Contributor, on the resource group
  (the template creates a role assignment)
- Azure CLI (`az login`)
- `Microsoft.CognitiveServices` resource provider registered:
  `az provider register -n Microsoft.CognitiveServices`
- Python 3.10+: `pip install -r requirements.txt`

## Deploy

```bash
# Object id of your signed-in user → receives the OpenAI User role
export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

az group create -n rg-openai-bicep-lab -l swedencentral
az deployment group create -g rg-openai-bicep-lab -f main.bicep -p main.bicepparam
```

> Note: if `AZURE_PRINCIPAL_ID` is unset, the account and deployment are still
> created — only the role assignment fails (the all-zero fallback can't resolve
> a principal). Delete the resource group or re-run with the variable set.

## Run the client

```bash
export AZURE_OPENAI_ENDPOINT=$(az deployment group show -g rg-openai-bicep-lab -n main --query properties.outputs.endpoint.value -o tsv)
export AZURE_OPENAI_DEPLOYMENT="chat"
python client.py
```

> Getting a 401/403 right after deploying? New role assignments can take a few
> minutes to propagate. Wait and retry before debugging.

## Cleaning up

OpenAI accounts are **soft-deleted** — purge or a redeploy with the same
(deterministic) name fails:

```bash
az group delete -n rg-openai-bicep-lab --yes
az cognitiveservices account purge -g rg-openai-bicep-lab -n <account-name> -l swedencentral
az cognitiveservices account list-deleted -o table   # should be empty
```

## Model/region selection (verified 2026-10-26 on a pay-as-you-go subscription)

Quota = `az cognitiveservices usage list -l <region>` limit (K TPM); retirement = inference
deprecation date from `az cognitiveservices model list -l <region>` (matches the
Microsoft Foundry model retirement schedule). **Quota is per subscription and
region — always check your own before deploying.**

| Model | Version | Lifecycle | Retirement | SKU | Quota SE/WE/EUS2 |
|---|---|---|---|---|---|
| **gpt-5.4-mini** | 2026-03-17 | GA | 2027-09-21 | **DataZoneStandard** | **200 / 200 / 200** |
| gpt-5.4-mini | 2026-03-17 | GA | 2027-09-21 | GlobalStandard | 0 / 0 / 0 |
| gpt-5.4-nano | 2026-03-17 | GA | 2027-09-21 | GlobalStandard (SE/WE), +DataZone (EUS2) | 0 / 0 / 0 |
| gpt-5.6-luna | 2026-07-09 | GA | 2028-01-11 | GlobalStandard + DataZoneStandard | 0 / 0 / 0 |
| gpt-5-mini | 2025-08-07 | GA | 2027-02-09 | GlobalStandard | 500 / 500 / 500 |
| gpt-5-mini | 2025-08-07 | GA | 2027-02-09 | DataZoneStandard | 0 / 0 / 0 |
| gpt-5-nano | 2025-08-07 | GA | 2027-02-09 | GlobalStandard + DataZoneStandard | 0 / 0 / 0 |
| gpt-4o-mini | 2024-07-18 | Deprecating | 2027-04-14 | Standard (SE/EUS2 only) | 200 / n/a / 200 |

**Default: `gpt-5.4-mini` @ `DataZoneStandard` in `swedencentral`** — the only
candidate with a retirement on/after Sep 2027, an EU DataZone SKU *and* PAYG
quota. `gpt-5.6-luna` retires later (2028-01-11) but had zero quota (needs a
quota-increase request). `gpt-4o-mini` is `Deprecating` (2027-04-14).

## Production notes

- `principalType: 'User'` fits a personal lab; for a service principal or
  managed identity (e.g. CI/CD) use `'ServicePrincipal'`.
- `publicNetworkAccess: 'Enabled'` keeps the lab simple; production should use
  private endpoints (`'Disabled'` + `Microsoft.Network/privateEndpoints`).
