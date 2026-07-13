#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

COSMOS_ENDPOINT=$(az cosmosdb show --name "$COSMOS" --resource-group "$RG" --query documentEndpoint -o tsv)
AOAI_ENDPOINT=$(az cognitiveservices account show --name "$AOAI" --resource-group "$RG" --query properties.endpoint -o tsv)
REDIS_HOST=$(az redisenterprise show -n "$REDIS" -g "$RG" --query hostName -o tsv)
: ${COSMOS_ENDPOINT:?Cosmos endpoint not found}
: ${AOAI_ENDPOINT:?Azure OpenAI endpoint not found}
: ${REDIS_HOST:?Redis endpoint not found}
az appconfig kv set -n "$APPCONFIG" --auth-mode login --key COSMOS_ENDPOINT --value "$COSMOS_ENDPOINT" --yes
az appconfig kv set -n "$APPCONFIG" --auth-mode login --key AOAI_ENDPOINT --value "$AOAI_ENDPOINT" --yes
az appconfig kv set -n "$APPCONFIG" --auth-mode login --key REDIS_HOST --value "$REDIS_HOST" --yes

APPINSIGHTS_CS=$(az monitor app-insights component show --app "$APPINSIGHTS" --resource-group "$RG" --query connectionString -o tsv)
: ${APPINSIGHTS_CS:?Appinsights connection string not found}

SECRET_URI=$(az keyvault secret set --vault-name "$KV" --name appinsights-cs --value "$APPINSIGHTS_CS" --query id -o tsv)
az appconfig kv set-keyvault -n "$APPCONFIG" --auth-mode login --key APPINSIGHTS_CS --secret-identifier "$SECRET_URI" --yes