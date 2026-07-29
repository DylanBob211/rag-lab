from os import environ

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
from azure.monitor.opentelemetry import configure_azure_monitor
from azure.appconfiguration.provider import load
from redis_entraid.cred_provider import create_from_default_azure_credential
from redis.client import Redis
from redisvl.extensions.cache.llm import SemanticCache
from redisvl.utils.vectorize import CustomTextVectorizer


__all__ = ["aoai", "semantic_cache", "container"]

_cred = DefaultAzureCredential()
_configs = load(
    environ["APPCONFIG_ENDPOINT"], credential=_cred, keyvault_credential=_cred
)

configure_azure_monitor(connection_string=_configs["APPINSIGHTS_CS"])

aoai = AzureOpenAI(
    azure_endpoint=_configs["AOAI_ENDPOINT"],
    azure_ad_token_provider=get_bearer_token_provider(
        _cred, "https://cognitiveservices.azure.com/.default"
    ),
    api_version="2024-10-21",
)

_cosmos_client = CosmosClient(_configs["COSMOS_ENDPOINT"], _cred)

_redis_cred_provider = create_from_default_azure_credential(
    scopes=("https://redis.azure.com/.default",)
)
_redis_client = Redis(
    host=_configs["REDIS_HOST"],
    port=10000,
    ssl=True,
    credential_provider=_redis_cred_provider,
)
_cosmos_db_name = _configs["COSMOS_DB_NAME"]
_cosmos_container_name = _configs["COSMOS_CONTAINER_NAME"]

_db = _cosmos_client.get_database_client(_cosmos_db_name)
container = _db.get_container_client(_cosmos_container_name)

semantic_cache = SemanticCache(
    redis_client=_redis_client,
    vectorizer=CustomTextVectorizer(
        embed=lambda t: (
            aoai.embeddings.create(input=t, model="embedder", dimensions=1536)
            .data[0]
            .embedding
        )
    ),
)
