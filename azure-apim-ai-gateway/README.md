# Lab: AI Gateway with Azure API Management — token limits per team

Blog post: **An AI Gateway with Azure API Management: Token Limits per Team**
Series: Azure AI with Bicep (part 4 of ongoing series)
Repo path: `labs/azure-apim-ai-gateway/`

## Overview

This lab puts an **Azure API Management (APIM) Developer** instance in front of
an existing **Azure OpenAI** deployment and demonstrates that two API consumers
("teams") get **independent token counters** when each uses its own APIM
subscription:

- Clients authenticate to the gateway with an **APIM subscription key**.
- The gateway authenticates to Azure OpenAI with its **system-assigned managed
  identity** (Cognitive Services OpenAI User role) — no Azure OpenAI API key is
  stored in APIM.
- An `llm-token-limit` inbound policy with
  `counter-key="@(context.Subscription.Id)"` enforces a small
  tokens-per-minute limit per APIM subscription.

**Lab cost:** APIM Developer ≈ $0.07/hour (check current pricing for your
region and agreement before deploying — see
[API Management pricing](https://azure.microsoft.com/en-us/pricing/details/api-management/)).
Provisioning takes ~30–40 minutes; the whole lab including tests and cleanup
fits in a few hours. Model usage is negligible (a few hundred tokens).
**A budget alert gives visibility but is not a guaranteed automatic spending
stop — delete the APIM instance when done.**

## Scope — what this lab is (and is not)

- Not fully keyless: clients still use APIM subscription keys.
- The token limit is a per-minute **rate limit** (HTTP 429), not a spending cap
  and not a daily/monthly **quota** (HTTP 403).
- Counters are tracked per gateway — no shared counter across regions.
- No backend network isolation is configured; anyone with direct access to the
  Azure OpenAI resource bypasses the gateway.

## Prerequisites

Tested with:

- Azure CLI ≥ 2.20 (`az --version`), signed in (`az login`)
- Bicep CLI (bundled with Azure CLI)
- Python ≥ 3.10 (standard library only — no pip installs)
- **Owner** or equivalent on the resource group, to create the APIM instance
  and assign the Cognitive Services OpenAI User role to its managed identity
- An existing Azure OpenAI resource with a chat model deployment. This lab
  reuses the resource from [`labs/azure-openai-bicep`](../azure-openai-bicep)
  (deploy it first if needed — see that README)
- Tested region: `swedencentral`; model `gpt-5.4-mini` on **`GlobalStandard`**
  (capacity 5). Note: our first attempt on `DataZoneStandard` at 1K TPM
  throttled sequential calls at ~1 request/minute — the *backend* 429 masked
  the APIM policy. Pick a SKU/capacity with enough headroom that the gateway
  limit is hit first.

## Files

| File | Purpose |
|---|---|
| `main.bicep` | APIM Developer instance + system-assigned managed identity |
| `main.bicepparam` | Parameters (publisher email/name — placeholders) |
| `token-limit-policy.xml` | **Policy fragment** to add inside the imported API's `<inbound>` section — not a complete policy document |
| `test_limits.py` | Bounded sequential test of the two team counters |
| `requirements.txt` | None needed — test uses the standard library |

## Deploy

### Step 0: cost check

APIM bills per hour while the instance exists. Verify the current Developer
price for your region before continuing, and plan to delete the instance after
the test.

### Step 1: deploy the APIM instance

```bash
az deployment group what-if \
  -g rg-openai-bicep-lab -n apim-whatif \
  --template-file main.bicep \
  --parameters publisherEmail='you@example.com' publisherName='Your Name'

az deployment group create \
  -g rg-openai-bicep-lab -n apim-deploy \
  --template-file main.bicep \
  --parameters publisherEmail='you@example.com' publisherName='Your Name'
```

The Bicep deploys **only the APIM instance** (~30–40 min for Developer tier).
Everything below is configured afterwards.

### Step 2: import the Azure OpenAI API

Portal path (wizard): APIM → **APIs → + Add API → Microsoft Foundry**, pick
the resource, client compatibility **Azure OpenAI**. The wizard wires up
operations, backend and managed-identity auth for you.

For this run we scripted the equivalent (tested commands):

```bash
# Import the OpenAI inference spec as an API (path: /openai)
az apim api import -g rg-openai-bicep-lab --service-name <apim-name> \
  --api-id azure-openai --path openai --display-name "Azure OpenAI" \
  --specification-url "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/OpenAIInference/stable/2024-10-21/inference.json" \
  --specification-format OpenApi --subscription-required true

# Backend pointing at the AOAI endpoint /openai, managed-identity credentials
az rest --method put \
  --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/rg-openai-bicep-lab/providers/Microsoft.ApiManagement/service/<apim-name>/backends/openai-backend?api-version=2023-05-01-preview" \
  --body '{"properties":{"url":"https://<oai-name>.openai.azure.com/openai","protocol":"http","credentials":{"managedIdentity":{"resource":"https://cognitiveservices.azure.com"}}}}'

# Cognitive Services OpenAI User for the APIM system-assigned identity
az role assignment create \
  --assignee-object-id <apim-identity-principal-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services OpenAI User" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-openai-bicep-lab/providers/Microsoft.CognitiveServices/accounts/<oai-name>
```

Role assignment propagation can take several minutes; a first call that
returns 401/403 usually just means "wait and retry".

### Step 3: create the two team subscriptions

APIM → **Subscriptions** → **+ Add subscription**, scope = the imported API,
or via REST (`PUT .../subscriptions/team-a` with
`{"properties":{"scope":"/apis/azure-openai","displayName":"team-a","state":"active"}}`):

- `team-a`
- `team-b`

Confirm the API requires a subscription (API → Settings → "Subscription
required" — `az apim api import --subscription-required true` already sets
it). Do **not** use the built-in all-access subscription for the test — the
APIM test console silently adds its key, which would mask which counter was
actually hit.

### Step 4: add the token-limit policy

API → **All operations** → policy editor → inside `<inbound>`, keep the
existing policies and add the fragment from `token-limit-policy.xml`
directly after `<base />` and before `set-backend-service`. Scripted
equivalent: `PUT .../apis/azure-openai/policies/policy` with a
`<policies>` document containing `<base />`, the `llm-token-limit` element
and `set-backend-service` in `<inbound>` (see the blog post).

`tokens-per-minute="500"` is deliberately small so a handful of sequential
requests visibly trips the limiter. With `estimate-prompt-tokens="false"` APIM
counts real `usage` from the model response — one request can pass through and
push the counter over the limit before the next is blocked.

### Step 6: run the test

```bash
export APIM_GATEWAY_URL="https://<apim-name>.azure-api.net"
export APIM_API_PATH="/<base-path>/openai/deployments/<deployment>/chat/completions?api-version=<version-shown-in-imported-operation>"
export TEAM_A_KEY="<primary-key-of-team-a-subscription>"
export TEAM_B_KEY="<primary-key-of-team-b-subscription>"
python test_limits.py
```

Expected:

1. Both teams return HTTP 200 with `x-lab-consumed-tokens` headers at baseline.
2. team-a receives a **gateway** `429` within the bounded request budget. You
   can tell it is the APIM policy (not the backend) because the 429 response
   carries the `x-lab-remaining-tokens` header and a `Retry-After` header, and
   the message comes from the policy.
3. team-b still returns 200 immediately after — the counters are independent.
4. team-a succeeds again after the per-minute window resets (~65 s wait).

The script is deliberately bounded: max 10 sequential requests per phase, a
prompt that produces ~150–175 tokens/call, no streaming, no retries that would
hide throttling. A 429 can also come from the Azure OpenAI backend itself —
check for the APIM headers (`x-lab-remaining-tokens: 0`) and the absence of a
model error message before drawing conclusions.

Also verify subscription enforcement: a request **without** an
`Ocp-Apim-Subscription-Key` header must be rejected (HTTP 401).

## Cleanup

```bash
# Delete only the lab APIM instance — keeps the Azure OpenAI resource alive
az apim delete -g rg-openai-bicep-lab -n <apim-name>
az apim show  -g rg-openai-bicep-lab -n <apim-name>   # should fail = deleted
```

If the lab is fully done and the OpenAI resource is no longer needed:

```bash
az group delete -n rg-openai-bicep-lab --yes
az cognitiveservices account list-deleted -o table   # note soft-deleted names
az cognitiveservices account purge -g rg-openai-bicep-lab -n <oai-name> -l <region>
az cognitiveservices account list-deleted -o table   # verify empty
```

Also remove the role assignment created for the APIM managed identity (deleted
automatically if you drop the whole RG) and any local files containing
subscription keys.

## Known limitations & troubleshooting

- **RBAC propagation**: a 401/403 right after import usually means the role
  assignment has not propagated yet — wait a few minutes.
- **429 source**: backend throttling also returns 429. Only the APIM policy
  adds `x-lab-remaining-tokens` / `x-lab-consumed-tokens` headers — use them to
  attribute the throttle.
- **Shared counter across scopes**: APIM uses one counter per `counter-key`
  value across *all* scopes where the same key is configured. If you add this
  policy at product *and* API scope with the same key, they share the counter.
- **Backend capacity**: the test assumes the model deployment has enough TPM
  capacity that APIM throttles first. With a 1K-TPM deployment and a 500 TPM
  policy, keep prompts small — exactly what `test_limits.py` does.
- **No hard cap**: concurrent requests can temporarily exceed the limit; the
  policy is a rate limiter, not a billing control.
