"""
index.py - Create the search index and index the PDFs from blob storage.
Authenticates with DefaultAzureCredential (your Azure CLI login locally,
a managed identity in Azure). No API keys.
"""
import os
import re
from io import BytesIO

import pypdf
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    AzureOpenAIVectorizer,
    AzureOpenAIVectorizerParameters,
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)
from azure.storage.blob import BlobServiceClient
from openai import AzureOpenAI

SEARCH_ENDPOINT = os.environ["AZURE_SEARCH_ENDPOINT"]
STORAGE_ACCOUNT = os.environ["AZURE_STORAGE_ACCOUNT"]
OPENAI_ENDPOINT = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
EMBEDDING_DEPLOY = os.environ.get("AZURE_OPENAI_EMBEDDING_DEPLOYMENT", "embedding")
INDEX_NAME = "rag-docs"
CONTAINER = "documents"
CHUNK_WORDS = 350  # roughly 500 tokens per chunk

cred = DefaultAzureCredential()

# ── OpenAI client (Entra ID token, no key) ───────────────────────────────────
oai = AzureOpenAI(
    azure_endpoint=OPENAI_ENDPOINT,
    azure_ad_token_provider=get_bearer_token_provider(
        cred, "https://cognitiveservices.azure.com/.default"
    ),
    api_version="2025-04-01-preview",
)


def embed_batch(texts: list[str]) -> list[list[float]]:
    response = oai.embeddings.create(model=EMBEDDING_DEPLOY, input=texts)
    return [item.embedding for item in response.data]


def safe_key(value: str) -> str:
    # Document keys may only contain letters, digits, '_', '-' and '='.
    return re.sub(r"[^A-Za-z0-9_\-=]", "_", value)


# ── Index definition ─────────────────────────────────────────────────────────
# The vectorizer lets Search embed the *query* itself at search time, using
# its own managed identity (role: Cognitive Services OpenAI User).
index = SearchIndex(
    name=INDEX_NAME,
    fields=[
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SearchableField(name="content", type=SearchFieldDataType.String),
        SimpleField(name="source", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="page", type=SearchFieldDataType.Int32, filterable=True),
        SearchField(
            name="contentVector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=1536,
            vector_search_profile_name="hnsw-profile",
        ),
    ],
    vector_search=VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="hnsw")],
        profiles=[
            VectorSearchProfile(
                name="hnsw-profile",
                algorithm_configuration_name="hnsw",
                vectorizer_name="aoai-vectorizer",
            )
        ],
        vectorizers=[
            AzureOpenAIVectorizer(
                vectorizer_name="aoai-vectorizer",
                parameters=AzureOpenAIVectorizerParameters(
                    resource_url=OPENAI_ENDPOINT,
                    deployment_name=EMBEDDING_DEPLOY,
                    model_name="text-embedding-3-small",
                    # no api_key: Search uses its system-assigned managed identity
                ),
            )
        ],
    ),
    semantic_search=SemanticSearch(
        configurations=[
            SemanticConfiguration(
                name="semantic-config",
                prioritized_fields=SemanticPrioritizedFields(
                    content_fields=[SemanticField(field_name="content")]
                ),
            )
        ]
    ),
)

SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=cred).create_or_update_index(index)
print(f"Index '{INDEX_NAME}' ready.")

# ── Read PDFs from blob, chunk, embed, upload ────────────────────────────────
container = BlobServiceClient(
    account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net", credential=cred
).get_container_client(CONTAINER)
search_client = SearchClient(endpoint=SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=cred)

total = 0
for blob in container.list_blobs():
    if not blob.name.lower().endswith(".pdf"):
        continue
    reader = pypdf.PdfReader(BytesIO(container.download_blob(blob.name).readall()))

    chunks = []
    for page_num, page in enumerate(reader.pages, start=1):
        words = (page.extract_text() or "").split()
        for start in range(0, len(words), CHUNK_WORDS):
            text = " ".join(words[start:start + CHUNK_WORDS])
            if len(text) >= 50:  # skip near-empty chunks
                chunks.append((page_num, start, text))

    docs = []
    for i in range(0, len(chunks), 16):  # embed 16 chunks per request
        batch = chunks[i:i + 16]
        vectors = embed_batch([c[2] for c in batch])
        for (page_num, start, text), vector in zip(batch, vectors):
            docs.append({
                "id": safe_key(f"{blob.name}-p{page_num}-c{start}"),
                "content": text,
                "source": blob.name,
                "page": page_num,
                "contentVector": vector,
            })

    for i in range(0, len(docs), 100):
        search_client.upload_documents(documents=docs[i:i + 100])
    print(f"  {blob.name}: {len(docs)} chunks")
    total += len(docs)

print(f"Indexed {total} chunks from '{CONTAINER}'.")
