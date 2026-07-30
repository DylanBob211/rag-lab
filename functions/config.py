from functools import lru_cache
from os import environ

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.appconfiguration.provider import load
from azure.storage.blob import BlobClient
from azure.monitor.opentelemetry import configure_azure_monitor
from redis_entraid.cred_provider import create_from_default_azure_credential
from redis.client import Redis
from redisvl.extensions.cache.llm import SemanticCache
from openai import AzureOpenAI
from redisvl.query.filter import Tag
from redisvl.query import FilterQuery
from redisvl.utils.vectorize import CustomTextVectorizer

sbus_queue = environ["SBUS_QUEUE"]


@lru_cache
def _cred():
    return DefaultAzureCredential()


@lru_cache
def _cfg():
    return load(
        environ["APPCONFIG_ENDPOINT"], credential=_cred(), keyvault_credential=_cred()
    )


@lru_cache
def init_telemetry():
    configure_azure_monitor(connection_string=_cfg()["APPINSIGHTS_CS"])


@lru_cache
def get_container():
    client = CosmosClient(_cfg()["COSMOS_ENDPOINT"], _cred())
    db = client.get_database_client(_cfg()["COSMOS_DB_NAME"])
    return db.get_container_client(_cfg()["COSMOS_CONTAINER_NAME"])


@lru_cache
def _aoai():
    return AzureOpenAI(
        azure_endpoint=_cfg()["AOAI_ENDPOINT"],
        azure_ad_token_provider=get_bearer_token_provider(
            _cred(), "https://cognitiveservices.azure.com/.default"
        ),
        api_version="2024-10-21",
    )


@lru_cache
def _cache():
    return SemanticCache(
        filterable_fields=[{"name": "doc_ids", "type": "tag"}],
        redis_client=Redis(
            host=_cfg()["REDIS_HOST"],
            port=10000,
            ssl=True,
            credential_provider=create_from_default_azure_credential(
                scopes=("https://redis.azure.com/.default",)
            ),
        ),
        vectorizer=CustomTextVectorizer(
            embed=lambda t: (
                _aoai()
                .embeddings.create(input=t, model="embedder", dimensions=1536)
                .data[0]
                .embedding
            )
        ),
    )


def download_text(url):
    blob = BlobClient.from_blob_url(url, credential=_cred())
    return blob.download_blob(encoding="utf-8").readall()


def embed_batch(chunks: list[str]) -> list[list[float]]:
    if not chunks:
        return []
    response = _aoai().embeddings.create(
        input=chunks, model="embedder", dimensions=1536
    )
    return [d.embedding for d in sorted(response.data, key=lambda d: d.index)]


def invalidate_cache(docId):
    cache = _cache()
    matches = cache.index.query(
        FilterQuery(
            filter_expression=Tag("doc_ids") == docId,
            return_fields=["id"],
            num_results=1000,
        )
    )
    keys = [m["id"] for m in matches]
    if keys:
        cache.drop(keys=keys)
