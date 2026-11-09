"""Minimal Azure OpenAI smoke test using Entra ID (no API keys)."""

import os

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

endpoint = os.environ["AZURE_OPENAI_ENDPOINT"]
deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "chat")

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)

client = AzureOpenAI(
    azure_endpoint=endpoint,
    azure_ad_token_provider=token_provider,
    api_version="2024-10-21",
)

# gpt-5.4-mini is a reasoning model: use max_completion_tokens (not max_tokens)
# and do NOT pass temperature — sampling params are rejected on this family.
# Reasoning tokens count toward the cap, so keep headroom above the reply length.
response = client.chat.completions.create(
    model=deployment,
    messages=[
        {"role": "user", "content": "Say hello from Azure OpenAI in one sentence."},
    ],
    max_completion_tokens=2000,
)

print(response.choices[0].message.content)
print(f"finish_reason: {response.choices[0].finish_reason}")
print(f"tokens: {response.usage.total_tokens}")
