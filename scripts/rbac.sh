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

log "Assigning user role for Azure OpenAI"
az role assignment create \
  --role "Cognitive Services OpenAI User" --scope "$AOAI_ID" --assignee "$ME"


KV_ID=$(az keyvault show --name "$KV" --resource-group "$RG" --query id -o tsv)

log "Assigning secret officer role for KV"
az role assignment create \
  --role "Key Vault Secrets Officer" --scope "$KV_ID" --assignee "$ME"

APPCONFIG_ID=$(az appconfig show --name "$APPCONFIG" --resource-group "$RG" --query id -o tsv)

log "Assigning configuration data owner role for APPCONFIG"
az role assignment create \
  --role "App Configuration Data Owner" --scope "$APPCONFIG_ID" --assignee "$ME"

log "Creating access policy for Redis"
az redisenterprise database access-policy-assignment create -g "$RG" \
  --cluster-name "$REDIS" --database-name default \
  --access-policy-assignment-name me --access-policy-name default \
  --no-wait --object-id "$ME"
