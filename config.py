from os import environ

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI


aoai_endpoint = environ["AOAI_ENDPOINT"]
cosmosdb_endpoint = environ["COSMOSDB_ENDPOINT"]

cred = DefaultAzureCredential()

aoai = AzureOpenAI(
  azure_endpoint=aoai_endpoint, 
  azure_ad_token_provider=get_bearer_token_provider(cred, "https://cognitiveservices.azure.com/.default"), 
  api_version="2024-10-21"
)

cosmos_client = CosmosClient(cosmosdb_endpoint, cred)

db = cosmos_client.get_database_client("ragdb")
container = db.get_container_client("docs")
