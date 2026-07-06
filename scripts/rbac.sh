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