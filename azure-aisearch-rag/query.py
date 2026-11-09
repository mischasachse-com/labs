"""
query.py - Answer a question with RAG: hybrid search + semantic ranker +
Azure OpenAI chat. No API keys anywhere.
"""
import os

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizableTextQuery
from openai import AzureOpenAI

SEARCH_ENDPOINT = os.environ["AZURE_SEARCH_ENDPOINT"]
OPENAI_ENDPOINT = os.environ["AZURE_OPENAI_ENDPOINT"].rstrip("/")
CHAT_DEPLOY = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "chat")
INDEX_NAME = "rag-docs"

cred = DefaultAzureCredential()
oai = AzureOpenAI(
    azure_endpoint=OPENAI_ENDPOINT,
    azure_ad_token_provider=get_bearer_token_provider(
        cred, "https://cognitiveservices.azure.com/.default"
    ),
    api_version="2025-04-01-preview",
)
search_client = SearchClient(endpoint=SEARCH_ENDPOINT, index_name=INDEX_NAME, credential=cred)

SYSTEM_PROMPT = (
    "You are a helpful assistant. Answer the question using ONLY the numbered "
    "context below. Cite the numbers you used, like [1]. If the answer is not "
    "in the context, say that you don't know."
)


def answer(question: str, top_k: int = 5) -> str:
    # 1. Hybrid search. Search embeds the question itself through the index
    #    vectorizer (its managed identity calls the embedding deployment).
    results = search_client.search(
        search_text=question,
        vector_queries=[
            VectorizableTextQuery(text=question, k_nearest_neighbors=top_k, fields="contentVector")
        ],
        query_type="semantic",
        semantic_configuration_name="semantic-config",
        select=["content", "source", "page"],
        top=top_k,
    )

    # 2. Build a numbered context from the top chunks
    context, sources = [], []
    for n, r in enumerate(results, start=1):
        context.append(f"[{n}] {r['content']}")
        sources.append(f"[{n}] {r['source']} (page {r['page']})")

    # 3. Generate the grounded answer
    response = oai.chat.completions.create(
        model=CHAT_DEPLOY,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": "Context:\n" + "\n\n".join(context) + f"\n\nQuestion: {question}"},
        ],
        max_completion_tokens=1000,
    )
    return response.choices[0].message.content + "\n\nSources:\n" + "\n".join(sources)


if __name__ == "__main__":
    print("\n" + answer(input("Your question: ")))
