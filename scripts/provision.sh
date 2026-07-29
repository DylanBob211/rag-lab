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
for ns in CognitiveServices DocumentDb Insights OperationalInsights Cache KeyVault AppConfiguration ContainerRegistry App Storage; do
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


have cosmosdb sql database show -a "$COSMOS" -g "$RG" -n "$COSMOS_DB_NAME" || \
az cosmosdb sql database create \
  --account "$COSMOS" --resource-group "$RG" --name ""$COSMOS_DB_NAME""

have cosmosdb sql container show -g "$RG" -a "$COSMOS" -d "$COSMOS_DB_NAME" -n "$COSMOS_CONTAINER_NAME" || \
az cosmosdb sql container create -g "$RG" -a "$COSMOS" -d "$COSMOS_DB_NAME" -n "$COSMOS_CONTAINER_NAME" \
  --partition-key-path /docId \
  --vector-embeddings '{"vectorEmbeddings":[{"path":"/embedding","dataType":"float32","distanceFunction":"cosine","dimensions":1536}]}' \
  --idx '{"indexingMode":"consistent","automatic":true,"includedPaths":[{"path":"/*"}],"excludedPaths":[{"path":"/embedding/*"}],"vectorIndexes":[{"path":"/embedding","type":"diskANN"}]}'

log "Ensuring Application Insights $APPINSIGHTS"
have monitor app-insights component show --app "$APPINSIGHTS" -g "$RG" || \
az monitor app-insights component create \
  --app "$APPINSIGHTS" --resource-group "$RG" --location "$LOC"

log "Ensuring Redis $REDIS"

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

log "Ensuring storage account $STORAGE_ACCOUNT"
have storage account show -n "$STORAGE_ACCOUNT" -g "$RG" || \
az storage account create -n "$STORAGE_ACCOUNT" -g "$RG" -l "$LOC" \
  --identity-type SystemAssigned --sku Standard_LRS

log "Ensuring blob storage $STORAGE_CONTAINER_NAME"
have storage container-rm show -n "$STORAGE_CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" || \
az storage container-rm create -n "$STORAGE_CONTAINER_NAME" --storage-account "$STORAGE_ACCOUNT"

log "Ensuring service bus namespace $SBUS_NAMESPACE"
have servicebus namespace show -n "$SBUS_NAMESPACE" -g "$RG" || \
az servicebus namespace create -n "$SBUS_NAMESPACE" -g "$RG" \
  --location "$LOC" --sku Standard --mi-system-assigned

log "Ensuring service bus queue $SBUS_QUEUE"
have servicebus queue show -n "$SBUS_QUEUE" -g "$RG" --namespace-name "$SBUS_NAMESPACE" || \
az servicebus queue create -n "$SBUS_QUEUE" -g "$RG" --namespace-name "$SBUS_NAMESPACE" \
  --enable-session \
  --enable-dead-lettering-on-message-expiration \
  --lock-duration PT30S \
  --max-delivery-count 3


log "Ensuring service plan for functionapp $FUNCTIONAPP_SERVICE_PLAN"
have functionapp plan show -n "$FUNCTIONAPP_SERVICE_PLAN" -g "$RG" --is-linux true || \
az functionapp plan create -n "$FUNCTIONAPP_SERVICE_PLAN" -g "$RG" --sku B1 -l "$LOC"

log "Ensuring functionapp $FUNCTIONAPP"
have functionapp show -n "$FUNCTIONAPP" -g "$RG" || \
az functionapp create -n "$FUNCTIONAPP" -g "$RG" \
  --storage-account "$STORAGE_ACCOUNT" --plan "$FUNCTIONAPP_SERVICE_PLAN" \
  --app-insights "$APPINSIGHTS" --assign-identity '[system]' \
  --runtime "python"

STORAGE_ACCOUNT_ID=$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RG" --query id -o tsv)
SBUS_QUEUE_ID=$(az servicebus queue show -n "$SBUS_QUEUE" -g "$RG" --namespace-name "$SBUS_NAMESPACE" --query id -o tsv)

log "Ensure eventgrid subscription to storage account"
have eventgrid system-topic show -g "$RG" -n "$STORAGE_ACCOUNT_SYSTEM_TOPIC" || \
az eventgrid system-topic create -g "$RG" -n "$STORAGE_ACCOUNT_SYSTEM_TOPIC" \
  --source "$STORAGE_ACCOUNT_ID" --topic-type Microsoft.Storage.StorageAccounts \
  --mi-system-assigned

have eventgrid system-topic event-subscription show -n "$SERVICE_BUS_STORAGE_ACCOUNT_SUBSCRIPTION_NAME" -g "$RG" || \
az eventgrid system-topic event-subscription create -n "$SERVICE_BUS_STORAGE_ACCOUNT_SUBSCRIPTION_NAME" -g "$RG" \
  --system-topic-name "$STORAGE_ACCOUNT_SYSTEM_TOPIC" \
  --delivery-identity systemassigned \
  --endpoint-type servicebusqueue --endpoint "$SBUS_QUEUE_ID" \
  --included-event-types Microsoft.Storage.BlobCreated Microsoft.Storage.BlobDeleted \
  --subject-begins-with /blobServices/default/containers/$STORAGE_CONTAINER_NAME/ \
  --delivery-attribute-mapping SessionId dynamic data.url

log "Provisioning done."