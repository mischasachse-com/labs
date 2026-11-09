# Lab: Chat with your own documents — RAG with Azure AI Search and Bicep

Companion code for the blog post on mischasachse.com. Builds on the blog 1 lab
(`labs/azure-openai-bicep`): it adds an embedding deployment to the existing
Azure OpenAI account, a storage account for your PDFs and an Azure AI Search
service (Basic) — all via Bicep, all keyless. Search has `disableLocalAuth: true`,
storage has `allowSharedKeyAccess: false`; every call uses Entra ID (RBAC).

## What gets deployed

| Resource | Notes |
|---|---|
| Embedding deployment `embedding` | `text-embedding-3-small` v1, DataZoneStandard, 50K TPM, on the blog 1 account |
| Storage account + container `documents` | Standard_LRS, no public access, no shared keys |
| Azure AI Search (Basic) | System-assigned identity, semantic ranker Free, API keys disabled |
| 4 role assignments | Search MI → OpenAI User; you → Storage Blob Data Contributor, Search Service Contributor, Search Index Data Contributor |

Your user already has `Cognitive Services OpenAI User` on the account from blog 1.

## Prerequisites

- The blog 1 lab is deployed in `rg-openai-bicep-lab` (OpenAI account + `chat` deployment)
- Azure CLI (`az login`), Bicep CLI 0.30+ (`az bicep upgrade`)
- `Microsoft.Search` and `Microsoft.Storage` providers registered:
  `az provider register -n Microsoft.Search` / `az provider register -n Microsoft.Storage`
- Python 3.10+: `pip install -r requirements.txt`
- One or more PDF files (no confidential data!)

## Check embedding quota

```bash
az cognitiveservices usage list -l swedencentral \
  --query "[?contains(name.value,'text-embedding-3-small')].{name:name.value,used:currentValue,limit:limit}" -o table
```

You need at least 50 (K TPM) free for the DataZoneStandard SKU. If not, lower
`embeddingCapacity` in `main.bicepparam`.

## Deploy

```bash
export AZURE_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

az deployment group what-if -g rg-openai-bicep-lab -f main.bicep -p main.bicepparam
az deployment group create  -g rg-openai-bicep-lab -f main.bicep -p main.bicepparam
```

What-if should show **Create** for the embedding deployment, storage account,
blob service, container, search service and four role assignments. The OpenAI
account itself is not changed.

## Environment variables from the deployment outputs

```bash
OUT=$(az deployment group show -g rg-openai-bicep-lab -n main --query properties.outputs)
export AZURE_SEARCH_ENDPOINT=$(echo $OUT | jq -r .searchEndpoint.value)
export AZURE_STORAGE_ACCOUNT=$(echo $OUT | jq -r .storageAccountName.value)
export AZURE_OPENAI_ENDPOINT=$(echo $OUT | jq -r .openAiEndpoint.value)
export AZURE_OPENAI_EMBEDDING_DEPLOYMENT=$(echo $OUT | jq -r .embeddingDeploymentName.value)
export AZURE_OPENAI_DEPLOYMENT="chat"   # chat deployment from blog 1
```

> Role assignments can take a few minutes to propagate. A `403` right after
> deploying usually means: wait 2–5 minutes and try again.

## Upload your PDFs

```bash
az storage blob upload-batch --account-name $AZURE_STORAGE_ACCOUNT \
  -d documents -s ./docs --pattern "*.pdf" --auth-mode login
```

## Index and ask

```bash
python index.py     # creates index 'rag-docs', chunks, embeds and uploads
python query.py     # asks for a question, answers with [n] citations + sources
```

## Cost and cleanup

Azure AI Search Basic is billed per hour (≈ €0.07/hour) — **delete it the same
day**. The semantic ranker Free plan includes 1,000 requests per month. Set a
budget alert on the subscription (e.g. €5 and €10).

Keep the blog 1 resources, remove only this lab:

```bash
SRCH=$(echo $AZURE_SEARCH_ENDPOINT | sed 's#https://##; s#\.search\.windows\.net##')
az search service delete -g rg-openai-bicep-lab -n $SRCH --yes
az storage account delete -g rg-openai-bicep-lab -n $AZURE_STORAGE_ACCOUNT --yes
OAI=$(echo $AZURE_OPENAI_ENDPOINT | sed 's#https://##; s#\..*##')
az cognitiveservices account deployment delete -g rg-openai-bicep-lab -n $OAI --deployment-name embedding
```

Or remove everything (blog 1 included), then purge the soft-deleted OpenAI account:

```bash
az group delete -n rg-openai-bicep-lab --yes
az cognitiveservices account purge -g rg-openai-bicep-lab -n $OAI -l swedencentral
```
