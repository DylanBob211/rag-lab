#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

log() { echo "RBAC ==> $*" >&2; }

# Resource ID risolti una volta sola: sono gli stessi per ogni profilo.
AOAI_ID=$(az cognitiveservices account show --name "$AOAI" --resource-group "$RG" --query id -o tsv)
KV_ID=$(az keyvault show --name "$KV" --resource-group "$RG" --query id -o tsv)
APPCONFIG_ID=$(az appconfig show --name "$APPCONFIG" --resource-group "$RG" --query id -o tsv)
ACR_ID=$(az acr show --name "$ACR" --resource-group "$RG" --query id -o tsv)

# grant_data_roles <principal-id> <principal-type> <profile>
#   principal-type : User | ServicePrincipal
#   profile        : dev -> ruoli di SCRITTURA (Officer/Owner, Cosmos Contributor),
#                           per ingest.py + config.sh. Niente AcrPull.
#                    app -> ruoli di LETTURA (User/Reader, Cosmos Reader) + AcrPull.
# La MECCANICA e' condivisa; cambiano solo i ruoli. Least privilege: lo sviluppatore
# scrive config e dati, l'app runtime li legge soltanto (Cosmos) e usa la cache Redis.
grant_data_roles() {
  local pid="$1" ptype="$2" profile="$3"
  local kv_role appconf_role cosmos_role

  case "$profile" in
    dev) kv_role="Key Vault Secrets Officer"
         appconf_role="App Configuration Data Owner"
         cosmos_role="00000000-0000-0000-0000-000000000002" ;;  # Cosmos Data Contributor (write)
    app) kv_role="Key Vault Secrets User"
         appconf_role="App Configuration Data Reader"
         cosmos_role="00000000-0000-0000-0000-000000000001" ;;  # Cosmos Data Reader (read-only)
    *)   echo "profilo sconosciuto: $profile" >&2; return 1 ;;
  esac

  # Assegna un ruolo Azure RBAC "normale" a questo principal.
  # --assignee-object-id + --assignee-principal-type: saltano il lookup su Entra
  # Graph, quindi niente 'PrincipalNotFound' se la MI e' stata appena creata.
  _assign() {
    az role assignment create \
      --assignee-object-id "$pid" --assignee-principal-type "$ptype" \
      --role "$1" --scope "$2"
  }

  log "[$profile] Cognitive Services OpenAI User"
  _assign "Cognitive Services OpenAI User" "$AOAI_ID"
  log "[$profile] $kv_role"
  _assign "$kv_role" "$KV_ID"
  log "[$profile] $appconf_role"
  _assign "$appconf_role" "$APPCONFIG_ID"

  # AcrPull: solo l'app deve pullare l'immagine dal registry.
  if [[ "$profile" == "app" ]]; then
    log "[$profile] AcrPull"
    _assign "AcrPull" "$ACR_ID"
  fi

  # --- Le DUE eccezioni DATA-PLANE (il trap: control-plane != data-plane) ---
  # Cosmos: sistema RBAC dati PROPRIO, con GUID fissi (...001 reader, ...002 contributor).
  log "[$profile] Cosmos data role ${cosmos_role##*-}"
  az cosmosdb sql role assignment create \
    --account-name "$COSMOS" --resource-group "$RG" \
    --principal-id "$pid" --scope "/" \
    --role-definition-id "$cosmos_role"

  # Redis: access-policy assignment Entra propria. Nome univoco per principal.
  log "[$profile] Redis access-policy"
  az redisenterprise database access-policy-assignment create -g "$RG" \
    --cluster-name "$REDIS" --database-name default \
    --access-policy-assignment-name "$profile" --access-policy-name default \
    --object-id "$pid"
}

# 1) Lo sviluppatore (tu): serve SCRITTURA per caricare i doc (ingest.py) e
#    popolare App Config + KV (config.sh).
ME=$(az ad signed-in-user show --query id -o tsv)
grant_data_roles "$ME" User dev

# 2) La managed identity della Container App: solo LETTURA + AcrPull.
#    Richiede che provision.sh abbia gia' creato il GUSCIO dell'app (che conia la MI).
APP_MI=$(az containerapp show -n "$APP" -g "$RG" --query identity.principalId -o tsv 2>/dev/null || true)
if [[ -n "${APP_MI:-}" && "$APP_MI" != "null" ]]; then
  grant_data_roles "$APP_MI" ServicePrincipal app
else
  log "SKIP profilo 'app': la Container App '$APP' non esiste ancora (la crea provision.sh)."
fi
