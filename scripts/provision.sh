#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

echo "Deploying to: $(az account show --query name -o tsv)"

log() { echo "PROVISION ==> $*" >&2; }

# have <az show args...> : succeeds (exit 0) if the resource already exists.
# Used as `have ... || az ... create` so each create runs only when absent.
# This is what makes re-runs idempotent: most `az create` return the existing
# resource, but a few (keyvault, appconfig, cosmos db/container, deployments,
# containerapp) error on re-run, so we guard every one uniformly.
have() { az "$@" >/dev/null 2>&1; }

preflight() {
  local sku_ok model_ok d name model version format sku capacity err

  sku_ok=$(az cognitiveservices account list-skus \
    --query "[?kind=='OpenAI' && name=='$AOAI_SKU' && contains(locations, '${LOC^^}')] | [0].name" -o tsv)
  : "${sku_ok:?The required SKU is not available at $LOC}"

  for d in "${AOAI_DEPLOYMENTS[@]}"; do
    IFS='|' read -r name model version format sku capacity <<< "$d"
    model_ok=$(az cognitiveservices model list --location "$LOC" \
      --query "[?kind=='OpenAI' && model.name=='$model' && model.version=='$version' && model.format=='$format' && contains(model.skus[].name, '$sku')] | [0].model.name" -o tsv)
    err="Model not found in $LOC: "
    err+="model=$model, version=$version, "
    err+="format=$format, sku=$sku"
    : "${model_ok:?$err}"
  done
}

preflight

log "Registering needed providers"
for ns in CognitiveServices DocumentDb Insights OperationalInsights Cache KeyVault AppConfiguration ContainerRegistry App; do
  az provider register --namespace Microsoft.$ns --wait
done

log "Creating resource group $RG in $LOC..."
az group create \
  --name "$RG" \
  --location "$LOC"


log "Ensuring Keyvault $KV"
have keyvault show -n "$KV" -g "$RG" || \
az keyvault create \
  --resource-group "$RG" --location "$LOC" --name "$KV" \
  --enable-rbac-authorization true

log "Ensuring Appconfig $APPCONFIG"
have appconfig show -n "$APPCONFIG" -g "$RG" || \
az appconfig create \
  --resource-group "$RG" --location "$LOC" --name "$APPCONFIG" --sku free \
  --disable-local-auth true

log "Ensuring Azure OpenAI account $AOAI (~1 min)..."
have cognitiveservices account show -n "$AOAI" -g "$RG" || \
az cognitiveservices account create \
  --resource-group "$RG" --name "$AOAI" --location "$LOC" \
  --kind "OpenAI" --sku "$AOAI_SKU" \
  --custom-domain "$AOAI"

log "Deploying ${#AOAI_DEPLOYMENTS[@]} model(s)..."
for d in "${AOAI_DEPLOYMENTS[@]}"; do
  IFS='|' read -r name model version format sku capacity <<< "$d"
  have cognitiveservices account deployment show \
    --resource-group "$RG" --name "$AOAI" --deployment-name "$name" || \
  az cognitiveservices account deployment create \
    --resource-group "$RG" --name "$AOAI" --deployment-name "$name" \
    --model-name "$model" --model-version "$version" --model-format "$format" \
    --sku-name "$sku" --sku-capacity "$capacity"
done

log "Ensuring Cosmos DB $COSMOS (vector search)..."
have cosmosdb show -n "$COSMOS" -g "$RG" || \
az cosmosdb create \
  --name "$COSMOS" --resource-group "$RG" \
  --locations regionName="$LOC" failoverPriority=0 isZoneRedundant=false \
  --capabilities EnableNoSQLVectorSearch


have cosmosdb sql database show -a "$COSMOS" -g "$RG" -n ragdb || \
az cosmosdb sql database create \
  --account "$COSMOS" --resource-group "$RG" --name "ragdb"

have cosmosdb sql container show -g "$RG" -a "$COSMOS" -d ragdb -n docs || \
az cosmosdb sql container create -g "$RG" -a "$COSMOS" -d ragdb -n docs \
  --partition-key-path /id \
  --vector-embeddings '{"vectorEmbeddings":[{"path":"/embedding","dataType":"float32","distanceFunction":"cosine","dimensions":1536}]}' \
  --idx '{"indexingMode":"consistent","automatic":true,"includedPaths":[{"path":"/*"}],"excludedPaths":[{"path":"/embedding/*"}],"vectorIndexes":[{"path":"/embedding","type":"diskANN"}]}'

log "Ensuring Application Insights $APPINSIGHTS"
have monitor app-insights component show --app "$APPINSIGHTS" -g "$RG" || \
az monitor app-insights component create \
  --app "$APPINSIGHTS" --resource-group "$RG" --location "$LOC"

log "Ensuring Redis $REDIS"
# --module RediSearch: redisvl's SemanticCache is built on RediSearch (FT.* commands);
#   without it the app dies with `unknown command 'FT._LIST'`. Modules are CREATE-TIME only.
# --clustering-policy EnterpriseCluster: RediSearch is unsupported under the OSS cluster API,
#   AND EnterpriseCluster exposes a single endpoint so the plain redis.Redis client (not
#   RedisCluster) works without MOVED redirects. The auto-created 'default' DB inherits both.
have redisenterprise show -n "$REDIS" -g "$RG" || \
az redisenterprise create -n "$REDIS" -g "$RG" --sku "Balanced_B0" --location "$LOC" \
  --public-network-access Enabled \
  --clustering-policy EnterpriseCluster \
  --module name="RediSearch"
# database update is a PATCH -> safe to re-run. NOTE: it can flip protocol/access-keys,
# but it CANNOT add modules or change clustering policy (those are create-time above).
az redisenterprise database update -g "$RG" --cluster-name "$REDIS" \
  --client-protocol Encrypted --access-keys-authentication Disabled

log "Ensuring ACR $ACR"
have acr show -n "$ACR" -g "$RG" || \
az acr create -n "$ACR" -g "$RG" --sku Basic --admin-enabled false

log "Ensuring Container Apps environment $ACA_ENV"
have containerapp env show -n "$ACA_ENV" -g "$RG" || \
az containerapp env create -n "$ACA_ENV" -g "$RG" -l "$LOC"

log "Ensuring Container App shell $APP (placeholder image, system-assigned MI)"
APPCONFIG_ENDPOINT=$(az appconfig show -n "$APPCONFIG" -g "$RG" --query endpoint -o tsv)
have containerapp show -n "$APP" -g "$RG" || \
az containerapp create -n "$APP" -g "$RG" --environment "$ACA_ENV" \
  --image mcr.microsoft.com/k8se/quickstart:latest \
  --system-assigned \
  --ingress external --target-port 8000 \
  --min-replicas 0 --max-replicas 2 \
  --env-vars APPCONFIG_ENDPOINT="$APPCONFIG_ENDPOINT"   # UNICO seed; ogni altro endpoint arriva da App Config

log "Provisioning done."