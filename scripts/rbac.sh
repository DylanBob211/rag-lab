#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

ME=$(az ad signed-in-user show --query id -o tsv)

log() { echo "RBAC ==> $*" >&2; }

log "Assigning contributor role for Cosmos"
az cosmosdb sql role assignment create \
  --account-name "$COSMOS" --resource-group "$RG" \
  --principal-id "$ME" --scope "/" \
  --role-definition-id 00000000-0000-0000-0000-000000000002

AOAI_ID=$(az cognitiveservices account show --name "$AOAI" --resource-group "$RG" --query id -o tsv)

log "Assigning user role to Azure OpenAI"
az role assignment create \
  --role "Cognitive Services OpenAI User" --scope "$AOAI_ID" --assignee "$ME"


KV_ID=$(az keyvault show --name "$KV" --resource-group "$RG" --query id -o tsv)

log "Assigning secret user role to KV"
az role assignment create \
  --role "Key Vault Secrets Officer" --scope "$KV_ID" --assignee "$ME"

APPCONFIG_ID=$(az appconfig show --name "$APPCONFIG" --resource-group "$RG" --query id -o tsv)

log "Assigning configuration data owner role to APPCONFIG"
az role assignment create \
  --role "App Configuration Data Owner" --scope "$APPCONFIG_ID" --assignee "$ME"

COSMOS_ENDPOINT=$(az cosmosdb show --name "$COSMOS" --resource-group "$RG" --query documentEndpoint -o tsv)
AOAI_ENDPOINT=$(az cognitiveservices account show --name "$AOAI" --resource-group "$RG" --query properties.endpoint -o tsv)
az appconfig kv set -n "$APPCONFIG" --key COSMOS_ENDPOINT --value "$COSMOS_ENDPOINT" --yes
az appconfig kv set -n "$APPCONFIG" --key AOAI_ENDPOINT --value "$AOAI_ENDPOINT" --yes

APPINSIGHTS_CS=$(az monitor app-insights component show --app "$APPINSIGHTS" --resource-group "$RG" --query connectionString -o tsv)
SECRET_URI=$(az keyvault secret set --vault-name "$KV" --name appinsights-cs --value "$APPINSIGHTS_CS" --query id -o tsv)
az appconfig kv set-keyvault -n "$APPCONFIG" --key APPINSIGHTS_CS --secret-identifier "$SECRET_URI" --yes