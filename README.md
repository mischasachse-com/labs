# Azure labs — mischasachse.com

Hands-on companion code for the blog series on
[mischasachse.com](https://mischasachse.com). Each lab deploys real Azure
resources with Bicep — always Entra ID / RBAC, never API keys — and is meant
to be deployed, tested and cleaned up again.

| Lab | Blog | What it does |
|---|---|---|
| [`azure-openai-bicep`](azure-openai-bicep/) | Azure OpenAI with Bicep: your first AI request without API keys | Azure OpenAI + gpt-5.4-mini deployment, `disableLocalAuth: true`, `DefaultAzureCredential` Python client |
| [`azure-aisearch-rag`](azure-aisearch-rag/) | Chat with your own documents: RAG with Azure AI Search and Bicep | AI Search (Basic) + storage + embedding deployment, managed identity everywhere, hybrid search with citations |
| [`azure-policy-ai`](azure-policy-ai/) | Azure Policy for AI: approved models, no API keys, allowed regions | Policy initiative (subscription scope) + RG assignment: deny local auth, allowed locations, network audit, approved models only |

## Conventions

- `main.bicep` + `main.bicepparam` per lab; deploy with `az deployment …`
- Principal/object IDs are never committed — they come from
  `readEnvironmentVariable('AZURE_PRINCIPAL_ID')`
- Clean up after testing: `az group delete --yes`, then
  `az cognitiveservices account purge` (soft-deleted accounts linger)
