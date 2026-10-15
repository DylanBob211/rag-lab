#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

log() { echo "RBAC ==> $*" >&2; }

# Resource IDs are resolved once: they are the same for every profile.
AOAI_ID=$(az cognitiveservices account show --name "$AOAI" --resource-group "$RG" --query id -o tsv)
KV_ID=$(az keyvault show --name "$KV" --resource-group "$RG" --query id -o tsv)
APPCONFIG_ID=$(az appconfig show --name "$APPCONFIG" --resource-group "$RG" --query id -o tsv)
ACR_ID=$(az acr show --name "$ACR" --resource-group "$RG" --query id -o tsv)
STORAGE_ACCOUNT_ID=$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --query id -o tsv)
SBUS_QUEUE_ID=$(az servicebus queue show -n "$SBUS_QUEUE" -g "$RG" --namespace-name "$SBUS_NAMESPACE" --query id -o tsv)

# assign <principal-id> <principal-type> <role> <scope>
# --assignee-object-id + --assignee-principal-type skip the Microsoft Graph
# lookup, so a freshly created managed identity doesn't fail with
# 'PrincipalNotFound' while Entra ID is still replicating it.
assign() {
  az role assignment create \
    --assignee-object-id "$1" --assignee-principal-type "$2" \
    --role "$3" --scope "$4"
}

# grant_data_roles <principal-id> <principal-type> <profile>
#   principal-type : User | ServicePrincipal
#   profile        : dev  -> write roles, so the developer can seed App Config,
#                            Key Vault and Cosmos (config.sh, upload_corpus.sh).
#                    func -> read config, write Cosmos (the ingestion function).
#                    app  -> read-only everywhere, plus AcrPull (the query API).
# The mechanics are shared; only the roles change (least privilege).
grant_data_roles() {
  local pid="$1" ptype="$2" profile="$3"
  local kv_role appconf_role cosmos_role

  case "$profile" in
    dev)  kv_role="Key Vault Secrets Officer"
          appconf_role="App Configuration Data Owner"
          cosmos_role="00000000-0000-0000-0000-000000000002" ;; # Cosmos DB Built-in Data Contributor
    func) kv_role="Key Vault Secrets User"
          appconf_role="App Configuration Data Reader"
          cosmos_role="00000000-0000-0000-0000-000000000002" ;; # Cosmos DB Built-in Data Contributor
    app)  kv_role="Key Vault Secrets User"
          appconf_role="App Configuration Data Reader"
          cosmos_role="00000000-0000-0000-0000-000000000001" ;; # Cosmos DB Built-in Data Reader
    *)    echo "unknown profile: $profile" >&2; return 1 ;;
  esac

  log "[$profile] Cognitive Services OpenAI User"
  assign "$pid" "$ptype" "Cognitive Services OpenAI User" "$AOAI_ID"
  log "[$profile] $kv_role"
  assign "$pid" "$ptype" "$kv_role" "$KV_ID"
  log "[$profile] $appconf_role"
  assign "$pid" "$ptype" "$appconf_role" "$APPCONFIG_ID"

  # Only the Container App pulls images from the registry.
  if [[ "$profile" == "app" ]]; then
    log "[$profile] AcrPull"
    assign "$pid" "$ptype" "AcrPull" "$ACR_ID"
  fi

  # Two data-plane exceptions: these services don't use regular Azure RBAC for
  # data access, so a control-plane role would not be enough.
  # Cosmos DB has its own SQL role system with fixed built-in role GUIDs.
  log "[$profile] Cosmos data role ${cosmos_role##*-}"
  az cosmosdb sql role assignment create \
    --account-name "$COSMOS" --resource-group "$RG" \
    --principal-id "$pid" --scope "/" \
    --role-definition-id "$cosmos_role"

  # Azure Managed Redis uses access-policy assignments, one per principal.
  log "[$profile] Redis access policy"
  az redisenterprise database access-policy-assignment create -g "$RG" \
    --cluster-name "$REDIS" --database-name default \
    --access-policy-assignment-name "$profile" --access-policy-name default \
    --object-id "$pid"
}

# 1) The developer running this script.
ME=$(az ad signed-in-user show --query id -o tsv)
grant_data_roles "$ME" User dev

# 2) The Container App's managed identity (created by provision.sh).
APP_MI=$(az containerapp show -n "$APP" -g "$RG" --query identity.principalId -o tsv 2>/dev/null || true)
if [[ -n "$APP_MI" && "$APP_MI" != "null" ]]; then
  grant_data_roles "$APP_MI" ServicePrincipal app
else
  log "SKIP profile 'app': Container App '$APP' does not exist yet (run provision.sh first)."
fi

# 3) The Function App's managed identity (created by provision.sh).
#    On top of the shared roles it reads blobs and consumes the Service Bus queue.
#    The Event Grid -> Service Bus sender role is granted in provision.sh,
#    because the event subscription can't be created without it.
FUNC_MI=$(az functionapp show -n "$FUNCTIONAPP" -g "$RG" --query identity.principalId -o tsv 2>/dev/null || true)
if [[ -n "$FUNC_MI" && "$FUNC_MI" != "null" ]]; then
  grant_data_roles "$FUNC_MI" ServicePrincipal func
  log "[func] Azure Service Bus Data Receiver"
  assign "$FUNC_MI" ServicePrincipal "Azure Service Bus Data Receiver" "$SBUS_QUEUE_ID"
  log "[func] Storage Blob Data Reader"
  assign "$FUNC_MI" ServicePrincipal "Storage Blob Data Reader" "$STORAGE_ACCOUNT_ID"
else
  log "SKIP profile 'func': Function App '$FUNCTIONAPP' does not exist yet (run provision.sh first)."
fi
