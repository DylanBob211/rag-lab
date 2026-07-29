from os import environ

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.appconfiguration.provider import load
from azure.storage.blob import BlobClient
from azure.monitor.opentelemetry import configure_azure_monitor
from openai import AzureOpenAI

_cred = DefaultAzureCredential()
_configs = load(
    environ["APPCONFIG_ENDPOINT"], credential=_cred, keyvault_credential=_cred
)
_cosmos_client = CosmosClient(_configs["COSMOS_ENDPOINT"], _cred)

_cosmos_db_name = _configs["COSMOS_DB_NAME"]
_cosmos_container_name = _configs["COSMOS_CONTAINER_NAME"]
sbus_queue = _configs["SBUS_QUEUE"]

_db = _cosmos_client.get_database_client(_cosmos_db_name)
container = _db.get_container_client(_cosmos_container_name)


configure_azure_monitor(connection_string=_configs["APPINSIGHTS_CS"])

aoai = AzureOpenAI(
    azure_endpoint=_configs["AOAI_ENDPOINT"],
    azure_ad_token_provider=get_bearer_token_provider(
        _cred, "https://cognitiveservices.azure.com/.default"
    ),
    api_version="2024-10-21",
)


def download_text(url):
    blob = BlobClient.from_blob_url(url, credential=_cred)
    return blob.download_blob(encoding="utf-8").readall()


def embed_batch(chunks: list[str]) -> list[list[float]]:
    if not chunks:
        return []
    response = aoai.embeddings.create(input=chunks, model="embedder", dimensions=1536)
    return [d.embedding for d in sorted(response.data, key=lambda d: d.index)]
