#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

az account set --subscription "$SUBSCRIPTION_ID"
az config set extension.dynamic_install_allow_preview=true

echo "Deploying to: $(az account show --query name -o tsv)"

log() { echo "PROVISION ==> $*" >&2; }

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


for ns in CognitiveServices DocumentDb Insights OperationalInsights; do
  az provider register --namespace Microsoft.$ns --wait
done

log "Creating resource group $RG in $LOC..."
az group create \
  --name "$RG" \
  --location "$LOC"

log "Creating Azure OpenAI account $AOAI (~1 min)..."
az cognitiveservices account create \
  --resource-group "$RG" --name "$AOAI" --location "$LOC" \
  --kind "OpenAI" --sku "$AOAI_SKU" \
  --custom-domain "$AOAI"

log "Deploying ${#AOAI_DEPLOYMENTS[@]} model(s)..."
for d in "${AOAI_DEPLOYMENTS[@]}"; do
  IFS='|' read -r name model version format sku capacity <<< "$d"
  az cognitiveservices account deployment create \
    --resource-group "$RG" --name "$AOAI" --deployment-name "$name" \
    --model-name "$model" --model-version "$version" --model-format "$format" \
    --sku-name "$sku" --sku-capacity "$capacity"
done

log "Creating Cosmos DB $COSMOS (vector search)..."
az cosmosdb create \
  --name "$COSMOS" --resource-group "$RG" \
  --locations regionName="$LOC" failoverPriority=0 isZoneRedundant=false \
  --capabilities EnableNoSQLVectorSearch


az cosmosdb sql database create \
  --account "$COSMOS" --resource-group "$RG" --name "ragdb"


az monitor app-insights component create \
  --app ai200-ai --resource-group "$RG" --location "$LOC"
  
log "Done. Everything is in resource group $RG."